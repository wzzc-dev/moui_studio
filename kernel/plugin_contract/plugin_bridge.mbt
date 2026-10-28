///|
/// 插件契约·运行时门面：**跨平台**的插件运行时接口。
///
/// 为什么在这里：`app` 是 `native+wasm-gc`，而两个后端（native 的 wasmoon
/// 宿主 / web 的浏览器 wasm 宿主）都是平台专属包。app 若直接 import 它们，
/// 就会被迫只支持一个平台。→ 门面定义在跨平台契约层，两个后端各实现
/// 一份，app 只认这个接口。
///
/// **能力缺席即降级**：`PluginBridge::unavailable()` 是缺省值——没装配
/// 插件运行时的入口（教学版 profile、测试入口）用它，UI 不显示插件入口
/// （与 `ai_available=false` 同款纪律）。

///|
/// 插件运行时门面。
pub(all) struct PluginBridge {
  /// 本端是否装配了真实的插件运行时（false = UI 不显示插件入口）。
  available : Bool
  /// 扫描并加载全部插件。**异步**：结果经 `on_result` 回调送回
  /// （插件是不受信任的代码，加载必须在 worker 上跑，不能在 UI 线程
  /// 同步执行——一个坏插件会把界面冻住）。
  load : ((Array[PluginLoadResult]) -> Unit) -> Unit
  /// 卸载单个插件。
  unload : (String) -> Unit
  /// 调用插件（请求 JSON 进，响应 JSON 出）。
  ///
  /// **异步**：结果经 `on_result` 回调送回。原因同 `load`——插件是
  /// 不受信任的代码，只能在 worker 上跑；同步门���无法等异步结果
  /// （在 UI 线程等回执会冻住界面）。
  call : (String, String, (Result[String, String]) -> Unit) -> Unit
  /// 插件是否已加载。
  is_loaded : (String) -> Bool
  /// **安装能力**：本端能否安装插件（false = UI 不显示「安装」入口）。
  ///
  /// **为什么要有**：浏览器没有文件系统，装不了插件——此时必须**显式**
  /// 说「本端不支持安装」，而不是给一个必然失败的按钮（与
  /// `export_available` 的纪律同款）。
  can_install : Bool
  /// **安装插件**：从本地目录安装（复制插件目录到插件根目录）。
  ///
  /// 参数是**源目录**（用户选的那份插件，含 `plugin.json` 与入口 wasm）。
  /// 回执：成功 = 插件 id；失败 = 原因（**必须能说清为什么**）。
  ///
  /// **异步**：与 `load` 同理（文件 I/O + 校验都不该在 UI 线程跑）。
  install : (String, (Result[String, String]) -> Unit) -> Unit
  /// **卸载插件**：删除插件目录（破坏性操作，UI 侧须先经确认卡）。
  ///
  /// 回执：成功 = 插件 id；失败 = 原因。
  remove : (String, (Result[String, String]) -> Unit) -> Unit
  /// 插件根目录（UI 展示用——让用户知道插件装在哪）。
  /// 空 = 本端没有插件目录概念（web 端）。
  plugins_root : String
}

///|
/// 加载结果（跨平台口径：native 与 web 共用同一形状）。
pub(all) enum PluginLoadResult {
  /// 加载成功：清单 + 贡献描述
  ///
  /// **带完整 manifest**（不只是 id）：宿主要在插件管理界面显示插件的
  /// 名字、版本与职责说明——只给 id 的话，界面只能把 id 当名字显示，
  /// 插件作者写的信息就白写了。
  Loaded(manifest~ : PluginManifest, contributions~ : PluginContributions)
  /// 加载失败（记原因；不阻断其余插件）
  ///
  /// 带 manifest 是「**尽可能**」——清单本身坏掉时拿不到 manifest，
  /// 此时 `plugin_id` 是从目录名兜底推断的（用于让错误可归因）。
  Failed(plugin_id~ : String, reason~ : String)
  /// 跳过（不兼容等，非错误）
  Skipped(reason~ : String)
}

///|
/// 不可用门面：没有插件运行时的入口用它。
///
/// 所有动作都是安全的空操作——**不报错**（教学版 profile 与测试入口
/// 不该因为「没有插件功能」而崩溃），但也不假装有插件。
pub fn PluginBridge::unavailable() -> PluginBridge {
  {
    available: false,
    load: fn(on_result) { on_result([]) },
    unload: fn(_plugin_id) { () },
    call: fn(_plugin_id, _request, on_result) {
      on_result(Err("本端没有插件运行时"))
    },
    is_loaded: fn(_plugin_id) { false },
    // 本端没有插件运行时 → 谈不上装/卸插件：**显式不可用**。
    can_install: false,
    install: fn(_source_dir, on_result) {
      on_result(Err("本端没有插件运行时"))
    },
    remove: fn(_plugin_id, on_result) {
      on_result(Err("本端没有插件运行时"))
    },
    plugins_root: "",
  }
}

///|
/// 装配真实运行时：把可用性标记为真。
///
/// `can_install` / `install` / `remove` 单独给——**运行时可用 ≠ 能装卸**
/// （web 端有运行时但没有文件系统）。
pub fn PluginBridge::with_available(
  load : ((Array[PluginLoadResult]) -> Unit) -> Unit,
  unload : (String) -> Unit,
  call : (String, String, (Result[String, String]) -> Unit) -> Unit,
  is_loaded : (String) -> Bool,
  can_install~ : Bool = false,
  install~ : (String, (Result[String, String]) -> Unit) -> Unit = fn(
    _source_dir,
    on_result,
  ) {
    on_result(Err("本端不支持安装插件"))
  },
  remove~ : (String, (Result[String, String]) -> Unit) -> Unit = fn(
    _plugin_id,
    on_result,
  ) {
    on_result(Err("本端不支持卸载插件"))
  },
  plugins_root~ : String = "",
) -> PluginBridge {
  {
    available: true,
    load,
    unload,
    call,
    is_loaded,
    can_install,
    install,
    remove,
    plugins_root,
  }
}

///|
/// 门面是否可用（有真实插件运行时）。
pub fn PluginBridge::is_available(self : PluginBridge) -> Bool {
  self.available
}

///|
/// 插件动作请求协议格式标识。
pub const PLUGIN_ACTION_FORMAT : String = "moui.studio.plugin.action"

///|
/// 插件动作请求协议版本。
pub const PLUGIN_ACTION_FORMAT_VERSION : Int32 = 1

///|
/// 插件视图请求协议格式标识。
pub const PLUGIN_VIEW_REQUEST_FORMAT : String = "moui.studio.plugin.viewreq"

///|
/// 插件视图请求协议版本。
pub const PLUGIN_VIEW_REQUEST_FORMAT_VERSION : Int32 = 1

///|
/// 构造插件动作请求（宿主 → 插件）。
///
/// 请求格式属**协议**，故放在契约层——两个后端与 app 共用同一份，
/// 不会出现「native 发一种、web 发另一种」。
pub fn plugin_action_request(
  plugin_id : String,
  action_id : String,
  payload : String,
) -> String {
  let fields : Map[String, Json] = Map([], capacity=6)
  fields["format"] = Json::string(PLUGIN_ACTION_FORMAT)
  fields["format_version"] = Json::number(
    PLUGIN_ACTION_FORMAT_VERSION.to_double(),
  )
  fields["plugin_id"] = Json::string(plugin_id)
  fields["action_id"] = Json::string(action_id)
  fields["payload"] = Json::string(payload)
  Json::object(fields).stringify()
}

///|
/// 构造插件视图请求（宿主 → 插件）。
pub fn plugin_view_request(
  plugin_id : String,
  panel_id : String,
  payload : String,
) -> String {
  let fields : Map[String, Json] = Map([], capacity=6)
  fields["format"] = Json::string(PLUGIN_VIEW_REQUEST_FORMAT)
  fields["format_version"] = Json::number(
    PLUGIN_VIEW_REQUEST_FORMAT_VERSION.to_double(),
  )
  fields["plugin_id"] = Json::string(plugin_id)
  fields["panel_id"] = Json::string(panel_id)
  fields["payload"] = Json::string(payload)
  Json::object(fields).stringify()
}
