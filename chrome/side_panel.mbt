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
