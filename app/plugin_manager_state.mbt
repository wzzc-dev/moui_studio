///|
/// 插件管理面板状态：独立对话框的显隐、选中项、安装/卸载进度。
///
/// **为什么独立切片**：插件管理是**一块独立的 UI**（独立模态对话框，
/// 不是设置面板里的一组）。它的状态与 `PluginState` 分开——
/// `PluginState` 管「插件运行态」（加载了什么、贡献了什么、谁失败了），
/// 本切片管「管理界面态」（面板开着没、选中谁、正在装谁）。
///
/// **纪律**：
/// - **禁用 ≠ 卸载**：禁用只过滤贡献项入口（插件文件留着）；
///   卸载删目录（破坏性，须经确认卡）。两者语义不同，UI 上分开。
/// - **安装/卸载是异步的**（文件 I/O 在 worker 上跑），故有 `busy` 标记
///   ——进行中时对应按钮禁用，避免重复提交。

///|
/// 插件管理面板的状态。
pub(all) struct PluginManagerState {
  /// 管理对话框是否打开。
  open : Bool
  /// 选中的插件 id（"" = 未选中；详情区显示它）。
  selected : String
  /// 正在安装/卸载的插件 id（空 = 空闲）。
  ///
  /// **为什么按插件 id 而不是布尔**：一次只允许一个 I/O 操作在跑
  /// （服务层的 worker 是串行的），按 id 记能同时表达「谁在忙」。
  busy : String
  /// 最近一次操作的回执（成功/失败原因）——**成功也要说**，
  /// 否则用户点了没反应会以为没生效。
  notice : String
  /// 最近一次操作是否失败（决定 notice 的呈现色）。
  notice_is_error : Bool
}

///|
/// 新建插件管理状态（对话框关闭、空闲）。
pub fn PluginManagerState::new() -> PluginManagerState {
  { open: false, selected: "", busy: "", notice: "", notice_is_error: false, }
}

///|
/// 打开管理面板（选中项保持不变——用户可能正在看某个插件的详情）。
pub fn PluginManagerState::open_manager(
  self : PluginManagerState,
) -> PluginManagerState {
  { ..self, open: true, }
}

///|
/// 关闭管理面板（清空瞬态：选中与回执——下次打开是干净的）。
pub fn PluginManagerState::close_manager(
  self : PluginManagerState,
) -> PluginManagerState {
  { ..self, open: false, selected: "", notice: "", notice_is_error: false, }
}

///|
/// 选中某个插件（详情区显示它）。
pub fn PluginManagerState::select(
  self : PluginManagerState,
  plugin_id : String,
) -> PluginManagerState {
  { ..self, selected: plugin_id, }
}

///|
/// 标记某个插件正在安装/卸载。
pub fn PluginManagerState::set_busy(
  self : PluginManagerState,
  plugin_id : String,
) -> PluginManagerState {
  { ..self, busy: plugin_id, }
}

///|
/// 记录一次操作回执（成功/失败都要说话）。
pub fn PluginManagerState::set_notice(
  self : PluginManagerState,
  message : String,
  is_error : Bool,
) -> PluginManagerState {
  { ..self, notice: message, notice_is_error: is_error, }
}

///|
/// 清空回执。
pub fn PluginManagerState::clear_notice(
  self : PluginManagerState,
) -> PluginManagerState {
  { ..self, notice: "", notice_is_error: false, }
}

///|
/// 某个插件是否正在被安装/卸载（对应按钮要禁用）。
pub fn PluginManagerState::is_busy_with(
  self : PluginManagerState,
  plugin_id : String,
) -> Bool {
  self.busy == plugin_id
}

///|
/// 是否正忙（全局一个 I/O 操作）。
pub fn PluginManagerState::is_busy(self : PluginManagerState) -> Bool {
  self.busy != ""
}
