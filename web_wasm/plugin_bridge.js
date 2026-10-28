// MoUI Studio Web 插件宿主胶水（wasm-gc import object）。
//
// 与 native 后端的关系：两个后端共用同一份**契约**（清单格式、视图协议、
// 宿主 API 面、错误语义）与同一个**插件 ABI**（标准 C 风格：字符串 = UTF-8
// 字节 + 显式长度），但执行机制不同——native 用 wasmoon 跑 guest，web 用
// 浏览器原生 WebAssembly。
//
// **为什么 JS 侧做内存搬运**：wasm-gc 的 `extern "wasm"` 只能传标量
// （i32/f64），MoonBit 侧无法直接读写**另一个** wasm 实例的线性内存
// （那是另一个模块的 memory）。但 JS 可以访问任何 wasm 实例的
// `instance.exports.memory`——所以内存搬运统一在 JS 侧做，MoonBit 侧只
// 负责「把请求 JSON 交给 JS」与「把响应 JSON 取回」。
//
// 异步/同步的解法：浏览器 `WebAssembly.instantiate` 是异步的，而宿主→
// 插件的调用必须同步（视图渲染路径要立刻拿到视图 JSON）。→ **预实例化**：
// 页面启动时异步加载并实例化插件；就绪后，宿主的同步调用只是「查表 +
// 调导出」。
//
// 弱隔离（如实声明）：浏览器 wasm 没有资源配额，且执行不可抢占——一个
// 死循环插件会卡住主线程。web 端只能靠「来源可信 + 能力白名单」。

// 字符串句柄表：MoonBit 侧逐字符写入/读出（照 window/web 的已验证做法）。
const stringHandles = new Map();
let nextStringId = 1;

function createStringHandle(value) {
  const id = nextStringId++;
  stringHandles.set(id, { value, offset: 0 });
  return id;
}

function readString(handle) {
  const entry = stringHandles.get(handle);
  return entry ? entry.value : "";
}

// 已预实例化的插件：plugin_id → { instance, exports, memory }。
const pluginInstances = new Map();

// 宿主推来的插件贡献描述：plugin_id → JSON。
const pushedContributions = new Map();

// 宿主侧的 push 通道（由 createStudioHostImports 建立时注入）。
let hostPushChannel = null;

// 插件来源清单：由页面在启动时给出（URL 列表 + 对应 id）。
let pluginSources = [];

// 宿主 API 的能力白名单：插件可以 import 的东西。插件 import 了一个
// 这里没给出的函数 → 实例化失败（缺 import），不会「装上但调用时才炸」。
function createPluginImports(pluginId) {
  return {
    studio: {
      ...stringImports(),
      log(message) {
        console.log(`[plugin ${pluginId}]`, readString(message));
      },
    },
  };
}

// 字符串句柄相关的 import（两端共用同一套协议）。
function stringImports() {
  return {
    begin_create_string() {
      return createStringHandle("");
    },
    string_append_char(handle, ch) {
      const entry = stringHandles.get(handle);
      if (entry) {
        entry.value += String.fromCodePoint(Number(ch));
      }
    },
    finish_create_string(handle) {
      return handle;
    },
    begin_read_string(id) {
      return createStringHandle(id === pendingResponseId ? pendingResponse : "");
    },
    string_read_char(handle) {
      const entry = stringHandles.get(handle);
      if (!entry || entry.offset >= entry.value.length) {
        return -1;
      }
      const code = entry.value.codePointAt(entry.offset);
      entry.offset += code > 0xffff ? 2 : 1;
      return code;
    },
    // 按下标读字符（宿主侧用；不推进句柄偏移）。
    string_read_char_at(handle, index) {
      const entry = stringHandles.get(handle);
      if (!entry || index >= entry.value.length) {
        return -1;
      }
      return entry.value.codePointAt(index);
    },
    finish_read_string(handle) {
      stringHandles.delete(handle);
    },
  };
}

// 上一次调用/查询的响应（插件返回的 UTF-8 字节）。
let pendingResponse = "";
let pendingResponseId = 0;

// 加载失败的插件：id → 原因。
//
// **为什么单独记**：宿主侧只从 `plugin_ids()` 拿**已就绪**的插件（成功的
// 才进 `pluginInstances`）。失败的插件不在这个列表里 → 宿主遍历不到 →
// 永远不会上报 `Failed` → 设置面板的「WASM 插件」分组显示「没有已加载
// 的 WASM 插件」，用户以为插件没装。实测（组件形态插件喂给 web 端）：
// 底栏无「插件」页签 + 设置面板说「没有已加载的 WASM 插件」，只有页面
// 底部一行灰色小字——违反「坏插件必须说话」的纪律。
//
// 故失败必须**显式**从 JS 侧报给宿主。
const pluginFailures = new Map();

// 插件的响应区在**它自己**的内存里——每个实例一份，故按实例存。
// 偏移由宿主注入的 ABI 描述给出（见 `registerAbi`）。
function responseAreaOf(entry) {
  if (!entry.responseArea) {
    entry.responseArea = abi.responseOffset;
  }
  return entry.responseArea;
}

/**
 * 注册插件来源（页面启动时调用，在 wasm 实例化之前）。
 * @param {Array<{id: string, url: string}>} sources
 */
export function registerPluginSources(sources) {
  pluginSources = Array.isArray(sources) ? sources.slice() : [];
}

/**
 * 预实例化全部插件（异步）。必须在 wasm 实例化之后、宿主首次调用之前完成；
 * 未就绪的插件在宿主侧表现为「未就绪」而不是报错。
 * @returns {Promise<Array<{id: string, ok: boolean, error?: string}>>}
 */
export async function preloadPlugins(pushContributions = null) {
  const results = [];
  for (const source of pluginSources) {
    try {
      const response = await fetch(source.url);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const bytes = await response.arrayBuffer();
      const { instance } = await WebAssembly.instantiate(bytes, {
        studio: createPluginImports(source.id),
      });
      const entry = { instance, exports: instance.exports, responseArea: 0 };
      pluginInstances.set(source.id, entry);
      // 告知插件响应区位置（它自己内存里的偏移）。C ABI：响应区在插件
      // 内存的偏移 0 处——但插件的内存基址由它自己知道，故传 0（相对
      // 偏移），插件据此在自己的内存里落响应。
      const setResponsePtr = entry.exports[abi.setResponsePtrExport];
      if (typeof setResponsePtr === "function") {
        setResponsePtr(abi.responseOffset);
      }
      results.push({ id: source.id, ok: true });
      // 插件就绪 → **主动把贡献描述推给宿主**（不等宿主来拉：宿主构造
      // runtime 早于插件就绪，拉只会拿到空列表）。
      if (pushContributions) {
        pushContributions(source.id, entry);
      }
    } catch (error) {
      // 失败必须**记住**并报给宿主（见 `pluginFailures` 的说明）。
      pluginFailures.set(source.id, String(error));
      results.push({ id: source.id, ok: false, error: String(error) });
    }
  }
  return results;
}

// 插件的导出名与内存偏移 —— **由宿主注入**（`registerAbi`），
// 不在这里硬编码。
//
// **为什么**：ABI 常量是插件与宿主之间的**契约**，唯一真源在
// `kernel/plugin_contract/plugin_abi.mbt`。两端（native / web）各读
// 同一份定义；若 JS 侧再抄一份，就会出现「改了一处、另一端仍用旧值」
// 的漂移——表现为「web 能加载、native 报 ABI 不兼容」这类只在单端
// 暴露的 bug。
//
// 注入前用**保守默认值**兜底（与契约层当前值一致）——宿主注入是
// 正常路径，默认值只是「注入前就被调用」时的安全网。
const abi = {
  requestOffset: 1024,
  responseOffset: 0,
  callExport: "studio_call",
  describeExport: "studio_describe",
  setResponsePtrExport: "studio_set_response_ptr",
  lengthExport: "studio_last_result_len",
};

/**
 * 注册宿主推送来的 ABI 描述（宿主启动时调用一次）。
 *
 * @param {object} descriptor 来自 `kernel/plugin_contract` 的 JSON 描述
 */
export function registerAbi(descriptor) {
  if (!descriptor || typeof descriptor !== "object") {
    return;
  }
  const pick = (key, fallback) =>
    typeof descriptor[key] === "number" || typeof descriptor[key] === "string"
      ? descriptor[key]
      : fallback;
  abi.requestOffset = pick("request_offset", abi.requestOffset);
  abi.responseOffset = pick("response_offset", abi.responseOffset);
  abi.callExport = pick("call_export", abi.callExport);
  abi.describeExport = pick("describe_export", abi.describeExport);
  abi.setResponsePtrExport = pick(
    "set_response_ptr_export",
    abi.setResponsePtrExport,
  );
  abi.lengthExport = pick("length_export", abi.lengthExport);
}

/**
 * 取当前 ABI 描述（调试用）。
 */
export function abiDescriptor() {
  return { ...abi };
}

/**
 * 读插件内存里的一段 UTF-8 字节。
 */
function readPluginBytes(entry, offset, length) {
  const memory = entry.exports.memory;
  if (!memory || length <= 0) {
    return new Uint8Array(0);
  }
  const view = new Uint8Array(memory.buffer, offset, length);
  return new Uint8Array(view); // 拷贝一份（内存可能被后续调用改写）
}

/**
 * 写插件内存（宿主 → 插件）。
 */
function writePluginBytes(entry, offset, bytes) {
  const memory = entry.exports.memory;
  if (!memory) {
    throw new Error("插件没有导出线性内存");
  }
  new Uint8Array(memory.buffer).set(bytes, offset);
}

/**
 * 调用一个已实例化的插件（标准 C ABI）。
 * @param {object} entry 插件实例记录
 * @param {Uint8Array} request 请求字节
 * @returns {Uint8Array|null} 响应字节（null = 失败）
 */
function invokePlugin(entry, request) {
  const call = entry.exports[abi.callExport];
  if (typeof call !== "function") {
    return null;
  }
  try {
    // 请求写入插件内存的请求区（偏移由宿主注入的 ABI 描述给出）。
    writePluginBytes(entry, abi.requestOffset, request);
    const length = call(abi.requestOffset, request.length);
    if (length < 0) {
      return null;
    }
    // 响应区：插件写在它自己内存的响应区偏移处（宿主已告知）。
    return readPluginBytes(entry, responseAreaOf(entry), length);
  } catch (error) {
    console.warn("[studio plugin] call failed:", error);
    return null;
  }
}

/**
 * 取插件的贡献描述（走 describe 导出）。
 */
function describePlugin(entry) {
  const describe = entry.exports[abi.describeExport];
  if (typeof describe !== "function") {
    return null;
  }
  try {
    const length = describe();
    if (length <= 0) {
      return null;
    }
    return readPluginBytes(entry, responseAreaOf(entry), length);
  } catch (error) {
    console.warn("[studio plugin] describe failed:", error);
    return null;
  }
}

/**
 * 构造「把插件贡献推给宿主」的回调（页面在 preload 后调用）。
 *
 * 宿主**导出**了 `studio_push_contributions`（见 `web_wasm/moon.pkg` 的
 * `link.exports`），JS 侧直接调它即可把贡献写进宿主的进程级槽位。
 */
export function createContributionsPusher(instance) {
  return (pluginId, entry) => {
    const described = describePlugin(entry);
    if (described === null) {
      return;
    }
    const idHandle = createStringHandle(pluginId);
    const jsonHandle = createStringHandle(new TextDecoder().decode(described));
    const push = instance.exports.studio_push_contributions;
    if (typeof push !== "function") {
      console.warn(
        "[studio plugin] host has no studio_push_contributions export; exports=",
        Object.keys(instance.exports).join(","),
      );
      return;
    }
    push(idHandle, jsonHandle);
    // **通知宿主刷新界面**。
    //
    // 为什么必须显式通知：web 端的浏览器事件循环是**按需驱动**的——
    // 没有重绘就没有 rAF 帧，定时器订阅不派发。于是「插件就绪」这件
    // 事若没人告诉宿主，宿主就永远停在首轮的空列表上（底栏的「插件」
    // 页签不出现）。实测：首帧 `ready=0`，直到用户点击界面才 `ready=1`。
    //
    // wasm 的 import 是单向的（宿主 → JS），JS 无法驱动 app 的 update；
    // 故走「宿主导出函数」这条反向通道（同 `studio_push_contributions`）。
    const changed = instance.exports.studio_plugins_changed;
    if (typeof changed === "function") {
      changed();
    }
  };
}

/**
 * 轮询宿主，请它重新加载插件列表（直到插件就绪）。
 *
 * **为什么用 JS 的 `setTimeout` 而不是宿主自己的定时器**：web 端的
 * 浏览器事件循环是**按需驱动**的——wasm 事件循环不跑时，定时器订阅
 * 就不派发（实测首帧 `ready=0` 之后，直到用户点击界面才出现 `ready=1`）。
 * JS 的 `setTimeout` 走浏览器**自己的**任务队列，与 wasm 的事件循环
 * 无关，故必定会被触发。
 *
 * 每次轮询宿主都会：
 *   - 经 program command 驱动 app update（`PluginsLoadRequested`）；
 *   - 宿主重查插件列表 → `PluginsScanned` → model 更新 → 重绘。
 *
 * @param {object} instance wasm 实例
 * @param {number} timeoutMs 总超时（毫秒）
 */
export function pollPluginsUntilReady(instance, timeoutMs = 10000) {
  const reload = instance.exports.studio_reload_plugins;
  if (typeof reload !== "function") {
    console.warn("[studio plugin] host has no studio_reload_plugins export");
    return;
  }
  const deadline = Date.now() + timeoutMs;
  const attempt = () => {
    if (Date.now() > deadline) {
      console.warn("[studio plugin] plugin polling timed out");
      return;
    }
    // 宿主返回**已就绪插件数**——>0 即插件已可用，不必再轮询。
    const ready = Number(reload()) || 0;
    if (ready > 0) {
      return;
    }
    setTimeout(attempt, 250);
  };
  setTimeout(attempt, 50);
}

/**
 * 构造给 wasm 的 import object（宿主侧 `studio.*` 声明）。
 *
 * 这一组是**宿主调用 JS** 的通道（wasm → JS）；插件自己的 import 是
 * **JS → 插件实例** 的另一条通道（见 createPluginImports）。
 */
export function createStudioHostImports() {
  const imports = {
    studio: {
      ...stringImports(),
      is_ready(pluginIdHandle) {
        return pluginInstances.has(readString(pluginIdHandle)) ? 1 : 0;
      },
      contributions(pluginIdHandle) {
        const entry = pluginInstances.get(readString(pluginIdHandle));
        if (!entry) {
          return 0;
        }
        const described = describePlugin(entry);
        if (!described) {
          return 0;
        }
        pendingResponse = new TextDecoder().decode(described);
        pendingResponseId = createStringHandle(pendingResponse);
        return described.length;
      },
      call(pluginIdHandle, requestHandle) {
        const entry = pluginInstances.get(readString(pluginIdHandle));
        if (!entry) {
          return -1;
        }
        const requestText = readString(requestHandle);
        const requestBytes = new TextEncoder().encode(requestText);
        const response = invokePlugin(entry, requestBytes);
        if (response === null) {
          return -1;
        }
        pendingResponse = new TextDecoder().decode(response);
        pendingResponseId = createStringHandle(pendingResponse);
        return response.length;
      },
      take_response_id() {
        return pendingResponseId;
      },
      plugin_ids() {
        // 已就绪的插件 id（逗号分隔）——宿主据此组装「已加载插件」视图。
        const ready = [...pluginInstances.keys()].join(",");
        return createStringHandle(ready);
      },
      plugin_failures() {
        // 加载失败的插件：JSON 对象 `{id: 原因}`。
        //
        // **为什么用 JSON 而不是分隔符拼接**：失败原因是插件运行时给的
        // 原始错误文本（wasm 的 CompileError 文本里含 `=`、`,`、空格，
        // 未来还可能含 `;`），任何分隔符方案都会被内容里的分隔符打破
        // ——实测「原因含 `;`」会把一条失败切成两条（测试已捕获）。
        // JSON 转义一切，是唯一不会与内容打架的编码。
        const payload = {};
        for (const [id, reason] of pluginFailures.entries()) {
          payload[id] = reason;
        }
        return createStringHandle(JSON.stringify(payload));
      },
      log(message) {
        console.log("[studio plugin]", readString(message));
      },
      // 宿主推来插件 ABI 描述（内存偏移、导出名）。
      //
      // **ABI 常量的唯一真源在契约层**（`kernel/plugin_contract/plugin_abi.mbt`），
      // native 与 web 共用。JS 侧不硬编码——否则两处手写副本会漂移。
      set_abi_descriptor(descriptorHandle) {
        const text = readString(descriptorHandle);
        try {
          registerAbi(JSON.parse(text));
        } catch (error) {
          console.warn("[studio plugin] bad ABI descriptor:", error);
        }
      },
    },
  };
  return imports;
}
