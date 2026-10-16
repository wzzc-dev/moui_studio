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
/// 画布 → 链逆映射：zoom=1 且原点在 0 时是恒等；缩放与摆放按
/// `chain = (local − origin) / zoom` 求逆。
///
/// 这条不变量是自由画布的命门：逆映射与绘制 transform 必须是**同一个**
/// 缩放，否则「画在这点在那」——而且只在 zoom ≠ 1 时出现，不带缩放的
/// 用例永远发现不了。
test "blocks_to_chain inverts zoom and script origin" {
  let at0 = ScriptOrigin::{ x: 0.0, y: 0.0, }
  let (cx, cy) = blocks_to_chain(120.0, 240.0, 1.0, at0)
  assert_eq(cx, 120.0)
  assert_eq(cy, 240.0)
  // zoom = 2：视口走两倍距离，链坐标只走一倍
  let (zx, zy) = blocks_to_chain(240.0, 480.0, 2.0, at0)
  assert_eq(zx, 120.0)
  assert_eq(zy, 240.0)
  // zoom = 0.5：视口走一半，链坐标走一倍
  let (hx, hy) = blocks_to_chain(60.0, 120.0, 0.5, at0)
  assert_eq(hx, 120.0)
  assert_eq(hy, 240.0)
  // 原点搬走：先减原点再除 zoom
  let moved = ScriptOrigin::{ x: 40.0, y: 60.0, }
  let (mx, my) = blocks_to_chain(280.0, 540.0, 2.0, moved)
  assert_eq(mx, 120.0)
  assert_eq(my, 240.0)
  // zoom ≤ 0 按 1.0 兜底（除零会炸成 ±∞）
  let (gx, gy) = blocks_to_chain(120.0, 240.0, 0.0, at0)
  assert_eq(gx, 120.0)
  assert_eq(gy, 240.0)
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
/// 画布滚动：手动滚动两轴都夹到非负；边缘自动滚只推进**纵向**。
test "blocks_ui scroll clamps both axes and steps vertically" {
  let s = BlocksUiState::new()
  let neg = apply_ui(s, CanvasScrolled(@geometry.Point::new(x=-50.0, y=-50.0)))
  assert_eq(neg.blocks_scroll.x, 0.0)
  assert_eq(neg.blocks_scroll.y, 0.0)
  let manual = apply_ui(
    s,
    CanvasScrolled(@geometry.Point::new(x=120.0, y=80.0)),
  )
  assert_eq(manual.blocks_scroll.x, 120.0)
  assert_eq(manual.blocks_scroll.y, 80.0)
  let down = apply_ui(s, BlocksAutoScroll(1))
  assert_eq(down.blocks_scroll.y, BLOCKS_UI_AUTOSCROLL_STEP)
  // 横向不随自动滚动变化（横滚由用户拖）
  assert_eq(down.blocks_scroll.x, 0.0)
  let up = apply_ui(down, BlocksAutoScroll(-1))
  assert_eq(up.blocks_scroll.y, 0.0)
  // 继续向上不越过 0
  let up2 = apply_ui(up, BlocksAutoScroll(-1))
  assert_eq(up2.blocks_scroll.y, 0.0)
}

///|
/// 缩放：按步进退档、夹到 [MIN, MAX]、0 = 复位 1.0。
test "blocks_ui zoom steps and clamps" {
  let s = BlocksUiState::new()
  let bigger = apply_ui(s, ZoomCanvas(1))
  assert_eq(bigger.canvas_zoom, 1.0 + BLOCKS_UI_ZOOM_STEP)
  let smaller = apply_ui(bigger, ZoomCanvas(-2))
  assert_eq(smaller.canvas_zoom, 1.0 - BLOCKS_UI_ZOOM_STEP)
  // 下限：再退不动
  let floor = apply_ui(smaller, ZoomCanvas(-99))
  assert_eq(floor.canvas_zoom, BLOCKS_UI_ZOOM_MIN)
  // 上限
  let ceiling = apply_ui(floor, ZoomCanvas(99))
  assert_eq(ceiling.canvas_zoom, BLOCKS_UI_ZOOM_MAX)
  // 0 = 复位
  let reset = apply_ui(ceiling, SetCanvasZoom(0.0))
  assert_eq(reset.canvas_zoom, 1.0)
  // 直接给值也夹
  let clamped = apply_ui(reset, SetCanvasZoom(9.0))
  assert_eq(clamped.canvas_zoom, BLOCKS_UI_ZOOM_MAX)
}

///|
/// 脚本搬移：只写 script_origins，原点夹非负（负原点会把脚本拖出画布）。
test "blocks_ui move script records origin and clamps negative" {
  let s = BlocksUiState::new()
  let moved = apply_ui(s, MoveScript("按钮.on_click", 240.0, 360.0))
  match moved.script_origins.get("按钮.on_click") {
    Some(origin) => {
      assert_eq(origin.x, 240.0)
      assert_eq(origin.y, 360.0)
    }
    None => fail("expected script origin")
  }
  let clamped = apply_ui(moved, MoveScript("按钮.on_click", -10.0, -20.0))
  match clamped.script_origins.get("按钮.on_click") {
    Some(origin) => {
      assert_eq(origin.x, 0.0)
      assert_eq(origin.y, 0.0)
    }
    None => fail("expected clamped script origin")
  }
  // 不同脚本各记各的（键 = handler_key）
  let other = apply_ui(clamped, MoveScript("标签.on_change", 40.0, 40.0))
  assert_true(other.script_origins.get("标签.on_change") is Some(_))
  assert_true(other.script_origins.get("按钮.on_click") is Some(_))
}

///|
/// 网格开关：默认开，切换即反。
test "blocks_ui grid toggles" {
  let s = BlocksUiState::new()
  assert_true(s.canvas_grid)
  let off = apply_ui(s, ToggleCanvasGrid)
  assert_false(off.canvas_grid)
  let on = apply_ui(off, ToggleCanvasGrid)
  assert_true(on.canvas_grid)
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
/// 拖放骨架：语句拖记 (分类, 模板, 指针)，表达式拖记模板下标，互不覆盖。
test "blocks_ui drag skeletons record statement vs expression" {
  let s = apply_ui(BlocksUiState::new(), PaletteDragStart(2, 0))
  match s.palette_drag {
    Some((category, template, _)) => {
      assert_eq(category, 2)
      assert_eq(template, 0)
    }
    None => fail("expected statement drag skeleton")
  }
  assert_true(s.expr_drag is None)
  let e = apply_ui(BlocksUiState::new(), PaletteExprDragStart(3))
  assert_eq(e.expr_drag, Some(3))
  assert_true(e.palette_drag is None)
}

///|
/// 调色板拖拽指针随 Changed 更新（画布实时插入线的数据源）。
test "blocks_ui palette drag moved updates pointer only while dragging" {
  let started = apply_ui(BlocksUiState::new(), PaletteDragStart(2, 0))
  let moved = apply_ui(
    started,
    PaletteDragMoved(@geometry.Point::new(x=120.0, y=64.0)),
  )
  match moved.palette_drag {
    Some((2, 0, p)) => {
      assert_eq(p.x, 120.0)
      assert_eq(p.y, 64.0)
    }
    _ => fail("expected updated drag pointer")
  }
  // 没有在拖动时收到 Moved：no-op（不凭空造拖拽态）
  let idle = apply_ui(
    BlocksUiState::new(),
    PaletteDragMoved(@geometry.Point::new(x=1.0, y=2.0)),
  )
  assert_true(idle.palette_drag is None)
}

///|
/// 关闭右键菜单：锚点清空（打开在壳，关闭是纯 UI 瞬态）。
test "blocks_ui context menu close clears anchor" {
  let open = BlocksUiState::new()
  open.block_menu = Some((2, 100.0, 80.0))
  let closed = apply_ui(open, BlocksContextMenuClose)
  assert_true(closed.block_menu is None)
}

///|
/// `hat_top` 只把**首行**变成帽子圆顶——后续块保持榫卯矩形，
/// 且圆顶不越出行框（几何层零改动，命中/插入不受影响）。
test "blocks_draw_plan hat_top caps only the first row" {
  let blocks = [
    row([], 0, @blk.BkCall, "set_text(结果, \"hi\")"),
    row([0], 0, @blk.BkCall, "append_row(名单)"),
  ]
  let rects = blocks_item_rects(blocks, avail_width=300.0)
  let mk = fn(hat_top : Bool) {
    blocks_draw_plan(
      blocks,
      ["a", "b"],
      rects,
      -1,
      "",
      None,
      0.0,
      0.0,
      hat_top~,
    )
  }
  fn first_hat(ops : Array[BlocksDrawOp]) -> Bool {
    for op in ops {
      match op {
        BlockOutline(_, _, _, _, _, _, _, hat) => return hat
        _ => ()
      }
    }
    false
  }
  fn last_hat(ops : Array[BlocksDrawOp]) -> Bool {
    let mut found = false
    for op in ops {
      match op {
        BlockOutline(_, _, _, _, _, _, _, hat) => found = hat
        _ => ()
      }
    }
    found
  }
  let with_hat = mk(true)
  assert_true(first_hat(with_hat))
  // 第二行必须是普通榫卯块（帽子只属于脚本头）
  assert_true(!last_hat(with_hat))
  // 缺省（编辑卡等场景）不画帽子
  assert_true(!first_hat(mk(false)))
}

///|
/// 帽子圆顶剪影的路径契约（Scratch 口径）：起点在**行顶左缘**（肩线），
/// 峰值隆起到行顶**上方** dome（圆顶是纯装饰，伸进首行上方的留白里，
/// 几何层零改动），左缘不小于行左缘，块体其余部分仍在行框内。
test "block_outline_path hat dome rises above the row frame" {
  let verbs = block_outline_path(10.0, 20.0, 200.0, 30.0, false, true, hat=true)
  // 起点 = 肩线左缘：(x, y)
  match verbs[0] {
    @core.MoveTo(p) => {
      assert_eq(p.x, 10)
      assert_eq(p.y, 20)
    }
    _ => fail("hat path must start with MoveTo")
  }
  let mut min_y : Double = 1000000.0
  let mut min_x : Double = 1000000.0
  let mut max_y : Double = 0.0
  for verb in verbs {
    match verb {
      @core.MoveTo(p) | @core.LineTo(p) => {
        if p.y < min_y {
          min_y = p.y
        }
        if p.x < min_x {
          min_x = p.x
        }
        if p.y > max_y {
          max_y = p.y
        }
      }
      // 圆顶峰值在 QuadTo 的终点上（控制点在肩线上方），必须一并扫描
      @core.QuadTo(c, e) => {
        if c.y < min_y {
          min_y = c.y
        }
        if e.y < min_y {
          min_y = e.y
        }
        if c.x < min_x {
          min_x = c.x
        }
        if e.x < min_x {
          min_x = e.x
        }
      }
      _ => ()
    }
  }
  // 峰值隆起到行顶上方 dome（y=20-9=11）；左缘不小于 x=10；
  // 块体底榫仍在底边下方（y+h+depth=56）——行框外的部分只有圆顶。
  assert_eq(min_y, 11.0)
  assert_true(min_x >= 10.0)
  assert_eq(max_y, 56.0)
}
