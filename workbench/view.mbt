///|
pub const EDITOR_TAB_HEIGHT : Double = 24.0

///|
fn[Msg] editor_empty(width : Double, height : Double) -> @moui.View[Msg] {
  @views.container(
    @views.spacer(min_length=0.0),
    background=@chrome.ide_editor_background(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
fn[Msg] editor_tab(
  entry : DocumentEntry,
  active : Bool,
  wrap : (WorkbenchMsg) -> Msg,
) -> @moui.View[Msg] {
  let label = entry.doc.title + (if entry.is_dirty() { " ●" } else { "" })
  let cell_width = (@chrome.text_estimate_width(label) + 40.0)
    .min(150.0)
    .max(64.0)
  let cells : Array[@moui.View[Msg]] = [
    @views.text(
      @chrome.fit_label(label, cell_width - 20.0),
      theme=@chrome.studio_theme(),
      width=(cell_width - 20.0).max(20.0),
      height=14.0,
      align=TextStart,
    ).foreground(
      if active {
        @chrome.ide_text()
      } else {
        @chrome.ide_text_faint()
      },
    ),
  ]
  if entry.doc.closable {
    cells.push(
      @views.text(
        "×",
        theme=@chrome.studio_theme(),
        width=14.0,
        height=14.0,
        align=TextCenter,
      )
      .foreground(@chrome.ide_text_faint())
      .on_tap(wrap(CloseDocument(entry.doc.id))),
    )
  }
  @views.container(
    @views.row(cells, spacing=2.0, align=Center),
    background=if active {
      @chrome.ide_panel()
    } else {
      @chrome.ide_editor_background()
    },
    width=cell_width,
    height=22.0,
    padding=0.0,
  ).on_tap(wrap(ActivateDocument(entry.doc.id)))
}

///|
fn[Msg] editor_tabs(
  state : WorkbenchState,
  wrap : (WorkbenchMsg) -> Msg,
  width : Double,
) -> @moui.View[Msg] {
  let cells : Array[@moui.View[Msg]] = []
  for i, entry in state.docs.entries {
    cells.push(editor_tab(entry, i == state.docs.active, wrap))
  }
  @views.container(
    @views.row(cells, spacing=2.0, align=Start).frame(
      width=(width - 12.0).max(80.0),
      height=EDITOR_TAB_HEIGHT,
    ),
    background=@chrome.ide_editor_background(),
    width~,
    height=EDITOR_TAB_HEIGHT,
    padding=0.0,
  )
}

///|
/// 统一编辑区：全局文档 tab + 当前文档的 provider 编辑面。找不到 provider
/// 时给一块空面，不 panic。
pub fn[Ctx, Msg] editor_area(
  state : WorkbenchState,
  ctx : Ctx,
  providers : Array[EditorProvider[Ctx, Msg]],
  preferred : String,
  wrap : (WorkbenchMsg) -> Msg,
  save : Msg,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let body_height = (height - EDITOR_TAB_HEIGHT).max(0.0)
  let body = match state.docs.active_entry() {
    None => editor_empty(width, body_height)
    Some(entry) => {
      let host : EditorHost[Msg] = {
        edit: value => wrap(EditDocument(entry.doc.id, value)),
        caret: (caret, selection) => {
          wrap(MoveDocumentCaret(entry.doc.id, caret, selection))
        },
        markdown: transaction => {
          wrap(ApplyMarkdownTransaction(entry.doc.id, transaction))
        },
        save,
        close: wrap(CloseDocument(entry.doc.id)),
      }
      match resolve_provider(providers, ctx, entry.doc, preferred) {
        None => editor_empty(width, body_height)
        Some(provider) =>
          (provider.render)(ctx, entry, host, width, body_height)
      }
    }
  }
  @views.container(
    @views.column([editor_tabs(state, wrap, width), body], spacing=0.0).frame(
      width~,
      height~,
    ),
    background=@chrome.ide_editor_background(),
    width~,
    height~,
    padding=0.0,
  )
}
