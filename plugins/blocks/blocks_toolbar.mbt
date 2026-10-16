///|
/// 积木画布工具条：撤销/重做 + 缩放组 + 网格开关 + 新事件头。
///
/// 从 `app/blocks_pane.mbt` 迁出（该文件已到 1200 行硬上限）：工具条是
/// **与 Msg 无关的纯视图**，按 non-render-component-cookbook 的既定口径
/// 「视图由父组装，动作以回调注入」，与 plugins/ai 的 `ai_session_list`
/// 同形态——壳只把 Model 投影成参数、把动作映射成 Msg。
///
/// **为什么不做浮动层**：浮动条要另算避让带（画布顶不被遮 + 缩小时不压到
/// 积木），而它只服务四个低频率动作。固定在窗格内一条 28pt 的行，读作
/// 「工具」而不是「贴纸」，且与 IDE 既有工具条节奏一致（PANEL_HEAD_HEIGHT
/// 30 的下一档）。

///|
/// 工具条高度（视图与壳的高度预算单点来源：`blocks_body_height` 扣它）。
pub const BLOCKS_TOOLBAR_HEIGHT : Double = 28.0

///|
/// 缩放读数的固定宽（「200%」「50%」「100%」各半角/全角混排，写死会截断）。
pub const BLOCKS_ZOOM_READOUT_WIDTH : Double = 52.0

///|
/// 工具条参数：读数 + 可用性 + 动作。**不读壳 Model**——壳投影后注入。
pub(all) struct BlocksToolbarParams[Msg] {
  /// 当前缩放倍率（读数与「是否在 1.0」的判据）。
  zoom : Double
  /// 点阵网格开/关（选中态描边）。
  grid : Bool
  /// 缩放是否已抵下限（减号置灰）。
  zoom_at_min : Bool
  /// 缩放是否已抵上限（加号置灰）。
  zoom_at_max : Bool
  /// 当前 handler 是否已有 OnStart（新事件头 chip 的选中态）。
  has_start_handler : Bool
  on_undo : Msg
  on_redo : Msg
  on_zoom_out : Msg
  on_zoom_in : Msg
  on_zoom_reset : Msg
  /// 「适应屏幕」：壳按内容包围盒 ÷ 画布视口预算好目标倍率后下发
  /// （SetCanvasZoom 自带夹取，视图不算几何）。
  on_zoom_fit : Msg
  on_toggle_grid : Msg
  on_new_script : Msg
  /// 图标钮构造器：由壳注入（`ide_chrome.icon_button` 是 app 本地助手，
  /// 插件不反向依赖 app）。与 plugins/ai 的 `ghost_icon` 同一形态——
  /// 「视图由父组装」的既定口径。
  icon_button : (@style.IconName, String, Bool, Msg) -> @moui.View[Msg]
}

///|
pub fn[Msg] blocks_canvas_toolbar(
  p : BlocksToolbarParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let percent = (p.zoom * 100.0).round().to_int()
  let zoom_label = t.translate("app.blocks.canvas.zoom_readout", values=[
    ("percent", percent.to_string()),
  ])
  let cells : Array[@moui.View[Msg]] = [
    // 撤销/重做：复用全局 Undo/Redo（顶栏已有同款钮）。灰度**不**作假：
    // 顶栏那两个钮也不反映可用性，本工具条与它同口径——撤销栈满/空由
    // update 自己兜（越界操作是 no-op），不在视图层再判一次。
    (p.icon_button)(
      ChevronLeft,
      t.translate("app.blocks.canvas.undo"),
      false,
      p.on_undo,
    ),
    (p.icon_button)(
      ChevronRight,
      t.translate("app.blocks.canvas.redo"),
      false,
      p.on_redo,
    ),
    // **竖线必须显式给轴**：`@chrome.hairline()` 是 `divider()` 的默认
    // `Horizontal`，放进 row 里会量到整行宽并盖住后面的兄弟（`chrome.mbt`
    // 自己写明了这个陷阱，2026-09-27 面板消失事故的根因）。工具条的
    // 撤销/重做与缩放组之间要的是**短竖分隔线**。
    @views.divider(axis=Vertical, color=@chrome.ide_border()),
    (p.icon_button)(
      Minus,
      t.translate("app.blocks.canvas.zoom_out"),
      p.zoom_at_min,
      p.on_zoom_out,
    ),
    // 缩放读数：本身也是「重置为 100%」的按钮（Figma 的百分比读数是可点的）
    @views.container(
      @views.center(
        @views.text(
          zoom_label,
          theme=@chrome.studio_theme(),
          role=Caption,
          width=BLOCKS_ZOOM_READOUT_WIDTH,
          height=16.0,
          align=TextCenter,
        ).foreground(
          if p.zoom == 1.0 {
            @chrome.ide_text_muted()
          } else {
            @chrome.ide_accent()
          },
        ),
        width=BLOCKS_ZOOM_READOUT_WIDTH,
        height=24.0,
      ),
      background=@chrome.ide_panel_alt(),
      corner_radius=4.0,
      width=BLOCKS_ZOOM_READOUT_WIDTH,
      height=24.0,
      padding=0.0,
    )
    .on_tap(p.on_zoom_reset)
    .accessibility_label(t.translate("app.blocks.canvas.zoom_reset")),
    (p.icon_button)(
      Plus,
      t.translate("app.blocks.canvas.zoom_in"),
      p.zoom_at_max,
      p.on_zoom_in,
    ),
    // 适应屏幕：内容包围盒 ÷ 视口的整倍适配（Scratch/Figma 的 fit）
    (p.icon_button)(
      Focus,
      t.translate("app.blocks.canvas.zoom_fit"),
      false,
      p.on_zoom_fit,
    ),
    // 网格开关：选中态用 ide_selection（本壳其余开关同口径）
    (p.icon_button)(
      Eye,
      t.translate("app.blocks.canvas.grid"),
      p.grid,
      p.on_toggle_grid,
    ),
    @views.spacer(min_length=6.0, weight=1.0),
    // 新事件头：复用既有创建入口（与左栏 hat 行的「⚡ 启动」同语义）
    @chrome.text_chip(
      t.translate("app.blocks.canvas.new_script"),
      p.on_new_script,
      120.0,
      p.has_start_handler,
    ),
  ]
  @views.container(
    @chrome.fill_row(cells, width, 4.0, Center),
    background=@chrome.ide_panel(),
    width~,
    height=BLOCKS_TOOLBAR_HEIGHT,
    padding=0.0,
  )
}
