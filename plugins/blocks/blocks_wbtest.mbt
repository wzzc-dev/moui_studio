///|
/// `plugins/blocks` 自身的冒烟测试：几何 / 命中 / 绘制计划三层各钉几条
/// **不变量**，防止包被单独改坏（app 的黑盒测试覆盖行为，这里覆盖契约）。
///
/// 选这三条的理由：它们是「画在哪」与「点在哪」必须同源的三处拐点——
/// 链条 y 换算、C 形右缩、洞与值段的判定分开。

///|
/// 块项构造助手：种类显式给定（C 形判定读 kind，测试要能造 BkIf/BkEnd）。
fn row(
  path : Array[Int],
  d : Int,
  kind : @blk.BlockKind,
  text : String,
) -> @blk.BlockItem {
  @blk.BlockItem::{ kind, depth: d, text, builtin: "", path, segments: None, }
}

///|
/// 链条 y 换算：说明横幅把链下移 `note_height`，点击要**减**回去。
/// 写成加会得到偏下 `2 × note_height` 的坐标——只在有说明时出现，
/// 不带说明的用例永远发现不了。
test "blocks_chain_y subtracts the note offset" {
  assert_eq(blocks_chain_y(42.0, 0.0, 0.0), 42.0)
  assert_eq(blocks_chain_y(52.0, 0.0, 22.0), 30.0)
  assert_eq(blocks_chain_y(52.0, 30.0, 22.0), 60.0)
}

///|
/// C 形体内右缩：同层兄弟**都**要缩（早先的实现只缩紧邻头块的那一行）。
test "blocks_in_c_body covers every sibling in the body" {
  // 头块必须是 C 头（BkIf），否则「在体内」的判定直接为 false。
  let blocks = [
    row([0], 0, @blk.BkIf, "如果"),
    row([0, 0], 1, @blk.BkCall, "第一行"),
    row([0, 1], 1, @blk.BkCall, "第二行"),
    row([1], 0, @blk.BkEnd, "结束"),
  ]
  assert_false(blocks_in_c_body(blocks, 0))
  assert_true(blocks_in_c_body(blocks, 1))
  assert_true(blocks_in_c_body(blocks, 2))
  assert_false(blocks_in_c_body(blocks, 3))
}

///|
/// 洞与值是两类段：`is_slot` 的是可拖放目标，带 `expr_path` 的叶子是
/// 可就地编辑的目标。几何推演只给洞产矩形——值段不进 `blocks_slot_rects`。
test "blocks_slot_rects only yields slot segments" {
  let segments = [
    @blk.TextSegment::{
      text: "设置文本(",
      is_slot: false,
      expr_path: None,
      pill: false,
      label_key: None,
    },
    @blk.TextSegment::{
      text: "lbl",
      is_slot: true,
      expr_path: Some([1]),
      pill: false,
      label_key: None,
    },
    @blk.TextSegment::{
      text: ")",
      is_slot: false,
      expr_path: None,
      pill: false,
      label_key: None,
    },
  ]
  let item = @blk.BlockItem::{
    kind: @blk.BkCall,
    depth: 0,
    text: "设置文本(lbl)",
    builtin: "",
    path: [0],
    segments: Some(segments),
  }
  let rect = @geometry.Rect::new(x=0.0, y=0.0, width=200.0, height=34.0)
  let measure = fn(text : String) -> Double { text.length().to_double() * 6.0 }
  let holes = blocks_slot_rects(item, rect, measure, lead=0.0)
  assert_eq(holes.length(), 1)
  // 空槽也有最小宽度（Scratch 的空槽是一个小胶囊）
  assert_true(holes[0].1.size.width >= 28.0)
}

///|
/// 切片助手：对状态施加一条 BlocksUiMsg，返回新状态（effect 恒为纯态 none）。
fn apply_ui(state : BlocksUiState, msg : BlocksUiMsg) -> BlocksUiState {
  update_blocks_ui(state, msg).0
}

///|
/// 语句面板开合：点分类展开，再点同一分类收起；点别的分类是切换、不收。
test "blocks_ui palette toggles open and collapses on repeat" {
  let s0 = BlocksUiState::new()
  assert_false(s0.statement_palette_open)
  let s1 = apply_ui(s0, ToggleStatementPalette(3))
  assert_true(s1.statement_palette_open)
  assert_eq(s1.selected_category, 3)
  // 切到另一个分类：仍展开，分类变了
  let s2 = apply_ui(s1, ToggleStatementPalette(2))
  assert_true(s2.statement_palette_open)
  assert_eq(s2.selected_category, 2)
  // 再点当前分类：收起
  let s3 = apply_ui(s2, ToggleStatementPalette(2))
  assert_false(s3.statement_palette_open)
  assert_eq(s3.selected_category, 2)
}

///|
/// 分类条选中与面板开合独立：SelectCategory 只改分类，不展开面板。
test "blocks_ui SelectCategory only changes category" {
  let s = apply_ui(BlocksUiState::new(), SelectCategory(1))
  assert_eq(s.selected_category, 1)
  assert_false(s.statement_palette_open)
}

///|
/// 画布滚动：手动滚动夹到非负；边缘自动滚按步长推进且不产生负偏移。
test "blocks_ui scroll clamps to non-negative and steps by constant" {
  let s = BlocksUiState::new()
  assert_eq(apply_ui(s, BlocksScrolled(-50.0)).blocks_scroll_y, 0.0)
  assert_eq(apply_ui(s, BlocksScrolled(120.0)).blocks_scroll_y, 120.0)
  let down = apply_ui(s, BlocksAutoScroll(1))
  assert_eq(down.blocks_scroll_y, BLOCKS_UI_AUTOSCROLL_STEP)
  let up = apply_ui(down, BlocksAutoScroll(-1))
  assert_eq(up.blocks_scroll_y, 0.0)
  // 继续向上不越过 0
  let up2 = apply_ui(up, BlocksAutoScroll(-1))
  assert_eq(up2.blocks_scroll_y, 0.0)
}

///|
/// 值编辑草稿：没打开时输入被忽略；打开后输入更新文本，取消清空。
test "blocks_ui value edit draft is gated and cancellable" {
  let s0 = BlocksUiState::new()
  // 未打开值编辑：输入不落
  let s_none = apply_ui(s0, BlockValueInput("42"))
  assert_true(s_none.block_value_edit is None)
  // 打开值编辑（组合根在壳里做，这里直接构造）
  let open = BlocksUiState::new()
  open.block_value_edit = Some((1, [0], "1"))
  let typed = apply_ui(open, BlockValueInput("42"))
  assert_eq(typed.block_value_edit, Some((1, [0], "42")))
  let cancelled = apply_ui(typed, BlockValueCancel)
  assert_true(cancelled.block_value_edit is None)
}

///|
/// 拖放骨架：语句拖记 (分类, 模板)，表达式拖记模板下标，互不覆盖。
test "blocks_ui drag skeletons record statement vs expression" {
  let s = apply_ui(BlocksUiState::new(), PaletteDragStart(2, 0))
  assert_eq(s.palette_drag, Some((2, 0)))
  assert_true(s.expr_drag is None)
  let e = apply_ui(BlocksUiState::new(), PaletteExprDragStart(3))
  assert_eq(e.expr_drag, Some(3))
  assert_true(e.palette_drag is None)
}

///|
/// 关闭右键菜单：锚点清空（打开在壳，关闭是纯 UI 瞬态）。
test "blocks_ui context menu close clears anchor" {
  let open = BlocksUiState::new()
  open.block_menu = Some((2, 100.0, 80.0))
  let closed = apply_ui(open, BlocksContextMenuClose)
  assert_true(closed.block_menu is None)
}
