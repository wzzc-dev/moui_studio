///|
/// 代码编辑器域 UI 状态切片（S5g 状态切片，ADR 0038/0039/0041）：
/// 受控代码编辑面的光标/选区/滚动、补全弹层的候选词与开关。
///
/// 纯界面瞬态，零副作用、零 IR/代码草稿真源触碰。编辑代码（EditCode）、
/// 采纳补全（ApplyCompletion）、触发补全/跳转声明（需读 code_draft/program
/// 计算）、IR 路径高亮/悬停（跨域共享）仍住壳——它们要么改文档真源，要么
/// 读跨域真相；触发补全由壳算完候选后经 `SetCompletions` 回写本切片。
pub(all) struct CodeUiState {
  /// 受控编辑器回传的光标/选区（切换 tab 恢复，不串台）。
  mut caret : Int
  mut selection : @core.TextRange?
  /// 「行号槽 / IR 竖尺 ↔ 编辑面」同步滚动的唯一事实。
  mut scroll : @geometry.Point
  /// 补全弹层候选词（由壳 TriggerCompletion 计算后回写）。
  mut completions : Array[String]
  /// 补全弹层是否展开。
  mut completion_open : Bool
}

///|
pub fn CodeUiState::new() -> CodeUiState {
  {
    caret: 0,
    selection: None,
    scroll: @geometry.Point::new(x=0.0, y=0.0),
    completions: [],
    completion_open: false,
  }
}

///|
/// 代码编辑器 UI 域消息：只承载纯界面态。
pub(all) enum CodeUiMsg {
  CaretMoved(Int, @core.TextRange?)
  Scrolled(Double)
  DismissCompletion
  /// 内部回写：壳 TriggerCompletion 算完候选词后落进切片。
  SetCompletions(Array[String])
  /// 采纳补全后的 UI 结果：推进光标、清选区、关弹层（代码草稿由壳回写）。
  ApplyCompletion(Int)
  /// 跳到声明/问题行的 UI 结果：钉光标、清选区、滚动对齐（目标由壳算）。
  GoToLine(Int, Double)
}

///|
/// 代码 UI 切片 update：纯状态转移，零副作用。
pub fn update_code_ui(
  state : CodeUiState,
  msg : CodeUiMsg,
) -> (CodeUiState, @moui.Effect[CodeUiMsg]) {
  let none = @moui.Effect::none()
  match msg {
    CaretMoved(caret, selection) => ({ ..state, caret, selection, }, none)
    Scrolled(y) => ({ ..state, scroll: @geometry.Point::new(x=0.0, y~), }, none)
    DismissCompletion => ({ ..state, completion_open: false, }, none)
    SetCompletions(candidates) =>
      ({ ..state, completions: candidates, completion_open: true, }, none)
    ApplyCompletion(caret) =>
      ({ ..state, caret, selection: None, completion_open: false, }, none)
    GoToLine(caret, scroll_y) =>
      (
        {
          ..state,
          caret,
          selection: None,
          scroll: @geometry.Point::new(x=0.0, y=scroll_y),
        },
        none,
      )
  }
}

///|
/// 代码 UI 域 Feature：view 域刻意 abort（视图由壳组装，与 ai/blocks/project
/// 同口径）。
pub fn code_ui_feature() -> @moui.Feature[CodeUiState, CodeUiMsg] {
  @moui.Feature::new(
    init=() => (CodeUiState::new(), @moui.Effect::none()),
    update=fn(state, message) { update_code_ui(state, message) },
    view=_state => abort("code ui views are composed by the parent shell"),
  )
}
