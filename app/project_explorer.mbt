///|
/// 左栏「资源管理器」页(VS Code 口径):单树多根 + 分区 + 行内动作。
///
/// 与旧版(M0-6a「工程列表 + 当前工程树」)的差别是三件事:
///
/// 1. **单树多根**。已导入的每个工程就是树里的一棵顶层文件夹,不再是
///    「上方一片工程列表、下方一棵当前工程的树」。点某个根行即切换到
///    该工程——「打开哪个工程」从两个控件收敛成一个(与 VS Code 的
///    multi-root workspace 同构)。
/// 2. **分区**。打开的编辑器 / 文件夹 / 大纲 / 时间线 四个可折叠分区,
///    与 VS Code 侧栏一一对应;折叠态是布局偏好,与树内目录折叠分开存。
/// 3. **行内动作**。改名 / 删除 / 新建只在**悬停行**出现(满屏图标会把
///    树读成一张操作表);新建是就地输入行,挂在目标目录之下。
///
/// 数据全部来自 `active_project_of` / `model.projects` 的**派生视图**:
/// 目录树由 `ScannedModule.dirs` 投影,文件列表随扫描快照,不单独存储
/// ——重新导入即刷新,与「扫描是真源」的口径一致。
///
/// 树形口径:**第一层是文件夹,不是包**。扫描层遍历过的每个目录(含不含
/// `moon.pkg`)都成为可折叠的行;该目录下的普通文件(README/LICENSE/
/// markdown/资源)直接挂在它下面。MoonBit 包的语义(入口类别)仍由
/// `ScannedModule.packages` 提供,在目录行的元信息位标注——「结构」与
/// 「语义」两个关注点分开,不再让包结构遮住文件。

///|
/// 资源管理器扁平行（虚拟化列表的数据项）：树形结构展平成行序列,
/// 行类型决定渲染分支。树行固定 24pt 高（@chrome.TREE_ROW_HEIGHT）,与
/// `virtual_list` 的固定步长窗口化契合——大目录只实例化可见行,
/// 展开/滚动不再整树重建（卡顿根因）。
///
/// 三处行内输入（新建文件 / 新建文件夹 / 改名）各自占一行,而不是挂在
/// 面板顶部:VS Code 的新建就发生在它要建进去的那个文件夹里,输入行贴着
/// 目标出现,用户才知道会建到哪。
priv enum ExplorerRow {
  /// 分区头（打开的编辑器 / 文件夹 / 大纲 / 时间线）
  SectionRow(String, String, Bool, Int) // id, label, expanded, count
  /// 分区空态提示
  SectionEmptyRow(String)
  /// inline 输入行（kind, depth）:kind = "file" / "folder" / "rename"
  InputRow(String, Int)
  /// 顶层根行（工程下标, 模块名, 根路径, 是否活动）
  RootRow(Int, String, String, Bool)
  /// 目录行（根下标, 目录 rel, 标签, 元信息, 深度, 是否展开）
  DirRow(Int, String, String, String, Int, Bool)
  /// 文件行（根下标, 文件 rel, 名称, 深度, 是否选中）
  FileRow(Int, String, String, Int, Bool)
  /// 打开的编辑器条目（tab 下标, 名称, 是否脏, 是否活动）
  EditorRow(Int, String, Bool, Bool)
  /// 大纲条目（符号名, 行号, 深度）
  OutlineRow(String, Int, Int)
  /// 时间线条目（目标, 作者是 Agent, 动作文案）
  TimelineRow(String, Bool, String)
}

///|
/// 资源管理器默认展开的分区（文件夹总是展开;其余收起,与 VS Code 首次
/// 启动的观感一致——侧栏先给树,大纲/时间线是按需展开的次级视图）。
pub const EXPLORER_SECTION_FOLDERS : String = "folders"

///|
/// 左栏「资源管理器」页主体（ide_shell 的 body 分派）。
pub fn project_explorer(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  // 工具栏（导入/新建/刷新/折叠）不参与虚拟化,滚动区只装行。
  let toolbar = explorer_toolbar(model, t, width)
  // 扫描进度读数（G2）:进行中才显示;导入完成/失败臂统一清 None
  let progress : Array[@moui.View[Msg]] = []
  match model.scan_progress {
    Some(line) =>
      progress.push(
        @views.padding_xy(
          @views.text(
            @chrome.fit_label(line, (width - 24.0).max(60.0)),
            theme=@chrome.studio_theme(),
            width=(width - 24.0).max(60.0),
            height=16.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_faint()),
          horizontal=12.0,
          vertical=2.0,
        ),
      )
    None => ()
  }
  // 树区:扁平行序列 → 虚拟化列表(只实例化可见行 + overscan)。
  // 偏移单一事实源:模型值按内容范围钳制后喂给列表——窗口化计算与
  // 绘制平移都从这一个值推导。此前用 ScrollRequest 做展开定位,与
  // 模型偏移双轨发散(请求偏移只生效一次,下一帧又被模型旧值覆盖),
  // 窗口按旧值算、绘制平移按新值走,视口落到 spacer 区读成
  // 「滚动后行消失」。
  let rows : Array[ExplorerRow] = explorer_rows(model, t)
  let toolbar_height = explorer_toolbar_height(model)
  let viewport_height = (height - toolbar_height - 4.0).max(@chrome.TREE_ROW_HEIGHT)
  let clamped_y = explorer_clamp_scroll_y(
    rows.length(),
    viewport_height,
    model.explorer_scroll.y,
  )
  let list = @views.virtual_list(
    rows,
    row => explorer_row_key(row),
    explorer_row_view(model, t, width~),
    item_height=@chrome.TREE_ROW_HEIGHT,
    viewport_height~,
    spacing=0.0,
    overscan=8,
    offset=@core.Point::new(x=0.0, y=clamped_y),
    on_scroll=offset => ExplorerScrolled(offset),
  )
  let all : Array[@moui.View[Msg]] = []
  all.push(toolbar)
  for view in progress {
    all.push(view)
  }
  all.push(list)
  @views.column(all, spacing=0.0)
}

// ============================================================================
// 工具栏
// ============================================================================

///|
/// 资源管理器顶部镶边总高（工具栏 + 按需的扫描进度行）。
///
/// **视图与视口高度必须共用这一个算式**：虚拟化列表的 `viewport_height`
/// 若比实际可用空间大，窗口会多算出一屏行、底部的行进到面板外面去；
/// 小则白白少渲染一屏。这里把「进度行在不在」也算进去——它是按需出现的
/// 第 17pt，正是最容易漏算的一处。
fn explorer_toolbar_height(model : Model) -> Double {
  // 动作行 26 + 空态才有的导入行 28
  let base = if model.projects.length() == 0 { 54.0 } else { 26.0 }
  // 溢出菜单展开时按行数加高（不变量:菜单行数与 `explorer_overflow_menu`
  // 实际产出的行数必须一致,否则视口会多算/少算一屏）。
  let menu = if model.explorer_menu_open {
    EXPLORER_MENU_ROWS.to_double() * @chrome.TREE_ROW_HEIGHT
  } else {
    0.0
  }
  let progress = match model.scan_progress {
    Some(_) => 20.0
    None => 0.0
  }
  base + menu + progress
}

///|
/// 溢出菜单的行数（与 `explorer_overflow_menu` 的产出等长;改菜单要同步
/// 改这里,`explorer_toolbar_height` 依赖它算视口）。
const EXPLORER_MENU_ROWS : Int = 5

///|
/// 顶部工具栏:四个图标动作（新建文件 / 新建文件夹 / 刷新 / 全部折叠）+
/// 右端 `⋯` 溢出菜单。
///
/// **导入行只在空态出现**（截图口径）:没有工程时它是唯一可发现的入口,
/// 图标化的文件夹加号对第一次打开这个面板的人不说明任何事,所以空态给一条
/// 带文字的「导入 MoonBit 工程…」。一旦有了工程,这条就消失——工作区的根
/// 才是主体,常驻的导入行白吃 28pt,而导入仍可从 `⋯` 菜单到达。
fn explorer_toolbar(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let has_project = model.projects.length() > 0
  let head : Array[@moui.View[Msg]] = []
  if !has_project {
    head.push(
      @views.container(
        @views.padding_edges(
          @views.row(
            [
              @views.icon(FolderOpen, size=13.0, color=@chrome.ide_accent()),
              @views.text(
                text(t, "app.project.import"),
                theme=@chrome.studio_theme(),
                width=(width - 60.0).max(60.0),
                height=18.0,
                align=TextStart,
              ).foreground(@chrome.ide_accent()),
            ],
            spacing=6.0,
            align=Center,
          ),
          left=12.0,
          right=8.0,
        ),
        height=28.0,
        width~,
        padding=0.0,
      ).on_tap(ImportProjectRequested),
    )
  }
  // 动作行:VS Code 的四个图标（新建文件 / 新建文件夹 / 刷新 / 全部折叠）。
  // 无工程时后三个禁用（点了没反应比灰掉更难懂）,但仍占位——工具栏跳动
  // 会让刚建立的肌肉记忆失准。
  let actions : Array[@moui.View[Msg]] = [
    explorer_tool_icon(
      FileNew,
      text(t, "app.explorer.new_file"),
      has_project,
      FileCreateAt(""),
    ),
    explorer_tool_icon(
      NewFolder,
      text(t, "app.explorer.new_folder"),
      has_project,
      FolderCreateAt(""),
    ),
    explorer_tool_icon(
      Refresh,
      text(t, "app.explorer.refresh"),
      has_project,
      ExplorerRefresh,
    ),
    explorer_tool_icon(
      CollapseAll,
      text(t, "app.explorer.collapse_all"),
      has_project,
      ExplorerCollapseAll,
    ),
  ]
  // 右端 `⋯` 溢出菜单（截图里标题栏右上角那一个）。用权重 spacer 顶到
  // 右缘——四个创建/视图动作靠左,溢出菜单靠右,与 VS Code 的分工一致。
  let actions_row : Array[@moui.View[Msg]] = []
  for action in actions {
    actions_row.push(action)
  }
  actions_row.push(@views.spacer(min_length=4.0, weight=1.0))
  actions_row.push(
    explorer_tool_icon(
      Ellipsis,
      text(t, "app.explorer.more"),
      true,
      ToggleExplorerMenu,
    ).background(
      if model.explorer_menu_open {
        @chrome.ide_hover()
      } else {
        @chrome.ide_panel()
      },
    ),
  )
  let action_row = @views.container(
    @views.padding_edges(
      @chrome.fill_row(actions_row, width, 2.0, Center),
      left=8.0,
      right=8.0,
    ),
    height=26.0,
    width~,
    padding=0.0,
  )
  let menu = explorer_overflow_menu(model, t, width)
  let cells : Array[@moui.View[Msg]] = []
  for view in head {
    cells.push(view)
  }
  cells.push(action_row)
  cells.push(menu)
  @views.column(cells, spacing=0.0)
}

///|
/// 标题栏 `⋯` 溢出菜单（就地展开的分区,与左栏分组头菜单同一手法:
/// 不用 `@views.dropdown`——它自带锚点与 DropdownState,塞进 26pt 的工具行
/// 会撑破行高）。
///
/// 里的动作默认是「对**活动工程根**的操作」:没有工程时给一条禁用的
/// 提示行,而不是给一个点了没用的菜单。
fn explorer_overflow_menu(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  if !model.explorer_menu_open {
    return @views.spacer(min_length=0.0)
  }
  let rows : Array[@moui.View[Msg]] = []
  let has_project = model.projects.length() > 0
  let add = fn(label : String, enabled : Bool, message : Msg) {
    rows.push(
      @views.container(
        @views.padding_edges(
          @views.text(
            label,
            theme=@chrome.studio_theme(),
            width=(width - 32.0).max(60.0),
            height=18.0,
            align=TextStart,
          ).foreground(if enabled { @chrome.ide_text() } else { @chrome.ide_text_faint() }),
          left=14.0,
          right=8.0,
        ),
        background=@chrome.ide_panel_alt(),
        height=@chrome.TREE_ROW_HEIGHT,
        width~,
        padding=0.0,
      ).on_tap(if enabled { message } else { Msg::Noop }),
    )
  }
  add(text(t, "app.explorer.new_file"), has_project, FileCreateAt(""))
  add(text(t, "app.explorer.new_folder"), has_project, FolderCreateAt(""))
  add(text(t, "app.explorer.refresh"), has_project, ExplorerRefresh)
  add(text(t, "app.explorer.collapse_all"), has_project, ExplorerCollapseAll)
  add(text(t, "app.project.import"), true, ImportProjectRequested)
  @views.column(rows, spacing=0.0)
}

///|
/// 工具栏图标动作（22×20 图标按钮 + hover 提示 + 禁用态变淡）。
fn explorer_tool_icon(
  icon : @style.IconName,
  tip : String,
  enabled : Bool,
  on_click : Msg,
) -> @moui.View[Msg] {
  // **透明底**:这是同一类缺陷的第三处。裸 container 无背景 → 回落环境
  // 面板色,24×20 的深灰圆角块直接画在工具栏上（截图里图标后面那些方块）。
  // 需要高亮态（溢出菜单展开）时由调用方显式 `.background(...)` 覆盖。
  @views.container(
    @views.center(
      @views.icon(
        icon,
        size=13.0,
        color=if enabled { @chrome.ide_text_muted() } else { @chrome.ide_text_faint() },
      ),
      width=22.0,
      height=18.0,
    ),
    background=@core.Color::rgba(r=0.0, g=0.0, b=0.0, a=0.0),
    corner_radius=3.0,
    width=24.0,
    height=20.0,
    padding=0.0,
  )
  .accessibility_label(tip)
  .on_hover(active => HoverHint(if active { tip } else { "" }))
  .on_tap(if enabled { on_click } else { Msg::Noop })
}

// ============================================================================
// 行序列（树 → 扁平）
// ============================================================================

///|
/// 分区的默认折叠态（未登记 = 展开）。文件夹分区默认展开,其余默认收起。
fn section_collapsed(model : Model, id : String) -> Bool {
  if id == EXPLORER_SECTION_FOLDERS {
    model.explorer_sections_collapsed.contains(id)
  } else {
    !model.explorer_sections_collapsed.contains("open:" + id)
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
fn explorer_rows(model : Model, t : @i18n.Translator) -> Array[ExplorerRow] {
  let rows : Array[ExplorerRow] = []
  push_editor_section(model, t, rows)
  push_folders_section(model, t, rows)
  push_outline_section(model, t, rows)
  push_timeline_section(model, t, rows)
  rows
}

///|
/// 「打开的编辑器」分区:打开的 tab 列表（脏标记 + 活动高亮）。
///
/// **没有打开的 tab 时整段不产出**（连分区头都不画）——与 VS Code 一致。
fn push_editor_section(
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  let count = model.open_project_files.length()
  if count == 0 {
    return
  }
  let id = "editors"
  let expanded = !section_collapsed(model, id)
  rows.push(
    SectionRow(id, text(t, "app.explorer.open_editors"), expanded, count),
  )
  if !expanded {
    return
  }
  for index, open in model.open_project_files {
    rows.push(
      EditorRow(
        index,
        rel_path_last_segment(open.rel),
        file_is_dirty(open),
        index == model.open_file_index,
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
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  if model.projects.length() == 0 && model.workspace_root is None {
    rows.push(SectionEmptyRow(text(t, "app.explorer.empty")))
    return
  }
  match model.workspace_root {
    Some(record) => push_workspace_root(model, t, rows, record)
    None =>
      for index, project in model.projects {
        push_project_root(model, t, rows, index, project)
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
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  record : WorkspaceRecord,
) -> Unit {
  // 折叠键用负下标:工作区根与「第 N 个工程根」共用一个键空间,
  // 用负数保证永不与成员下标相撞。
  let root_key = root_collapse_key(WORKSPACE_ROOT_INDEX, "")
  let expanded = !dir_collapsed(model, root_key)
  rows.push(
    RootRow(
      WORKSPACE_ROOT_INDEX,
      record.name,
      record.root,
      model.workspace_root is Some(_),
    ),
  )
  if !expanded {
    return
  }
  // 就地输入行挂在根行之下（新建目标 = 工作区根 "")
  push_input_rows(model, rows, WORKSPACE_ROOT_INDEX, "", 1)
  // 逐层铺开:目录（含成员的中间目录）在前、文件在后。
  //
  // **不再遍历成员平铺**——那正是「examples 下的模块直接显示、收起 examples
  // 收不掉里面」的根因:成员路径是多段的,平铺会让中间目录不存在。
  push_workspace_tier(model, t, rows, record, "", 1)
}

///|
/// 递归铺开工作区根下 `parent_rel` 这一层:每个子目录一行,成员在自己那
/// 一层由成员行渲染,其余目录继续递归;最后是这一层的文件。
fn push_workspace_tier(
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  record : WorkspaceRecord,
  parent_rel : String,
  depth : Int,
) -> Unit {
  let tier = workspace_tier(model, record, parent_rel)
  for name in tier.dirs {
    let rel = join_rel(parent_rel, name)
    let key = root_collapse_key(WORKSPACE_ROOT_INDEX, rel)
    let expanded = !dir_collapsed(model, key)
    match member_index_at(model, rel) {
      Some(index) =>
        // 这一层正好是一个成员:渲染成员行（元信息给入口概要 + 成员内部）
        push_member_dir(model, t, rows, index, rel, name, depth)
      None => {
        rows.push(DirRow(WORKSPACE_ROOT_INDEX, rel, name, "", depth, expanded))
        if expanded {
          push_workspace_tier(model, t, rows, record, rel, depth + 1)
        }
      }
    }
  }
  for name in tier.files {
    push_file_row(
      model,
      rows,
      WORKSPACE_ROOT_INDEX,
      join_rel(parent_rel, name),
      depth,
    )
  }
}

///|
/// 工作区根在折叠键空间里的下标（与成员下标不冲突）。
pub const WORKSPACE_ROOT_INDEX : Int = -1

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

///|
/// 算出工作区根下 `parent_rel` 这一层的子项:目录 = 扫描到的真实目录 ∪
/// 成员路径在这一层的前缀段;文件 = 该层的普通文件。
fn workspace_tier(
  model : Model,
  record : WorkspaceRecord,
  parent_rel : String,
) -> ExplorerTier {
  let dir_names : Array[String] = []
  // 1) 扫描到的真实目录（非成员部分已经在扫描层排除了成员内部）
  for child in child_dirs_of(record.dirs, parent_rel) {
    dir_names.push(rel_path_last_segment(child.rel_path))
  }
  // 2) 成员路径在这一层的前缀段——中间目录也要补出来
  for project in model.projects {
    let member_rel = tree_rel_of_project(model, project)
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
fn member_index_at(model : Model, rel : String) -> Int? {
  let mut index = 0
  for project in model.projects {
    if tree_rel_of_project(model, project) == rel {
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
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int,
  member_rel : String,
  label : String,
  depth : Int,
) -> Unit {
  let project = model.projects[index]
  let meta = project_entry_meta(project)
  // 折叠键用**成员下标 + 成员在树上的 rel**:成员路径可能是多段的
  // （`examples/terminal`）,键必须唯一到"这一层的那一个目录",否则
  // `examples` 与 `examples/terminal` 会互相折叠。
  let key = root_collapse_key(index, member_rel)
  let expanded = !dir_collapsed(model, key)
  rows.push(DirRow(index, member_rel, label, meta, depth, expanded))
  if !expanded {
    return
  }
  push_input_rows(model, rows, index, "", depth + 1)
  for child in child_dirs_of(project.scanned.dirs, "") {
    push_member_dir_subtree(
      model,
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
        push_file_row(model, rows, index, join_rel(member_rel, name), depth + 1)
      }
    None => ()
  }
}

///|
/// 成员内部的目录子树（rel 为**工程相对**路径;行上的 rel 带成员前缀）。
fn push_member_dir_subtree(
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int,
  project : ProjectRecord,
  rel : String,
  depth : Int,
) -> Unit {
  let member_rel = tree_rel_of_project(model, project)
  let dir = find_dir(project.scanned.dirs, rel)
  let label = rel_path_last_segment(rel)
  let meta = project_dir_meta(project, rel, t)
  let expanded = !dir_collapsed(model, root_collapse_key(index, rel))
  rows.push(DirRow(index, rel, label, meta, depth, expanded))
  if !expanded {
    return
  }
  push_input_rows(model, rows, index, rel, depth + 1)
  for child in child_dirs_of(project.scanned.dirs, rel) {
    push_member_dir_subtree(
      model,
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
          model,
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
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int,
  project : ProjectRecord,
) -> Unit {
  let active = index == model.active_project
  // 折叠键带根下标:不同工程的同名目录（如每个工程都有 `app/`）必须
  // 各折各的——按 rel 单键会让折叠一个工程的 app/ 把别的也折上。
  let root_key = root_collapse_key(index, "")
  let expanded = !dir_collapsed(model, root_key)
  rows.push(RootRow(index, project.module_name, project.root, active))
  if !expanded {
    return
  }
  // 就地输入行挂在根行之下（新建的目标目录 = 工程根 ""）
  push_input_rows(model, rows, index, "", 1)
  for child in child_dirs_of(project.scanned.dirs, "") {
    push_dir_subtree(model, t, rows, index, project, child.rel_path, 1)
  }
  // 根目录自身的普通文件(README/LICENSE/moon.mod 等)挂在根行之下
  match find_dir(project.scanned.dirs, "") {
    Some(dir) =>
      for name in sorted_names(dir.files) {
        push_file_row(model, rows, index, name, 1)
      }
    None => ()
  }
}

///|
/// 递归挂一棵目录子树:目录行(折叠态则到此为止)→ 就地输入行 → 子目录 →
/// 该目录的文件。
fn push_dir_subtree(
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
  index : Int,
  project : ProjectRecord,
  rel : String,
  depth : Int,
) -> Unit {
  let dir = find_dir(project.scanned.dirs, rel)
  let label = rel_path_last_segment(rel)
  let meta = project_dir_meta(project, rel, t)
  let expanded = !dir_collapsed(model, root_collapse_key(index, rel))
  rows.push(DirRow(index, rel, label, meta, depth, expanded))
  if expanded {
    push_input_rows(model, rows, index, rel, depth + 1)
    for child in child_dirs_of(project.scanned.dirs, rel) {
      push_dir_subtree(
        model,
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
          // 文件 rel 必须带目录前缀(选中/打开/改名都按「工程相对路径」
          // 寻址);根目录(rel = "")的文件 rel 就是文件名本身。
          let file_rel = join_rel(rel, name)
          push_file_row(model, rows, index, file_rel, depth + 1)
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
  model : Model,
  rows : Array[ExplorerRow],
  index : Int,
  rel : String,
  depth : Int,
) -> Unit {
  ignore(index)
  // 判据只看**目标目录**:`file_create_dir` 已经是树相对路径（工作区导入时
  // 带成员前缀），它在整棵树里唯一。早先还额外要求
  // `index == active_project`,那条守卫让「工作区根上新建」
  // （index = WORKSPACE_ROOT_INDEX,永远不等于 active_project）永远画不出
  // 输入行——点了 ＋ 什么都没发生。
  if model.file_create_dir != rel {
    return
  }
  if model.file_create_open {
    rows.push(InputRow("file", depth))
  }
  if model.folder_create_open {
    rows.push(InputRow("folder", depth))
  }
}

///|
/// 挂一个文件行(rel = 该文件相对模块根的完整路径;重命名态替换为输入行)。
fn push_file_row(
  model : Model,
  rows : Array[ExplorerRow],
  index : Int,
  rel : String,
  depth : Int,
) -> Unit {
  if index == model.active_project && model.file_rename_open == Some(rel) {
    rows.push(InputRow("rename", depth))
  } else {
    rows.push(
      FileRow(
        index,
        rel,
        rel_path_last_segment(rel),
        depth,
        model.selected_project_file == Some(rel),
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
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  let id = "outline"
  let symbols = match active_project_file(model) {
    Some(open) => outline_symbols(open.rel, open.draft)
    None => []
  }
  let expanded = !section_collapsed(model, id)
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
  model : Model,
  t : @i18n.Translator,
  rows : Array[ExplorerRow],
) -> Unit {
  let id = "timeline"
  let recent = recent_tail(model.recent_changes, EXPLORER_TIMELINE_ROWS)
  let expanded = !section_collapsed(model, id)
  rows.push(
    SectionRow(
      id,
      text(t, "app.explorer.timeline"),
      expanded,
      model.recent_changes.length(),
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
/// 分区里最多列几条时间线（侧栏是提示,不是完整历史）。
const EXPLORER_TIMELINE_ROWS : Int = 12

// ============================================================================
// 大纲符号提取
// ============================================================================

///|
/// 大纲符号（名称 + 行号 + 缩进层级）。
pub(all) struct OutlineSymbol {
  name : String
  line : Int
  depth : Int
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
fn markdown_heading(line : String) -> (Int, String)? {
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
fn moonbit_declaration(line : String) -> (Int, String)? {
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
fn leading_spaces(line : String) -> Int {
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
pub fn root_collapse_key(index : Int, rel : String) -> String {
  "\{index}:\{rel}"
}

///|
/// 直接子目录(rel_path 的父链正好是 parent;**文件夹优先、同类按名称**
/// 排序,与 VS Code 的资源管理器一致——扫描序是 BFS 发现序,不是给人读的序)。
///
/// 根目录条目(rel_path = "")的父链也是 ""——它必须被显式排除,否则
/// `child_dirs_of(dirs, "")` 把根自己收进来,`push_dir_subtree` 无限递归
/// 爆栈(实测 SIGSEGV: Thread stack size exceeded 的根因)。
fn child_dirs_of(
  dirs : Array[@project.ScannedDir],
  parent : String,
) -> Array[@project.ScannedDir] {
  let children : Array[@project.ScannedDir] = []
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
fn name_order(left : String, right : String) -> Int {
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
fn find_dir(
  dirs : Array[@project.ScannedDir],
  rel : String,
) -> @project.ScannedDir? {
  for dir in dirs {
    if dir.rel_path == rel {
      return Some(dir)
    }
  }
  None
}

///|
/// 目录是否折叠(默认展开)。
fn dir_collapsed(model : Model, key : String) -> Bool {
  model.project_tree_collapsed.contains(key)
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
fn file_icon(name : String) -> @style.IconName {
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
fn file_tint(name : String) -> @chrome.IconTint {
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
  row_count : Int,
  viewport_height : Double,
  scroll_y : Double,
) -> Double {
  let max_scroll = (row_count.to_double() * @chrome.TREE_ROW_HEIGHT - viewport_height).max(
    0.0,
  )
  if scroll_y < 0.0 {
    0.0
  } else if scroll_y > max_scroll {
    max_scroll
  } else {
    scroll_y
  }
}

///|
/// 展开「揭示」的目标滚动偏移:目录行在扁平序列中的行号 × 行高。
/// update 在展开时直接写入模型——单一事实源,视图钳制后生效,
/// 无请求/模型双轨。
pub fn explorer_dir_scroll_target(
  model : Model,
  index : Int,
  rel : String,
) -> @core.Point {
  let target = explorer_find_dir_row(model, index, rel)
  @core.Point::new(x=0.0, y=target.to_double() * @chrome.TREE_ROW_HEIGHT)
}

///|
/// 在**当前行序列**里定位目录行的行号（未找到返回 0）。
///
/// 走的是真实的 `explorer_rows` 派生（而不是另写一遍行数累计）:分区的
/// 折叠态、就地输入行都会改变行号,重新推导一遍必然与视图不同步——
/// 这正是旧实现「展开后滚到空处」的根因。
fn explorer_find_dir_row(model : Model, index : Int, rel : String) -> Int {
  let rows = explorer_rows(model, translator(model))
  let mut position = 0
  for row in rows {
    match row {
      DirRow(row_index, row_rel, _, _, _, _) =>
        if row_index == index && row_rel == rel {
          return position
        }
      RootRow(row_index, _, _, _) =>
        if row_index == index && rel == "" {
          return position
        }
      _ => ()
    }
    position = position + 1
  }
  0
}

// ============================================================================
// 行渲染
// ============================================================================

///|
/// 虚拟化行的稳定 key:行类型 + 身份(rel/下标),滚动窗口重挂时不串状态。
fn explorer_row_key(row : ExplorerRow) -> String {
  match row {
    SectionRow(id, _, _, _) => "section-\{id}"
    SectionEmptyRow(id) => "section-empty-\{id}"
    InputRow(kind, _) => "input-\{kind}"
    RootRow(index, _, _, _) => "root-\{index}"
    DirRow(index, rel, _, _, _, _) => "dir-\{index}:\{rel}"
    FileRow(index, rel, _, _, _) => "file-\{index}:\{rel}"
    EditorRow(index, _, _, _) => "editor-\{index}"
    OutlineRow(name, line, _) => "outline-\{line}:\{name}"
    TimelineRow(target, _, action) => "timeline-\{target}:\{action}"
  }
}

///|
/// 缩进导轨宽（每层 12pt,与标签缩进同一步长）。
const EXPLORER_INDENT_STEP : Double = 12.0

///|
/// 树行缩进:第一层从 8 起,逐层 +12——导轨画在同一批 x 上,层级因此
/// 读成连续的竖线而不是一串错位的空格。
fn explorer_indent(depth : Int) -> Double {
  8.0 + depth.to_double() * EXPLORER_INDENT_STEP
}

///|
/// inline 输入行的 ✓ / × 动作格（20×16 文字按钮,消息在构造点显式给出）。
fn explorer_input_action(
  glyph : String,
  color : @core.Color,
  message : Msg,
) -> @moui.View[Msg] {
  @views.text(
    glyph,
    theme=@chrome.studio_theme(),
    width=20.0,
    height=16.0,
    align=TextCenter,
  )
  .foreground(color)
  .on_tap(message)
}

///|
/// 缩进导轨:为 depth 层各画一条 1pt 竖线（`divider` 竖放）。
///
/// 导轨是 VS Code 树最容易辨认的特征,也是唯一不用读文字就能跟住层级的
/// 线索。行高 24 里导轨留上下 4pt 的呼吸,不顶到相邻行。
fn explorer_guides(depth : Int) -> @moui.View[Msg] {
  let lines : Array[@moui.View[Msg]] = []
  let mut level = 0
  while level < explorer_guide_line_count(depth) {
    // 导轨 = **一格里一条 1pt 竖线**。两个坑都踩过了,这里的写法是被实测
    // 逼出来的唯一正确形态:
    //
    // 1. 给 divider 套**裸 container** → 裸 container 无背景、回落环境面板
    //    色,每格背后多出 12×16 的深灰圆角块（用户截图里那排黑方块）。
    // 2. 直接给 divider 加 `.frame(width=12, height=16)` → 竖放 divider
    //    **填满可用宽**（12pt),整格变成一条实心竖条,比 (1) 更糟
    //    （实测:1pt 线数从 N 变 0,12×16 实心块变 N）。
    //
    // 正解:`center` 给出 12×16 的格子 + **透明背景**,divider 保 1pt 厚
    // 并居中。格子负责占位,线负责视觉,两者都不画多余的底。
    lines.push(
      @views.center(
        @views.divider(
          axis=@core.Axis::Vertical,
          thickness=1.0,
          color=@chrome.ide_border_soft(),
        ),
        width=EXPLORER_INDENT_STEP,
        height=@chrome.TREE_ROW_HEIGHT - 8.0,
        background=@core.Color::rgba(r=0.0, g=0.0, b=0.0, a=0.0),
      ),
    )
    level = level + 1
  }
  if lines.length() == 0 {
    @views.spacer(min_length=0.0)
  } else {
    @views.row(lines, spacing=0.0, align=Center)
  }
}

///|
/// 扁平行 → 视图(分支渲染)。
fn explorer_row_view(
  model : Model,
  t : @i18n.Translator,
  width~ : Double,
) -> (ExplorerRow) -> @moui.View[Msg] {
  fn(row : ExplorerRow) -> @moui.View[Msg] {
    match row {
      SectionRow(id, label, expanded, count) =>
        explorer_section_row(id, label, expanded, count, width)
      SectionEmptyRow(line) =>
        explorer_empty_row(line, EXPLORER_SECTION_INDENT, width)
      InputRow(kind, depth) => explorer_input_row(model, kind, depth, width)
      RootRow(index, name, root, active) =>
        explorer_root_row(model, name, root, index, active, width)
      DirRow(index, rel, label, meta, depth, expanded) =>
        explorer_dir_row(
          model, t, index, rel, label, meta, depth, expanded, width,
        )
      FileRow(index, rel, name, depth, selected) =>
        explorer_file_row(model, t, index, rel, name, depth, selected, width)
      EditorRow(index, name, dirty, active) =>
        explorer_editor_row(model, index, name, dirty, active, width)
      OutlineRow(name, line, depth) =>
        explorer_outline_row(name, line, depth, width)
      TimelineRow(target, by_agent, action) =>
        explorer_timeline_row(target, by_agent, action, width)
    }
  }
}

///|
/// 分区行缩进（分区头/空态比第一层目录再进一档,读成「挂在分区下」）。
const EXPLORER_SECTION_INDENT : Int = 1

///|
/// 分区头:箭头 + 名称 + 计数徽标。
fn explorer_section_row(
  id : String,
  label : String,
  expanded : Bool,
  count : Int,
  width : Double,
) -> @moui.View[Msg] {
  let cells : Array[@moui.View[Msg]] = [
    @views.container(
      @views.center(
        @views.icon(
          if expanded {
            ChevronDown
          } else {
            ChevronRight
          },
          size=12.0,
          color=@chrome.ide_text_muted(),
        ),
        width=14.0,
        height=16.0,
      ),
      width=14.0,
      height=16.0,
      padding=0.0,
    ),
    @views.text(
      label,
      theme=@chrome.studio_theme(),
      width=(width - 74.0).max(48.0),
      height=18.0,
      align=TextStart,
    ).foreground(@chrome.ide_text()),
  ]
  if count > 0 {
    cells.push(
      @views.text(
        count.to_string(),
        theme=@chrome.studio_theme(),
        role=Caption,
        width=24.0,
        height=16.0,
        align=TextEnd,
      ).foreground(@chrome.ide_text_faint()),
    )
  }
  @views.container(
    @views.padding_edges(
      @chrome.fill_row(cells, (width - 8.0).max(80.0), 4.0, Center),
      left=8.0,
      right=12.0,
    ),
    background=@chrome.ide_panel(),
    height=@chrome.TREE_ROW_HEIGHT,
    width~,
    padding=0.0,
  )
  .accessibility_label(label)
  .on_tap(ToggleExplorerSection(id))
}

///|
/// 分区空态行（一行灰字,不占整块高度）。
fn explorer_empty_row(
  line : String,
  depth : Int,
  width : Double,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_edges(
      @views.text(
        @chrome.fit_label(line, (width - explorer_indent(depth) - 20.0).max(60.0)),
        theme=@chrome.studio_theme(),
        width=(width - explorer_indent(depth) - 20.0).max(60.0),
        height=18.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
      left=explorer_indent(depth),
      right=12.0,
    ),
    height=@chrome.TREE_ROW_HEIGHT,
    width~,
    padding=0.0,
  )
}

///|
/// inline 输入行:输入框 + ✓ / ×（新建文件 / 新建文件夹 / 改名共用）。
///
/// 三条输入通道的提交/取消/草稿消息在这里**显式分派**。刻意不用
/// `(commit, dismiss)` 元组再 `on_tap(commit)`：那样「这些变体由谁构造」
/// 在源码里只剩一个裸标识符，死消息门（`validate-dead-messages` 视
/// `Variant =>` 为匹配臂、不视为构造点）读不到构造位置，会把它们判成死
/// 变体。分支写全还有第二个好处：加通道时编译器会在这里报穷尽性。
fn explorer_input_row(
  model : Model,
  kind : String,
  depth : Int,
  width : Double,
) -> @moui.View[Msg] {
  let creating_folder = kind == "folder"
  let renaming = kind == "rename"
  let placeholder = if renaming { "" } else { "name" }
  let indent = explorer_indent(depth)
  let commit_view = if renaming {
    explorer_input_action("✓", @chrome.ide_accent(), FileRenameCommit)
  } else if creating_folder {
    explorer_input_action("✓", @chrome.ide_accent(), FolderCreateCommit)
  } else {
    explorer_input_action("✓", @chrome.ide_accent(), FileCreateCommit)
  }
  let dismiss_view = if renaming {
    explorer_input_action("×", @chrome.ide_text_faint(), FileRenameDismiss)
  } else if creating_folder {
    explorer_input_action("×", @chrome.ide_text_faint(), FolderCreateDismiss)
  } else {
    explorer_input_action("×", @chrome.ide_text_faint(), FileCreateDismiss)
  }
  let on_input = value => {
    if renaming {
      FileRenameDraft(value)
    } else if creating_folder {
      FolderCreateDraft(value)
    } else {
      FileCreateDraft(value)
    }
  }
  @views.container(
    @views.padding_edges(
      @views.row(
        [
          explorer_guides(depth),
          @views.text_field(
            model.file_name_draft,
            on_input~,
            placeholder~,
            variant=Outline,
            width=(width - indent - 72.0).max(60.0),
            height=20.0,
          ),
          commit_view,
          dismiss_view,
        ],
        spacing=4.0,
        align=Center,
      ),
      left=indent - EXPLORER_INDENT_STEP,
      right=10.0,
    ),
    background=@chrome.ide_panel(),
    height=@chrome.TREE_ROW_HEIGHT,
    width~,
    padding=0.0,
  )
}

///|
/// 根行（= 工程的顶层文件夹）:导轨占位 + 箭头 + 文件夹图标 + 模块名 +
/// 悬停动作。点击 = 切换活动工程（VS Code 里点顶层文件夹是折叠;这里
/// 折叠在箭头上,点行切换活动工程——因为 Studio 同时只跑一个工程,
/// 「哪个是活动的」必须有一个一眼可见的落点）。
fn explorer_root_row(
  model : Model,
  name : String,
  root : String,
  index : Int,
  active : Bool,
  width : Double,
) -> @moui.View[Msg] {
  let expanded = !dir_collapsed(model, root_collapse_key(index, ""))
  let key = explorer_row_key(RootRow(index, name, root, active))
  let row = explorer_tree_row(
    model,
    key~,
    depth=0,
    twisty=Some(ToggleProjectDirAt(index, "")),
    expanded~,
    icon=if expanded { FolderOpened } else { Folder },
    icon_color=if active { @chrome.ide_accent() } else { @chrome.ide_text_muted() },
    label=name,
    meta=project_entry_meta_of(model, index),
    selected=active,
    width~,
    on_click=Some(SetActiveProject(index)),
    trailing=Some(
      @views.icon(Trash, size=12.0, color=@chrome.ide_text()).on_tap(
        RemoveProject(index),
      ),
    ),
    trailing_width=18.0,
  )
  row
}

///|
/// 目录行:导轨 + 箭头 + 文件夹图标 + 名称 + 语义徽标 + 悬停动作。
fn explorer_dir_row(
  model : Model,
  t : @i18n.Translator,
  index : Int,
  rel : String,
  label : String,
  meta : String,
  depth : Int,
  expanded : Bool,
  width : Double,
) -> @moui.View[Msg] {
  let key = explorer_row_key(DirRow(index, rel, label, meta, depth, expanded))
  explorer_tree_row(
    model,
    key~,
    depth~,
    twisty=Some(ToggleProjectDirAt(index, rel)),
    expanded~,
    icon=if expanded { FolderOpened } else { Folder },
    icon_color=@chrome.ide_text_muted(),
    label~,
    meta~,
    selected=false,
    width~,
    on_click=None,
    trailing=Some(dir_hover_actions(rel, t, width)),
    trailing_width=36.0,
  )
}

///|
/// 目录行的悬停动作:新建文件 / 新建文件夹。
///
/// VS Code 在文件夹行上给的正是这一对（两个图标并排）。两个都必须带
/// **本目录** 的 rel——不带目录会让「在某文件夹上按新建」默默建到工程根,
/// 是这类就地输入最容易出的错。
///
/// 用 `on_hover` 写状态栏提示:图标没有文字,提示是唯一的可发现性来源
/// （与 `icon_button` 同一口径）。但**行本身已经挂了 on_hover**（写
/// `ExplorerHover` 控制行内动作显隐）,同一行再挂一个会互相覆盖——
/// 所以这里用 `accessibility_label` 给出名字,不抢 hover 槽。
fn dir_hover_actions(
  rel : String,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  ignore(width)
  @views.row(
    [
      explorer_row_action(
        FileNew,
        text(t, "app.explorer.new_file"),
        FileCreateAt(rel),
      ),
      explorer_row_action(
        NewFolder,
        text(t, "app.explorer.new_folder"),
        FolderCreateAt(rel),
      ),
    ],
    spacing=4.0,
    align=Center,
  )
}

///|
/// 行内动作图标（16×16,`accessibility_label` 给名字）。
///
/// 刻意**不**用 `@views.icon().on_hover(...)`:行级 `on_hover` 已经占用了
/// 那一槽（写 `ExplorerHover` 控制行内动作的显隐）,再挂一个会互相覆盖,
/// 症状是「悬停行里点不到动作」。名字走可达性标签,键盘/读屏用户拿得到。
fn explorer_row_action(
  icon : @style.IconName,
  label : String,
  message : Msg,
) -> @moui.View[Msg] {
  @views.container(
    @views.center(
      @views.icon(icon, size=12.0, color=@chrome.ide_text()),
      width=16.0,
      height=16.0,
    ),
    width=16.0,
    height=16.0,
    padding=0.0,
  )
  .accessibility_label(label)
  .on_tap(message)
}

///|
/// 文件行:导轨 + 类型图标 + 名称 + 悬停动作（改名 / 删除）。
fn explorer_file_row(
  model : Model,
  t : @i18n.Translator,
  index : Int,
  rel : String,
  name : String,
  depth : Int,
  selected : Bool,
  width : Double,
) -> @moui.View[Msg] {
  let key = explorer_row_key(FileRow(index, rel, name, depth, selected))
  explorer_tree_row(
    model,
    key~,
    depth~,
    twisty=None,
    expanded=false,
    icon=file_icon(name),
    // 类型色（Seti 口径）:颜色是「这是什么文件」的第一眼线索
    icon_color=@chrome.ide_file_color(file_tint(name)),
    label=name,
    meta="",
    selected~,
    width~,
    on_click=Some(SelectProjectFileAt(index, rel)),
    trailing=Some(
      @views.row(
        [
          explorer_row_action(
            FileNew,
            text(t, "app.explorer.rename"),
            FileRenameStart(rel),
          ),
          explorer_row_action(
            Trash,
            text(t, "app.explorer.delete"),
            RequestConfirm(CkDeleteProjectFile(rel)),
          ),
        ],
        spacing=4.0,
        align=Center,
      ),
    ),
    trailing_width=36.0,
  )
}

///|
/// 打开的编辑器条目:脏点 + 文件名 + 关闭 ×。
fn explorer_editor_row(
  model : Model,
  index : Int,
  name : String,
  dirty : Bool,
  active : Bool,
  width : Double,
) -> @moui.View[Msg] {
  let key = "editor-\{index}"
  explorer_tree_row(
    model,
    key~,
    depth=EXPLORER_SECTION_INDENT,
    twisty=None,
    expanded=false,
    icon=file_icon(name),
    icon_color=if active {
      @chrome.ide_accent()
    } else {
      @chrome.ide_file_color(file_tint(name))
    },
    label=name,
    meta=if dirty { "●" } else { "" },
    selected=active,
    width~,
    on_click=Some(SelectFileTab(index)),
    trailing=Some(
      @views.text(
        "×",
        theme=@chrome.studio_theme(),
        width=14.0,
        height=16.0,
        align=TextCenter,
      )
      .foreground(@chrome.ide_text_faint())
      .on_tap(CloseFileTab(index)),
    ),
    trailing_width=18.0,
  )
}

///|
/// 大纲条目:符号名 + 行号（右对齐,VS Code 的 Outline 同款）。
fn explorer_outline_row(
  name : String,
  line : Int,
  depth : Int,
  width : Double,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_edges(
      @views.row(
        [
          explorer_guides(EXPLORER_SECTION_INDENT + depth),
          @views.text(
            name,
            theme=@chrome.studio_theme(),
            width=(width - 96.0 - depth.to_double() * 8.0).max(48.0),
            height=18.0,
            align=TextStart,
          ).foreground(@chrome.ide_text()),
          @views.text(
            line.to_string(),
            theme=@chrome.studio_theme(),
            role=Caption,
            width=32.0,
            height=16.0,
            align=TextEnd,
          ).foreground(@chrome.ide_text_faint()),
        ],
        spacing=4.0,
        align=Center,
      ),
      left=explorer_indent(EXPLORER_SECTION_INDENT),
      right=12.0,
    ),
    height=@chrome.TREE_ROW_HEIGHT,
    width~,
    padding=0.0,
  )
}

///|
/// 时间线条目:目标 + 作者 + 动作（原底部「最近修改」行,搬进分区）。
fn explorer_timeline_row(
  target : String,
  by_agent : Bool,
  action : String,
  width : Double,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_edges(
      @views.row(
        [
          @views.text(
            target,
            theme=@chrome.studio_theme(),
            width=64.0,
            height=18.0,
            align=TextStart,
          ).foreground(@chrome.ide_text()),
          @views.text(
            if by_agent {
              "AI"
            } else {
              "·"
            },
            theme=@chrome.studio_theme(),
            role=Caption,
            width=20.0,
            height=16.0,
            align=TextStart,
          ).foreground(if by_agent { @chrome.ide_accent() } else { @chrome.ide_text_faint() }),
          @views.text(
            action,
            theme=@chrome.studio_theme(),
            width=(width - 128.0).max(40.0),
            height=18.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_muted()),
        ],
        spacing=6.0,
        align=Center,
      ),
      left=explorer_indent(EXPLORER_SECTION_INDENT),
      right=12.0,
    ),
    height=@chrome.TREE_ROW_HEIGHT,
    width~,
    padding=0.0,
  )
}

// ============================================================================
// 通用树行（导轨 + 箭头 + 图标 + 标签 + 元信息 + 悬停动作）
// ============================================================================

///|
/// 通用树行:手搓而不是用 `@views.tree_view`——内置树行只有 id/label,
/// 没有图标、导轨、元信息与悬停动作,而 VS Code 口径的行四样都要。
///
/// **悬停动作占位纪律**:`trailing_width` 是**始终**预留的宽度,非悬停行
/// 用等宽空白占位。若让动作只在悬停时占宽,标签会在鼠标扫过整棵树时
/// 左右跳动（实测最刺眼的一处）。
fn explorer_tree_row(
  model : Model,
  key~ : String,
  depth~ : Int,
  twisty~ : Msg?,
  expanded~ : Bool,
  icon~ : @style.IconName,
  icon_color~ : @core.Color,
  label~ : String,
  meta~ : String,
  selected~ : Bool,
  width~ : Double,
  on_click~ : Msg?,
  trailing? : @moui.View[Msg]? = None,
  trailing_width? : Double = 0.0,
) -> @moui.View[Msg] {
  let hovered = model.explorer_hover == key
  let indent = explorer_indent(depth)
  let cells : Array[@moui.View[Msg]] = [
    explorer_guides(depth),
    match twisty {
      Some(message) =>
        // **不能用裸 `container`**:裸 container 没有背景,会回落环境面板色
        // ——在编辑器底色上读成一个 14×16 的黑方块（截图里箭头位置那一块）。
        // 这里只需要一个可点热区 + 一个图标,所以用**透明背景**的 `center`:
        // 几何与原来逐字相同,但不画任何底。
        @views.center(
          @views.icon(
            if expanded {
              ChevronDown
            } else {
              ChevronRight
            },
            size=11.0,
            color=@chrome.ide_text_muted(),
          ),
          width=14.0,
          height=16.0,
          background=@core.Color::rgba(r=0.0, g=0.0, b=0.0, a=0.0),
        ).on_tap(message)
      // 叶子占位:**透明空文本**——裸 container 会回落环境面板色,
      // 在选中行(@chrome.ide_selection 蓝)上读成黑方块(实测缺陷)。
      None => @views.text("", width=14.0, height=16.0)
    },
    @views.icon(icon, size=13.0, color=icon_color),
  ]
  // 标签宽度必须**从剩余空间反推**,不能写死:有 meta 时会多出一个单元格
  // 加一条间距,写死的宽度会让整行溢出,行尾的 meta 被裁成「64」。
  let meta_width = @chrome.TREE_META_WIDTH
  let reserved = 14.0 +
    13.0 +
    (if meta != "" { meta_width + 2.0 } else { 0.0 }) +
    trailing_width +
    (if trailing_width > 0.0 { 2.0 } else { 0.0 }) +
    18.0
  let label_width = (width - indent - reserved).max(40.0)
  cells.push(
    @views.text(
      label,
      theme=@chrome.studio_theme(),
      width=label_width,
      height=18.0,
      align=TextStart,
    ).foreground(if selected { @chrome.ide_text() } else { @chrome.ide_text_muted() }),
  )
  if meta != "" {
    cells.push(
      @views.text(
        @chrome.fit_label(meta, meta_width),
        theme=@chrome.studio_theme(),
        role=Caption,
        width=meta_width,
        height=16.0,
        align=TextEnd,
      ).foreground(@chrome.ide_text_faint()),
    )
  }
  // 尾部动作格:悬停才画,但**宽度始终占用**（占位见函数注释）。
  if trailing_width > 0.0 {
    match trailing {
      Some(action) =>
        if hovered {
          cells.push(action)
        } else {
          cells.push(@views.text("", width=trailing_width, height=16.0))
        }
      None => ()
    }
  }
  let row = @views.container(
    @views.padding_edges(
      @chrome.fill_row(cells, (width - 8.0).max(80.0), 4.0, Center),
      left=indent - 4.0,
      right=12.0,
    ),
    background=if selected { @chrome.ide_selection() } else { @chrome.ide_panel() },
    height=@chrome.TREE_ROW_HEIGHT,
    width~,
    padding=0.0,
  )
  let clickable = match on_click {
    Some(message) => row.on_tap(message)
    None => row
  }
  // 悬停观察者写模型槽（框架的 hover 是**转移沿**回调,不会每帧刷）。
  // 行内动作据此显隐——这是「满屏图标」与「找不到操作」之间唯一的解。
  clickable
  .on_hover(active => ExplorerHover(if active { key } else { "" }))
  .accessibility_label(label)
}

///|
/// 包类别标签:入口(web / native)或普通包。
fn project_kind_label(
  kind : @project.PackageKind,
  t : @i18n.Translator,
) -> String {
  match kind {
    @project.PkWebEntry => text(t, "app.project.kind.web")
    @project.PkNativeEntry => text(t, "app.project.kind.native")
    @project.PkPlain => text(t, "app.project.kind.plain")
  }
}

///|
/// 根行的概要:web / native 入口与逻辑包数量。
fn project_entry_meta(project : ProjectRecord) -> String {
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
fn project_entry_meta_of(model : Model, index : Int) -> String {
  if index >= 0 && index < model.projects.length() {
    project_entry_meta(model.projects[index])
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
pub fn explorer_section_expanded(model : Model, id : String) -> Bool {
  !section_collapsed(model, id)
}

///|
/// 目录排序探针:黑盒测试用它锁定「文件夹优先 + 名称不区分大小写」。
pub fn explorer_child_dirs_for_test(
  dirs : Array[@project.ScannedDir],
  parent : String,
) -> Array[@project.ScannedDir] {
  child_dirs_of(dirs, parent)
}

///|
/// 行序列探针（黑盒测试用它锁定树的行序与可见性）。
pub fn explorer_rows_for_test(model : Model) -> Array[String] {
  let out : Array[String] = []
  for row in explorer_rows(model, translator(model)) {
    out.push(explorer_row_key(row))
  }
  out
}

///|
/// 文件类型图标探针（后缀 → 图标的映射）。
pub fn file_icon_for_test(name : String) -> @style.IconName {
  file_icon(name)
}

///|
/// 文件类型色系探针（形状与颜色必须同源）。
pub fn file_tint_for_test(name : String) -> @chrome.IconTint {
  file_tint(name)
}

///|
/// 缩进导轨的绘制条数 = 层级数（第 0 层 = 0 条,只有占位）。
/// 视图与测试共用这一个口径,测试不必自己复述「第 0 层画几条」。
pub fn explorer_guide_line_count(depth : Int) -> Int {
  depth.max(0)
}
