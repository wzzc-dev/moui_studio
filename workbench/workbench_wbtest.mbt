///|
struct TestCtx {
  markdown : Bool
}

///|
enum TestMsg {
  Ping(String)
}

///|
fn file_doc(rel : String) -> Document {
  {
    id: file_document_id(rel),
    title: rel,
    resource: rel,
    kind: FileDoc,
    closable: true,
  }
}

///|
fn studio_provider(
  id : String,
  priority : Int32,
) -> EditorProvider[TestCtx, TestMsg] {
  {
    id,
    priority,
    accepts: (_ctx, doc) => doc.kind is StudioDoc,
    render: (_ctx, _entry, _host, _width, _height) => {
      @views.spacer(min_length=0.0)
    },
  }
}

///|
fn file_provider(
  id : String,
  priority : Int32,
  wants_markdown : Bool,
) -> EditorProvider[TestCtx, TestMsg] {
  {
    id,
    priority,
    accepts: (ctx, doc) => doc.kind is FileDoc && ctx.markdown == wants_markdown,
    render: (_ctx, _entry, _host, _width, _height) => {
      @views.spacer(min_length=0.0)
    },
  }
}

///|
test "workbench/store starts with one pinned studio document" {
  let store = DocumentStore::new()
  assert_eq(store.entries.length(), 1)
  assert_eq(store.active, 0)
  assert_eq(store.active_entry().unwrap().doc.id, STUDIO_DOC_ID)
  assert_eq(store.active_entry().unwrap().doc.closable, false)
  // 常驻文档拒绝关闭
  assert_eq(store.close(STUDIO_DOC_ID).entries.length(), 1)
}

///|
test "workbench/store upserts and activates file documents" {
  let store = DocumentStore::new()
  let (opened, index) = store.upsert_file(
    file_doc("src/a.mbt"),
    TextBuffer::new("src/a.mbt", "let a = 1"),
  )
  assert_eq(index, 1)
  assert_eq(opened.active, 1)
  assert_eq(opened.entries.length(), 2)
  // 同 id 原位替换 = 重新读取刷新内容
  let (refreshed, same_index) = opened.upsert_file(
    file_doc("src/a.mbt"),
    TextBuffer::new("src/a.mbt", "let a = 2"),
  )
  assert_eq(same_index, 1)
  assert_eq(refreshed.entries.length(), 2)
  assert_eq(refreshed.entries[1].text_buffer().unwrap().draft, "let a = 2")
  // 不存在的 id 激活是 no-op
  assert_eq(refreshed.activate("file:missing").active, 1)
}

///|
test "workbench/store close converges active index" {
  let store = DocumentStore::new()
  let (a, _) = store.upsert_file(file_doc("a"), TextBuffer::new("a", ""))
  let (b, _) = a.upsert_file(file_doc("b"), TextBuffer::new("b", ""))
  let (c, _) = b.upsert_file(file_doc("c"), TextBuffer::new("c", ""))
  let on_a = c.activate(file_document_id("a"))
  let after_a = on_a.close(file_document_id("a"))
  // 关闭活动文档后停在同下标的下一篇
  assert_eq(after_a.active, 1)
  assert_eq(after_a.active_entry().unwrap().doc.resource, "b")
  let after_b = after_a.close(file_document_id("b"))
  assert_eq(after_b.active, 1)
  assert_eq(after_b.active_entry().unwrap().doc.resource, "c")
  let after_c = after_b.close(file_document_id("c"))
  // 尾部关闭回退到常驻文档
  assert_eq(after_c.active, 0)
  assert_eq(after_c.active_entry().unwrap().doc.id, STUDIO_DOC_ID)
}

///|
test "workbench/store rename keeps body and finds by resource" {
  let store = DocumentStore::new()
  let (opened, _) = store.upsert_file(
    file_doc("notes.md"),
    TextBuffer::new("notes.md", "# hi"),
  )
  let renamed = opened.rename_file("notes.md", "docs/readme.md", "readme.md")
  assert_eq(renamed.find(file_document_id("notes.md")), -1)
  let index = renamed.find(file_document_id("docs/readme.md"))
  assert_eq(index, 1)
  assert_eq(renamed.find_file("docs/readme.md"), 1)
  assert_eq(renamed.entries[index].doc.resource, "docs/readme.md")
  assert_eq(renamed.entries[index].doc.title, "readme.md")
  assert_eq(renamed.entries[index].text_buffer().unwrap().draft, "# hi")
}

///|
test "workbench/store edit and caret stay keyed by document id" {
  let store = DocumentStore::new()
  let (opened, _) = store.upsert_file(
    file_doc("a.mbt"),
    TextBuffer::new("a.mbt", "old"),
  )
  let edited = opened.edit(file_document_id("a.mbt"), "new")
  assert_eq(edited.entries[1].text_buffer().unwrap().draft, "new")
  assert_eq(edited.entries[1].text_buffer().unwrap().saved, "old")
  assert_true(edited.entries[1].is_dirty())
  assert_true(edited.any_file_dirty())
  let moved = edited.move_caret(
    file_document_id("a.mbt"),
    3,
    Some(@core.TextRange::new(start=1, end=3)),
  )
  assert_eq(moved.entries[1].text_buffer().unwrap().caret, 3)
  // 常驻文档没有正文，编辑/光标消息原样丢弃
  let studio_edited = moved.edit(STUDIO_DOC_ID, "ignored")
  assert_true(studio_edited.entries[0].text_buffer() is None)
  assert_eq(studio_edited.entries[1].text_buffer().unwrap().draft, "new")
}

///|
test "workbench/store exposes active file and save/close by resource" {
  let store = DocumentStore::new()
  assert_true(store.active_file() is None)
  let (opened, _) = store.upsert_file(
    file_document("a.mbt", "a.mbt"),
    TextBuffer::new("a.mbt", "old"),
  )
  let (doc, buffer) = opened.active_file().unwrap()
  assert_eq(doc.resource, "a.mbt")
  assert_eq(buffer.draft, "old")
  let edited = opened.edit(file_document_id("a.mbt"), "new")
  let saved = edited.mark_saved("a.mbt")
  assert_false(saved.any_file_dirty())
  assert_eq(saved.entries[1].text_buffer().unwrap().saved, "new")
  assert_eq(saved.file_entries().length(), 1)
  assert_eq(saved.entry(file_document_id("a.mbt")).unwrap().doc.title, "a.mbt")
  assert_eq(saved.close_file("a.mbt").entries.length(), 1)
}

///|
test "workbench/store applies markdown transactions to the md session" {
  let store = DocumentStore::new()
  let (opened, _) = store.upsert_file(
    file_doc("note.md"),
    TextBuffer::new("note.md", "# Hi"),
  )
  let buffer = opened.entries[1].text_buffer().unwrap()
  assert_true(buffer.md_session is Some(_))
  let transaction = @moui_richtext.MarkdownEditTransaction::from_sources(
    "# Hi",
    "# Hi\n",
    caret=5,
    reason=@moui_richtext.MarkdownEditReason::TextInput,
  )
  let applied = opened.apply_markdown_transaction(
    file_document_id("note.md"),
    transaction,
  )
  let next = applied.entries[1].text_buffer().unwrap()
  assert_eq(next.draft, "# Hi\n")
  assert_eq(next.caret, 5)
  assert_eq(next.md_session.unwrap().source(), "# Hi\n")
  assert_true(next.is_dirty())
}

///|
test "workbench/provider resolution honors preferred, priority and ties" {
  let providers : Array[EditorProvider[TestCtx, TestMsg]] = [
    studio_provider("studio.first", 50),
    studio_provider("studio.second", 50),
    studio_provider("studio.high", 80),
    file_provider("file.markdown", 20, true),
    file_provider("file.text", 0, false),
  ]
  let studio = studio_document()
  let note = file_doc("note.md")
  // preferred 命中且 accepts 时优先于更高优先级
  assert_eq(
    resolve_provider(providers, { markdown: true, }, studio, "studio.first").unwrap().id,
    "studio.first",
  )
  // 无 preferred：最高优先级；同优先级先注册者胜出
  let tied : Array[EditorProvider[TestCtx, TestMsg]] = [
    studio_provider("studio.first", 50),
    studio_provider("studio.second", 50),
  ]
  assert_eq(
    resolve_provider(tied, { markdown: false, }, studio, "").unwrap().id,
    "studio.first",
  )
  assert_eq(
    resolve_provider(providers, { markdown: false, }, studio, "").unwrap().id,
    "studio.high",
  )
  // preferred 不认领当前文档时回退到优先级最高的认领者
  assert_eq(
    resolve_provider(providers, { markdown: true, }, note, "studio.high").unwrap().id,
    "file.markdown",
  )
  // markdown 插件关闭 → 文件回退 mono 编辑面
  assert_eq(
    resolve_provider(providers, { markdown: false, }, note, "").unwrap().id,
    "file.text",
  )
  let empty : Array[EditorProvider[TestCtx, TestMsg]] = []
  assert_true(resolve_provider(empty, { markdown: false, }, note, "") is None)
}

///|
test "workbench/layout toggles, restores and clamps" {
  let state = WorkbenchState::new()
  assert_eq(state.layout.pane_live, true)
  assert_eq(state.layout.pane_blocks, true)
  assert_eq(state.layout.split_ratio, 0.55)
  let toggled = update_workbench(state, TogglePaneLive)
  assert_eq(toggled.layout.pane_live, false)
  let shown = update_workbench(toggled, ShowPaneLive)
  assert_eq(shown.layout.pane_live, true)
  let blocks = update_workbench(shown, TogglePaneBlocks)
  assert_eq(blocks.layout.pane_blocks, false)
  assert_eq(update_workbench(blocks, ShowPaneBlocks).layout.pane_blocks, true)
  assert_eq(update_workbench(state, SetSplitRatio(0.1)).layout.split_ratio, 0.2)
  assert_eq(update_workbench(state, SetSplitRatio(0.9)).layout.split_ratio, 0.8)
  assert_eq(
    update_workbench(state, SetSplitRatio(0.63)).layout.split_ratio,
    0.63,
  )
}

///|
fn panel(
  id : String,
  location : PanelLocation,
  selected : Bool,
) -> PanelContribution[TestCtx, TestMsg] {
  {
    id,
    location,
    label_key: id,
    badge: _ctx => 2,
    selected: _ctx => selected,
    on_select: _ctx => Ping(id),
    render: (_ctx, _width, _height) => @views.spacer(min_length=0.0),
  }
}

///|
test "workbench/panels filter by location and selected state" {
  let panels : Array[PanelContribution[TestCtx, TestMsg]] = [
    panel("left.tree", PanelLeft, false),
    panel("left.ai", PanelLeft, true),
    panel("bottom.audit", PanelBottom, false),
  ]
  assert_eq(panels_at(panels, PanelLeft).length(), 2)
  assert_eq(panels_at(panels, PanelRight).length(), 0)
  assert_eq(
    selected_panel(panels, PanelLeft, { markdown: false, }).unwrap().id,
    "left.ai",
  )
  assert_true(selected_panel(panels, PanelBottom, { markdown: false, }) is None)
}

///|
test "workbench/commands find by id and expose all action channels" {
  let commands : Array[CommandContribution[TestCtx, TestMsg]] = [
    {
      id: "test.apply",
      label_key: "app.command.apply",
      group_key: "app.group.test",
      run: _ctx => Apply(Ping("apply")),
    },
    {
      id: "test.dispatch",
      label_key: "",
      group_key: "app.group.test",
      run: _ctx => Dispatch(Ping("dispatch")),
    },
    {
      id: "test.unavailable",
      label_key: "app.command.unavailable",
      group_key: "app.group.test",
      run: _ctx => Unavailable,
    },
  ]
  assert_true(find_command(commands, "missing") is None)
  let apply = find_command(commands, "test.apply").unwrap()
  assert_eq(apply.label_key, "app.command.apply")
  match (apply.run)({ markdown: false, }) {
    Apply(Ping(value)) => assert_eq(value, "apply")
    _ => fail("expected Apply")
  }
  match
    (find_command(commands, "test.dispatch").unwrap().run)({ markdown: false, }) {
    Dispatch(Ping(value)) => assert_eq(value, "dispatch")
    _ => fail("expected Dispatch")
  }
  match
    (find_command(commands, "test.unavailable").unwrap().run)({
      markdown: false,
    }) {
    Unavailable => ()
    _ => fail("expected Unavailable")
  }
}
