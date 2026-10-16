///|
/// 积木右键菜单（Scratch/IDE 口径）。
///
/// 从 `app/blocks_pane.mbt` 迁出（该文件已触 1200 行硬上限）：菜单是**与
/// 壳 Model 无关的纯视图**，按「视图由父组装」出壳——壳把「有没有选中块 /
/// 当前分类」投影成参数，动作经 on_* 回壳。
///
/// 动作全部复用**既有消息**——`DuplicateBlock` / `DeleteBlock` 已经是右栏
/// 编辑卡上的按钮载体，这里只是把同一批动作搬到指针处。**不新开执行路径**：
/// 菜单是「同一动作的第二个入口」，不是第二套语义。
///
/// 每一项都先关菜单（见各行的 `on_*` 串联）——点完不关菜单，用户会以为
/// 没生效。

///|
/// 菜单行宽（固定：菜单是浮层，宽随内容长会让它在窄屏挤出视口）。
pub const BLOCK_MENU_WIDTH : Double = 168.0

///|
pub(all) struct BlockMenuParams[Msg] {
  /// 是否选中了积木（false = 点空白处，给画布级动作）。
  has_block : Bool
  on_run_single : Msg
  on_duplicate : Msg
  on_delete : Msg
  /// 画布级动作：打开语句插入面板（点空白处时唯一的入口）。
  on_open_palette : Msg
}

///|
pub fn[Msg] block_context_menu(
  p : BlockMenuParams[Msg],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let rows : Array[@moui.View[Msg]] = []
  if p.has_block {
    // 「运行这一块」放最前：Scratch 里点击积木的直接动作就是运行。
    rows.push(
      menu_action_row(
        t.translate("app.run.single"),
        @chrome.ide_success(),
        p.on_run_single,
      ),
    )
    rows.push(
      menu_action_row(
        t.translate("app.block.duplicate"),
        @chrome.ide_text(),
        p.on_duplicate,
      ),
    )
    rows.push(
      menu_action_row(
        t.translate("app.block.delete"),
        @chrome.ide_danger(),
        p.on_delete,
      ),
    )
  } else {
    // 点空白处：给画布级动作（至少要有可插入语句的入口，否则菜单是空的）
    rows.push(
      menu_action_row(
        t.translate("app.blocks.rail.hint"),
        @chrome.ide_text_muted(),
        p.on_open_palette,
      ),
    )
  }
  @views.container(
    @views.column(rows, spacing=0.0),
    background=@chrome.ide_panel_alt(),
    corner_radius=6.0,
    width=BLOCK_MENU_WIDTH,
    padding=0.0,
  )
}

///|
/// 菜单行：文字 + 点击派发。动作后**先关菜单**再执行——菜单留着会挡住
/// 结果（删除后菜单还悬在那里，用户以为没删掉）。
fn[Msg] menu_action_row(
  label : String,
  color : @core.Color,
  action : Msg,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_xy(
      @views.text(
        @chrome.fit_label(label, 140.0),
        theme=@chrome.studio_theme(),
        width=140.0,
        height=18.0,
        align=TextStart,
      ).foreground(color),
      horizontal=12.0,
      vertical=0.0,
    ),
    height=28.0,
    width=BLOCK_MENU_WIDTH,
    padding=0.0,
  ).on_tap(action)
}
