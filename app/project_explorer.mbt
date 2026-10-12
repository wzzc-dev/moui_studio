///|
using @proj {type ExplorerRow}

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
  let viewport_height = (height - toolbar_height - 4.0).max(
    @chrome.TREE_ROW_HEIGHT,
  )
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
          ).foreground(
            if enabled {
              @chrome.ide_text()
            } else {
              @chrome.ide_text_faint()
            },
          ),
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
        color=if enabled {
          @chrome.ide_text_muted()
        } else {
          @chrome.ide_text_faint()
        },
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
        explorer_empty_row(line, @proj.EXPLORER_SECTION_INDENT, width)
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
        @chrome.fit_label(
          line,
          (width - explorer_indent(depth) - 20.0).max(60.0),
        ),
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
    icon_color=if active {
      @chrome.ide_accent()
    } else {
      @chrome.ide_text_muted()
    },
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
    depth=@proj.EXPLORER_SECTION_INDENT,
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
          explorer_guides(@proj.EXPLORER_SECTION_INDENT + depth),
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
      left=explorer_indent(@proj.EXPLORER_SECTION_INDENT),
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
          ).foreground(
            if by_agent {
              @chrome.ide_accent()
            } else {
              @chrome.ide_text_faint()
            },
          ),
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
      left=explorer_indent(@proj.EXPLORER_SECTION_INDENT),
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
    ).foreground(
      if selected {
        @chrome.ide_text()
      } else {
        @chrome.ide_text_muted()
      },
    ),
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
    background=if selected {
      @chrome.ide_selection()
    } else {
      @chrome.ide_panel()
    },
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

///|
pub type ProjectRecord = @proj.ProjectRecord

///|
pub type WorkspaceRecord = @proj.WorkspaceRecord

///|
pub type OpenProjectFile = @proj.OpenProjectFile

///|
pub type RecentChange = @proj.RecentChange

///|
pub type OutlineSymbol = @proj.OutlineSymbol

///|
/// 行模型快照:从 Model 组装工程域只读视图数据。
fn explorer_data_of(model : Model) -> @proj.ExplorerData {
  {
    projects: model.projects,
    active_project: model.active_project,
    workspace_root: model.workspace_root,
    open_project_files: model.open_project_files,
    open_file_index: model.open_file_index,
    project_tree_collapsed: model.project_tree_collapsed,
    explorer_sections_collapsed: model.explorer_sections_collapsed,
    selected_project_file: model.selected_project_file,
    recent_changes: model.recent_changes,
    file_create_dir: model.file_create_dir,
    file_create_open: model.file_create_open,
    file_rename_open: model.file_rename_open,
    folder_create_open: model.folder_create_open,
  }
}

///|
fn explorer_rows(model : Model, t : @i18n.Translator) -> Array[ExplorerRow] {
  @proj.explorer_rows(explorer_data_of(model), t)
}

///|
fn section_collapsed(model : Model, id : String) -> Bool {
  @proj.section_collapsed(explorer_data_of(model), id)
}

///|
fn dir_collapsed(model : Model, key : String) -> Bool {
  @proj.dir_collapsed(explorer_data_of(model), key)
}

///|
fn file_icon(name : String) -> @style.IconName {
  @proj.file_icon(name)
}

///|
fn file_tint(name : String) -> @chrome.IconTint {
  @proj.file_tint(name)
}

///|
pub fn join_rel(rel : String, name : String) -> String {
  @proj.join_rel(rel, name)
}

///|
pub fn parent_of(rel : String) -> String {
  @proj.parent_of(rel)
}

///|
pub fn rel_path_last_segment(rel : String) -> String {
  @proj.rel_path_last_segment(rel)
}

///|
pub fn root_collapse_key(index : Int, rel : String) -> String {
  @proj.root_collapse_key(index, rel)
}

///|
pub fn outline_symbols(rel : String, source : String) -> Array[OutlineSymbol] {
  @proj.outline_symbols(rel, source)
}

///|
pub fn workspace_display_name(root : String) -> String {
  @proj.workspace_display_name(root)
}

///|
pub fn explorer_clamp_scroll_y(
  rows : Int,
  viewport_height : Double,
  y : Double,
) -> Double {
  @proj.explorer_clamp_scroll_y(rows, viewport_height, y)
}

///|
fn explorer_row_key(row : ExplorerRow) -> String {
  @proj.explorer_row_key(row)
}

///|
pub fn explorer_section_expanded(model : Model, id : String) -> Bool {
  @proj.explorer_section_expanded(explorer_data_of(model), id)
}

///|
pub fn explorer_child_dirs_for_test(
  dirs : Array[@project.ScannedDir],
  parent : String,
) -> Array[@project.ScannedDir] {
  @proj.explorer_child_dirs_for_test(dirs, parent)
}

///|
fn project_entry_meta_of(model : Model, index : Int) -> String {
  @proj.project_entry_meta_of(explorer_data_of(model), index)
}

///|
pub fn tree_rel_of_project(model : Model, project : ProjectRecord) -> String {
  @proj.tree_rel_of_project(explorer_data_of(model), project)
}

///|
pub fn tree_rel_of_project_file(
  model : Model,
  project : ProjectRecord,
  project_rel : String,
) -> String {
  @proj.tree_rel_of_project_file(explorer_data_of(model), project, project_rel)
}

///|
pub fn active_project_file(model : Model) -> OpenProjectFile? {
  @proj.active_project_file(explorer_data_of(model))
}

///|
pub fn file_is_dirty(open : OpenProjectFile) -> Bool {
  @proj.file_is_dirty(open)
}

///|
fn recent_tail(
  changes : Array[RecentChange],
  count : Int,
) -> Array[RecentChange] {
  @proj.recent_tail(changes, count)
}
