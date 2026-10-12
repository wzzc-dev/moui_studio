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
  seq : Int
}

///|
/// 打开的工程文件 tab（G4 多标签:数组承载,随 tab 携带光标状态）。
/// saved_content 是脏标记的基准;draft 是编辑中的内容。
pub(all) struct OpenProjectFile {
  rel : String
  saved_content : String
  draft : String
  /// 该 tab 的光标/选区（受控编辑器回传,切换 tab 恢复,不串台）
  caret : Int
  selection : @core.TextRange?
  /// `.md` tab 的 MoMark 文档会话（块级结构 + 选区 reveal 的真编辑面）;
  /// 非 md tab 恒为 None。用 `with_md_session` 惰性重建,避免每个构造点
  /// 都要判后缀。
  md_session : @moui_richtext.MarkdownDocumentSession?
}
