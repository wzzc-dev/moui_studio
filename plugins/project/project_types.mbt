///|
/// MoUI Studio 工程域·共享数据类型(S2a 出壳:类型随行模型迁移,
/// 壳经 `pub type` 别名零改动引用;插件禁 import app)。

///|
/// 一个导入的 MoonBit 工程(会话内,不持久化)。
pub(all) struct ProjectRecord {
  /// 工程根目录(用户选中的绝对路径)
  root : String
  /// moon.mod 的 name(如 "examples/counter")
  module_name : String
  /// 扫描结果:包清单 + 入口判定
  scanned : @scan.ScannedModule
}

///|
/// 工作区根记录（资源管理器的单根行）。
///
/// `dirs` 是工作区根**自己**那一层的目录树（含非成员目录的递归展开），
/// rel_path 相对工作区根;成员目录**不**在 `dirs` 里——它们各自作为子行
/// 挂在这条根行之下（成员自己的目录树走各自 `ProjectRecord.scanned.dirs`）。
pub(all) struct WorkspaceRecord {
  root : String
  /// 根行的展示名（取根目录的最后一段）
  name : String
  dirs : Array[@scan.ScannedDir]
}

///|
/// 工作区根的展示名（路径最后一段;空则退回全路径）。
pub fn workspace_display_name(root : String) -> String {
  let name = rel_path_last_segment(root)
  if name == "" {
    root
  } else {
    name
  }
}

///|
/// 最近修改条目：谁在什么时候动了哪个对象（改属性/插控件/AI diff）。
/// 会话内 UI 事实，不进 IR、不持久化——它是「人做过什么」的教学材料。
pub(all) struct RecentChange {
  target : String
  // 作者标签（"你" / "Agent"）：i18n 在渲染层解析
  by_agent : Bool
  action : String
  seq : Int32
}

///|
/// 工程域状态切片(S2b-1 出壳):资源管理器/工程树的全部壳状态。
/// 壳经 `Feature::scope` 式单一字段 `model.project_state` 读写;文档正文
/// 与 tab 归 `moui_studio/workbench`(DocumentStore),这里不再持有可写副本。
/// 跨域真相(IR/undo/通知/事件出站)仍住壳——切片零副作用,ai_sessions 先例。
pub(all) struct ProjectState {
  projects : Array[ProjectRecord]
  active_project : Int32
  workspace_root : WorkspaceRecord?
  project_tree_collapsed : Array[String]
  explorer_sections_collapsed : Array[String]
  selected_project_file : String?
  explorer_scroll : @core.Point
  explorer_hover : String
  explorer_menu_open : Bool
  scan_progress : String?
  file_create_dir : String
  file_create_open : Bool
  file_rename_open : String?
  folder_create_open : Bool
  file_name_draft : String
  /// 左栏结构树（程序对象树）搜索查询与展开分组集合（S5f 并入切片）。
  mut tree_query : String
  mut tree_collapsed : Array[String]
  /// 结构树里展开着「新建」菜单的分组（"" = 没有）。
  mut tree_create_group : String
  /// G4 全文搜索查询草稿（命中集/忙碌标记是服务态，仍住壳）。
  mut search_query : String
}
