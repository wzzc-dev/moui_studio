///|
/// S5f 工程域纯 UI 状态切片白盒测试：文件 CRUD 输入态、全文搜索草稿、
/// 结构树搜索/分组折叠/「新建」菜单开合。这些臂自壳迁入，全部零副作用
/// （Effect::none）；运行/写盘/回执仍住壳。文档 tab 归 workbench，
/// 这里只验证资源管理器的只读行投影。
fn apply_ui(state : ProjectState, msg : ProjectMsg) -> ProjectState {
  update_project(state, msg).0
}

///|
fn explorer_data_with_editors(
  editors : Array[OpenEditorRow],
  active : Int32,
) -> ExplorerData {
  {
    projects: [],
    active_project: -1,
    workspace_root: None,
    open_editors: editors,
    open_editor_active: active,
    project_tree_collapsed: [],
    explorer_sections_collapsed: [],
    selected_project_file: None,
    recent_changes: [],
    file_create_dir: "",
    file_create_open: false,
    file_rename_open: None,
    folder_create_open: false,
  }
}

///|
test "open editor projection returns the active row only" {
  let data = explorer_data_with_editors(
    [
      OpenEditorRow::{
        id: "file:a.md",
        index: 0,
        rel: "a.md",
        label: "a.md",
        dirty: false,
        draft: "# A",
      },
      OpenEditorRow::{
        id: "file:b.mbt",
        index: 1,
        rel: "b.mbt",
        label: "b.mbt",
        dirty: true,
        draft: "fn main {}",
      },
    ],
    1,
  )
  let active = active_open_editor(data).unwrap()
  assert_eq(active.rel, "b.mbt")
  assert_true(active.dirty)
  // Studio 文档是活动文档时没有文件行
  assert_true(
    active_open_editor(explorer_data_with_editors(data.open_editors, -1))
    is None,
  )
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
