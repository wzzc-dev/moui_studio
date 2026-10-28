///|
/// Web 端插件运行时：浏览器原生 WebAssembly 宿主。
///
/// **为什么不是 wasmoon**：wasmoon 的 `wasmoon_runtime` 支持 `native` 与
/// `wasm` 两个 target，但**不支持 `wasm-gc`**（MoonBit 的 wasm-gc 是
/// 与 wasm 不同的后端：GC 引用类型 + 不同的 import 机制）。本仓 web
/// 入口跑在 `wasm-gc` 上（`moui_web_renderer` 的 boot 路径），所以 web
/// 端用**浏览器原生 `WebAssembly`**——这也是浏览器里最自然的选择。
///
/// **与 native 后端的关系**：两个后端**共用同一份契约**
/// （`kernel/plugin_contract`：清单格式、视图协议、宿主 API 面、错误
/// 语义）与**同一个插件 ABI**（标准 C 风格：字符串 = UTF-8 字节 + 显式
/// 长度），上层（app/kernel）**完全 unaware** 后端差异。
///
/// **两段边界，各用各的合适机制**：
///
/// | 边界 | 机制 | 为什么 |
/// | --- | --- | --- |
/// | MoonBit(wasm-gc) ↔ JS | **字符串句柄**（逐字符） | wasm-gc 的 `extern "wasm"` 只能传标量；i32 是 wasm-gc **自己**的内存地址，JS 读它需要那个实例的 memory，而 JS 拿不到别的 wasm-gc 实例的 memory。故只能逐字符搬（照 `wzzc-dev/window/web` 的已验证做法）。 |
/// | JS ↔ 插件实例 | **标准 C ABI**（UTF-8 字节 + 长度） | JS 能访问插件实例的 `exports.memory`（标准 wasm 惯例）→ 直接按字节搬，无需逐字符。 |
///
/// **同步/异步的解法**：浏览器 `WebAssembly.instantiate` 是异步的，
/// 而宿主→插件的调用必须同步（视图渲染路径要拿到视图 JSON）。→ **JS 侧
/// 预实例化**：页面启动时异步加载并实例化插件，实例化完成后，宿主侧的
/// 同步 `studio_call` 只是「查表 + 调导出」。
///
/// **弱隔离（如实声明）**：浏览器 wasm 无资源配额（没有 wasmoon 的
/// `ResourceBudget` 等价物），且 wasm 执行**不可抢占**——一个死循环
/// 插件会卡住主线程。→ web 端只能靠「来源可信 + 能力白名单」。
/// 文档与 UI 必须写明这一点，不得与 native 端并列宣称同等安全。

///|
/// JS 侧字符串句柄（外部类型——它的实现住在 JS 侧）。
#external
pub type WebString

///|
/// 开一个空字符串句柄。
extern "wasm" fn studio_begin_create_string() -> WebString = "studio" "begin_create_string"

///|
/// 往句柄里追加一个字符。
extern "wasm" fn studio_string_append_char(
  handle : WebString,
  ch : Char,
) -> Unit = "studio" "string_append_char"

///|
/// 结束写入（句柄可用）。
extern "wasm" fn studio_finish_create_string(handle : WebString) -> WebString = "studio" "finish_create_string"

///|
/// 读一个字符串句柄（逐字符读）。
extern "wasm" fn studio_begin_read_string(id : Int32) -> WebString = "studio" "begin_read_string"

///|
extern "wasm" fn studio_string_read_char(handle : WebString) -> Int32 = "studio" "string_read_char"

///|
extern "wasm" fn studio_finish_read_string(handle : WebString) -> Unit = "studio" "finish_read_string"

///|
/// 调用插件（C ABI 在 JS 侧实现）：
/// - 入参：插件 id 句柄 + 请求 JSON 句柄（JS 侧转 UTF-8 字节，按 C ABI
///   写进插件内存后调 `studio_call(ptr, len)`）。
/// - 返回：响应字节数（负数 = 失败）。
/// - 响应经 `studio_take_response_id()` 取回。
extern "wasm" fn studio_call(
  plugin_id : WebString,
  request : WebString,
) -> Int32 = "studio" "call"

///|
/// 宿主侧日志（诊断用）：写到浏览器控制台。
extern "wasm" fn studio_host_log(message : WebString) -> Unit = "studio" "log"

///|
/// 读 JS 侧已预实例化的插件 id 列表（逗号分隔）。
///
/// JS 侧在页面启动时预实例化插件（浏览器 instantiate 是异步的），并把
/// 插件 id 列表交给宿主——宿主据此组装「已加载插件」视图。
extern "wasm" fn studio_plugin_ids() -> WebString = "studio" "plugin_ids"

///|
/// 读 JS 侧**加载失败**的插件（`id=原因` 用 `;` 分隔多条）。
///
/// **为什么需要**：宿主只从 `studio_plugin_ids` 拿**已就绪**的插件，
/// 失败的插件不在其中 → 宿主遍历不到 → 永远不会上报 `Failed` →
/// 设置面板显示「没有已加载的 WASM 插件」，用户以为插件没装。
/// 「坏插件必须说话」——故失败必须显式从 JS 侧报上来。
extern "wasm" fn studio_plugin_failures() -> WebString = "studio" "plugin_failures"

///|
/// 取回上一次调用的响应（字符串 id）。
extern "wasm" fn studio_take_response_id() -> Int32 = "studio" "take_response_id"

///|
/// 插件是否就绪（JS 侧预实例化完成）。
extern "wasm" fn studio_is_ready(plugin_id : WebString) -> Int32 = "studio" "is_ready"

///|
/// 取插件的贡献描述（返回长度，响应经 take_response 取回）。
extern "wasm" fn studio_contributions(plugin_id : WebString) -> Int32 = "studio" "contributions"

///|
/// MoonBit 字符串 → JS 侧字符串句柄。
///
/// **逐字符**（照 `wzzc-dev/window/web` 的已验证做法：`web_string_to_extern`
/// 同一模式）——wasm-gc 的 import 只能传标量，字符串必须逐字符搬。
/// 插件描述与视图 JSON 都不大，这个代价可接受。
pub fn string_to_js(text : String) -> WebString {
  let handle = studio_begin_create_string()
  for index in 0..<text.length() {
    studio_string_append_char(handle, text.code_unit_at(index).unsafe_to_char())
  }
  studio_finish_create_string(handle)
}

///|
/// JS 侧字符串句柄 → MoonBit 字符串。
pub fn string_from_js(handle : WebString) -> String {
  let buffer = StringBuilder()
  while true {
    let code = studio_string_read_char(handle)
    if code == -1 {
      break
    }
    buffer.write_char(code.unsafe_to_char())
  }
  studio_finish_read_string(handle)
  buffer.to_string()
}

///|
/// 贡献描述错误列表 → 一句话原因（进 UI 提示）。
fn describe_contrib_errors(
  errors : Array[@plugin_contract.PluginContribError],
) -> String {
  let parts : Array[String] = []
  for error in errors {
    parts.push(error.message())
  }
  parts.join("；")
}

///|
/// 读 JS 侧的插件 id 列表（逗号分隔；空 = 没有插件）。
pub fn web_plugin_ids() -> Array[String] {
  let handle = studio_plugin_ids()
  let text = string_from_js(handle)
  let ids : Array[String] = []
  for part in text.split(",") {
    let trimmed = part.trim()
    if trimmed != "" {
      ids.push(trimmed.to_owned())
    }
  }
  ids
}

///|
/// 解析 JS 侧传来的失败列表（JSON 对象 `{id: 原因}`）→ `[(插件 id, 原因)]`。
///
/// **为什么用 JSON**：失败原因是插件运行时给的原始错误文本（wasm 的
/// CompileError 文本里含 `=`、`,`、空格），任何分隔符方案都会被内容里
/// 的分隔符打破——实测「原因含 `;`」会把一条失败切成两条。
/// JSON 转义一切，是唯一不会与内容打架的编码。
///
/// 纯函数（不碰 extern）——故可被测试直接调用。
pub fn parse_plugin_failures(text : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let payload = @json.parse(text) catch { _ => return out }
  let fields = match payload {
    Object(fields) => fields
    _ => return out
  }
  for (id, value) in fields {
    match value {
      Json::String(reason) => out.push((id, reason))
      _ => out.push((id, "未知原因"))
    }
  }
  out
}

///|
/// 读 JS 侧的插件失败列表 → `[(插件 id, 原因)]`。
pub fn web_plugin_failures() -> Array[(String, String)] {
  let handle = studio_plugin_failures()
  let text = string_from_js(handle)
  parse_plugin_failures(text)
}

///|
/// web 端的最小清单。
///
/// **web 端拿不到清单文件**（浏览器没有文件系统，插件以 URL 提供），
/// 所以这里只带 id——插件管理界面在 web 端显示的是 id 而非作者写的
/// 名字。这是浏览器限制的如实反映，不是偷懒。
fn web_manifest_of(plugin_id : String) -> @plugin_contract.PluginManifest {
  {
    id: plugin_id,
    name: plugin_id,
    version: "",
    description: "",
    entry: "",
    capabilities: [],
    min_api_version: 1,
    // web 端目前只支持**核心 wasm**形态（浏览器原生 `WebAssembly`
    // 不直接吃 component binary——需要 `jco` 转译或 wasm 端运行时）。
    abi: @plugin_contract.AbiCore,
  }
}

///|
/// Web 端插件运行时（浏览器宿主）。
///
/// **插件 id 是动态查询的**，不是构造时的快照——JS 侧的插件预实例化
/// 是**异步**的（浏览器 `WebAssembly.instantiate`），而宿主在
/// `program()` 构造期就建好了本运行时；那一刻插件还没就绪，快照会拿到
/// 空列表。故每次需要时现查 JS 侧。
pub(all) struct PluginRuntimeWeb {
  /// 保留字段：web 端的状态全在 JS 侧（插件实例），宿主侧无实例缓存。
  /// 之所以保留结构体而非空元组——MoonBit 的空结构体需要至少一个字段
  /// （或用 `Unit` 承载），且结构体形态便于将来加宿主侧状态。
  _reserved : Unit
}

///|
/// 建 web 端运行时。
pub fn PluginRuntimeWeb::new() -> PluginRuntimeWeb {
  { _reserved: (), }
}

///|
/// 实时查已就绪插件的贡献描述（插件 id → 贡献 JSON）。
///
/// 每次调用都向 JS 侧现查——插件就绪晚于宿主构造 runtime（浏览器
/// instantiate 异步），缓存只在 push 那一刻更新，而视图渲染随时可能
/// 发生。
pub fn PluginRuntimeWeb::ready_contributions(
  _self : PluginRuntimeWeb,
) -> Map[String, String] {
  let out : Map[String, String] = Map([], capacity=8)
  for plugin_id in web_plugin_ids() {
    match studio_contributions_for(plugin_id) {
      Some(json) => out.set(plugin_id, json)
      None => ()
    }
  }
  out
}

///|
/// 向 JS 侧取某个插件的贡献描述 JSON（同步）。
fn studio_contributions_for(plugin_id : String) -> String? {
  let handle = string_to_js(plugin_id)
  let length = studio_contributions(handle)
  studio_finish_read_string(handle)
  if length <= 0 {
    return None
  }
  let response_id = studio_take_response_id()
  let response_handle = studio_begin_read_string(response_id)
  Some(string_from_js(response_handle))
}

///|
/// 当前已就绪的插件 id 列表（向 JS 侧现查）。
pub fn PluginRuntimeWeb::ready_plugin_ids(
  _self : PluginRuntimeWeb,
) -> Array[String] {
  web_plugin_ids()
}

///|
/// 构造给 app 用的插件门面（跨平台契约）。
///
/// web 端的加载是「JS 侧预实例化 + 宿主侧取贡献描述」——
/// 宿主侧不再真正「加载」，因此 `load` 只回执已有实例的贡献描述。
pub fn plugin_bridge_for(
  runtime : PluginRuntimeWeb,
) -> @plugin_contract.PluginBridge {
  {
    available: true,
    load: fn(on_result) {
      let results : Array[@plugin_contract.PluginLoadResult] = []
      let ready = runtime.ready_plugin_ids()
      studio_host_log(
        string_to_js("plugin load: ready=" + ready.length().to_string()),
      )
      for plugin_id in ready {
        match runtime.contributions_of(plugin_id) {
          Ok(contributions) =>
            results.push(
              @plugin_contract.Loaded(
                manifest=web_manifest_of(plugin_id),
                contributions~,
              ),
            )
          Err(reason) => {
            studio_host_log(
              string_to_js(
                "plugin contributions failed: " + plugin_id + " -> " + reason,
              ),
            )
            results.push(@plugin_contract.Failed(plugin_id~, reason~))
          }
        }
      }
      // **加载失败的插件也要上报**——否则设置面板会说「没有已加载的
      // WASM 插件」，用户以为插件没装（而不是「插件坏了」）。
      // 这在 web 端尤其要紧：失败的插件根本不在 `ready` 列表里。
      for (plugin_id, reason) in web_plugin_failures() {
        studio_host_log(
          string_to_js("plugin load failed: " + plugin_id + " -> " + reason),
        )
        results.push(@plugin_contract.Failed(plugin_id~, reason~))
      }
      on_result(results)
    },
    unload: fn(_plugin_id) { () },
    call: fn(plugin_id, request, on_result) {
      // web 端的插件调用是**同步**的（JS 侧预实例化完成 → 查表 + 调
      // 导出），但门面的形态仍按「回调送回」——两端对 app 的形状一致，
      // app 不感知后端差异。
      on_result(runtime.call(plugin_id, request))
    },
    is_loaded: fn(plugin_id) { runtime.is_ready(plugin_id) },
    // 浏览器**没有文件系统** → 装不了、卸不了插件。
    //
    // 显式声明不可用（而非给一个必然失败的按钮）：UI 据此隐藏
    // 「安装/卸载」入口，并说明「本端不支持安装插件」。
    can_install: false,
    install: fn(_source_dir, on_result) {
      on_result(
        Err("浏览器端不支持安装插件（没有文件系统）"),
      )
    },
    remove: fn(_plugin_id, on_result) {
      on_result(
        Err("浏览器端不支持卸载插件（没有文件系统）"),
      )
    },
    // web 端插件以 URL 提供，没有「插件根目录」概念。
    plugins_root: "",
  }
}

///|
/// 插件是否就绪（JS 侧预实例化完成）。
pub fn PluginRuntimeWeb::is_ready(
  _self : PluginRuntimeWeb,
  plugin_id : String,
) -> Bool {
  let handle = string_to_js(plugin_id)
  let ready = studio_is_ready(handle)
  studio_finish_read_string(handle)
  ready == 1
}

///|
/// 取插件的贡献描述 JSON。
pub fn PluginRuntimeWeb::contributions_of(
  _self : PluginRuntimeWeb,
  plugin_id : String,
) -> Result[@plugin_contract.PluginContributions, String] {
  let handle = string_to_js(plugin_id)
  let length = studio_contributions(handle)
  studio_finish_read_string(handle)
  if length <= 0 {
    return Err("插件未就绪或无贡献描述")
  }
  let response_id = studio_take_response_id()
  let response_handle = studio_begin_read_string(response_id)
  let text = string_from_js(response_handle)
  match @plugin_contract.decode_contributions(text) {
    Ok(value) => Ok(value)
    Err(errors) =>
      Err("贡献描述非法：\{describe_contrib_errors(errors)}")
  }
}

///|
/// 调用插件（请求 JSON 进，响应 JSON 出）。
///
/// 插件 ABI 是标准 C 风格（UTF-8 字节 + 长度）——但**字节搬运在 JS 侧**
/// 完成（JS 能访问插件实例的 `exports.memory`）。MoonBit 侧只负责把
/// 请求 JSON 交给 JS、把响应 JSON 取回（字符串句柄，逐字符）。
pub fn PluginRuntimeWeb::call(
  _self : PluginRuntimeWeb,
  plugin_id : String,
  request : String,
) -> Result[String, String] {
  let plugin_handle = string_to_js(plugin_id)
  let request_handle = string_to_js(request)
  let length = studio_call(plugin_handle, request_handle)
  studio_finish_read_string(plugin_handle)
  studio_finish_read_string(request_handle)
  if length < 0 {
    return Err("插件调用失败（JS 侧报告错误）")
  }
  let response_id = studio_take_response_id()
  let response_handle = studio_begin_read_string(response_id)
  Ok(string_from_js(response_handle))
}
