///|
/// Web 端插件槽位：JS 侧预实例化的插件贡献，宿主按需读取。
///
/// **为什么用槽位而不是消息**：浏览器 `WebAssembly.instantiate` 是
/// **异步**的，而插件实例化完成后**没有任何消息**能回到 app（wasm
/// import 是单向的：宿主 → JS；JS 无法反向驱动 app 的 update）。
/// 若走「宿主发消息请求加载」的路子，首轮请求必然早于插件就绪，
/// 拿回空列表——实测正是如此（宿主查询时刻比插件就绪早约 90ms）。
///
/// 槽位是本仓既有的范式（`preview_web_slot.mbt` 的预览 web 控制器同款）：
/// 组合根在装配时安装槽位，视图/处理器按需读取。web 端插件走同一路子：
///
/// ```text
/// JS 侧 preloadPlugins() 完成
///   └─ 写入 JS 侧缓存（pluginInstances）
/// 宿主侧每次渲染/取用
///   └─ 读槽位 → 同步查 JS 侧 plugin_ids() / contributions()
/// ```
///
/// 代价：**插件贡献不进 model**（model 只存已加载插件的描述快照）。
/// 故 app 侧仍走 `PluginsScanned` 消息更新 model —— 但那一步由**渲染
/// 期的读取**驱动：读到非空就发一次消息。

///|
/// 已加载插件的贡献快照（宿主侧缓存）。
pub(all) struct WebPluginSnapshot {
  /// 插件 id → 贡献描述 JSON
  contributions : Map[String, String]
}

///|
/// 进程级槽位：当前可用的插件贡献（JS 侧就绪的插件）。
let plugin_snapshot_slot : Ref[WebPluginSnapshot] = Ref({
  contributions: Map([], capacity=8),
})

///|
/// 插件贡献的**实时查询器**：`() -> Map[String, String]`。
///
/// web 端用：每次宿主需要时同步向 JS 侧查插件的贡献描述。之所以
/// 「实时查」而不是读缓存——插件就绪时刻晚于宿主构造 runtime（浏览器
/// instantiate 异步），缓存只在 push 那一刻更新；而视图渲染随时可能
/// 发生，实时查保证「渲染时插件已就绪」。
pub type WebPluginProvider = () -> Map[String, String]

///|
/// 进程级槽位：web 端的插件贡献查询器（web 入口装配时安装）。
let web_provider_slot : Ref[WebPluginProvider?] = Ref(None)

///|
/// 安装 web 端的插件贡献查询器。
pub fn install_web_plugin_provider(provider : WebPluginProvider) -> Unit {
  web_provider_slot.val = Some(provider)
}

///|
/// 读取当前就绪的插件贡献（宿主每次需要时同步向 JS 侧查）。
///
/// 返回的 Map 是「插件 id → 贡献描述 JSON」。
pub fn web_plugin_contributions() -> Map[String, String] {
  match web_provider_slot.val {
    Some(provider) => provider()
    None => plugin_snapshot_slot.val.contributions
  }
}

///|
/// 记录一个插件的贡献描述 JSON（由 web 入口在 JS 侧推送时写入）。
///
/// web 端插件就绪后由 JS 主动推来（宿主构造 runtime 早于插件就绪，
/// 宿主「拉」只会拿到空列表）——见 `docs/plugin-system.md`。
pub fn install_web_plugin_contributions(
  plugin_id : String,
  contributions_json : String,
) -> Unit {
  let contributions = plugin_snapshot_slot.val.contributions
  contributions.set(plugin_id, contributions_json)
  plugin_snapshot_slot.val = { contributions, }
}

///|
/// 「插件就绪」通知器：`() -> Unit`（web 入口安装）。
///
/// **为什么需要它**：web 端的浏览器事件循环是**按需驱动**的——没有
/// 重绘就没有 rAF 帧，`web_timer_dispatch_due()` 不跑，定时器订阅
/// （含插件重试节拍）就不派发。于是「插件就绪」这件事没人告诉宿主，
/// 宿主永远停在首轮的空列表上——底栏的「插件」页签不出现。
///
/// JS 侧插件就绪后**主动**调宿主导出的 `studio_plugins_changed`，
/// 宿主经这个通知器触发一次重绘（进而唤醒事件循环与定时器），
/// 插件列表随之被重查、页签随之出现。
pub type WebPluginReadyNotifier = () -> Unit

///|
/// 进程级槽位：插件就绪通知器（web 入口装配时安装）。
let web_ready_notifier_slot : Ref[WebPluginReadyNotifier?] = Ref(None)

///|
/// 安装插件就绪通知器（web 入口装配时调用一次）。
pub fn install_web_plugin_ready_notifier(
  notifier : WebPluginReadyNotifier,
) -> Unit {
  web_ready_notifier_slot.val = Some(notifier)
}

///|
/// 通知宿主「插件列表可能变了」（web 入口在 JS 侧推送后调用）。
///
/// 未装配通知器（native 端 / 单元测试）→ 空操作。
pub fn notify_web_plugins_changed() -> Unit {
  match web_ready_notifier_slot.val {
    Some(notifier) => notifier()
    None => ()
  }
}

///|
/// 「重载插件列表」的触发器：`() -> Unit`（web 入口安装）。
///
/// **为什么需要它**：web 端插件就绪后，宿主必须**重新加载插件列表**并
/// 更新 model（`PluginsScanned` 回执）。但 wasm 的 import 是单向的，
/// JS 无法直接驱动 app 的 update。
///
/// 而宿主侧的定时器重试**救不了**：静止时浏览器事件循环**不派发定时器**
/// （web 端的 rAF 由 `window.request_redraw` 排起，而那条路只在 wasm
/// 自己的事件循环里跑；JS 从 wasm 外部同步调宿主导出函数时，wasm 的
/// 事件循环并没有在跑——实测脏标记设上了（`needs_redraw=true`），
/// 但重试节拍始终不发）。
///
/// 故走「宿主导出函数 → `dispatch_action_command` → program command
/// → `dispatch(消息)`」这条**同步**路径：它直接调 runtime 的 dispatch
/// 闭包，**不依赖 rAF**，故必定生效。
pub type WebPluginReloadTrigger = () -> Int32

///|
/// 进程级槽位：重载插件列表的触发器（web 入口装配时安装）。
let web_reload_trigger_slot : Ref[WebPluginReloadTrigger?] = Ref(None)

///|
/// 安装「重载插件列表」的触发器（web 入口装配时调用一次）。
pub fn install_web_plugin_reload_trigger(
  trigger : WebPluginReloadTrigger,
) -> Unit {
  web_reload_trigger_slot.val = Some(trigger)
}

///|
/// 请求重新加载插件列表（web 入口在 JS 侧轮询时调用）。
///
/// 返回**已加载插件数**（JS 侧据此停止轮询——插件就绪后不必再轮询）。
/// 未装配触发器（native 端 / 单元测试）→ 0。
pub fn reload_web_plugins() -> Int32 {
  match web_reload_trigger_slot.val {
    Some(trigger) => trigger()
    None => 0
  }
}
