///|
/// S5f 工程域纯 UI 状态切片白盒测试：文件 tab 切换/关闭、文件 CRUD 输入态、
/// 全文搜索草稿、结构树搜索/分组折叠/「新建」菜单开合。这些臂自壳迁入，
/// 全部零副作用（Effect::none）；运行/写盘/回执仍住壳。
fn apply_ui(state : ProjectState, msg : ProjectMsg) -> ProjectState {
  update_project(state, msg).0
}

///|
fn ui_open_file(rel : String) -> OpenProjectFile {
  OpenProjectFile::{
    rel,
    saved_content: "",
    draft: "",
    caret: 0,
    selection: None,
    md_session: None,
  }
}

///|
fn state_with_tabs(rels : Array[String]) -> ProjectState {
  let files : Array[OpenProjectFile] = []
  for rel in rels {
    files.push(ui_open_file(rel))
  }
  { ..ProjectState::new(), open_project_files: files, open_file_index: 0, }
}

///|
test "select file tab moves active index within range" {
  let state = state_with_tabs(["a", "b", "c"])
  assert_eq(apply_ui(state, SelectFileTab(2)).open_file_index, 2)
  // 越界不动（不 panic，不产生 effect）
  assert_eq(apply_ui(state, SelectFileTab(9)).open_file_index, 0)
  assert_eq(apply_ui(state, SelectFileTab(-1)).open_file_index, 0)
}

///|
test "close file tab removes tab and collapses active to a valid index" {
  // 关闭中间下标：tab 移除、其后元素前移，active 收敛到删除下标
  // （沿用壳原 close_open_file_at 的同位置规则）。
  let three = state_with_tabs(["a", "b", "c"])
  let after_b = apply_ui(three, CloseFileTab(1))
  assert_eq(after_b.open_project_files.length(), 2)
  assert_eq(after_b.open_project_files[0].rel, "a")
  assert_eq(after_b.open_project_files[1].rel, "c")
  assert_eq(after_b.open_file_index, 1)
  // 关闭尾部 active：active 回退一格
  let tail = { ..state_with_tabs(["a", "b", "c"]), open_file_index: 2, }
  let after_tail = apply_ui(tail, CloseFileTab(2))
  assert_eq(after_tail.open_file_index, 1)
  // 关到空：active 归 -1
  let single = apply_ui(state_with_tabs(["a"]), CloseFileTab(0))
  assert_eq(single.open_project_files.length(), 0)
  assert_eq(single.open_file_index, -1)
  // 越界 no-op
  assert_eq(apply_ui(three, CloseFileTab(9)).open_project_files.length(), 3)
}

///|
test "file create draft only accepted while create input open" {
  let closed = apply_ui(ProjectState::new(), FileCreateDraft("x.mbt"))
  assert_eq(closed.file_name_draft, "")
  let opened = {
    ..ProjectState::new(),
    file_create_open: true,
    file_create_dir: "app",
  }
  let drafted = apply_ui(opened, FileCreateDraft("form.mbt"))
  assert_eq(drafted.file_name_draft, "form.mbt")
  let dismissed = apply_ui(drafted, FileCreateDismiss)
  assert_false(dismissed.file_create_open)
  assert_eq(dismissed.file_name_draft, "")
  assert_eq(dismissed.file_create_dir, "")
}

///|
test "rename start seeds basename and draft toggles guard" {
  let started = apply_ui(
    ProjectState::new(),
    FileRenameStart("app/handlers.mbt"),
  )
  assert_eq(started.file_rename_open, Some("app/handlers.mbt"))
  // 草稿只填文件名（提交时按目录拼回），不携带整个 rel
  assert_eq(started.file_name_draft, "handlers.mbt")
  // 未打开改名输入时草稿不接受
  let guarded = apply_ui(ProjectState::new(), FileRenameDraft("x"))
  assert_eq(guarded.file_name_draft, "")
  let drafted = apply_ui(started, FileRenameDraft("renamed.mbt"))
  assert_eq(drafted.file_name_draft, "renamed.mbt")
  let dismissed = apply_ui(drafted, FileRenameDismiss)
  assert_eq(dismissed.file_rename_open, None)
  assert_eq(dismissed.file_name_draft, "")
}

///|
test "search draft is pure state and stays in the slice" {
  let typed = apply_ui(ProjectState::new(), SetSearchQuery("program"))
  assert_eq(typed.search_query, "program")
}

///|
test "tree create menu toggles same group closed and switches group" {
  let opened = apply_ui(ProjectState::new(), ToggleTreeCreate("controls"))
  assert_eq(opened.tree_create_group, "controls")
  // 同组再点 = 收起
  let closed = apply_ui(opened, ToggleTreeCreate("controls"))
  assert_eq(closed.tree_create_group, "")
  // 换组 = 切到新组
  let switched = apply_ui(opened, ToggleTreeCreate("variables"))
  assert_eq(switched.tree_create_group, "variables")
}

///|
test "tree query and group collapse toggle" {
  let queried = apply_ui(ProjectState::new(), SetTreeQuery("按钮"))
  assert_eq(queried.tree_query, "按钮")
  let collapsed = apply_ui(queried, ToggleTreeGroup("controls"))
  assert_true(collapsed.tree_collapsed.contains("controls"))
  // 再点同组 = 展开（从集合移除）
  let expanded = apply_ui(collapsed, ToggleTreeGroup("controls"))
  assert_false(expanded.tree_collapsed.contains("controls"))
}

///|
test "all ui arms return no effect" {
  let messages : Array[ProjectMsg] = [
    SelectFileTab(0),
    CloseFileTab(0),
    FileCreateDraft("x"),
    FileCreateDismiss,
    FileRenameStart("a/b.mbt"),
    FileRenameDraft("y"),
    FileRenameDismiss,
    SetSearchQuery("q"),
    ToggleTreeCreate("g"),
    SetTreeQuery("q"),
    ToggleTreeGroup("g"),
  ]
  for msg in messages {
    match update_project(ProjectState::new(), msg).1 {
      @moui.Effect::NoEffect => ()
      _ => abort("纯 UI 臂必须无副作用")
    }
  }
}
