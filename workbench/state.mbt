///|
pub(all) struct LayoutState {
  pane_live : Bool
  pane_blocks : Bool
  split_ratio : Double
}

///|
pub(all) struct WorkbenchState {
  docs : DocumentStore
  layout : LayoutState
}

///|
pub fn LayoutState::new() -> LayoutState {
  { pane_live: true, pane_blocks: true, split_ratio: 0.55, }
}

///|
pub fn WorkbenchState::new() -> WorkbenchState {
  { docs: DocumentStore::new(), layout: LayoutState::new(), }
}

///|
pub(all) enum WorkbenchMsg {
  ActivateDocument(String)
  CloseDocument(String)
  EditDocument(String, String)
  MoveDocumentCaret(String, Int32, @core.TextRange?)
  ApplyMarkdownTransaction(String, @moui_richtext.MarkdownEditTransaction)
  TogglePaneLive
  TogglePaneBlocks
  ShowPaneLive
  ShowPaneBlocks
  SetSplitRatio(Double)
}

///|
/// 纯状态迁移，零 Effect。工作区/模式与「显示积木时自动选子程序」属于
/// app 的壳策略，由组合根在收到消息后补后处理。
pub fn update_workbench(
  state : WorkbenchState,
  msg : WorkbenchMsg,
) -> WorkbenchState {
  match msg {
    ActivateDocument(id) => { ..state, docs: state.docs.activate(id), }
    CloseDocument(id) => { ..state, docs: state.docs.close(id), }
    EditDocument(id, value) => { ..state, docs: state.docs.edit(id, value), }
    MoveDocumentCaret(id, caret, selection) =>
      { ..state, docs: state.docs.move_caret(id, caret, selection), }
    ApplyMarkdownTransaction(id, transaction) =>
      { ..state, docs: state.docs.apply_markdown_transaction(id, transaction), }
    TogglePaneLive =>
      {
        ..state,
        layout: { ..state.layout, pane_live: !state.layout.pane_live, },
      }
    TogglePaneBlocks =>
      {
        ..state,
        layout: { ..state.layout, pane_blocks: !state.layout.pane_blocks, },
      }
    ShowPaneLive => { ..state, layout: { ..state.layout, pane_live: true, }, }
    ShowPaneBlocks =>
      { ..state, layout: { ..state.layout, pane_blocks: true, }, }
    SetSplitRatio(ratio) => {
      let clamped = if ratio.is_nan() { 0.55 } else { ratio.max(0.2).min(0.8) }
      { ..state, layout: { ..state.layout, split_ratio: clamped, }, }
    }
  }
}
