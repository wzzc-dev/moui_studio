///|
/// 积木画布的**纯几何层**：布局常量、行矩形推导、C 形（包裹）判定、
/// 命中测试、落槽计算、行首箭头/引导宽。
///
/// 这一层零 `Model`、零 `Msg`、零服务耦合——它只认识 `@blk.BlockItem`
/// 与 `@geometry.Rect`。壳侧的视图函数（`blocks_canvas`，住 app）与
/// update 臂都消费这里的事实，因此「画在哪」与「点在哪」永远同源。
///
/// 与绘制层的共同纪律见 `blocks_draw.mbt` 与 `blocks_slot_hit.mbt`：
/// 三者共用同一套输入（段表 + 注入的度量），不各算一份。

///|
/// 积木拖拽态：同层重排——list_path 定位语句列表，from/to 是
/// 兄弟下标与落槽（落槽 = 落在原下标 to 的语句之前）。
///
/// 纯数据（Int / Array[Int] / Bool），零框架依赖，因此住在几何层：
/// `blocks_insert_mark` 与 update 臂都读它。
pub(all) struct BlocksDragState {
  /// 源语句所在的语句列表路径（拖动前算定）
  list_path : Array[Int]
  /// 源语句的**完整 IR 路径**（链下标在跨层移动时不够用：目标列表要用
  /// 路径寻址，而链下标随展开的装饰块变化）。
  from_path : Array[Int]
  from : Int
  /// 落槽位置。`to_list` 为空时是「同列表内重排」语义。
  to : Int
  /// **落点所在的列表路径**（可能跨层：拖进 C 形块的洞里）。
  /// 空数组 = 顶层。与 `list_path` 不同即为跨层移动——
  /// 那走 `@blk.move_stmt_at`，同层仍走 `reorder_stack`。
  to_list : Array[Int]
  /// 当前落点**是否被语言规则接受**（`@blk.drop_accepts_stmt`）。
  /// 拖拽过程中据此画拒绝反馈；松手时也据此决定要不要真的写 IR。
  valid : Bool
}

///|
/// 块行高（画布局部坐标，导出给壳侧的画布高度预算与 `app.BLOCK_ROW_HEIGHT`
/// 引用）。**行距 = 行高**（`block_step = block_height`）——Scratch 的堆叠
/// 咬合：行与行**零缝隙**，上一行的底榫插进下一行的顶卯（榫深见
/// `block_outline_path`）。行距大于行高会让榫头悬在缝隙里
/// （实测「积木形状和 Scratch 差很多」的主因之一）。
pub const BLOCKS_ROW_HEIGHT : Double = 34.0

///|
/// 布局常量（画布局部坐标）。包内私有——壳侧不需要它们，几何事实由本包
/// 的导出函数承载（`blocks_item_rects` / `blocks_visual_rects` / `blocks_draw_plan`）。
let block_height : Double = BLOCKS_ROW_HEIGHT

///|
let block_step : Double = block_height

///|
let block_indent : Double = 24.0

///|
let block_margin : Double = 10.0

///|
let block_width : Double = 430.0

///|
/// C 形块左壁的厚度（与块体同色的一条竖边，读作「包裹」）。
let block_arm_width : Double = 10.0

///|
/// **画布局部 y → 链条 y** 的换算：绘制与命中**共用这一个函数**。
///
/// 为什么必须抽出来：说明横幅会把积木链整体下移 `note_height`，于是
/// 「画在哪里」与「点在哪里」之间多了一个偏移。两处各写一遍的后果是
/// **点击落到所点那块上方的块**（或落空），而且**只在有说明时**才出现
/// ——没说明时一切正常，不带说明的用例永远发现不了。
///
/// 推导（`y_offset = 0` 时）：
/// - 绘制：`dy = frame.y + note_height`，所以链坐标 `c` 渲染在
///   `frame.y + note_height + c`；
/// - 点击：用户点在那个可见位置，`local = position.y - frame.y
///   = note_height + c`；
/// - 求逆：`c = local - note_height`。
///
/// **是减不是加**。写成加会得到一个偏下 `2 × note_height` 的链坐标，
/// 于是点击落到所点那块**下方**的块——而且只在有说明时出现。
pub fn blocks_chain_y(
  local_y : Double,
  y_offset : Double,
  note_height : Double,
) -> Double {
  local_y - note_height + y_offset
}

///|
/// 脚本原点缺省值（左上留白给缩放读数与网格边）。
pub const BLOCKS_SCRIPT_MARGIN : Double = 24.0

///|
/// **画布视口坐标 → 链条坐标** 的换算：自由画布（缩放 + 脚本摆放）下
/// 「画在哪」与「点在哪」的**唯一**逆映射。
///
/// 三层坐标：
/// - 链坐标 `chain`：`blocks_item_rects` 的输出，脚本内部；
/// - 画布内容坐标 `field`：`chain × zoom + script_origin + pan`；
/// - 视口坐标 `local`：指针/帧原点。
///
/// 求逆：`chain = (local − script_origin) / zoom`。
///
/// **缩放只在绘制期表达**（`push_transform(Transform2D::scale(zoom, zoom))`），
/// 几何函数（`blocks_item_rects` / `blocks_slot_rects` / …）的签名与输出
/// **完全不变**——它们在链坐标里算，缩放由 transform 统一作用于绘制，
/// 所以逆映射只需要除掉 zoom，不需要改任何一个几何函数。这是「几何零
/// 签名改动」的前提，也是本函数存在的唯一理由。
///
/// **所有**吃画布局部坐标的调用点必须走这里（少改一处 = 该处在
/// zoom ≠ 1 时系统性偏移，而且只在缩放后出现，不带缩放的用例永远发现不了）：
/// 1. `@blk.blocks_hit_index`（点选/右键/落槽容器判定）
/// 2. `@blk.blocks_value_hit`（点值就地编辑）
/// 3. `@blk.blocks_slot_hit`（表达式拖入洞）
/// 4. `@blk.blocks_drop_list_of`（拖拽容器判定）
/// 5. `@blk.blocks_drop_slot`（拖拽槽位判定）
/// 6. `@blk.blocks_insert_mark`（插入线 y/宽）
///
/// 之后仍要过 `blocks_chain_y`（说明横幅的下移量与 y_offset 的逆）——
/// 两件事是正交的：zoom 属于画布，note 属于脚本链。
pub fn blocks_to_chain(
  local_x : Double,
  local_y : Double,
  zoom : Double,
  origin : ScriptOrigin,
) -> (Double, Double) {
  // zoom 夹到下限之上：0 或负值会让逆映射炸成 ±∞（除零），
  // 调用方传 0 一律按 1.0 处理（未初始化/复位中的中间态）。
  let scale = if zoom > 0.0 { zoom } else { 1.0 }
  ((local_x - origin.x) / scale, (local_y - origin.y) / scale)
}

///|
/// 脚本说明横幅的高度（含上下间距）。
///
/// 由调用方（壳侧 `blocks_pane`）同时用于「画布高度」与「积木链下移量」，
/// 常量放这里保证两处同源。
pub const BLOCKS_NOTE_HEIGHT : Double = 22.0

///|
/// 拖拽时触发自动滚动的边缘带高度：指针进入画布上/下 24pt 内即开始滚动。
pub const BLOCKS_EDGE_ZONE : Double = 24.0

///|
/// C 形块（控制流「包裹」形态）的几何：哪一行是 C 的**顶**，它的弧要拉多高。
///
/// Scratch 的核心视觉语义是「C 形包裹」：`如果/重复/当` 的块体向下包住
/// 它自己的子栈，子栈因此看起来**在里面**，而不是靠缩进「大概在里面」。
///
/// **为什么是纯视图**：`BlockItem` 是扁平链 + `depth`，控制流被展开成
/// `if → 子栈 → elseIf/else → 子栈 → end` 的兄弟序列。C 的边界可以从这个
/// 序列**推导**出来（不需要 IR 或投影改动）：
/// - 顶 = `BkIf / BkElseIf / BkElse / BkCountLoop / BkWhile`；
/// - 底 = 下一个**同深度**的装饰块（`BkElseIf / BkElse / BkEnd`——
///   它们的 `path` 为空，是既有的「装饰块没有对应语句」标记）；
/// - `end` 是最后一个 C 的收尾，`elseIf/else` 同时收上一个 C、开下一个。
///
/// 返回 `(行下标 → 壁长)`，即该顶块要向下延伸多少才够包住子栈。
/// 逐个头块找**最近的**同深度装饰块：`if` 与它后面的 `elseIf` 各自成 C，
/// 各由自己的收尾行结束。
///
/// **顶块本身保持一行高**（它是 C 的「帽」），壁负责从帽底拉到收尾块顶边
/// ——「帽 + 左壁 + 底口」才是 Scratch 的 C 形。早先的实现改成把**顶块矩形
/// 拉高**去包住子栈，于是顶块的填充盖住了子行的上半部分（实测顶块
/// 10..130 覆盖了子行 50..124），子块看着像陷进父块里。
///
/// `rects` 只读 `origin.y`（各行的顶边不因扩张而变），所以传基础矩形或
/// 视觉矩形都得到同一结果。
pub fn blocks_c_arms(
  blocks : Array[@blk.BlockItem],
  rects : Array[@geometry.Rect],
) -> Map[Int, Double] {
  let arms : Map[Int, Double] = Map([])
  let mut i = 0
  while i < blocks.length() {
    let head = blocks[i]
    let is_head = match head.kind {
      @blk.BkIf
      | @blk.BkElseIf
      | @blk.BkCase
      | @blk.BkElse
      | @blk.BkCountLoop
      | @blk.BkWhile
      | @blk.BkMatch => true
      _ => false
    }
    if is_head && i < rects.length() {
      // 找同深度的下一个装饰块（else-if / else / end）
      let mut j = i + 1
      let mut terminator = blocks.length()
      while j < blocks.length() {
        let item = blocks[j]
        if item.depth == head.depth &&
          (
            item.kind is @blk.BkElseIf ||
            item.kind is @blk.BkCase ||
            item.kind is @blk.BkElse ||
            item.kind is @blk.BkEnd
          ) {
          terminator = j
          break
        }
        j = j + 1
      }
      // 弧高 = 顶块**基础底边**到收尾块**顶边**的距离。
      //
      // 基础底边用常量 `block_height` 算，**不**用 `rects[i].size.height`：
      // 传入的 rects 可能是已扩张的视觉矩形（顶行被拉高），用它会把上一段
      // 弧叠进来。所有基础行都是 `block_height` 高（`blocks_item_rects`
      // 恒设），所以 `origin.y + block_height` 在两种 rects 下都成立。
      // **只依赖 origin.y**（扩张不改顶边），函数因此对两种输入都安全。
      let head_bottom = rects[i].origin.y + block_height
      let terminator_top = if terminator < rects.length() {
        rects[terminator].origin.y
      } else {
        head_bottom
      }
      arms[i] = (terminator_top - head_bottom).max(0.0)
    }
    i = i + 1
  }
  arms
}

///|
/// 把基础行矩形调成**视觉矩形**：给 C 的子行右缩，让 C 的右墙看得见。
///
/// 这里**不再拉高顶块**。早先的实现把顶块矩形拉高去「包住」子栈，结果顶块
/// 自己的填充盖住了子行的上半部分（实测顶块 10..130 覆盖了子行 50..124），
/// 子块看着像陷进父块里。正确的 C 形由三段拼成：
///
/// - **帽** = 顶块本身（一行高，正常绘制）；
/// - **左壁** = `BlockArm`（从帽底拉到收尾块顶边，见 `blocks_c_arms`）；
/// - **底口** = 收尾块（`end` / `else` / `elseIf` 自己那一行）。
///
/// 所以视觉矩形与基础矩形只差**子行的右缩**这一件事——高度完全不动。
/// 缩进是「在里面」的第二个信号（第一个是左壁）。
///
/// 右缩必须对**同一个体内的所有行**生效。判据不能是「向上第一个更浅的行
/// 是 C 头就返回」——同层兄弟会提前短路（实测子栈里只有第一行被缩、
/// 第二行没有）。见 `blocks_in_c_body`。
pub fn blocks_visual_rects(
  blocks : Array[@blk.BlockItem],
  rects : Array[@geometry.Rect],
) -> Array[@geometry.Rect] {
  let out : Array[@geometry.Rect] = []
  let mut i = 0
  for r in rects {
    let inset = if blocks_in_c_body(blocks, i) { block_arm_width } else { 0.0 }
    out.push(
      @geometry.Rect::new(
        x=r.origin.x,
        y=r.origin.y,
        width=(r.size.width - inset).max(40.0),
        height=r.size.height,
      ),
    )
    i = i + 1
  }
  out
}

///|
/// 第 `index` 行是否在某个 C 形块的**体内**。
///
/// 判据：**向上跨过所有同层兄弟**（它们与自己在同一个体内，不该短路），
/// 直到遇到一个更浅的行；那一行是 C 头（`if/elseIf/else/loop/while`）就
/// 说明本行在它的体内。
///
/// 早先的实现在遇到**第一个同层行**时就返回 false——于是子栈里只有紧邻
/// 头块的那一行被缩进，其余同层兄弟全都不缩（实测第一子行 w=416、
/// 第二子行 w=426）。「同层」恰恰是「同一个体内的兄弟」，不是「不在体内」。
pub fn blocks_in_c_body(blocks : Array[@blk.BlockItem], index : Int) -> Bool {
  if index <= 0 || index >= blocks.length() {
    return false
  }
  let depth = blocks[index].depth
  let mut j = index - 1
  while j >= 0 {
    let item = blocks[j]
    if item.depth < depth {
      // 找到所属的父层：它是 C 头才算「在体内」
      return match item.kind {
        @blk.BkIf
        | @blk.BkElseIf
        | @blk.BkCase
        | @blk.BkElse
        | @blk.BkCountLoop
        | @blk.BkWhile
        | @blk.BkMatch => true
        _ => false
      }
    }
    j = j - 1
  }
  false
}

///|
/// 积木行矩形。`avail_width` 是画布可用宽：**必须传**（默认值是历史常量，
/// 只在没有视口信息的纯逻辑测试里用）。
///
/// **块宽随内容**（Scratch 口径）：每行的宽度由展示文本估宽决定，不再
/// 撑满画布（用户报的「积木左右撑满了」）。估宽与 `@chrome.fit_label` 同一把尺
/// （`@chrome.text_estimate_width`），除以 `@chrome.LABEL_WIDTH_SAFETY` 抵消 @chrome.fit_label 的
/// 安全系数——否则「按估宽定的块」会被 @chrome.fit_label 再截一次（估宽刚好等于
/// 预算时省略号照样出现）。上限仍是画布预算：超长语句照旧截成省略号，
/// 下限 64 保证小积木（如「结束」帽）仍有可点的命中区。
///
/// `display_texts` 是**绘制侧展示文本**（本地化标签 + 语句文本）。宽度
/// 从它算，命中侧就必须传同一份——两处各算一份宽度，「画的块」与「命中
/// 的块」会错开一截。缺省（纯逻辑测试）按 `item.text` 估，几何自洽。
pub fn blocks_item_rects(
  blocks : Array[@blk.BlockItem],
  avail_width? : Double = block_width,
  display_texts? : Array[String] = [],
) -> Array[@geometry.Rect] {
  let rects : Array[@geometry.Rect] = []
  // 预算下限必须**不超过可用宽**：下限高于画布可用宽时块体本身就越出
  // 画布（实测 1100 窗口下画布 155、下限 160，块文字越出裁剪区 5px）。
  // 下限只防「画布极窄时块缩成 0」——取可用宽与 160 的较小者，再兜底 80。
  let budget = (avail_width - block_margin * 2.0).max(
    (avail_width * 0.5).max(80.0).min(160.0),
  )
  for item in blocks {
    let x = block_margin + item.depth.to_double() * block_indent
    let display = if rects.length() < display_texts.length() {
      display_texts[rects.length()]
    } else {
      item.text
    }
    // 行首内边距：条件块先画一枚徽标（占 28pt），其余 10pt。
    // 与 `blocks_draw_plan` 的 label_x 偏移同一口径（两处各算会错位）。
    let lead_pad = match item.kind {
      @blk.BkIf | @blk.BkElseIf | @blk.BkWhile => 28.0
      _ => 10.0
    }
    // 内容宽 = 内边距 + 展示文本估宽（含返回箭头前缀）÷安全系数 + 右缘余量。
    // 估宽偏窄 ~2%（见 `@chrome.fit_label` 的注释），除以安全系数后实渲必然放得下。
    let prefix = if item.kind is @blk.BkReturn { "↩ " } else { "" }
    let content = lead_pad +
      @chrome.text_estimate_width("\{prefix}\{display}") /
      @chrome.LABEL_WIDTH_SAFETY +
      12.0
    let max_width = (budget - item.depth.to_double() * block_indent).max(64.0)
    let width = content.min(max_width).max(64.0)
    rects.push(
      @geometry.Rect::new(
        x~,
        y=block_margin + rects.length().to_double() * block_step,
        width~,
        height=block_height,
      ),
    )
  }
  rects
}

///|
/// 命中测试：返回压点所在行（链条下标），无命中返回 -1。
///
/// `avail_width` 与 `display_texts` **必须与绘制侧同值**（画布可用宽 +
/// 展示文本）：绘制用真实宽算块体，命中用不同的宽/文本就会在「块右缘 →
/// 旧默认宽」那段空白里误判命中，或把块内点击判到块外。默认值只服务
/// 没有视口信息的纯逻辑测试。
pub fn blocks_hit_index(
  blocks : Array[@blk.BlockItem],
  x : Double,
  y : Double,
  avail_width? : Double = block_width,
  display_texts? : Array[String] = [],
) -> Int {
  let rects = blocks_visual_rects(
    blocks,
    blocks_item_rects(blocks, avail_width~, display_texts~),
  )
  let mut i = rects.length()
  while i > 0 {
    i = i - 1
    let r = rects[i]
    if x >= r.origin.x &&
      x <= r.origin.x + r.size.width &&
      y >= r.origin.y &&
      y <= r.origin.y + r.size.height {
      return i
    }
  }
  -1
}

///|
pub fn blocks_parent_of(path : Array[Int]) -> Array[Int] {
  let parent : Array[Int] = []
  let mut i = 0
  while i < path.length() - 1 {
    parent.push(path[i])
    i = i + 1
  }
  parent
}

///|
pub fn blocks_same_path(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 落槽计算：同层兄弟中，中心线在指针上方的个数（0..=兄弟数）。
/// 只在拖拽块的兄弟层内计数——跨层移动不在 v1 范围。
pub fn blocks_drop_slot(
  blocks : Array[@blk.BlockItem],
  list_path : Array[Int],
  pointer_y : Double,
  rects : Array[@geometry.Rect],
) -> Int {
  let mut slot = 0
  let mut i = 0
  for item in blocks {
    if blocks_same_path(blocks_parent_of(item.path), list_path) {
      let r = rects[i]
      if r.origin.y + r.size.height / 2.0 <= pointer_y {
        slot = slot + 1
      }
    }
    i = i + 1
  }
  slot
}

///|
/// **调色板拖入的落槽指示线**（`blocks_insert_mark` 的指针版孪生）。
///
/// 为什么另立一个函数而不是复用 `blocks_insert_mark`：后者吃的是
/// `BlocksDragState`（「已抓住哪一块 + 它原来在哪」），而调色板拖入时
/// 手里**没有**已存在的块——只有指针位置。两者的目标列表/槽位推导完全
/// 一样（`blocks_drop_list_of` + `blocks_drop_slot`），差别只在输入。
/// 塞一个假的 `BlocksDragState` 进去会让 `to_list` 的来源说不清。
///
/// 返回 `(y, 宽, 是否有效)`——与 `blocks_insert_mark` 同一形状，画布侧的
/// `InsertMark` op 直接吃。**永远有效**：调色板骨架是合法语句（模板本身
/// 由 `parse_handler_body` 校验过），不存在「放不进去」的语言级拒绝；
/// 拒绝只发生在「指针不在任何行上」，那时返回 `None`（不画线）。
///
/// 指针是**链坐标**（画布 drag 分支已除回 zoom/原点）。
pub fn blocks_drop_mark_at(
  blocks : Array[@blk.BlockItem],
  rects : Array[@geometry.Rect],
  pointer_x : Double,
  pointer_y : Double,
) -> (Double, Double, Bool)? {
  // 顶层是兜底目标：指针不在任何行上时，落到脚本末尾（Scratch 里拖到
  // 最外层是最常见的动作）。
  let top : Array[Int] = []
  let to_list = blocks_drop_list_of(blocks, rects, pointer_y, top)
  let slot = blocks_drop_slot(blocks, to_list, pointer_y, rects)
  // 找目标列表里的第 slot 行：线画在它顶缘上方；列表为空（空容器）时
  // 锚在**容器头**的底缘——那是空体第一行该出现的位置。
  let mut mark_y : Double? = None
  let mut mark_w : Double = 300.0
  let mut seen = 0
  let mut i = 0
  for item in blocks {
    if blocks_same_path(blocks_parent_of(item.path), to_list) {
      let r = rects[i]
      mark_w = r.size.width
      if seen == slot {
        mark_y = Some(r.origin.y - 3.0)
      }
      seen = seen + 1
    }
    i = i + 1
  }
  if seen == slot && seen > 0 {
    // 落到最后一个兄弟之后：线画在其底缘下方
    let mut i2 = 0
    for item in blocks {
      if blocks_same_path(blocks_parent_of(item.path), to_list) {
        let r = rects[i2]
        mark_y = Some(r.origin.y + r.size.height + 3.0)
      }
      i2 = i2 + 1
    }
  }
  // 空容器：锚在容器头底缘（与 `blocks_insert_mark` 同一处理）
  if seen == 0 && slot == 0 && to_list.length() > 0 {
    let owner_path : Array[Int] = []
    let mut k = 0
    while k < to_list.length() - 1 {
      owner_path.push(to_list[k])
      k = k + 1
    }
    let mut i3 = 0
    for item in blocks {
      if blocks_same_path(item.path, owner_path) {
        let r = rects[i3]
        mark_y = Some(r.origin.y + r.size.height + 3.0)
        mark_w = r.size.width
      }
      i3 = i3 + 1
    }
  }
  // pointer_x 不进判定（落槽只按纵向算，与 `blocks_drop_slot` 同口径），
  // 收下它是为了让「横向也参与」的未来改动能就地加。
  let _ = pointer_x
  match mark_y {
    Some(y) => Some((y, mark_w, true))
    None => None
  }
}

///|
/// 落点所在的**语句列表路径**：指针 `pointer_y` 停在哪个容器里。
///
/// Scratch 的「拖进洞里」：指针停在某个 C 形头（`if/重复/当`）的行上时，
/// 落点是**它的体内**（头块的 then 体路径 = 头语句路径 ++ `[0]`）；否则
/// 落点与源同层（同层重排）。
///
/// 判据用「指针落在头的**下半行**」而不是整行：头的上半部分属于「插到它
/// 前面」，下半部分才是「放进它里面」——与 Scratch 的命中区一致，也让
/// 「插在 if 前」与「放进 if 里」两个意图可以分别表达。
pub fn blocks_drop_list_of(
  blocks : Array[@blk.BlockItem],
  rects : Array[@geometry.Rect],
  pointer_y : Double,
  fallback : Array[Int],
) -> Array[Int] {
  let mut i = 0
  for item in blocks {
    let r = rects[i]
    let mid = r.origin.y + r.size.height / 2.0
    // 指针落在该行的下半部分
    if pointer_y >= mid && pointer_y <= r.origin.y + r.size.height {
      // 是 C 形头 → 落进体内
      let is_head = match item.kind {
        @blk.BkIf | @blk.BkCountLoop | @blk.BkWhile => true
        _ => false
      }
      if is_head && item.path.length() > 0 {
        // 体内路径：头语句路径 ++ [0]（If 的 then / 循环的循环体）
        let body_list : Array[Int] = []
        for part in item.path {
          body_list.push(part)
        }
        body_list.push(0)
        return body_list
      }
    }
    i = i + 1
  }
  // 指针落在**所有行之外**（画布下方空白）：目标是**顶层末尾**，不是源列表。
  //
  // 这里曾经回落成 `fallback`（= 源列表），对嵌套在循环里的块就是**循环体
  // 本身**——于是「拖到空白处」被当成「留在循环里」，`break` 这类只能在
  // 特定容器里的语句会被错误放行。空白处按 Scratch 语义是「放到最外层末尾」。
  if pointer_y > 0.0 && blocks.length() > 0 {
    let last = rects[rects.length() - 1]
    if pointer_y > last.origin.y + last.size.height {
      let top : Array[Int] = []
      return top
    }
  }
  fallback
}

///|
/// 文本宽度度量：绘制计划**注入**它而不是自己拿 `TextSystem`——
/// 计划函数是纯的（便于单测），而 `TextSystem` 只在布局上下文里。
/// 默认实现返回 0（不画插槽），这样既有的无度量调用方行为不变。
pub fn no_text_measure(_text : String) -> Double {
  0.0
}

///|
/// 行首箭头前缀：返回块画「↩ 」——「离开子程序」的方向感。
/// 标签与插槽洞的引导宽度都由它拼出（两处各写一份条件就会错位）。
pub fn blocks_row_arrow(item : @blk.BlockItem) -> String {
  if item.kind is @blk.BkReturn {
    "↩ "
  } else {
    ""
  }
}

///|
/// 一行的**插槽引导宽度**：洞的游标从「标签起始 x + 引导宽」开始累加段宽。
/// 引导 = 箭头前缀 + 本地化标签与分隔空格（`lead_texts`，与展示文本同源
/// 产出）。绘制（`push_slot_holes`）与命中（`blocks_slot_hit`）都走这里。
pub fn blocks_row_lead_width(
  item : @blk.BlockItem,
  lead_text : String,
  measure : (String) -> Double,
) -> Double {
  measure("\{blocks_row_arrow(item)}\{lead_text}")
}
