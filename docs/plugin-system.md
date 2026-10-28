# MoUI Studio 插件系统

MoUI Studio 可以加载**运行时**插件：第三方代码以 WebAssembly 形式被
Studio 加载，贡献命令、面板与界面，并被沙箱化执行。

本文写明：架构、清单格式、视图协议、宿主 API 白名单、资源配额、
两个后端的差异，以及**安全边界**（这一节最重要，请先读它）。

---

## 安全边界（先读）

### 插件运行时不是安全边界

Studio 的插件执行依赖 [wasmoon](https://github.com/Milky2018/wasmoon)
（native 端）与浏览器原生 `WebAssembly`（web 端）。两者都**不是**
经过审计的沙箱：

- wasmoon 官方 README 自述为 **“A slow and insecure runtime for
  WebAssembly”**，并明确写道：

  > The interpreter, JIT native glue, process-level trap handling, WASI
  > host access, component runtime, and proposal implementations should be
  > treated as experimental unless independently audited for the intended
  > deployment. **Do not use the project as a security boundary** or in
  > production merely because a feature is listed as supported.

- 浏览器原生 wasm 同样不是沙箱：它没有资源配额，且 wasm 执行**不可抢占**
  ——一个死循环插件会卡住主线程。

### 因此：只安装可信来源的插件

Studio 的隔离由**宿主侧**的四层构成，而不是由 wasm 运行时提供：

1. **能力白名单**：插件只能 import 宿主明确提供的能力函数。没声明的
   能力**不提供**——插件 import 缺失会导致实例化失败（而不是运行时才
   发现能力不存在）。
2. **不开放 WASI**：插件拿不到文件系统、网络、环境变量。工程文件只能
   经 `studio.workspace_read` / `studio.workspace_write` 访问，且路径经
   宿主校验（限工程根内、拒绝 `..` 与绝对路径）。
3. **资源配额**（native 端）：每个插件独立 `Store` + `ResourceBudget`
   （内存 / 表 / GC / 代码 / 待办工作 / 输入字节 / 编译单元）。
4. **超时**（两端）：单次导出调用有执行时限。

即便如此，**不受信任的插件仍可能经运行时的缺陷影响宿主进程**。
Studio 不提供插件签名、来源校验或权限确认流程——

> **请只安装你信任来源的插件。**

### web 端比 native 端弱

| | native（wasmoon） | web（浏览器原生 wasm） |
| --- | --- | --- |
| 资源配额 | 有（`ResourceBudget`） | **无** |
| 超时终止 | 可取消执行 | 只能**放弃等待**；wasm 不可抢占 |
| 插件来源 | 本地目录扫描 | URL（浏览器无文件系统） |
| 隔离强度 | 较强 | **弱** |

web 端插件应当被视为「与宿主同信任级的代码」。

---

## 架构

```text
组合根 (native: cmd/moui_studio, macos_skia | web: web_wasm)
   │  装配 PluginBridge（native = wasmoon 宿主 | web = 浏览器 wasm 宿主）
   ▼
app (native + wasm-gc)
   │  plugin_state        插件状态切片（描述 / 贡献 / 错误）
   │  plugin_view_interp  视图协议 JSON → @moui.View[Msg]（两端共用一份）
   │  plugin_panels       插件面板（底栏页签）
   ▼
kernel/plugin_contract (native + wasm-gc)
   │  清单格式 / 视图协议 / 贡献描述 / 宿主 API 面 / PluginBridge 契约
   ▼
services/plugin_runtime (native)  |  services/plugin_runtime_web (wasm-gc)
   wasmoon Store 生命周期、宿主函数、配额   浏览器 WebAssembly + JS 胶水
```

**契约共用，执行机制分端**：`kernel/plugin_contract` 定义清单格式、
视图协议、宿主 API 面与错误语义；native 与 web 各实现一份执行后端。
`app` / `kernel` **不感知**后端差异。

---

## 插件目录与清单

插件是**一个目录**，含一份清单与入口 wasm：

```text
.studio/plugins/<plugin-id>/
   plugin.json
   <entry>.wasm
```

`plugin.json`：

```json
{
  "format": "moui.studio.plugin",
  "format_version": 1,
  "id": "com.example.hello",
  "name": "Hello Plugin",
  "version": "1.0.0",
  "description": "示例插件",
  "entry": "hello.wasm",
  "capabilities": ["CapCommands", "CapPanels"],
  "min_api_version": 1,
  "abi": "core"
}
```

字段纪律：

- `format` + `format_version` 是**格式门卫**——不匹配整单拒绝，不猜、不迁移。
  （`format_version` 与插件自己的 `version` 是两回事：前者是文件布局版本。）
- `id` 只允许 `[A-Za-z0-9._-]`；`entry` 必须是**相对**路径且不含 `..`。
- `capabilities` 是**请求**不是许可——宿主按能力白名单决定实际授予什么。
- `min_api_version` 高于宿主 API 版本 → 插件被**跳过**（不是失败）。
- `abi` 是**可选**的（缺省 `core`，既有清单零改动）：`"core"` = 核心
  wasm 模块，`"component"` = WebAssembly 组件（见
  [组件形态](#组件形态component-model)）。未知取值 → 清单被拒
  （**不**静默回落 `core`——那会让组件插件被当核心模块加载，用户看到的
  错误与真实原因不符）。

### 能力枚举

| 能力 | 含义 |
| --- | --- |
| `CapCommands` | 贡献命令 |
| `CapPanels` | 贡献面板 |
| `CapEditor` | 认领某类文档的编辑面 |
| `CapWorkspaceRead` | 读工程文件与状态投影 |
| `CapWorkspaceWrite` | 写工程文件 |
| `CapEvents` | 向事件总线发事件 |

**默认不授予** `CapWorkspaceRead` / `CapWorkspaceWrite`——改用户代码需要
显式信任。

---

## 插件 ABI

插件有**两种 ABI 形态**并存，由清单的 `abi` 字段声明（**缺省 `core`**，
既有插件零改动）：

| 形态 | `abi` | 入口 | 字符串传递 |
| --- | --- | --- | --- |
| 核心模块 | `"core"`（默认） | 核心 wasm 模块 | 手写 C 风格（offset/len + 响应区约定） |
| 组件 | `"component"` | WebAssembly **组件** | **Canonical ABI**（类型化 string） |

两者**行为完全一致**（同样的请求/响应 JSON、同样的视图协议），宿主都认；
差别只在**怎么传字符串**与**ABI 怎么稳定**。

> 组件形态的完整说明见 [组件形态（Component Model）](#组件形态component-model)。

### 用标准 C 风格，不用 MoonBit 的 String

字符串一律是 **UTF-8 字节 + 显式长度**。

**为什么不用 MoonBit 写插件**：MoonBit `wasm` target 的 `String` 是
**GC 引用**（对象布局 `[p-8: kind][p-4: length][p: data]`）。宿主往
guest 内存里写裸字节**不会被插件识别为 String**——实测插件读到的长度
恒为 0，请求内容为空（`kind` 标记不匹配）。宿主也无法构造一个合法的
MoonBit 对象：MoonBit 没有导出内部指针的公开 API。

跨语言 ABI 只能用**标准 C 风格**：宿主与插件都只当字节处理，不涉及
任何 GC 语义。因此插件用 **Rust / C / TinyGo** 等输出
`wasm32-unknown-unknown` 的工具链编写；参考实现是 Rust 版
（`samples/plugin_fixture/`）。

### 导出约定

| 导出 | 签名 | 用途 |
| --- | --- | --- |
| `studio_describe` | `() -> i32` | 贡献描述 JSON（响应字节数） |
| `studio_call` | `(ptr : i32, len : i32) -> i32` | 统一入口：请求 JSON 进，响应 JSON 出 |
| `studio_last_result_len` | `() -> i32` | 上一次返回的字节数 |
| `studio_set_response_ptr` | `(ptr : i32) -> ()` | 宿主告知响应区位置（内存基址随实例而定） |

**调用序列**：

```text
实例化 → studio_set_response_ptr(RESPONSE_OFFSET)
       → 宿主把请求 JSON 写进 guest 内存的 REQUEST_OFFSET
       → studio_call(REQUEST_OFFSET, request_len) → 响应字节数
       → 宿主从 RESPONSE_OFFSET 读回响应字节
```

响应区偏移 `PLUGIN_ABI_RESPONSE_OFFSET` = 0，请求区偏移
`PLUGIN_ABI_REQUEST_OFFSET` = 1024（guest 内存默认 1 页 = 64KB，写在
高端会越界）。

**偏移是相对内存起点的**（不是绝对地址）——这与宿主的内存句柄 API
（wasmoon 的 `Memory::write_byte(offset, ..)`、浏览器的
`Uint8Array(memory.buffer)` 下标）一致，插件与宿主必须同解。

### ABI 常量的唯一真源

上面这些常量（内存偏移、导出名）是**插件与宿主之间的契约**——与请求
格式、视图协议同属一层，故定义在**契约层**：

```
kernel/plugin_contract/plugin_abi.mbt
  ├── PLUGIN_ABI_REQUEST_OFFSET / RESPONSE_OFFSET / *_EXPORT
  └── plugin_abi_descriptor()  → JSON 描述
```

**两端怎么读它**：

| 端 | 怎么拿到常量 |
| --- | --- |
| native | 直接引用契约层的常量（`plugin_host.mbt` 里只是别名，无副本） |
| web | 宿主启动时经 `studio_set_abi_descriptor` import 把 JSON 描述推给 JS；JS 的 `registerAbi()` 收下 |

**为什么 web 不直接写死**：JS 读不到 MoonBit 的常量。曾经两端各硬编码
一份（native 在 `.mbt`、web 在 `plugin_bridge.js`），**没有任何机制保证
同步**——改一处忘另一处，就会出现「web 能加载、native 报 ABI 不兼容」
这类**只在单端暴露**的 bug。

现在 web 侧的值是**宿主推过来的**，故「native 与 web 用同一份 ABI
定义」不只是约定，而是**机制保证**：改契约层的常量，两端同时跟着变。

（JS 侧保留了一份与契约层当前值相同的**兜底默认值**——只在「注入前就
被调用」时生效，正常路径永远是注入值。）

### 两端的两段边界（各用各的合适机制）

插件 ABI 在 native 与 web **完全相同**，但**宿主与插件之间**隔着两段
边界，两段各用各的机制：

| 边界 | native | web |
| --- | --- | --- |
| 宿主 ↔ 插件 | 直接读写 guest 内存（同一实例） | JS 侧读写插件的 `exports.memory` |
| 宿主 ↔ JS | 不存在 | **字符串句柄**（逐字符） |

web 端为什么需要字符串句柄：wasm-gc 的 `extern "wasm"` 只能传标量，
i32 是 wasm-gc **自己**的内存地址——JS 读它需要那个实例的 memory，
而 JS 拿不到别的 wasm-gc 实例的 memory。故 MoonBit ↔ JS 只能逐字符搬
（照 `wzzc-dev/window/web` 的已验证做法），而 JS ↔ 插件可以直接按字节
（JS 拿得到插件实例的 memory）。

### 插件不能有 `println`

宿主**不提供 WASI**（沙箱的一部分）。MoonBit 的 `println` 会引入
`wasi_snapshot_preview1.fd_write` import → 插件**实例化失败**。
插件要输出信息，走宿主函数或返回值，不要用标准输出。

### 贡献描述格式

```json
{
  "format": "moui.studio.plugin.contrib",
  "format_version": 1,
  "panels": { "main": "主面板" },
  "commands": { "reset": "重置" }
}
```

### 视图协议格式

插件贡献的界面是一棵**声明式 JSON 树**（不是闭包——闭包无法跨 WASM
边界搬运）：

```json
{
  "format": "moui.studio.plugin.view",
  "format_version": 1,
  "key": "root",
  "node": "Column",
  "children": [
    { "key": "label", "node": "Text", "text": "你好" },
    { "key": "btn", "node": "Button", "label": "点我", "action": "increment" }
  ]
}
```

**白名单节点**：`Column` / `Row` / `Text` / `Button` / `TextField` /
`Checkbox` / `Spacer` / `Divider` / `LabeledBox`。

修饰字段：`width` / `height` / `padding` / `spacing` / `background` /
`foreground` / `font_size` / `weight` / `key`。

颜色格式：`#RRGGBB` 或 `#AARRGGBB`（非法值在解码阶段被拒，不会静默忽略）。

**交互不跨界传闭包**：控件的 `action` 是一个字符串 id；宿主把它转成
`Msg::PluginAction(plugin_id, action_id, payload)`，由 update 侧决定
是否回问插件。

### 面板视图怎么加载

插件的面板**按需加载**（不预载全部面板）：

```text
插件加载完成 / 切到插件页签
  └─ 派生：找出「已加载 + 启用 + 有面板贡献 + 视图未拿到 + 未请求过」的面
      └─ 发 Msg::PluginPanelRequest(plugin_id, panel_id)
          └─ 宿主向插件发视图请求（format = moui.studio.plugin.viewreq）
              └─ 插件回一份视图协议 JSON
                  └─ 回执 Msg::PluginPanelSpec(plugin_id, panel_id, json)
                      └─ 缓存 → 下次渲染解释成 @moui.View
```

**「未请求过」的守卫是必需的**：面板每次重渲都会走到派生点，没有它就会
把 worker 队列打满（同一个面堆积成百上千个请求）。

视图请求与动作请求**形态不同**，插件靠请求的 `format` 区分：

| 请求 | `format` | 插件该回什么 |
| --- | --- | --- |
| 视图请求 | `moui.studio.plugin.viewreq` | 该面板的视图协议 JSON |
| 动作请求 | `moui.studio.plugin.action` | 处理后的**新**视图协议 JSON |

### 交互不跨界传闭包

控件的 `action` 是一个字符串 id；宿主把它转成
`Msg::PluginAction(plugin_id, panel_id, action_id, payload)`，由 update
侧决定是否回问插件。**消息带面板 id** 是必需的——插件处理动作后回的是
一份**新视图**，宿主要靠它把新视图归到正确的面板（否则新视图进不了
缓存，界面不重绘）。

第一版**不支持**插件自定义绘制（`PaintContext` 不可序列化）。

### 动作请求格式

```json
{
  "format": "moui.studio.plugin.action",
  "format_version": 1,
  "plugin_id": "com.example.hello",
  "action_id": "increment",
  "payload": ""
}
```

---

## 宿主 API 白名单

| import | 语义 | 需要的能力 |
| --- | --- | --- |
| `studio.log(message)` | 写日志 | 无（基础） |
| `studio.state_get(key)` | 读插件私有状态 | 无 |
| `studio.state_set(key, value)` | 写插件私有状态 | 无 |
| `studio.action_dispatch(action, payload)` | 触发宿主动作 | `CapCommands` |
| `studio.emit_event(name, payload)` | 发事件到事件总线 | `CapEvents` |
| `studio.workspace_read(path)` | 读工程文件 | `CapWorkspaceRead` |
| `studio.workspace_write(path, content)` | 写工程文件 | `CapWorkspaceWrite` |

**没声明的能力一律不提供**——插件 import 缺失会导致实例化失败，
而不是「装上了但调用时才失败」。

---

## 在 Studio 里管理插件

### 两个入口

| 入口 | 位置 | 说明 |
| --- | --- | --- |
| **插件管理面板** | 命令面板 →「插件管理」（分组「插件」） | **独立模态对话框**——装/卸/详情都在里面 |
| 设置面板 | 设置 →「WASM 插件」分组 | 列出已加载插件 + 启停；含一个「插件管理」入口按钮 |

**为什么要独立面板**：成熟 IDE 的插件管理都是独立面板（VS Code 的扩展页、
JetBrains 的插件设置）——它要装/卸/看详情/看状态，设置面板塞不下，也不该塞
（设置是「配置」，插件管理是「操作」）。

**命令面板入口是必需的**：设置面板内容超长，插件那一组在**滚动区下方**——
web 端实测点不到（语义节点落在视口外，点击落空）。命令面板不受滚动影响。

### 插件管理面板里有什么

- **安装插件**按钮：选一个插件目录（含 `plugin.json` 与入口 wasm），
  校验后复制到插件根目录。**本端不支持时不给按钮**，只说明原因
  （浏览器没有文件系统）——不给必然失败的按钮。
- **插件列表**：每个插件一行——名字（**可点，展开详情**）、版本、职责，
  右侧是启用/禁用与卸载。
- **详情**（选中后展开）：能力、贡献的面与命令、ABI 形态（core / component）。
- **加载失败**的插件：列出来 + 原因（**无卸载按钮**——它没装上，卸什么？）。
- **操作回执**：装完/卸完都要说话（含失败原因）——点了没反应会让人以为没生效。

### 禁用 ≠ 卸载

| | 禁用 | 卸载 |
| --- | --- | --- |
| 做什么 | 只过滤贡献项入口 | **删插件目录**（递归） |
| 可逆 | 是（再启用即可） | **否** |
| 确认 | 不需要 | **需要**（走 `pending_confirm` 确认卡，`CkUninstallPlugin`） |
| 插件还在列表里 | 是 | 否 |

卸载是**不可逆**的破坏性操作，故必须经确认卡——与删控件/删工程文件同一纪律。

### 安装的校验

装之前逐项检查（`services/plugin_runtime/plugin_install.mbt`）：

1. 源目录存在且是目录；
2. 清单存在且合法（格式 + 版本门卫）；
3. 入口文件在源目录里存在；
4. **目标未装过**（不覆盖——升级需先卸载）；
5. 卸载时校验插件 id 合法（防 `..` 拼出插件根目录之外的路径）。

复制**而非移动**（用户的源目录不动）；卸载**递归**（`@x/fs.remove_dir`
底层是 `rmdir`，非递归，只删空目录，故自己走文件→子目录→目录）。

### 设置面板 →「WASM 插件」分组

- 列出**已加载**的插件：名字、版本、职责（都来自插件清单），
  右侧是启用/禁用开关。
- 列出**加载失败**的插件：插件 id + 失败原因。失败插件没有开关
  ——它没加载上，给一个开关是假的。

启用/禁用走的是与内置插件**同一份**禁用清单（`plugin_disabled`），
所以两者的语义一致，持久化键也相同。

**内置插件**（ai / terminal / markdown）在上一组里——它们是**静态
装配**的，启停只是过滤贡献项入口；WASM 插件是**运行时加载**的，有
自己的生命周期与失败态。两组分开呈现，不混在一张表里。

### 插件从哪来

| 端 | 来源 | 原因 |
| --- | --- | --- |
| native | `<工程根>/.studio/plugins/<plugin-id>/` | 本地目录扫描（`.studio/` 在 `.gitignore` 里，插件不入版本库）；**可从任意目录安装** |
| web | URL（页面启动时注册） | 浏览器没有文件系统，本地目录扫描与安装卸载在 web 端**不可达** |

native 端的扫描根是**相对当前工作目录**的 `.studio/plugins`——从工程根
启动 Studio 才能找到插件。

---

## 生命周期与并发

- **加载**在后台 worker 上跑（插件是不受信任的代码，绝不在 UI 线程同步
  执行——一个死循环插件会冻住界面）。回执经 `Msg::PluginsScanned` 进
  update。
- **失败隔离**：一个插件坏（清单错、wasm 校验失败、实例化失败、运行期
  trap）不影响其余插件；失败原因进插件管理面板，不会静默消失。
- **调用串行化**：wasmoon 的 `Store` 绑定创建线程 → 同一插件的调用串行。
- **卸载**：`Store::close()` 释放内存 / 表 / GC 域与配额（幂等）；卸载后
  再调用得到明确错误，不是 use-after-close。

---

## web 端（浏览器）后端

web 端用**浏览器原生 `WebAssembly`**，不是 wasmoon——wasmoon 的运行时
包支持 `native` 与 `wasm` target，但**不支持 `wasm-gc`**，而本仓 web
入口跑在 `wasm-gc` 上。

- 浏览器 `WebAssembly.instantiate` 是**异步**的，而宿主→插件的调用必须
  同步 → **JS 侧预实例化**：页面启动时异步加载并实例化插件；就绪后宿主
  的同步调用只是「查表 + 调导出」。
- 插件来源是 **URL**（浏览器没有文件系统，本地目录扫描在 web 端不可达）。
- JS 胶水：`web_wasm/plugin_bridge.js`。

### 时序：插件就绪后如何通知宿主

浏览器事件循环是**按需驱动**的：没有重绘就没有 rAF 帧，
`web_timer_dispatch_due()` 不跑，定时器订阅（包括插件重试节拍）
就不派发。于是「插件就绪」这件事**若没人告诉宿主，宿主就永远停在
首轮的空列表上**——底栏的「插件」页签不出现。

实测（浏览器控制台）：

```text
[studio plugin] plugin load: ready=0     ← 页面加载时（插件还没就绪）
…用户点击界面后…
[studio plugin] plugin load: ready=1     ← 重绘唤醒事件循环，重试节拍才跑
```

即：**静止时那条「每 300ms 重查插件」的定时器链是死的**。

**宿主自己的定时器救不了**：web 端 rAF 由 `window.request_redraw`
排起，而那条路只在 wasm 自己的事件循环里生效——JS 从 wasm 外部同步
调宿主导出函数时，wasm 的事件循环并没有在跑。实测：通知后脏标记确实
设上了（`needs_redraw=true needs_rebuild=true`），但重试节拍始终不发。

故改由 **JS 的 `setTimeout`** 轮询（浏览器**自己**的任务队列，与 wasm
的事件循环无关，故必定触发）：

```text
JS 侧 preloadPlugins() 完成
  └─ studio_push_contributions(id, json)   → 宿主写入进程级槽位
  └─ studio_plugins_changed()              → 宿主强制重建 + 重绘
  └─ setTimeout 轮询 studio_reload_plugins() → 宿主重查插件列表
        └─ dispatch_action_command(重载插件命令)
              └─ dispatch(PluginsLoadRequested) → app update
                    └─ PluginsScanned → model 更新 → 插件页签出现
```

三个函数都是**宿主导出**给 JS 调的（`web_wasm/moon.pkg` 的
`link.exports`）——wasm 的 import 是单向的（宿主 → JS），JS 无法
反向驱动 app 的 update，故只能走导出这条反向通道。

**为什么用 program command 驱动 app update**：
`AppRuntime::dispatch_action_command` 会**同步**调 runtime 的 dispatch
闭包（`handle()` → `dispatch(消息)`），**不依赖 rAF**——故从 wasm 外部
调用也必定生效。命令本身必须**稳定**（`Eq` 比对整个 `ActionCommand`，
含 label / group），故用固定文案而非 i18n。

宿主侧的「强制重建」用**同尺寸 `Resize`** 表达：
`RuntimeState::dispatch_event` 的 `Resize` 分支会
`request_root_rebuild` + 置脏重绘，而尺寸赋值是同值——故它只当
「强制重建并重绘」用，不改视口。

### 单一渲染路径（web 与 native 同款）

插件的视图**一律**来自 model 缓存的 `panel_spec`（`PluginPanelSpec`
消息回填）。web 端与 native 端**同一条路径**。

曾经 web 端另有一条「渲染期实时问插件」的绕行路径（进程级槽位 +
同步调用），它有三个问题，故已删除：

1. **重复渲染**——web 插件的贡献也进 model 的 `descriptors`，两条路径
   都渲染 → 同一个插件的面出现两份（且内容不同：实时路径带最新动作，
   缓存路径是首次快照）。
2. **每帧调插件**——渲染期同步调用插件。插件是**不受信任的代码**，
   不该在渲染路径上跑（只该在 effect 里跑）。
3. **状态竞争**——实时路径的视图请求会覆盖动作刚记下的状态。

配套地，**加载回执是幂等的**：`PluginState::apply_load_results` 按插件
id **替换**而非追加——同一个插件被重载（web 端轮询、native 端重扫）
时不会在列表里堆多份。

### 插件侧的请求区分

`studio_call` 是视图请求与动作请求的**统一入口**，插件靠请求 JSON 的
`format` 字段区分（`moui.studio.plugin.viewreq` / `moui.studio.plugin.action`）。

**插件只在收到动作请求时才改状态**——视图请求不动计数与「最后动作」。
否则宿主每次渲染都问一次视图时，刚记下的「最后动作」会被随后的视图
请求抹掉（界面回到 `last=` 空）。

---

## 组件形态（Component Model）

插件也可以是 **WebAssembly 组件**（而非核心模块）——清单写
`"abi": "component"`。

### WIT 定义

组件形态的 ABI 由 WIT 声明（`kernel/plugin_contract/wit/plugin.wit`）：

```wit
package moui:plugin@0.1.0;

interface plugin {
  describe: func() -> string;                 // 贡献描述 JSON
  call: func(request: string) -> string;      // 请求 JSON → 响应 JSON
}

world plugin-world {
  export plugin;
}
```

**与核心模块形态的差别**：

| | 核心模块 | 组件 |
| --- | --- | --- |
| 字符串 | 手写字节搬运（offset/len + 响应区） | **Canonical ABI 自动编解码** |
| 类型 | 自己约定 | **WIT 声明**，编译期检查 |
| 导出查找 | `Function::from_export(name)` | `instance.bind("moui:plugin/plugin@0.1.0#call")` |
| 跨语言 | 需手写 ABI | 官方 `wit-bindgen`（Rust/TS/C/C++/MoonBit） |
| 宿主能力 | 宿主函数白名单 | **无**（world 只 export 不 import） |

**沙箱不放松**：组件形态**不注册任何宿主函数**——它是比核心模块**更
严格**的一档（核心模块能按能力白名单拿到宿主函数，组件拿不到）。

### 字符串编码：MoonBit 组件是 UTF-16

**Canonical ABI 的 `string` 在 MoonBit 组件里是 UTF-16LE**（MoonBit 的
`String` 内部即 UTF-16），不是 UTF-8。

实测：按 UTF-8 降级 → 宿主按 UTF-16 解读 → 乱码（`≻潦浲瑡㨢洢畯`
就是 `"studio_describe"` 的 UTF-16 编码）。改按 UTF-16 降级 → 往返正确。

这是**组件形态唯一的坑**，且只在 MoonBit 侧出现（Rust/TS 的
`wit-bindgen` 生成的胶水自己处理）。

### 构建流程

```sh
sh scripts/build_plugin_component.sh
# → samples/plugin_fixture_component/dist/plugin_fixture.component.wasm
```

三步（标准链路）：

```sh
moon run --target wasm --release src/impl/main.mbt   # ① 核心 wasm
wasm-tools component embed wit <core.wasm> -o e.wasm --encoding utf16  # ② 嵌 WIT
wasm-tools component new e.wasm -o plugin.component.wasm              # ③ 组件
```

**注意**：`moon build --target wasm` **不产出二进制**（只出 WAT）——要用
`moon run` 才链接出 wasm。

### 参考实现

`samples/plugin_fixture_component/` 是 MoonBit 写的组件形态参考实现
（与 `samples/plugin_fixture` 的 Rust 核心模块版**行为一致**）。

它的 Canonical ABI 胶水是**手写**的（`src/cabi/cabi.mbt`）：MoonBit
`wasm` target 的内联 wasm 白名单不含 `$moonbit.init_array8` 等 GC 内部
函数，而 `wit-bindgen` 生成的胶水依赖它们。故用纯线性内存操作实现
bump 分配器与字符串编解码。

### 现状与限制

- **native 端**：✅ 完整支持（wasmoon 0.18.0 原生支持 Component Model——
  `Milky2018/wasmoon/component`）。端到端测试见
  `services/plugin_runtime/plugin_component_e2e_wbtest.mbt`。
- **web 端**：❌ **暂不支持**。浏览器原生 `WebAssembly.instantiate`
  不直接吃 component binary——需要 `jco transpile` 转成 JS 胶水 +
  核心 wasm，或引入 wasm 的 wasm 端运行时。web 端目前仍是核心模块
  形态（清单的 `abi` 字段在 web 端按 `core` 处理）。
  实测行为与用户可见性见「当前形态的边界」章节。

### 与「视图协议」的关系

组件形态只解决**插件 ABI** 这一层的序列化。**视图协议仍是 JSON**——
因为它要跨到 `@views.*` 解释器（`View[Msg]` 带闭包，闭包无法跨
WASM 边界）。

故当前是**两层编码**：

```text
插件 ──WIT（自动）──> 宿主 ──JSON（手写）──> @views.* 解释器
```

**更正（曾误判）**：早先以为「视图协议迁 WIT 就得动 Moui 的 core」
（要把 `ViewNode` 的数据部分抽出来可序列化）。读代码后确认**这个前提
不成立**：

- 视图协议**从不触碰** `ViewNode`。`kernel/plugin_contract` 整个包
  **不 import moui**（只依赖 `moonbitlang/core/json` 与 `debug`），
  协议节点集是自有的 `PluginViewNode` 枚举（9 个白名单节点）。
- `@views.*` 只出现在**宿主侧解释器** `app/plugin_view_interp.mbt`，
  那里已经是宿主自己的代码，把 JSON 换成 WIT 值不改变它的位置。
- `ViewNode` 是 16 方法的 open trait，**闭包确实不能跨界**——但闭包
  一直都在宿主侧构造（`on_click` 传 `Msg`、`checkbox` 的
  `(Bool) -> Msg`），协议里只传 **action id 字符串**。

所以迁视图协议是**契约层内的自闭环改造**，不涉及跨仓库改动。
详见「视图协议迁到 WIT 的影响评估」。

---

## 当前形态的边界（web 端暂不支持组件形态）

**现状是可行且有意的**：native 端完整支持组件形态，web 端继续用核心模块
形态，等浏览器原生支持组件运行时再统一。

### 实测行为

把一个**组件形态**插件喂给 web 端（浏览器实测）：

```text
fetch 成功 → 14439 字节
WebAssembly.instantiate() 失败：
  CompileError: expected version 01 00 00 00, found 0d 00 01 00 @+4
```

`0d 00 01 00` 是**组件 binary 的 magic**（核心模块是 `00 61 73 6d`），
浏览器按核心模块解析 → 版本检查失败。`WebAssembly.compile()` 同样失败。

### 用户看到什么

| 位置 | 表现 |
| --- | --- |
| 底栏 | **没有「插件」页签**（没有可用插件 → 页签不出现，与既有纪律一致） |
| 设置面板「WASM 插件」 | 列出 `com.example.fixture` + `加载失败：<原因>` |
| 页面底部状态行 | `插件加载失败: com.example.fixture (CompileError: …)` |

### 一个曾存在的缺陷（已修）

web 端原本**只把「已就绪」的插件报给宿主**——失败的插件根本不在
`plugin_ids()` 列表里，宿主遍历不到，于是永远不会上报 `Failed`。
结果：设置面板显示「**没有已加载的 WASM 插件。**」，用户以为插件没装，
而不是「插件坏了」——违反「坏插件必须说话」的纪律。

修法：JS 侧记录失败（`pluginFailures`），经新增 import
`studio_plugin_failures` 显式报给宿主；宿主侧解析后并入
`PluginLoadResult::Failed`。

**失败列表用 JSON 编码**（`{id: 原因}`）而非分隔符拼接——失败原因是
插件运行时的原始错误文本（wasm 的 `CompileError` 文本含 `=`、`,`、空格），
任何分隔符方案都会被内容里的分隔符打破。实测「原因含 `;`」会把一条失败
切成两条（测试已锁住）。

---

## 影响评估：两个待做项

本节记录两项**尚未实施**的后续改造的真实成本（基于对当前代码的
实测核查，不是估计）。

### 1. web 端组件形态支持

**结论：中等偏大，但有明确路径，不需改 moui。**

瓶颈不在宿主，在**浏览器**。官方 WebAssembly Feature Status 数据
（`webassembly.org/features.json`）中，`componentModel` 的 phase 是 **1**，
且 Chrome / Firefox / Safari / Node.js **四个平台的 features 表里都没有
`componentModel` 条目**——即浏览器尚无组件运行时。（对比：`gc` 在
Chrome 119 / Firefox 120 / Safari 18.2 均已支持，列在表里。）

所以 web 端吃 component binary 只有两条路：

| 方案 | 做法 | 代价 | 风险 |
| --- | --- | --- | --- |
| **A. `jco transpile`** | 构建期把组件转成「JS 胶水 + 核心 wasm」，web 端只加载核心 wasm | 引入 Node 构建期依赖（本机当前**未装** `jco`；node v18 可用）；胶水代码进 bundle | `jco` 对 MoonBit 组件无官方支持——本仓组件是**手写 Canonical ABI** 的（`samples/plugin_fixture_component/src/cabi/`），`jco` 的胶水生成器认不了这种自定义导出 |
| **B. wasm 端运行时** | 把 wasmtime/wasmer 编译成 wasm 跑在浏览器里 | 体积巨大（wasmtime wasm 后端数十 MB）、启动慢 | 需要 WASI 能力，**与沙箱纪律冲突**（不能给插件开文件系统） |

**代价换算**：方案 A 若可行，改动集中在 `web_wasm/plugin_bridge.js`
——现有加载路径是 `WebAssembly.instantiate(bytes, imports)` +
按 `abi.callExport` / `abi.describeExport` 取导出（`plugin_bridge.js:138-267`）。
组件形态要换成「转译后的胶水模块」，并新增 `abi` 分支。宿主侧
`services/plugin_runtime_web/runtime_web.mbt` 的 `web_manifest_of` 现在
**硬编码 `abi: AbiCore`**（`runtime_web.mbt:169`），要改成按清单读。

**但 A 有个硬伤**：`jco` 的价值在于自动生成 Canonical ABI 胶水，而本仓
的 MoonBit 组件是手写 ABI（因为 MoonBit `wasm` target 的内联白名单不含
`$moonbit.init_array8` 等 GC 内部函数，`wit-bindgen` 生成的胶水跑不起来，
详见「组件形态」章节）。手写 ABI 的组件**没法用 `jco` 转译**——除非给
MoonBit 组件换一条能产出标准 ABI 的路（比如 Rust 写组件，或让
`wit-bindgen` 支持 MoonBit）。

→ **建议**：web 端组件形态**暂缓**，等浏览器原生支持或 MoonBit 侧
有标准 ABI 产出路径。当前 native 端已完整支持组件形态，web 端继续用
核心模块形态，是合理且有意的分层。

### 2. 视图协议迁到 WIT

**结论：比早先判断的小得多——契约层内自闭环，不改 moui。**

**早先的误判**：曾认为迁视图协议要「动 Moui core，把 `ViewNode` 的
数据部分抽出来可序列化」。核查后这个前提不成立：

| 核查项 | 事实 |
| --- | --- |
| 契约层依赖 | `kernel/plugin_contract/moon.pkg` 只 import `moonbitlang/core/json` 与 `debug`，**完全不 import moui** |
| `ViewNode` 是否被触及 | 插件链路**从不引用** `ViewNode`——全仓只有 `services/export/kernel_runner.mbt` 里一段 `#|` 注释掉的死代码提到它 |
| 闭包在哪 | `on_click` 传 `Msg`（非闭包）；`checkbox` 的 `(Bool) -> Msg` 与 `text_field` 的 `(String) -> Msg` **都在宿主侧构造**（`app/plugin_view_interp.mbt:160-169`），协议里只传 action id 字符串 |
| `@views.*` 位置 | 只出现在**宿主侧解释器** `app/plugin_view_interp.mbt`，它本来就在宿主，不在契约层 |

**真实改动量**（当前协议是 9 个白名单节点 + 8 个修饰字段）：

| 文件 | 现状 | 迁 WIT 后 | 量级 |
| --- | --- | --- | --- |
| `kernel/plugin_contract/wit/plugin.wit` | 12 行（只声明 `describe`/`call`） | 加 `view` 接口：`variant node` + `record spec` + `record modifier` | ~40 行 WIT |
| `kernel/plugin_contract/plugin_view.mbt` | 268 行（枚举 + JSON 编码） | 枚举保留，**删掉 encode 侧** | 减 ~100 行 |
| `kernel/plugin_contract/plugin_view_codec.mbt` | 203 行（JSON 解码） | **整体删除**，换成 WIT 解码 | 减 ~200 行 |
| `app/plugin_view_interp.mbt` | 196 行 | 改 `decode_view` 的输入类型；**解释逻辑不动** | 改 ~20 行 |
| `services/plugin_runtime/runtime.mbt` | 按 abi 分派 | 组件分支多一条「取视图」路径 | 改 ~40 行 |
| `services/plugin_runtime_web/runtime_web.mbt` | JSON 字符串往返 | 组件分支要过 JS（**见下**） | 改 ~60 行 |

**关键收益**：JSON 编解码那 ~300 行手写代码**可以整体删掉**，换成
Canonical ABI 自动编解码。协议从「手写 JSON + 门卫 + 错误分类」变成
「WIT 声明 + 编译器检查」。这比现在更安全，不是更花哨。

**真正的难点在 web 端**：JS 侧要吃组件的 Canonical ABI 值。浏览器没有
组件运行时，JS 胶水只能处理**核心 wasm**——组件的 `record`/`variant`/
`list` 需要在 JS 侧手写解码（`ComponentValue` 的 `Record`/`Variant`/
`List` 变体在 wasmoon 侧是现成的，JS 侧没有）。

→ **建议**：视图协议迁 WIT 的**前置条件是 web 端组件形态先落地**。
在浏览器没有组件运行时之前，迁了也只有 native 端能用，web 端还得
留 JSON 路径——**两套编码并存比一套更糟**。故正确顺序是：
先 web 端组件形态 → 再统一迁视图协议；或干脆等浏览器原生支持后一起做。

---

## 参考实现

`samples/plugin_fixture/` 是一个最小插件：声明一个面板与一条命令，
按钮点击后计数 +1 并重绘面板。

```sh
sh scripts/build_plugin.sh          # → samples/plugin_fixture/dist/plugin_fixture.wasm
```

（`moon build --target wasm` 只产出 WAT；`scripts/build_plugin.sh` 用
`wasm-tools parse` 转成二进制 wasm——宿主加载的是二进制。）

`samples/plugin_fixture_component/` 是同一套行为的**组件形态**版本
（MoonBit 写，走 Canonical ABI）。

```sh
sh scripts/build_plugin_component.sh
# → samples/plugin_fixture_component/dist/plugin_fixture.component.wasm
```

---

## 相关文档

- [DSL 规范](dsl-spec.md)
- [程序 IR 与 `.studio.json` 格式](ir-schema.md)
