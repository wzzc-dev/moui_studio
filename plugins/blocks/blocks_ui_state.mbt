///|
/// 积木域 UI 状态切片（S5e 状态切片，ADR 0038/0039/0040/0041）：
/// 语句插入面板开合/分类、画布受控滚动、值就地编辑草稿、表达式/语句拖放的
/// 拖拽骨架、画布右键菜单锚点。
///
/// 纯界面偏好与瞬态，零副作用、零 IR 真源触碰。**需要读 program 几何或会
/// 提交 IR 的臂留壳**（契约 3）：画布手势 BlocksCanvasPress/DragTo/Release
/// （命中/落槽/重排）、EditBlockValue（打开时取叶子当前值）、BlocksContextMenu
/// （设置选中块）、BlockValueCommit、*Drop、BlocksMenuAction（递归回喂）。
/// 这些留壳臂经组合根直接读写 `model.blocks_ui.*`（与 ai_ui 改名臂同形态）。
pub(all) struct BlocksUiState {
  /// 语句插入面板：选中分类下标（-1 = 全部）与开合。
  /// 组合根的「插入后自动收起面板」直接写 statement_palette_open，故均为 mut。
  mut selected_category : Int
  mut statement_palette_open : Bool
  /// 积木画布受控滚动偏移（拖到边缘自动滚动在 update 内步进）。
  mut blocks_scroll_y : Double
  /// 正在编辑的值：语句链下标 + 表达式路径 + 输入文本；None = 无值编辑。
  /// 打开（EditBlockValue）/提交（BlockValueCommit）在壳，草稿在切片。
  mut block_value_edit : (Int, Array[Int], String)?
  /// 画布右键菜单锚点：(链下标, 局部 x, 局部 y)；打开在壳（带选中），关在切片。
  mut block_menu : (Int, Double, Double)?
  /// 从调色板拖动的语句骨架（分类下标, 模板下标）；落地（Drop*）在壳。
  mut palette_drag : (Int, Int)?
  /// 从调色板拖动的表达式模板下标；落地（ExpressionDrop）在壳。
  mut expr_drag : Int?
}

///|
/// 切片初始态。
pub fn BlocksUiState::new() -> BlocksUiState {
  {
    selected_category: -1,
    statement_palette_open: false,
    blocks_scroll_y: 0.0,
    block_value_edit: None,
    block_menu: None,
    palette_drag: None,
    expr_drag: None,
  }
}

///|
/// 边缘自动滚动单步（原 app BLOCKS_AUTOSCROLL_STEP）。
pub const BLOCKS_UI_AUTOSCROLL_STEP : Double = 28.0

///|
/// 积木域 UI 子消息：纯界面偏好与瞬态，零副作用。
pub(all) enum BlocksUiMsg {
  /// 切换语句插入面板（再点同分类收起）。
  ToggleStatementPalette(Int)
  /// 切换积木分类条选中分类。
  SelectCategory(Int)
  /// 画布受控滚动。
  BlocksScrolled(Double)
  /// 拖到画布边缘按方向步进滚动。
  BlocksAutoScroll(Int)
  /// 值就地编辑草稿输入。
  BlockValueInput(String)
  /// 取消值编辑。
  BlockValueCancel
  /// 开始拖动语句骨架（分类, 模板）。
  PaletteDragStart(Int, Int)
  /// 开始拖动表达式模板。
  PaletteExprDragStart(Int)
  /// 关闭画布右键菜单。
  BlocksContextMenuClose
}

///|
/// 积木 UI 切片 update：纯状态转移，零副作用。
pub fn update_blocks_ui(
  state : BlocksUiState,
  msg : BlocksUiMsg,
) -> (BlocksUiState, @moui.Effect[BlocksUiMsg]) {
  let none = @moui.Effect::none()
  match msg {
    ToggleStatementPalette(index) =>
      (
        {
          ..state,
          selected_category: index,
          statement_palette_open: if state.statement_palette_open &&
            state.selected_category == index {
            false
          } else {
            true
          },
        },
        none,
      )
    SelectCategory(index) => ({ ..state, selected_category: index, }, none)
    BlocksScrolled(y) => ({ ..state, blocks_scroll_y: y.max(0.0), }, none)
    BlocksAutoScroll(direction) =>
      (
        {
          ..state,
          blocks_scroll_y: (state.blocks_scroll_y +
          direction.to_double() * BLOCKS_UI_AUTOSCROLL_STEP).max(0.0),
        },
        none,
      )
    BlockValueInput(text) =>
      match state.block_value_edit {
        Some((index, path, _)) =>
          ({ ..state, block_value_edit: Some((index, path, text)), }, none)
        None => (state, none)
      }
    BlockValueCancel => ({ ..state, block_value_edit: None, }, none)
    PaletteDragStart(category, template) =>
      ({ ..state, palette_drag: Some((category, template)), }, none)
    PaletteExprDragStart(template) =>
      ({ ..state, expr_drag: Some(template), }, none)
    BlocksContextMenuClose => ({ ..state, block_menu: None, }, none)
  }
}

///|
/// 积木 UI 域 Feature：view 域刻意 abort（视图由壳组装，与 ai/project 同口径）。
pub fn blocks_ui_feature() -> @moui.Feature[BlocksUiState, BlocksUiMsg] {
  @moui.Feature::new(
    init=() => (BlocksUiState::new(), @moui.Effect::none()),
    update=fn(state, message) { update_blocks_ui(state, message) },
    view=_state => abort("blocks ui views are composed by the parent shell"),
  )
}
