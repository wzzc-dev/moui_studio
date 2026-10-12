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
