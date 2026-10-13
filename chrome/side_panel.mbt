///|
/// VS Code 侧面板（side panel）壳原子：分区头 / 分区。
///
/// 与 `panel_head` 的分工：`panel_head`（30pt）回答「这个**面板**是谁」，本节
/// 回答「面板里这**一段**是谁」。侧面板的正文是一条滚动区，里面并排若干个分区
/// （VS Code 的调试侧栏：变量 / 监视 / 调用堆栈 / 断点就是这种形态）——每个分区
/// 一条 22pt 的弱化小标题，右缘挂该分区自己的动作。
///
/// 两条纪律从 `panel_head` 继承：
/// 1. 尾部动作必须贴右缘——权重 spacer 的 `weight` 真的给上，标题只占内容宽，
///    余量才真正交给 spacer（否则「贴右缘」只是由标题宽度碰巧保证的）。
/// 2. 尾部占位**按调用方声明的实际宽**预留（`trailing_widths`）——统一按 22 留
///    会把宽徽标顶出右缘。

// ============================================================================
// 分区头
// ============================================================================

///|
/// 侧栏分区头：22pt 高、Caption 字号、弱化标签 + 可选前置字形 + 右缘动作簇。
///
/// `lead` 是前置字形槽——折叠分区的雪佛龙走这里（整条分区头可点，见
/// `.on_tap` 由调用方自行挂上）。
///
/// **底色必须显式**：无背景 container 在 paint 期回落到环境 Base 刷子，与所在
/// 面板不同色就会在分区之间露一条脏边（本仓反复踩的 ambient 坑）。
pub fn[Msg] section_head(
  label : String,
  width : Double,
  trailing? : Array[@moui.View[Msg]] = [],
  trailing_widths? : Array[Double] = [],
  lead? : @moui.View[Msg]? = None,
) -> @moui.View[Msg] {
  let mut reserved = 0.0
  let mut i = 0
  for item in trailing {
    ignore(item)
    reserved = reserved +
      (if i < trailing_widths.length() { trailing_widths[i] } else { 22.0 })
    i = i + 1
  }
  let gaps = 4.0 * (trailing.length() + 1).to_double()
  let label_w = (text_estimate_width(label) * 1.02 + 8.0)
    .min((width - 16.0 - reserved - gaps).max(28.0))
    .max(24.0)
  let cells : Array[@moui.View[Msg]] = []
  match lead {
    Some(glyph) => cells.push(glyph)
    None => ()
  }
  cells.push(
    @views.text(
      label,
      theme=studio_theme(),
      role=Caption,
      width=label_w,
      height=14.0,
      align=TextStart,
    ).foreground(ide_text_faint()),
  )
  // 权重 1：把后面的动作推到右缘。`min_length` 只保证最小间隙。
  cells.push(@views.spacer(min_length=6.0, weight=1.0))
  for item in trailing {
    cells.push(item)
  }
  @views.container(
    fill_row(cells, (width - 16.0).max(80.0), 4.0, Center),
    background=ide_panel_alt(),
    height=SECTION_HEAD_HEIGHT,
    padding=0.0,
  )
}

///|
/// 分区头高（比 `PANEL_HEAD_HEIGHT` 矮一档：分区是面板内的分段，不是面板本身）。
pub const SECTION_HEAD_HEIGHT : Double = 22.0

// ============================================================================
// 分区
// ============================================================================

// ============================================================================
// 视图切换器（页块）
// ============================================================================

///|
/// 侧栏页块高（VS Code 侧栏标题块口径：22pt，装 12pt 字 + 上下各 ~4pt 呼吸）。
pub const PAGE_TILE_HEIGHT : Double = 22.0

///|
/// 页块宽（唯一来源）：图表槽 + 可选标签 + 两侧内垫。
///
/// **调用方的宽度账必须走这里**——把「带标签」与「图标 only」两档的宽度
/// 各写一份，窄窗降级那档就会算错（本仓「两处各算一份」的复发缺陷族）。
/// `label` 为空串 = 图标 only 档（窄窗降级用）。
pub fn page_tile_width(label : String) -> Double {
  if label == "" {
    return PAGE_TILE_ICON_WIDTH
  }
  (8.0 + PAGE_TILE_GLYPH + 5.0 + text_estimate_width(label) * 1.02 + 8.0).max(
    40.0,
  )
}

///|
/// 页块图表槽宽（与 `page_tile` 内的图标盒同源）。
const PAGE_TILE_GLYPH : Double = 11.0

///|
/// 图标 only 档宽：两个内垫 + 图表槽（窄窗紧急档用）。
pub const PAGE_TILE_ICON_WIDTH : Double = 24.0

///|
/// 侧栏页块（VS Code 侧栏标题块）：前置字形 + 标签 + 常驻选中底块。
///
/// 与 `ghost_icon_button` 的分工：ghost 是「安静的动作」，选中才点亮；页块是
/// **常驻的身份**——它一直在那里说明「你现在在哪个视图」，所以未选中态也有
/// 自己的底色（与所在面板同色 = 视觉安静），选中态才抬起一档。
///
/// **底色必须显式**：`surface` 由调用方给（通常等于所在面板底色）。无背景
/// container 会在 paint 期回落到环境 Base 刷子，与面板不同色就在页块周围露
/// 一圈脏边（本仓反复踩的 ambient 坑）。
///
/// `label` 为空串 = 图标 only 档（窄窗降级），此时宽度由 `page_tile_width`
/// 的图标档给出，字形居中。
pub fn[Msg] page_tile(
  icon : @style.IconName,
  label : String,
  tip : String,
  selected : Bool,
  on_click : Msg,
  on_hover : (String) -> Msg,
  surface : @core.Color,
  width : Double,
  hovered? : String = "",
) -> @moui.View[Msg] {
  let tint = if selected { ide_text() } else { ide_text_faint() }
  let cells : Array[@moui.View[Msg]] = [
    @views.icon(icon, size=PAGE_TILE_GLYPH, color=tint),
  ]
  if label != "" {
    cells.push(
      @views.text(
        label,
        theme=studio_theme(),
        role=Caption,
        width=(width - 16.0 - PAGE_TILE_GLYPH - 5.0).max(20.0),
        height=14.0,
        align=TextStart,
      ).foreground(tint),
    )
  }
  // 图标 only 档：行宽收成字形槽，`center` 才会把字形摆在中线上；带标签档
  // 行吃满内宽，标签才有从左缘起算的位置。
  let inner_w = if label == "" {
    PAGE_TILE_GLYPH
  } else {
    (width - 16.0).max(PAGE_TILE_GLYPH)
  }
  let tile = @views.container(
      @views.center(
        @views.row(cells, spacing=5.0, align=Center).frame(width=inner_w),
        width~,
        height=PAGE_TILE_HEIGHT,
      ),
      background=if selected { ide_hover() } else { surface },
      corner_radius=4.0,
      width~,
      height=PAGE_TILE_HEIGHT,
      padding=0.0,
    )
    .accessibility_label(tip)
    // 悬停把说明写进状态栏（与 app 侧 `ghost_icon_button` 同口径：`on_hover`
    // 由组合根注入状态写回，`hovered` 也是组合根传来的当前悬停文案）。
    // chrome 包不认识 app 的 `HoverHint`，所以这一层只能以回调注入。
    //
    // **带标签的页块不弹浮层**：页块上已经写着「检查器 / AI」，再弹一块同名提示
    // 是纯重复（用户报的「已经有文字了，小 tips 去掉吧」）。只有**图标 only**
    // 降级档（窄窗）才需要浮层补名字——那时标签不画，这一页在视觉上没名字。
    .on_hover(active => on_hover(if active { tip } else { "" }))
    .on_tap(on_click)
  if label == "" {
    @views.tooltip(
      tile,
      tip,
      visible=tip != "" && hovered == tip,
      theme=studio_theme(),
    )
  } else {
    tile
  }
}

///|
/// 侧栏分区：分区头 + 正文。正文由调用方给（宽度已按面板内宽算好），这里只负责
/// 上下两段的装配与显式定尺——列不定尺会被 ContainerBox 按内容高居中。
pub fn[Msg] side_panel_section(
  label : String,
  content : @moui.View[Msg],
  width : Double,
  trailing? : Array[@moui.View[Msg]] = [],
  trailing_widths? : Array[Double] = [],
  lead? : @moui.View[Msg]? = None,
) -> @moui.View[Msg] {
  @views.column(
    [section_head(label, width, trailing~, trailing_widths~, lead~), content],
    spacing=0.0,
  ).frame(width~)
}

// ============================================================================
// 页块切换头部（页块切换器 + 右缘动作簇）
// ============================================================================

///|
/// 一个页块的声明：字形 + 页名（页名同时是 tooltip / 无障碍标签）。
pub(all) struct PageSpec {
  icon : @style.IconName
  label : String
}

///|
/// 页切换头：**页块切换器靠左、动作簇靠右**，整行 `PANEL_HEAD_HEIGHT`。
///
/// 三段分组（历史 bug 的修正结论，见 `memories/repo/moui-studio.md` 的
/// 「右栏头的 ✕」条）：页块永远在最左（它就是「我在哪一页」），动作簇永远贴
/// 右缘，其中**关闭整个面板**的那枚在最右。对象级动作（如「清空选中」）不
/// 进头部——它属于正文首段的**对象条**，两者必须是不同的带，否则「清空」与
/// 「关闭面板」会互换位置（2026-09-30 事故形态）。
///
/// **宽度预算**：带标签的页块（≈85）× N ＋动作簇（24×M）＋间隙。窄窗紧急收缩
/// 档可把侧栏压到 170pt，所以这里按**实测可用宽**在「带标签」与「图标 only」
/// 两档之间降级——两档宽度都走 `page_tile_width` 的同一来源，调用方不再自己
/// 算一份（本仓复发的「两处各算一份」缺陷族）。
pub fn[Msg] page_switcher_head(
  pages : Array[PageSpec],
  selected_index : Int,
  on_select : (Int) -> Msg,
  actions : Array[@moui.View[Msg]],
  action_widths : Array[Double],
  width : Double,
  on_hover : (String) -> Msg,
  hovered? : String = "",
) -> @moui.View[Msg] {
  let gap = 4.0
  let inner = (width - 16.0).max(80.0)
  let mut actions_w = 0.0
  let mut index = 0
  for action in actions {
    ignore(action)
    actions_w = actions_w +
      (if index < action_widths.length() { action_widths[index] } else { 24.0 }) +
      (if index > 0 { gap } else { 0.0 })
    index = index + 1
  }
  let mut labelled_w = 0.0
  index = 0
  for page in pages {
    labelled_w = labelled_w +
      page_tile_width(page.label) +
      (if index > 0 { gap } else { 0.0 })
    index = index + 1
  }
  let use_labels = labelled_w + actions_w + 8.0 <= inner
  let tiles : Array[@moui.View[Msg]] = []
  index = 0
  for page in pages {
    // 降级时标签不画，但**无障碍标签与 tooltip 恒为完整页名**——「图标 only」
    // 是视觉降级，不该让这一页在语义上失去名字。
    let shown = if use_labels { page.label } else { "" }
    tiles.push(
      page_tile(
        page.icon,
        shown,
        page.label,
        index == selected_index,
        on_select(index),
        on_hover,
        ide_panel(),
        page_tile_width(shown),
        hovered~,
      ),
    )
    index = index + 1
  }
  @views.container(
    @views.padding_xy(
      fill_row(
        [
          @views.row(tiles, spacing=gap, align=Center),
          @views.spacer(min_length=4.0, weight=1.0),
          @views.row(actions, spacing=gap, align=Center),
        ],
        inner,
        gap,
        Center,
      ),
      horizontal=8.0,
      vertical=0.0,
    ),
    background=ide_panel(),
    height=PANEL_HEAD_HEIGHT,
    width~,
    padding=0.0,
  )
}

// ============================================================================
// 子页签条（视图切换器）
// ============================================================================

///|
/// 子页签条行高（与 `PANEL_HEAD_HEIGHT` 同节奏，单独一个常量便于调用方算高度）。
pub const SUB_TAB_ROW_HEIGHT : Double = 30.0

///|
/// 侧栏子页签条（VS Code 视图切换器口径）：等宽扁平文字页签，活动态 = 亮一档
/// 的文字 + 2pt 强调色下划线。
///
/// **等宽格子是刻意的**（不改成内容宽）：窄窗紧急收缩可把侧栏压到 170pt，
/// 内容宽页签在那里必然溢出。`cell` 宽把 n−1 个间隙与左右内垫一起算进去——
/// 旧版只减了内垫忘了间隙，最长那个页签正好顶到右边缘被切掉半个字（实测截图）。
///
/// 泛型 + 回调注入（`labels` 已本地化、`on_select(index)` 给消息）：chrome 包
/// 不认识 app 的 `ContextTab`，页签同一性留在调用方。
pub fn[Msg] sub_tab_row(
  labels : Array[String],
  selected_index : Int,
  on_select : (Int) -> Msg,
  width : Double,
  background : @core.Color,
) -> @moui.View[Msg] {
  let count = labels.length()
  if count == 0 {
    return @views.container(@views.empty(), width~, height=0.0, padding=0.0)
  }
  let gap = 3.0
  let cell_width = ((width - 12.0 - (count - 1).to_double() * gap) /
  count.to_double()).max(28.0)
  let tabs : Array[@moui.View[Msg]] = []
  let mut index = 0
  for label in labels {
    let selected = index == selected_index
    tabs.push(
      @views.container(
        // 列必须显式定尺：不定尺的列按内容高测量，下划线会跟着漂。
        @views.column(
          [
            @views.text(
              label,
              theme=studio_theme(),
              width=cell_width,
              height=16.0,
              align=TextCenter,
            ).foreground(if selected { ide_text() } else { ide_text_faint() }),
            // 活动态下划线：2pt 强调色条；非活动态同高的「空条」占位，
            // 各格因此严格等高（高度不随选中跳变）。
            @views.container(
              @views.empty(),
              background=if selected { ide_accent() } else { background },
              width=(cell_width - 12.0).max(8.0),
              height=2.0,
              corner_radius=1.0,
              padding=0.0,
            ),
          ],
          spacing=gap,
          align=Center,
        ).frame(width=cell_width, height=22.0),
        // 底色必须显式：无背景 container 在 paint 期回落到环境 Base 刷子，
        // 与页签行的底不同色就会在每个格子里露一块异色（本仓反复踩的 ambient 坑）。
        background~,
        width=cell_width,
        height=22.0,
        padding=0.0,
      )
      .accessibility_label(label)
      .on_tap(on_select(index)),
    )
    index = index + 1
  }
  @views.container(
    @views.padding_xy(
      fill_row(tabs, (width - 12.0).max(80.0), gap, Center),
      horizontal=6.0,
      vertical=0.0,
    ),
    background~,
    height=SUB_TAB_ROW_HEIGHT,
    width~,
    padding=0.0,
  )
}

// ============================================================================
// 对象条（分区头 + 身份行 + 尾部动作）
// ============================================================================

///|
/// 身份行的行高（24pt：与树行同节奏，装 18pt 名称 + 上下各 3pt 呼吸）。
pub const OBJECT_ROW_HEIGHT : Double = 24.0

///|
/// 对象条：分区头 + 「名称 · 种类」身份行 + 右缘的可选清除动作。
///
/// 这是 VS Code 侧栏「当前对象是谁 + 一键放掉它」的通用形态：头部只放**面板级**
/// 的东西（页块切换器 / 设置 / 关闭），身份与对象级动作下移到正文首段——两者
/// 的语义分工必须是**不同的带**，否则「清空」与「关闭面板」会互换位置
/// （本仓 2026-09-30 的事故形态：点清空面板不动，用户读到「关闭关错了东西」）。
///
/// 泛型 + 回调注入：chrome 不认识 app 的选中状态与消息，所以名称/种类文案、
/// 「有没有选中」、清除消息与悬停回调全部由调用方给（`on_clear` 为 `None` =
/// 没有可清的东西，不画按钮——不出死 UI）。
pub fn[Msg] object_strip(
  label : String,
  name : String,
  kind : String,
  has_selection : Bool,
  on_clear : Msg,
  clear_tip : String,
  width : Double,
  on_hover : (String) -> Msg,
  hovered? : String = "",
) -> @moui.View[Msg] {
  let inner = (width - 16.0).max(80.0)
  // 名称与种类按内容给宽，余量交给权重 spacer 把清除钮推到右缘。
  let name_w = (text_estimate_width(name) * 1.02 + 8.0)
    .min((inner - 84.0).max(40.0))
    .max(40.0)
  let cells : Array[@moui.View[Msg]] = [
    @views.text(
      name,
      theme=studio_theme(),
      width=name_w,
      height=18.0,
      align=TextStart,
    ).foreground(if has_selection { ide_text() } else { ide_text_faint() }),
  ]
  if kind != "" {
    cells.push(
      @views.text(
        kind,
        theme=studio_theme(),
        role=Caption,
        width=(text_estimate_width(kind) * 1.02 + 8.0).max(36.0),
        height=16.0,
        align=TextStart,
      ).foreground(ide_text_faint()),
    )
  }
  // 权重 1：把清除钮推到右缘。行必须显式定宽，spacer 才拿得到 slack。
  cells.push(@views.spacer(min_length=6.0, weight=1.0))
  if has_selection {
    let button = @views.container(
        @views.center(
          @views.icon(Close, size=10.0, color=ide_text_muted()),
          width=18.0,
          height=18.0,
        ),
        background=ide_panel(),
        corner_radius=6.0,
        width=18.0,
        height=18.0,
        padding=0.0,
      )
      .accessibility_label(clear_tip)
      .on_hover(active => on_hover(if active { clear_tip } else { "" }))
      .on_tap(on_clear)
    cells.push(
      @views.tooltip(
        button,
        clear_tip,
        visible=clear_tip != "" && hovered == clear_tip,
        theme=studio_theme(),
      ),
    )
  }
  @views.column(
    [
      section_head(label, width),
      @views.container(
        @views.padding_xy(
          fill_row(cells, inner, 6.0, Center),
          horizontal=8.0,
          vertical=0.0,
        ),
        background=ide_panel(),
        height=OBJECT_ROW_HEIGHT,
        width~,
        padding=0.0,
      ),
    ],
    spacing=0.0,
  ).frame(width~)
}
