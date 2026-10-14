///|
/// 运行域·预览/编译输出 UI 状态切片（S5i，ADR 0041 插件化）。
///
/// 只承载「外壳级」运行面板的纯界面态：编译输出面板开关、预览渲染器
/// （内嵌框 / Web）选择。真正的运行/编译/预览服务编排（PreviewNavigate
/// 等）与 Web 预览打开后的自动切档仍住壳（服务/Effect 层）。
///
/// PreviewMode 枚举是 app 侧产品档位，插件不反向依赖 app；切片只存
/// `web_preview : Bool`（PmWeb=true / PmFrame=false），壳在边界做换转。
///
/// 视图由父组装（与 ai/blocks/code 同口径），本 Feature 的 view 域 abort。

///|
/// 运行域 UI 状态：全部字段 mut，随 Feature::scope 进壳单一聚合字段。
pub(all) struct RunUiState {
  mut compile_output_open : Bool
  mut web_preview : Bool
}

///|
pub fn RunUiState::new() -> RunUiState {
  { compile_output_open: false, web_preview: false, }
}

///|
/// 运行域 UI 消息：只承载纯界面态。
pub(all) enum RunUiMsg {
  /// 编译输出面板开关（取反）。
  ToggleCompileOutput
  /// 选择预览渲染器：true=Web，false=内嵌框。
  SetPreviewMode(Bool)
}

///|
/// 运行 UI 切片 update：纯状态转移，零副作用。
pub fn update_run_ui(
  state : RunUiState,
  msg : RunUiMsg,
) -> (RunUiState, @moui.Effect[RunUiMsg]) {
  let none = @moui.Effect::none()
  match msg {
    ToggleCompileOutput =>
      ({ ..state, compile_output_open: !state.compile_output_open, }, none)
    SetPreviewMode(web) => ({ ..state, web_preview: web, }, none)
  }
}

///|
/// 运行 UI 域 Feature：view 域刻意 abort（视图由壳组装）。
pub fn run_ui_feature() -> @moui.Feature[RunUiState, RunUiMsg] {
  @moui.Feature::new(
    init=() => (RunUiState::new(), @moui.Effect::none()),
    update=fn(state, message) { update_run_ui(state, message) },
    view=_state => abort("run ui views are composed by the parent shell"),
  )
}
