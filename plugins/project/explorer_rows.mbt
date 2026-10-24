///|
/// 资源管理器行模型(S2a 出壳):树行构造/大纲解析/路径与滚动工具。
/// 状态经 `ExplorerData` 快照注入;消息回调与渲染留在壳(下一切片)。

///|
/// 资源管理器扁平行（虚拟化列表的数据项）：树形结构展平成行序列,
/// 行类型决定渲染分支。树行固定 24pt 高（@chrome.TREE_ROW_HEIGHT）,与
/// `virtual_list` 的固定步长窗口化契合——大目录只实例化可见行,
/// 展开/滚动不再整树重建（卡顿根因）。
///
/// 三处行内输入（新建文件 / 新建文件夹 / 改名）各自占一行,而不是挂在
/// 面板顶部:VS Code 的新建就发生在它要建进去的那个文件夹里,输入行贴着
/// 目标出现,用户才知道会建到哪。
pub(all) enum ExplorerRow {
  /// 分区头（打开的编辑器 / 文件夹 / 大纲 / 时间线）
  SectionRow(String, String, Bool, Int32) // id, label, expanded, count
  /// 分区空态提示
  SectionEmptyRow(String)
  /// inline 输入行（kind, depth）:kind = "file" / "folder" / "rename"
  InputRow(String, Int32)
  /// 顶层根行（工程下标, 模块名, 根路径, 是否活动）
  RootRow(Int32, String, String, Bool)
  /// 目录行（根下标, 目录 rel, 标签, 元信息, 深度, 是否展开）
  DirRow(Int32, String, String, String, Int32, Bool)
  /// 文件行（根下标, 文件 rel, 名称, 深度, 是否选中）
  FileRow(Int32, String, String, Int32, Bool)
  /// 打开的编辑器条目（tab 下标, 文档 id, 名称, 是否脏, 是否活动）
  EditorRow(Int32, String, String, Bool, Bool)
  /// 大纲条目（符号名, 行号, 深度）
  OutlineRow(String, Int32, Int32)
  /// 时间线条目（目标, 作者是 Agent, 动作文案）
  TimelineRow(String, Bool, String)
}

///|
/// 分区的默认折叠态（未登记 = 展开）。文件夹分区默认展开,其余默认收起。
pub fn section_collapsed(data : ExplorerData, id : String) -> Bool {
  if id == EXPLORER_SECTION_FOLDERS {
    data.explorer_sections_collapsed.contains(id)
  } else {
    !data.explorer_sections_collapsed.contains("open:" + id)
  }
}

///|
/// 树形结构 → 扁平行序列(纯派生)。
///
/// 行序与截图里的 VS Code 侧栏逐条对齐:
///
/// 1. **打开的编辑器**——只在真的有 tab 时出现。VS Code 也是这样:空的时候
///    整个分区连同标题都不画（一个「打开的编辑器 / 没有打开的文件」的空壳
///    白占两行,而侧栏最贵的就是纵向空间）。
/// 2. **顶层文件夹**——直接铺在工具栏之下,**没有**「文件夹」分区头。
///    工作区的根就是这个面板的主体,给它再套一层同名标题只是多一行灰字
///    （VS Code 的多根工作区同样不画这一层）。
/// 3. **大纲** / 4. **时间线**——次级视图,折叠态默认收起。
///
/// 前两条是**按截图校正过的**:早先版本无论有没有 tab 都画「打开的编辑器」
/// 标题、并且在根之上又加了一层「文件夹」头,两处都白吃掉 24pt。
pub fn explorer_rows(
  data : ExplorerData,
  t : @i18n.Translator,
) -> Array[ExplorerRow] {
  let rows : Array[ExplorerRow] = []
  push_editor_section(data, t, rows)
  push_folders_section(data, t, rows)
  push_outline_section(data, t, rows)
  push_timeline_section(data, t, rows)
  rows
}

///|
/// 「打开的编辑器」分区:打开的 tab 列表（脏标记 + 活动高亮）。
///
/// **没有打开的 tab 时整段不产出**（连分区头都不画）——与 VS Code 一致。
fn push_editor_section(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  let count = data.open_editors.length()
  if count == 0 {
    return
  }
  let id = "editors"
  let expanded = !section_collapsed(data, id)
  rows.push(
    SectionRow(id, text(t, "app.explorer.open_editors"), expanded, count),
  )
  if !expanded {
    return
  }
  for editor in data.open_editors {
    rows.push(
      EditorRow(
        editor.index,
        editor.id,
        editor.label,
        editor.dirty,
        editor.index == data.open_editor_active,
      ),
    )
  }
}

///|
/// 顶层文件夹:单树多根——每个已导入工程一棵顶层文件夹,直接铺开。
///
/// 不画「文件夹」分区头（见 `explorer_rows` 的说明）;没有工程时给一行
/// 空态提示（导入入口在工具栏,已经永远可见）。
///
/// **工作区导入时只有一棵根**:`moon.work` 的那个根（截图里的 `MoUI`）。
/// 成员模块是它的子目录,根上的 `gradlew`/`README.md`/`moon.work`… 与成员
/// 目录**同级**列出——这正是用户反馈「看不到根目录下的文件」的修复点。
/// 没有这层统一根,53 个成员会各自成为顶层行,而根自己那一层无处安放。
fn push_folders_section(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  if data.projects.length() == 0 && data.workspace_root is None {
    rows.push(SectionEmptyRow(text(t, "app.explorer.empty")))
    return
  }
  match data.workspace_root {
    Some(record) => push_workspace_root(data, t, rows, record)
    None =>
      for index, project in data.projects {
        push_project_root(data, t, rows, index, project)
      }
  }
}

///|
/// 工作区根子树（截图里的顶层 `MoUI` 行）。
///
/// 行序与 Finder/VS Code 一致:**文件夹在前、文件在后**,两类各自按名称
/// 排序。成员目录与根上的普通目录（`docs/`、`scripts/`…）混在同一层同级
/// 排序——成员身份是语义,不该改变它在树上的位置。
fn push_workspace_root(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  record : WorkspaceRecord,
) -> Unit {
  // 折叠键用负下标:工作区根与「第 N 个工程根」共用一个键空间,
  // 用负数保证永不与成员下标相撞。
  let root_key = root_collapse_key(WORKSPACE_ROOT_INDEX, "")
  let expanded = !dir_collapsed(data, root_key)
  rows.push(
    RootRow(
      WORKSPACE_ROOT_INDEX,
      record.name,
      record.root,
      data.workspace_root is Some(_),
    ),
  )
  if !expanded {
    return
  }
  // 就地输入行挂在根行之下（新建目标 = 工作区根 "")
  push_input_rows(data, rows, WORKSPACE_ROOT_INDEX, "", 1)
  // 逐层铺开:目录（含成员的中间目录）在前、文件在后。
  //
  // **不再遍历成员平铺**——那正是「examples 下的模块直接显示、收起 examples
  // 收不掉里面」的根因:成员路径是多段的,平铺会让中间目录不存在。
  push_workspace_tier(data, t, rows, record, "", 1)
}

///|
/// 递归铺开工作区根下 `parent_rel` 这一层:每个子目录一行,成员在自己那
/// 一层由成员行渲染,其余目录继续递归;最后是这一层的文件。
fn push_workspace_tier(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  record : WorkspaceRecord,
  parent_rel : String,
  depth : Int32,
) -> Unit {
  let tier = workspace_tier(data, record, parent_rel)
  for name in tier.dirs {
    let rel = join_rel(parent_rel, name)
    let key = root_collapse_key(WORKSPACE_ROOT_INDEX, rel)
    let expanded = !dir_collapsed(data, key)
    match member_index_at(data, rel) {
      Some(index) =>
        // 这一层正好是一个成员:渲染成员行（元信息给入口概要 + 成员内部）
        push_member_dir(data, t, rows, index, rel, name, depth)
      None => {
        rows.push(DirRow(WORKSPACE_ROOT_INDEX, rel, name, "", depth, expanded))
        if expanded {
          push_workspace_tier(data, t, rows, record, rel, depth + 1)
        }
      }
    }
  }
  for name in tier.files {
    push_file_row(
      data,
      rows,
      WORKSPACE_ROOT_INDEX,
      join_rel(parent_rel, name),
      depth,
    )
  }
}

///|
/// 算出工作区根下 `parent_rel` 这一层的子项:目录 = 扫描到的真实目录 ∪
/// 成员路径在这一层的前缀段;文件 = 该层的普通文件。
fn workspace_tier(
  data : ExplorerData,
  record : WorkspaceRecord,
  parent_rel : String,
) -> ExplorerTier {
  let dir_names : Array[String] = []
  // 1) 扫描到的真实目录（非成员部分已经在扫描层排除了成员内部）
  for child in child_dirs_of(record.dirs, parent_rel) {
    dir_names.push(rel_path_last_segment(child.rel_path))
  }
  // 2) 成员路径在这一层的前缀段——中间目录也要补出来
  for project in data.projects {
    let member_rel = tree_rel_of_project(data, project)
    if member_rel == "" {
      continue
    }
    let segment = tier_segment_below(member_rel, parent_rel)
    if segment != "" && !dir_names.contains(segment) {
      dir_names.push(segment)
    }
  }
  let files : Array[String] = []
  match find_dir(record.dirs, parent_rel) {
    Some(dir) =>
      for name in dir.files {
        files.push(name)
      }
    None => ()
  }
  ExplorerTier::{ dirs: sorted_names(dir_names), files: sorted_names(files), }
}

///|
/// 把 `rel` 相对 `parent` 的**第一段**取出来（不在 parent 之下则空串）。
///
/// `tier_segment_below("examples/terminal", "examples") = "terminal"`;
/// `tier_segment_below("examples/terminal", "") = "examples"`。
fn tier_segment_below(rel : String, parent : String) -> String {
  let rest = if parent == "" {
    rel
  } else if rel == parent {
    // 成员**就是**这一层:它自己由成员行渲染,不再补一个同名中间目录
    return ""
  } else if rel.has_prefix(parent + "/") {
    rel[parent.length() + 1:].to_owned()
  } else {
    return ""
  }
  head_segment(rest)
}

///|
/// 取路径的第一段（`a/b/c` → `a`;无斜杠 → 整串）。
fn head_segment(rel : String) -> String {
  let mut i = 0
  for c in rel {
    if c == '/' {
      return rel[0:i].to_owned()
    }
    i = i + 1
  }
  rel
}

///|
/// 树相对路径是否**正好**是一个成员的根（是则这一行由成员行渲染）。
fn member_index_at(data : ExplorerData, rel : String) -> Int32? {
  let mut index = 0
  for project in data.projects {
    if tree_rel_of_project(data, project) == rel {
      return Some(index)
    }
    index = index + 1
  }
  None
}

///|
/// 一个成员模块在树上的目录行（工作区根的子目录）。
///
/// 成员的 `rel` 在树上必须带成员路径前缀（`moui_studio/app/app.mbt`）——
/// 工作区的树只有一个命名空间,不带前缀会让两个成员的同名文件撞成一行。
fn push_member_dir(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int32,
  member_rel : String,
  label : String,
  depth : Int32,
) -> Unit {
  let project = data.projects[index]
  let meta = project_entry_meta(project)
  // 折叠键用**成员下标 + 成员在树上的 rel**:成员路径可能是多段的
  // （`examples/terminal`）,键必须唯一到"这一层的那一个目录",否则
  // `examples` 与 `examples/terminal` 会互相折叠。
  let key = root_collapse_key(index, member_rel)
  let expanded = !dir_collapsed(data, key)
  rows.push(DirRow(index, member_rel, label, meta, depth, expanded))
  if !expanded {
    return
  }
  push_input_rows(data, rows, index, "", depth + 1)
  for child in child_dirs_of(project.scanned.dirs, "") {
    push_member_dir_subtree(
      data,
      t,
      rows,
      index,
      project,
      child.rel_path,
      depth + 1,
    )
  }
  match find_dir(project.scanned.dirs, "") {
    Some(dir) =>
      for name in sorted_names(dir.files) {
        push_file_row(data, rows, index, join_rel(member_rel, name), depth + 1)
      }
    None => ()
  }
}

///|
/// 成员内部的目录子树（rel 为**工程相对**路径;行上的 rel 带成员前缀）。
fn push_member_dir_subtree(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int32,
  project : ProjectRecord,
  rel : String,
  depth : Int32,
) -> Unit {
  let member_rel = tree_rel_of_project(data, project)
  let dir = find_dir(project.scanned.dirs, rel)
  let label = rel_path_last_segment(rel)
  let meta = project_dir_meta(project, rel, t)
  let expanded = !dir_collapsed(data, root_collapse_key(index, rel))
  rows.push(DirRow(index, rel, label, meta, depth, expanded))
  if !expanded {
    return
  }
  push_input_rows(data, rows, index, rel, depth + 1)
  for child in child_dirs_of(project.scanned.dirs, rel) {
    push_member_dir_subtree(
      data,
      t,
      rows,
      index,
      project,
      child.rel_path,
      depth + 1,
    )
  }
  match dir {
    Some(entry) =>
      for name in sorted_names(entry.files) {
        push_file_row(
          data,
          rows,
          index,
          join_rel(member_rel, join_rel(rel, name)),
          depth + 1,
        )
      }
    None => ()
  }
}

///|
/// 一棵工程根子树：根行（= 工程根目录自身,折叠它收起整棵树）→ 目录 → 文件。
///
/// `depth` 从 0 起算:根行与 VS Code 的顶层文件夹行同语义（可折叠、可
/// 就地新建、右侧元信息给入口概要）。
fn push_project_root(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int32,
  project : ProjectRecord,
) -> Unit {
  let active = index == data.active_project
  // 折叠键带根下标:不同工程的同名目录（如每个工程都有 `app/`）必须
  // 各折各的——按 rel 单键会让折叠一个工程的 app/ 把别的也折上。
  let root_key = root_collapse_key(index, "")
  let expanded = !dir_collapsed(data, root_key)
  rows.push(RootRow(index, project.module_name, project.root, active))
  if !expanded {
    return
  }
  // 就地输入行挂在根行之下（新建的目标目录 = 工程根 ""）
  push_input_rows(data, rows, index, "", 1)
  for child in child_dirs_of(project.scanned.dirs, "") {
    push_dir_subtree(data, t, rows, index, project, child.rel_path, 1)
  }
  // 根目录自身的普通文件(README/LICENSE/moon.mod 等)挂在根行之下
  match find_dir(project.scanned.dirs, "") {
    Some(dir) =>
      for name in sorted_names(dir.files) {
        push_file_row(data, rows, index, name, 1)
      }
    None => ()
  }
}

///|
/// 递归挂一棵目录子树:目录行(折叠态则到此为止)→ 就地输入行 → 子目录 →
/// 该目录的文件。
fn push_dir_subtree(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int32,
  project : ProjectRecord,
  rel : String,
  depth : Int32,
) -> Unit {
  let dir = find_dir(project.scanned.dirs, rel)
  let label = rel_path_last_segment(rel)
  let meta = project_dir_meta(project, rel, t)
  let expanded = !dir_collapsed(data, root_collapse_key(index, rel))
  rows.push(DirRow(index, rel, label, meta, depth, expanded))
  if expanded {
    push_input_rows(data, rows, index, rel, depth + 1)
    for child in child_dirs_of(project.scanned.dirs, rel) {
      push_dir_subtree(data, t, rows, index, project, child.rel_path, depth + 1)
    }
    match dir {
      Some(entry) =>
        for name in sorted_names(entry.files) {
          // 文件 rel 必须带目录前缀(选中/打开/改名都按「工程相对路径」
          // 寻址);根目录(rel = "")的文件 rel 就是文件名本身。
          let file_rel = join_rel(rel, name)
          push_file_row(data, rows, index, file_rel, depth + 1)
        }
      None => ()
    }
  }
}

///|
/// 目标目录下的 inline 输入行（新建文件 / 新建文件夹 / 改名共用一行位）。
///
/// 挂在**展开的目录之下**而不是面板顶部:用户在哪一层点的新建,输入行就
/// 出现在哪一层,提交目标不需要猜。
fn push_input_rows(
  data : ExplorerData,
  rows : Array[ExplorerRow],
  index : Int32,
  rel : String,
  depth : Int32,
) -> Unit {
  ignore(index)
  // 判据只看**目标目录**:`file_create_dir` 已经是树相对路径（工作区导入时
  // 带成员前缀），它在整棵树里唯一。早先还额外要求
  // `index == active_project`,那条守卫让「工作区根上新建」
  // （index = WORKSPACE_ROOT_INDEX,永远不等于 active_project）永远画不出
  // 输入行——点了 ＋ 什么都没发生。
  if data.file_create_dir != rel {
    return
  }
  if data.file_create_open {
    rows.push(InputRow("file", depth))
  }
  if data.folder_create_open {
    rows.push(InputRow("folder", depth))
  }
}

///|
/// 挂一个文件行(rel = 该文件相对模块根的完整路径;重命名态替换为输入行)。
fn push_file_row(
  data : ExplorerData,
  rows : Array[ExplorerRow],
  index : Int32,
  rel : String,
  depth : Int32,
) -> Unit {
  if index == data.active_project && data.file_rename_open == Some(rel) {
    rows.push(InputRow("rename", depth))
  } else {
    rows.push(
      FileRow(
        index,
        rel,
        rel_path_last_segment(rel),
        depth,
        data.selected_project_file == Some(rel),
      ),
    )
  }
}

///|
/// 「大纲」分区:当前活动文件的行级符号。
///
/// 数据源是**当前 tab 的草稿**（不是磁盘内容）:编辑中的文件大纲应随
/// 输入即时变化,而不是等保存。没有打开文件时给空态。
fn push_outline_section(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  let id = "outline"
  let symbols = match active_open_editor(data) {
    Some(editor) => outline_symbols(editor.rel, editor.draft)
    None => []
  }
  let expanded = !section_collapsed(data, id)
  rows.push(
    SectionRow(id, text(t, "app.explorer.outline"), expanded, symbols.length()),
  )
  if !expanded {
    return
  }
  if symbols.length() == 0 {
    rows.push(SectionEmptyRow(text(t, "app.explorer.outline_empty")))
    return
  }
  for symbol in symbols {
    rows.push(OutlineRow(symbol.name, symbol.line, symbol.depth))
  }
}

///|
/// 「时间线」分区:会话内的改动记录（原「最近修改」底部条搬进分区）。
fn push_timeline_section(
  data : ExplorerData,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  let id = "timeline"
  let recent = recent_tail(data.recent_changes, EXPLORER_TIMELINE_ROWS)
  let expanded = !section_collapsed(data, id)
  rows.push(
    SectionRow(
      id,
      text(t, "app.explorer.timeline"),
      expanded,
      data.recent_changes.length(),
    ),
  )
  if !expanded {
    return
  }
  if recent.length() == 0 {
    rows.push(SectionEmptyRow(text(t, "app.explorer.timeline_empty")))
    return
  }
  for change in recent {
    rows.push(
      TimelineRow(change.target, change.by_agent, text(t, change.action)),
    )
  }
}

///|
/// 大纲符号（名称 + 行号 + 缩进层级）。
pub(all) struct OutlineSymbol {
  name : String
  line : Int32
  depth : Int32
}

///|
/// 从源码文本抽出大纲符号（纯函数,不依赖模型）。
///
/// 识别口径是**声明行**而不是完整语言服务:MoonBit 的 `fn` / `struct` /
/// `enum` / `trait` / `impl` / `type` / `let` / `test`，Markdown 的标题。
/// 前导空格决定层级。这不是编译器级的符号表（那需要 `moon ide` 子进程），
/// 但足以让侧栏列出「这个文件里有什么」——VS Code 的 Outline 在没有语言
/// 服务时也是这个降级形态。
pub fn outline_symbols(rel : String, source : String) -> Array[OutlineSymbol] {
  let symbols : Array[OutlineSymbol] = []
  let markdown = rel.has_suffix(".md")
  let mut line_no = 0
  for view in source.split("\n") {
    line_no = line_no + 1
    let line = view.to_owned()
    if markdown {
      match markdown_heading(line) {
        Some((level, title)) =>
          symbols.push(OutlineSymbol::{
            name: title,
            line: line_no,
            depth: level - 1,
          })
        None => ()
      }
    } else {
      match moonbit_declaration(line) {
        Some((indent, name)) =>
          symbols.push(OutlineSymbol::{ name, line: line_no, depth: indent, })
        None => ()
      }
    }
  }
  symbols
}

///|
/// Markdown 标题行 → (层级, 标题文本);非标题返回 None。
fn markdown_heading(line : String) -> (Int32, String)? {
  let mut hashes = 0
  for c in line {
    if c == '#' {
      hashes = hashes + 1
    } else {
      break
    }
  }
  if hashes == 0 || hashes > 6 {
    return None
  }
  let rest = line[hashes:].to_owned()
  // ATX 标题要求 `#` 后跟空格（`#tag` 不是标题）
  if !rest.has_prefix(" ") {
    return None
  }
  let title = rest.trim(chars=" \t").to_owned()
  if title == "" {
    None
  } else {
    Some((hashes, title))
  }
}

///|
/// MoonBit 声明行的关键字（顺序即匹配优先级）。
fn moonbit_decl_keywords() -> Array[String] {
  [
    "pub fn", "fn", "pub struct", "struct", "pub enum", "enum", "pub trait", "trait",
    "impl", "pub type", "type", "typealias", "pub let", "let", "const", "test",
  ]
}

///|
/// 声明行 → (缩进层级, 展示名);非声明返回 None。
///
/// 展示名取关键字之后的标识符;`impl` 行没有名字可取时用整行（
/// `impl @core.ViewNode for Divider` 这种,裁掉多余空白后仍可读）。
fn moonbit_declaration(line : String) -> (Int32, String)? {
  let indent = leading_spaces(line)
  let trimmed = line.trim(chars=" \t").to_owned()
  if trimmed == "" {
    return None
  }
  // 注释行不是声明
  if trimmed.has_prefix("//") || trimmed.has_prefix("///") {
    return None
  }
  for keyword in moonbit_decl_keywords() {
    if !trimmed.has_prefix(keyword) {
      continue
    }
    let after = trimmed[keyword.length():].to_owned()
    // `pub fnx` 这类前缀误命中要挡掉:关键字后必须是空白或行尾
    if after != "" && !after.has_prefix(" ") {
      continue
    }
    let name = declaration_name(after.trim(chars=" \t").to_owned())
    if name != "" {
      return Some((indent, name))
    }
  }
  None
}

///|
/// 声明后的名字:标识符（`foo(...)` → `foo`）;若第一个非空字符是引号
/// （`test "名字"`）,取引号里的字面量。取不到返回空串。
fn declaration_name(rest : String) -> String {
  if rest.has_prefix("\"") {
    let inner = rest[1:].to_owned()
    let mut literal = ""
    for c in inner {
      // 用码点比较而不是字符字面量 `'"'`：死消息门
      // （`validate-dead-messages`）的注释/字符串剥离器不认字符字面量，
      // 源码里出现一个「内含引号的字符字面量」会让它把该引号当成字符串
      // 起始、此后整份文件都被抹成空白——该文件里所有变体随即被判成
      // 「没有构造点」而整套失败（实测）。码点写法在语义上完全等价。
      if c.to_int() == 34 {
        break
      }
      literal = literal + c.to_string()
    }
    return literal
  }
  let mut name = ""
  for c in rest {
    let code = c.to_int()
    let is_word = (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F
    if is_word {
      name = name + c.to_string()
    } else {
      break
    }
  }
  name
}

///|
/// 行首空格数（Tab 按 2 个空格计）。
fn leading_spaces(line : String) -> Int32 {
  let mut count = 0
  for c in line {
    if c == ' ' {
      count = count + 1
    } else if c == '\t' {
      count = count + 2
    } else {
      break
    }
  }
  // 缩进档位化:2 空格一档（MoonBit 惯例）,避免层级抖动
  count / 2
}

// ============================================================================
// 树结构工具
// ============================================================================

///|
/// 目录折叠键（根下标 + rel）:不同工程的同名目录各自折叠。
pub fn root_collapse_key(index : Int32, rel : String) -> String {
  "\{index}:\{rel}"
}

///|
/// 直接子目录(rel_path 的父链正好是 parent;**文件夹优先、同类按名称**
/// 排序,与 VS Code 的资源管理器一致——扫描序是 BFS 发现序,不是给人读的序)。
///
/// 根目录条目(rel_path = "")的父链也是 ""——它必须被显式排除,否则
/// `child_dirs_of(dirs, "")` 把根自己收进来,`push_dir_subtree` 无限递归
/// 爆栈(实测 SIGSEGV: Thread stack size exceeded 的根因)。
pub fn child_dirs_of(
  dirs : Array[@scan.ScannedDir],
  parent : String,
) -> Array[@scan.ScannedDir] {
  let children : Array[@scan.ScannedDir] = []
  for dir in dirs {
    if dir.rel_path == "" {
      continue
    }
    if parent_of(dir.rel_path) == parent {
      children.push(dir)
    }
  }
  // 目录之间按名称排序（不区分大小写,与 VS Code 的 natural sort 观感
  // 一致;ASCII 比较会把大写全排到前面,读起来是乱的）
  children.sort_by(fn(left, right) {
    name_order(
      rel_path_last_segment(left.rel_path),
      rel_path_last_segment(right.rel_path),
    )
  })
  children
}

///|
/// 名称排序:不区分大小写,大小写只作同名前后的决胜。
///
/// **必须用 `lexical_compare`,不能用 `compare`**——MoonBit 的
/// `String::compare` 是**先比长度**的序（实测 `"zeta".compare("Alpha") = -1`
/// 而 `"ab".compare("b") = 1`）,拿它排文件名会得到「短的在前」这种没人
/// 认得的顺序（实测该缺陷被本文件的排序测试逮住）。
fn name_order(left : String, right : String) -> Int32 {
  let folded = left.to_lower().lexical_compare(right.to_lower())
  if folded != 0 {
    folded
  } else {
    left.lexical_compare(right)
  }
}

///|
/// 文件名排序（同一个 `name_order` 口径）。
fn sorted_names(names : Array[String]) -> Array[String] {
  let sorted = names.copy()
  sorted.sort_by(name_order)
  sorted
}

///|
/// 拼接目录与名称（根目录 rel = "" 时就是名称本身）。
pub fn join_rel(rel : String, name : String) -> String {
  if rel == "" {
    name
  } else {
    "\{rel}/\{name}"
  }
}

///|
/// 相对路径的父路径("a/b/c" → "a/b";无斜杠 → "")。
pub fn parent_of(rel : String) -> String {
  let mut last = -1
  let mut i = 0
  for c in rel {
    if c == '/' {
      last = i
    }
    i = i + 1
  }
  if last < 0 {
    ""
  } else {
    rel[0:last].to_owned()
  }
}

///|
/// 相对路径的最后一段("a/b/c" → "c";"" → "")。
pub fn rel_path_last_segment(rel : String) -> String {
  let mut last = -1
  let mut i = 0
  for c in rel {
    if c == '/' {
      last = i
    }
    i = i + 1
  }
  rel[last + 1:].to_owned()
}

///|
/// 按 rel_path 找目录条目。
fn find_dir(dirs : Array[@scan.ScannedDir], rel : String) -> @scan.ScannedDir? {
  for dir in dirs {
    if dir.rel_path == rel {
      return Some(dir)
    }
  }
  None
}

///|
/// 目录是否折叠(默认展开)。
pub fn dir_collapsed(data : ExplorerData, key : String) -> Bool {
  data.project_tree_collapsed.contains(key)
}

///|
/// 目录行元信息:是 MoonBit 包则标注入口类别(web / native / 包),
/// 否则标注文件数。结构与语义的关注点在这一行汇合。
fn project_dir_meta(
  project : ProjectRecord,
  rel : String,
  t : @i18n.Translator,
) -> String {
  for pkg in project.scanned.packages {
    if pkg.rel_path == rel {
      return project_kind_label(pkg.kind, t)
    }
  }
  match find_dir(project.scanned.dirs, rel) {
    Some(dir) => "\{dir.files.length()}"
    None => ""
  }
}

///|
/// 文件类型图标（VS Code 的 Seti 口径:一眼看出这是什么文件）。
pub fn file_icon(name : String) -> @style.IconName {
  match file_tint(name) {
    @chrome.TintCode => FileCode
    @chrome.TintDoc => FileMarkdown
    @chrome.TintConfig => FileJson
    @chrome.TintAsset => FileImage
    @chrome.TintPlain => File
  }
}

///|
/// 文件名的类型色系（图标形状与颜色共用同一个判据——两处各写一遍后缀
/// 列表,迟早会出现「形状是 JSON、颜色是文档」这种自相矛盾的行）。
pub fn file_tint(name : String) -> @chrome.IconTint {
  if name.has_suffix(".mbt") || name.has_suffix(".mbti") {
    @chrome.TintCode
  } else if name.has_suffix(".md") || name.has_suffix(".markdown") {
    @chrome.TintDoc
  } else if name.has_suffix(".json") ||
    name.has_suffix(".mod") ||
    name.has_suffix(".work") ||
    name.has_suffix(".pkg") ||
    name.has_suffix(".toml") ||
    name.has_suffix(".yaml") ||
    name.has_suffix(".yml") {
    @chrome.TintConfig
  } else if name.has_suffix(".png") ||
    name.has_suffix(".jpg") ||
    name.has_suffix(".jpeg") ||
    name.has_suffix(".gif") ||
    name.has_suffix(".webp") ||
    name.has_suffix(".svg") ||
    name.has_suffix(".ico") {
    @chrome.TintAsset
  } else {
    @chrome.TintPlain
  }
}

// ============================================================================
// 滚动
// ============================================================================

///|
/// 滚动偏移钳制：窗口化计算与绘制平移共用的同一口径——负值归 0,
/// 超出内容尾部钳到 `行数×行高 - 视口`（内容不足一屏 = 0）。虚拟化
/// 列表视口落进尾部 spacer 区时行会「消失」,钳制保证偏移永远落在
/// 真实行范围内。
pub fn explorer_clamp_scroll_y(
  row_count : Int32,
  viewport_height : Double,
  scroll_y : Double,
) -> Double {
  let max_scroll = (row_count.to_double() * @chrome.TREE_ROW_HEIGHT -
  viewport_height).max(0.0)
  if scroll_y < 0.0 {
    0.0
  } else if scroll_y > max_scroll {
    max_scroll
  } else {
    scroll_y
  }
}

///|
/// 虚拟化行的稳定 key:行类型 + 身份(rel/下标),滚动窗口重挂时不串状态。
pub fn explorer_row_key(row : ExplorerRow) -> String {
  match row {
    SectionRow(id, _, _, _) => "section-\{id}"
    SectionEmptyRow(id) => "section-empty-\{id}"
    InputRow(kind, _) => "input-\{kind}"
    RootRow(index, _, _, _) => "root-\{index}"
    DirRow(index, rel, _, _, _, _) => "dir-\{index}:\{rel}"
    FileRow(index, rel, _, _, _) => "file-\{index}:\{rel}"
    EditorRow(_, id, _, _, _) => "editor-\{id}"
    OutlineRow(name, line, _) => "outline-\{line}:\{name}"
    TimelineRow(target, _, action) => "timeline-\{target}:\{action}"
  }
}

///|
/// 包类别标签:入口(web / native)或普通包。
pub fn project_kind_label(
  kind : @scan.PackageKind,
  t : @i18n.Translator,
) -> String {
  match kind {
    @scan.PkWebEntry => text(t, "app.project.kind.web")
    @scan.PkNativeEntry => text(t, "app.project.kind.native")
    @scan.PkPlain => text(t, "app.project.kind.plain")
  }
}

///|
/// 根行的概要:web / native 入口与逻辑包数量。
pub fn project_entry_meta(project : ProjectRecord) -> String {
  let parts : Array[String] = []
  if project.scanned.web_entry != "" {
    parts.push("web:\{project.scanned.web_entry}")
  }
  if project.scanned.native_entry != "" {
    parts.push("native:\{project.scanned.native_entry}")
  }
  parts.push("program:\{project.scanned.program_packages.length()}")
  let mut out = ""
  let mut i = 0
  for part in parts {
    if i > 0 {
      out = out + " · "
    }
    out = out + part
    i = i + 1
  }
  out
}

///|
/// 根行的入口概要（按工程下标取;越界给空串）。
pub fn project_entry_meta_of(data : ExplorerData, index : Int32) -> String {
  if index >= 0 && index < data.projects.length() {
    project_entry_meta(data.projects[index])
  } else {
    ""
  }
}

// ============================================================================
// 测试探针（黑盒包看不见私有派生,这四件是唯一出口）
// ============================================================================

///|
/// 分区当前是否展开（视图与测试共用的单一判定,避免测试自己复述
/// 「默认谁展开」的规则而与视图漂移）。
pub fn explorer_section_expanded(data : ExplorerData, id : String) -> Bool {
  !section_collapsed(data, id)
}

///|
/// 目录排序探针:黑盒测试用它锁定「文件夹优先 + 名称不区分大小写」。
pub fn explorer_child_dirs_for_test(
  dirs : Array[@scan.ScannedDir],
  parent : String,
) -> Array[@scan.ScannedDir] {
  child_dirs_of(dirs, parent)
}

///|

///|
/// 打开的编辑器只读行投影：文档正文归 workbench，插件只读展示与本行
/// 派生（大纲取活动行草稿），不持有可写副本。
pub(all) struct OpenEditorRow {
  id : String
  index : Int32
  rel : String
  label : String
  dirty : Bool
  draft : String
}

///|
/// 资源管理器行模型的只读快照:壳从 ExplorerData 组装,行模型只经它读取工程域
/// 状态(插件不持有可变状态——markdown/terminal 无状态视图贡献先例)。
pub(all) struct ExplorerData {
  projects : Array[ProjectRecord]
  active_project : Int32
  workspace_root : WorkspaceRecord?
  open_editors : Array[OpenEditorRow]
  /// 文件行里的活动下标；-1 = 活动的是 Studio 文档（不画文件编辑器行）
  open_editor_active : Int32
  project_tree_collapsed : Array[String]
  explorer_sections_collapsed : Array[String]
  selected_project_file : String?
  recent_changes : Array[RecentChange]
  file_create_dir : String
  file_create_open : Bool
  file_rename_open : String?
  folder_create_open : Bool
}

///|
/// 资源管理器默认展开的分区（文件夹总是展开;其余收起,与 VS Code 首次
/// 启动的观感一致——侧栏先给树,大纲/时间线是按需展开的次级视图）。
pub const EXPLORER_SECTION_FOLDERS : String = "folders"

///|
/// 工作区根在折叠键空间里的下标（与成员下标不冲突）。
pub const WORKSPACE_ROOT_INDEX : Int32 = -1

///|
/// 分区行缩进（分区头/空态比第一层目录再进一档,读成「挂在分区下」）。
pub const EXPLORER_SECTION_INDENT : Int32 = 1

///|
/// 工程在工作区里的相对路径（工作区根到工程根）;单模块导入 = ""。
pub fn tree_rel_of_project(
  data : ExplorerData,
  project : ProjectRecord,
) -> String {
  match data.workspace_root {
    None => ""
    Some(record) =>
      if project.root.has_prefix(record.root + "/") {
        project.root[record.root.length() + 1:].to_owned()
      } else {
        ""
      }
  }
}

///|
/// 工程相对路径 → 工作区相对路径（在树上寻址用）。
pub fn tree_rel_of_project_file(
  data : ExplorerData,
  project : ProjectRecord,
  project_rel : String,
) -> String {
  join_rel(tree_rel_of_project(data, project), project_rel)
}

///|
/// 活动文件行（-1 = Studio 文档常驻，或下标越界）。
pub fn active_open_editor(data : ExplorerData) -> OpenEditorRow? {
  if data.open_editor_active >= 0 &&
    data.open_editor_active < data.open_editors.length() {
    Some(data.open_editors[data.open_editor_active])
  } else {
    None
  }
}

///|
/// 最近修改尾部 N 条（新的在下——设计稿是最近在最上，取尾部后反转）。
pub fn recent_tail(
  changes : Array[RecentChange],
  count : Int32,
) -> Array[RecentChange] {
  let tail : Array[RecentChange] = []
  let mut index = changes.length() - 1
  while index >= 0 && tail.length() < count {
    tail.push(changes[index])
    index = index - 1
  }
  tail
}

// ============================================================================
// 底栏（审计 + Console）
// ============================================================================

///|
/// 常用取词（视图层统一入口;与壳 i18n.mbt 同实现,插件自持 1 行）。
fn text(t : @i18n.Translator, key : String) -> String {
  t.translate(key)
}

///|
/// 分区里最多列几条时间线（侧栏是提示,不是完整历史）。
const EXPLORER_TIMELINE_ROWS : Int32 = 12

// ============================================================================
// 大纲符号提取
// ============================================================================

///|
/// 工作区根下的**一层**子项:目录（可能含成员）与文件,各自排好序。
///
/// 为什么要按层拼装而不是「遍历成员平铺」:成员路径可以是多段的
/// （`examples/terminal`、`benchmarks/full_cycle`）。直接遍历成员会让
/// `examples/terminal` 变成顶层的一行,而 `examples` 这个**中间目录根本不存在**
/// ——用户看到的正是「examples 下的模块被平铺出来,收起 examples 收不掉里面」
/// （实测反馈）。正确的树必须先有 `examples` 节点,成员挂在它之下。
priv struct ExplorerTier {
  /// 子目录名（已排序）
  dirs : Array[String]
  /// 该层普通文件名（已排序）
  files : Array[String]
}
