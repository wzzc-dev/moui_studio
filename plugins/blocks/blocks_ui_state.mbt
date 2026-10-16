///|
/// 脚本在画布上的摆放原点。
///
/// 独立成结构而不是内联元组：`Map[String, (Double, Double)>` 的收尾 `>` 会被
/// 解析器当成比较运算符（实测 [3002] parse error），且元组在字段多的
/// 结构体里可读性差。**视图事实不是程序语义**：搬脚本只改这张表，
/// IR 零改动，撤销栈不记（与「挪控件」不同级）。
pub(all) struct ScriptOrigin {
  x : Double
  y : Double
} derive(Eq)

///|
pub extend ScriptOrigin with Eq::{not_equal, equal}

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
  /// 语句面板搜索查询（"" = 无过滤）：本地即时过滤，零副作用。
  mut palette_query : String
  /// 积木画布受控滚动偏移（**双轴**：自由画布的内容场大于视口时横纵都要滚）。
  mut blocks_scroll : @geometry.Point
  /// 画布缩放倍率（1.0 = 原始尺寸；绘制期 transform，几何与命中换算见
  /// `blocks_to_chain`）。缩放是**视图偏好**，不碰 IR、不进撤销栈。
  mut canvas_zoom : Double
  /// 画布点阵网格开关（绘制期画，命中层不认它）。
  mut canvas_grid : Bool
  /// 脚本在画布上的摆放原点，键 = `handler_key(控件名, 事件标签)`。
  /// 经组合根序列化进 settings（视图事实，非程序语义）。
  mut script_origins : Map[String, ScriptOrigin]
  /// 正在编辑的值：语句链下标 + 表达式路径 + 输入文本；None = 无值编辑。
  /// 打开（EditBlockValue）/提交（BlockValueCommit）在壳，草稿在切片。
  mut block_value_edit : (Int, Array[Int], String)?
  /// 画布右键菜单锚点：(链下标, 局部 x, 局部 y)；打开在壳（带选中），关在切片。
  mut block_menu : (Int, Double, Double)?
  /// 从调色板拖动的语句骨架（分类下标, 模板下标, 当前指针视口坐标）；
  /// 指针随 Changed 事件更新，画布据此**实时**画插入线（拖拽中可见落点）。
  /// 落地（Drop*）在壳。
  mut palette_drag : (Int, Int, @geometry.Point)?
  /// 从调色板拖动的表达式模板下标；落地（ExpressionDrop）在壳。
  mut expr_drag : Int?
}

///|
/// 切片初始态。
pub fn BlocksUiState::new() -> BlocksUiState {
  {
    selected_category: -1,
    statement_palette_open: false,
    palette_query: "",
    blocks_scroll: @geometry.Point::new(x=0.0, y=0.0),
    canvas_zoom: 1.0,
    canvas_grid: true,
    script_origins: Map([]),
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
/// 缩放倍率下限（再小积木文字不可读）。
pub const BLOCKS_UI_ZOOM_MIN : Double = 0.5

///|
/// 缩放倍率上限（再大插槽与文本的比例失真）。
pub const BLOCKS_UI_ZOOM_MAX : Double = 2.0

///|
/// 缩放单步（工具条 +/- 与快捷键共用同一档距）。
pub const BLOCKS_UI_ZOOM_STEP : Double = 0.25

///|
/// 积木域 UI 子消息：纯界面偏好与瞬态，零副作用。
pub(all) enum BlocksUiMsg {
  /// 切换语句插入面板（再点同分类收起）。
  ToggleStatementPalette(Int)
  /// 切换积木分类条选中分类。
  SelectCategory(Int)
  /// 语句面板搜索查询（本地过滤）。
  SetPaletteQuery(String)
  /// 画布受控滚动（**双轴**）。
  CanvasScrolled(@geometry.Point)
  /// 拖到画布边缘按方向步进**纵向**滚动（横向不自动滚：横滚由用户拖）。
  BlocksAutoScroll(Int)
  /// 画布缩放（夹到 [MIN, MAX]；0 = 适应屏幕，由壳换算成具体倍率）。
  SetCanvasZoom(Double)
  /// 按步进缩放（+1 / −1 档）。
  ZoomCanvas(Int)
  /// 切换画布点阵网格。
  ToggleCanvasGrid
  /// 搬移脚本到画布某点（壳换算成内容坐标后下发；只写 script_origins）。
  MoveScript(String, Double, Double)
  /// 值就地编辑草稿输入。
  BlockValueInput(String)
  /// 取消值编辑。
  BlockValueCancel
  /// 开始拖动语句骨架（分类, 模板）。
  PaletteDragStart(Int, Int)
  /// 拖动中更新调色板指针（画布实时插入线的数据源）。
  PaletteDragMoved(@geometry.Point)
  /// 取消调色板拖拽（指针不在画布上松手 = 不插入；同时清语句与表达式
  /// 两个拖拽瞬态——调色板行收不到画布的事件，落点合法性由 update 侧
  /// 按画布帧判定后走这里）。
  PaletteDragCancel
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
    SetPaletteQuery(query) => ({ ..state, palette_query: query, }, none)
    CanvasScrolled(offset) =>
      (
        {
          ..state,
          blocks_scroll: @geometry.Point::new(
            x=offset.x.max(0.0),
            y=offset.y.max(0.0),
          ),
        },
        none,
      )
    BlocksAutoScroll(direction) =>
      (
        {
          ..state,
          blocks_scroll: @geometry.Point::new(
            x=state.blocks_scroll.x,
            y=(state.blocks_scroll.y +
            direction.to_double() * BLOCKS_UI_AUTOSCROLL_STEP).max(0.0),
          ),
        },
        none,
      )
    // 缩放：0 = 复位到 1.0（工具条「重置为 100%」）；否则按步进退档并夹住。
    SetCanvasZoom(value) =>
      if value <= 0.0 {
        ({ ..state, canvas_zoom: 1.0, }, none)
      } else {
        (
          {
            ..state,
            canvas_zoom: value.clamp(
              min=BLOCKS_UI_ZOOM_MIN,
              max=BLOCKS_UI_ZOOM_MAX,
            ),
          },
          none,
        )
      }
    ZoomCanvas(steps) =>
      (
        {
          ..state,
          canvas_zoom: (state.canvas_zoom +
          steps.to_double() * BLOCKS_UI_ZOOM_STEP).clamp(
            min=BLOCKS_UI_ZOOM_MIN,
            max=BLOCKS_UI_ZOOM_MAX,
          ),
        },
        none,
      )
    ToggleCanvasGrid => ({ ..state, canvas_grid: !state.canvas_grid, }, none)
    // 脚本搬移：原点夹非负（负原点会把脚本拖出内容场左上，再也点不回来）。
    // Map 是共享可变引用（与 runtime_values 同口径）：原位写入即可，
    // 不必重建整张表——重建会让 spread 之外的读者拿到旧表。
    MoveScript(key, x, y) => {
      state.script_origins[key] = ScriptOrigin::{
        x: x.max(0.0),
        y: y.max(0.0),
      }
      (state, none)
    }
    BlockValueInput(text) =>
      match state.block_value_edit {
        Some((index, path, _)) =>
          ({ ..state, block_value_edit: Some((index, path, text)), }, none)
        None => (state, none)
      }
    BlockValueCancel => ({ ..state, block_value_edit: None, }, none)
    PaletteDragStart(category, template) =>
      (
        {
          ..state,
          palette_drag: Some(
            (category, template, @geometry.Point::new(x=0.0, y=0.0)),
          ),
        },
        none,
      )
    PaletteDragMoved(position) =>
      match state.palette_drag {
        None => (state, none)
        Some((category, template, _)) =>
          (
            { ..state, palette_drag: Some((category, template, position)), },
            none,
          )
      }
    PaletteDragCancel =>
      ({ ..state, palette_drag: None, expr_drag: None, }, none)
    PaletteExprDragStart(template) =>
      ({ ..state, expr_drag: Some(template), }, none)
    BlocksContextMenuClose => ({ ..state, block_menu: None, }, none)
  }
}

///|
/// 画布缩放夹取（视图层与测试同口径：ZoomCanvas/SetCanvasZoom 都用它）。
pub fn BlocksUiState::clamp_zoom(value : Double) -> Double {
  value.clamp(min=BLOCKS_UI_ZOOM_MIN, max=BLOCKS_UI_ZOOM_MAX)
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
