///|
/// MoUI Studio 工程域·子消息与切片 update(S2b-2 出壳)。
///
/// 14 个纯态臂从壳 `update_ide_msgs` 迁来:全部只读写 `ProjectState`,
/// effect 恒为 none(切片零副作用,ai_sessions 先例)。跨域臂仍住壳:
/// 文件装载/保存回执(通知 + 自动构建)、选中装载(服务任务)、扫描/导入/
/// 改名/删除/构建/存储回执、新建工程流——它们触碰通知、事件出站、
/// 服务任务或程序真源,按 ADR 0038 契约 3 留根臂。
///
/// `ToggleProjectDirAt` 的「展开揭示滚动」需要行推导 + translator,由
/// 根 `ProjectOp` 委托臂后处理(切片只做纯折叠翻转)。

///|
/// 工程域子消息:资源管理器交互 + 工程 tab 编辑(active tab 的草稿/
/// 光标/MoMark 事务)。载荷与壳侧原变体逐字一致。
pub(all) enum ProjectMsg {
  SetActiveProject(Int32) // 切活动工程(选中文件复位)
  ToggleProjectDirAt(Int32, String) // 单树多根:根下标 + 目录 rel(纯折叠翻转)
  ExplorerHover(String) // 悬停行 key(空串 = 无悬停)
  ToggleExplorerSection(String) // 分区折叠(布局偏好,open: 前缀口径)
  FileCreateAt(String) // 就地新建文件(目标目录 rel)
  FolderCreateAt(String) // 就地新建文件夹(同形)
  ToggleExplorerMenu // 溢出菜单开合
  FolderCreateDraft(String) // 文件夹名草稿输入
  FolderCreateDismiss // 文件夹输入行关闭
  ExplorerCollapseAll // 全部折叠(整棵树逐层)
  ExplorerScrolled(@core.Point) // 树区滚动偏移(单一事实源)
  ProjectFileCaretMoved(Int32, @core.TextRange?) // active tab 光标/选区回传
  EditProjectFile(String) // active tab 草稿编辑
  ProjectFileMarkdownTransaction(@moui_richtext.MarkdownEditTransaction)
  // .md tab 的 MoMark 编辑事务
  // --- S5f 从壳并入的纯 UI 臂（文件 tab/CRUD 输入态 + 结构树 + 搜索草稿） ---
  SelectFileTab(Int32) // 选中已打开的 tab（只切 active，不装载）
  CloseFileTab(Int32) // 关闭 tab 并把 active 收敛到合法范围
  FileCreateDraft(String) // 新建文件名草稿（仅在新建输入打开时接受）
  FileCreateDismiss // 关闭新建输入行
  FileRenameStart(String) // 打开改名输入（带 rel，草稿只填文件名）
  FileRenameDraft(String) // 改名草稿（仅在改名输入打开时接受）
  FileRenameDismiss // 关闭改名输入行
  SetSearchQuery(String) // 全文搜索查询草稿（运行/回执在服务层）
  ToggleTreeCreate(String) // 结构树「新建」分组菜单开合（同组再点收起）
  SetTreeQuery(String) // 结构树搜索查询
  ToggleTreeGroup(String) // 结构树分组折叠翻转
}

///|
/// 切片初始态(壳 initial_model 同一口径)。
pub fn ProjectState::new() -> ProjectState {
  {
    projects: [],
    active_project: -1,
    workspace_root: None,
    open_project_files: [],
    open_file_index: -1,
    project_tree_collapsed: [],
    explorer_sections_collapsed: [],
    selected_project_file: None,
    explorer_scroll: @core.Point::new(x=0.0, y=0.0),
    explorer_hover: "",
    explorer_menu_open: false,
    scan_progress: None,
    file_create_dir: "",
    file_create_open: false,
    file_rename_open: None,
    folder_create_open: false,
    file_name_draft: "",
    tree_query: "",
    tree_collapsed: [],
    tree_create_group: "",
    search_query: "",
  }
}

///|
/// 工程域切片 update:纯态消息处理,零副作用(服务任务/通知/事件
/// 出站都在根臂)。未覆盖的消息不属于本切片(防御性原样返回)。
pub fn update_project(
  state : ProjectState,
  msg : ProjectMsg,
) -> (ProjectState, @moui.Effect[ProjectMsg]) {
  let none = @moui.Effect::none()
  match msg {
    SetActiveProject(index) =>
      ({ ..state, active_project: index, selected_project_file: None, }, none)
    ToggleProjectDirAt(index, rel) => {
      // 纯折叠翻转;「展开后滚到该行」的揭示由根臂后处理(需要行推导
      // 与 translator——切片拿不到,也不该拿)。
      let key = root_collapse_key(index, rel)
      let collapsed : Array[String] = []
      let mut removed = false
      for item in state.project_tree_collapsed {
        if item == key {
          removed = true
        } else {
          collapsed.push(item)
        }
      }
      if !removed {
        collapsed.push(key)
      }
      ({ ..state, project_tree_collapsed: collapsed, }, none)
    }
    ExplorerHover(key) => ({ ..state, explorer_hover: key, }, none)
    ToggleExplorerSection(id) => {
      // 分区折叠是布局偏好,与树内目录折叠分开存。文件夹分区默认展开,
      // 其余默认收起——「展开」登记成 `open:<id>` 标记,「折叠」才是裸 id。
      let toggled : Array[String] = []
      let open_key = "open:" + id
      let track_key = if id == EXPLORER_SECTION_FOLDERS { id } else { open_key }
      let mut removed = false
      for item in state.explorer_sections_collapsed {
        if item == track_key {
          removed = true
        } else {
          toggled.push(item)
        }
      }
      if !removed {
        toggled.push(track_key)
      }
      ({ ..state, explorer_sections_collapsed: toggled, }, none)
    }
    FileCreateAt(rel) =>
      // 目标目录必须展开,否则输入行折在树里看不见。
      (
        {
          ..state,
          file_create_open: true,
          file_create_dir: rel,
          folder_create_open: false,
          file_rename_open: None,
          file_name_draft: "",
          project_tree_collapsed: unfold_dir(state, state.active_project, rel),
        },
        none,
      )
    FolderCreateAt(rel) =>
      // 与 FileCreateAt 完全同形(只是打开的是文件夹输入行)。
      (
        {
          ..state,
          folder_create_open: true,
          file_create_dir: rel,
          file_create_open: false,
          file_rename_open: None,
          file_name_draft: "",
          project_tree_collapsed: unfold_dir(state, state.active_project, rel),
        },
        none,
      )
    ToggleExplorerMenu =>
      ({ ..state, explorer_menu_open: !state.explorer_menu_open, }, none)
    FolderCreateDraft(value) =>
      if state.folder_create_open {
        ({ ..state, file_name_draft: value, }, none)
      } else {
        (state, none)
      }
    FolderCreateDismiss =>
      ({ ..state, folder_create_open: false, file_name_draft: "", }, none)
    ExplorerCollapseAll =>
      // 整棵树逐层折上;滚动回顶。枚举与「导入后默认折叠」共用
      // collapse_all_tree_keys——各写一遍必然漏层。
      (
        {
          ..state,
          project_tree_collapsed: collapse_all_tree_keys(state),
          explorer_scroll: @core.Point::new(x=0.0, y=0.0),
        },
        none,
      )
    ExplorerScrolled(offset) => ({ ..state, explorer_scroll: offset, }, none)
    ProjectFileCaretMoved(caret, selection) =>
      // 受控编辑器光标回传:没有这个往返,光标会被模型旧值复位。
      match active_file_of(state) {
        None => (state, none)
        Some(open) =>
          (
            {
              ..state,
              open_project_files: replace_open_file_at(
                state.open_project_files,
                state.open_file_index,
                { ..open, caret, selection, },
              ),
            },
            none,
          )
      }
    EditProjectFile(draft) =>
      match active_file_of(state) {
        None => (state, none)
        Some(open) =>
          (
            {
              ..state,
              open_project_files: replace_open_file_at(
                state.open_project_files,
                state.open_file_index,
                { ..open, draft, },
              ),
            },
            none,
          )
      }
    ProjectFileMarkdownTransaction(transaction) =>
      // `.md` tab 的 MoMark session 编辑事务:session apply(增量),
      // 草稿/光标随事务回写;session 缺失时换源重建,不让事务丢失。
      match active_file_of(state) {
        None => (state, none)
        Some(open) => {
          let session = match open.md_session {
            Some(session) => session.apply(transaction)
            None =>
              @moui_richtext.MarkdownDocumentSession::new(transaction.source)
          }
          (
            {
              ..state,
              open_project_files: replace_open_file_at(
                state.open_project_files,
                state.open_file_index,
                {
                  ..open,
                  draft: transaction.source,
                  caret: transaction.caret,
                  selection: transaction.selection,
                  md_session: Some(session),
                },
              ),
            },
            none,
          )
        }
      }
    SelectFileTab(index) =>
      if index >= 0 && index < state.open_project_files.length() {
        ({ ..state, open_file_index: index, }, none)
      } else {
        (state, none)
      }
    CloseFileTab(index) => (close_open_file(state, index), none)
    FileCreateDraft(value) =>
      if state.file_create_open {
        ({ ..state, file_name_draft: value, }, none)
      } else {
        (state, none)
      }
    FileCreateDismiss =>
      (
        {
          ..state,
          file_create_open: false,
          file_name_draft: "",
          file_create_dir: "",
        },
        none,
      )
    FileRenameStart(rel) =>
      // 草稿只填文件名：提交时按 file_create_dir 拼回目录（与新建同口径）。
      (
        {
          ..state,
          file_rename_open: Some(rel),
          file_create_open: false,
          folder_create_open: false,
          file_name_draft: rel_path_last_segment(rel),
        },
        none,
      )
    FileRenameDraft(value) =>
      if state.file_rename_open is Some(_) {
        ({ ..state, file_name_draft: value, }, none)
      } else {
        (state, none)
      }
    FileRenameDismiss =>
      ({ ..state, file_rename_open: None, file_name_draft: "", }, none)
    SetSearchQuery(value) => ({ ..state, search_query: value, }, none)
    ToggleTreeCreate(group) =>
      (
        {
          ..state,
          tree_create_group: if state.tree_create_group == group {
            ""
          } else {
            group
          },
        },
        none,
      )
    SetTreeQuery(query) => ({ ..state, tree_query: query, }, none)
    ToggleTreeGroup(group) => {
      let collapsed : Array[String] = []
      let mut removed = false
      for item in state.tree_collapsed {
        if item == group {
          removed = true
        } else {
          collapsed.push(item)
        }
      }
      if !removed {
        collapsed.push(group)
      }
      ({ ..state, tree_collapsed: collapsed, }, none)
    }
  }
}

///|
/// 工程域 Feature(S2b-2):view 域刻意 abort——资源管理器视图由壳组装
/// (ai_sessions 同款口径)。
pub fn project_feature() -> @moui.Feature[ProjectState, ProjectMsg] {
  @moui.Feature::new(
    init=() => (ProjectState::new(), @moui.Effect::none()),
    update=fn(state, message) { update_project(state, message) },
    view=_state => abort("project views are composed by the parent shell"),
  )
}

// ============================================================================
// 切片私有助手(随臂迁来;壳侧同名包装保留给根臂调用)
// ============================================================================

///|
/// active tab(越界/无 tab 返回 None)。
fn active_file_of(state : ProjectState) -> OpenProjectFile? {
  if state.open_file_index >= 0 &&
    state.open_file_index < state.open_project_files.length() {
    Some(state.open_project_files[state.open_file_index])
  } else {
    None
  }
}

///|
/// 把目标目录从折叠集里摘掉(就地新建前调用:输入行要在可见处出现)。
fn unfold_dir(
  state : ProjectState,
  index : Int32,
  rel : String,
) -> Array[String] {
  let key = root_collapse_key(index, rel)
  let kept : Array[String] = []
  for item in state.project_tree_collapsed {
    if item != key {
      kept.push(item)
    }
  }
  kept
}

///|
/// 「全部折叠」的目标折叠集(整棵树逐层折上)。
pub fn collapse_all_tree_keys(state : ProjectState) -> Array[String] {
  let collapsed : Array[String] = []
  seed_all_collapse_keys(collapsed, state)
  collapsed
}

///|
pub fn seed_all_collapse_keys(
  collapsed : Array[String],
  state : ProjectState,
) -> Unit {
  match state.workspace_root {
    Some(workspace) =>
      seed_workspace_collapse_keys(collapsed, state.projects, workspace)
    None => {
      let mut index = 0
      for project in state.projects {
        seed_project_collapse_keys(collapsed, index, project, "")
        index = index + 1
      }
    }
  }
}

///|
pub fn seed_workspace_collapse_keys(
  collapsed : Array[String],
  projects : Array[ProjectRecord],
  workspace : WorkspaceRecord,
) -> Unit {
  push_collapse_key(collapsed, root_collapse_key(WORKSPACE_ROOT_INDEX, ""))
  for dir in workspace.dirs {
    if dir.rel_path != "" {
      push_collapse_key(
        collapsed,
        root_collapse_key(WORKSPACE_ROOT_INDEX, dir.rel_path),
      )
    }
  }
  let mut index = 0
  for project in projects {
    seed_project_collapse_keys(
      collapsed,
      index,
      project,
      tree_rel_under_workspace(workspace.root, project.root),
    )
    index = index + 1
  }
}

///|
pub fn seed_project_collapse_keys(
  collapsed : Array[String],
  index : Int32,
  project : ProjectRecord,
  row_rel : String,
) -> Unit {
  push_collapse_key(collapsed, root_collapse_key(index, row_rel))
  push_member_prefix_keys(collapsed, row_rel)
  for dir in project.scanned.dirs {
    if dir.rel_path != "" {
      push_collapse_key(collapsed, root_collapse_key(index, dir.rel_path))
    }
  }
}

///|
fn push_collapse_key(collapsed : Array[String], key : String) -> Unit {
  if !collapsed.contains(key) {
    collapsed.push(key)
  }
}

///|
fn push_member_prefix_keys(
  collapsed : Array[String],
  member_rel : String,
) -> Unit {
  let mut i = 0
  for c in member_rel {
    if c == '/' {
      push_collapse_key(
        collapsed,
        root_collapse_key(WORKSPACE_ROOT_INDEX, member_rel[0:i].to_owned()),
      )
    }
    i = i + 1
  }
}

///|
pub fn tree_rel_under_workspace(
  workspace_root : String,
  project_root : String,
) -> String {
  if project_root.has_prefix(workspace_root + "/") {
    project_root[workspace_root.length() + 1:].to_owned()
  } else {
    ""
  }
}

///|
/// 关闭下标处的 tab 并把 active 收敛到合法范围（S5f 自壳迁入）。
/// 删的是 active 时停在同位置的下一个 tab，尾部则回退一格。
pub fn close_open_file(state : ProjectState, index : Int32) -> ProjectState {
  if index < 0 || index >= state.open_project_files.length() {
    return state
  }
  let files : Array[OpenProjectFile] = []
  for i, file in state.open_project_files {
    if i != index {
      files.push(file)
    }
  }
  let next_index = if files.is_empty() {
    -1
  } else if index < files.length() {
    index
  } else {
    files.length() - 1
  }
  { ..state, open_project_files: files, open_file_index: next_index, }
}

///|
/// 原位替换下标处的 tab(光标/草稿/脏基准回写;壳根臂装载/保存也走这里)。
pub fn replace_open_file_at(
  files : Array[OpenProjectFile],
  index : Int32,
  open : OpenProjectFile,
) -> Array[OpenProjectFile] {
  let next : Array[OpenProjectFile] = []
  for i, file in files {
    if i == index {
      next.push(open)
    } else {
      next.push(file)
    }
  }
  next
}
