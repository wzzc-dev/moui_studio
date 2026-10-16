///|
/// 积木画布的**绘制计划层**：`blocks_draw_plan` 产出纯数据的
/// `BlocksDrawOp` 序列（可快照测试），壳侧只负责把 op 翻译成 paint 命令。
///
/// 与几何层（`blocks_geometry.mbt`）、命中层（`blocks_slot_hit.mbt`）的共同
/// 纪律：三者共用同一套输入（段表 + 注入的度量），**不各算一份**——画在一处
/// 点在另一处，而且因为两者**一起**偏，只测其中一边的用例发现不了。

///|
/// 落槽指示线（**链条坐标**）：拖拽中按同层兄弟中心线算出插入位置，
/// 返回 (y, 宽)。从绘制计划里提出来——画布在选中块处拆成两段后，「插在
/// 哪里」是链条坐标的事实，由调用方一次性算好、再按段换算成本地坐标
/// 下发；绘制层只画，不再自己解释拖拽态（两段各自用子集矩形推槽位，
/// 跨段的兄弟列表会算错位置）。
///
/// 返回 `(y, 宽, 是否有效)`。
///
/// 三条纪律，都由实测暴露：
///
/// 1. **按落点列表 `to_list` 算，不是源列表 `list_path`**——跨层拖拽
///    （拖进 C 形块的洞里）时，指示线必须出现在**目标容器**的兄弟之间；
///    用源列表算会让线画在原来的位置上（用户看到「插回原处」的假反馈）。
/// 2. **子块宽度要减右缩**：C 体内的行被 `blocks_visual_rects` 收窄了
///    `block_arm_width`，线跟着收窄才与目标行对齐。
/// 3. **无效落点用不同颜色**（`valid == false`）：Scratch 在放不进去时
///    不给插入线，这里给一条**红色**线——比「什么都不画」更明确
///    （否则用户以为拖拽坏了）。
pub fn blocks_insert_mark(
  blocks : Array[@blk.BlockItem],
  rects : Array[@geometry.Rect],
  drag : BlocksDragState?,
) -> (Double, Double, Bool)? {
  match drag {
    None => None
    Some(d) => {
      // 目标列表**就是 `to_list`**，不要按「空数组」回落到源列表——
      // 空数组是**顶层**这个合法目标（Scratch 里拖到最外层是最常见的动作）。
      // 回落会让「拖到顶层」把线画在源容器（可能是某个 C 形体内）的位置上，
      // 与松手后的真实落点不符。
      // 按下时 `to_list` 已初始化为 `list_path`，所以它始终有意义。
      let target = d.to_list
      let mut mark_y : Double? = None
      let mut mark_w : Double = 300.0
      let mut seen = 0
      let mut i = 0
      for item in blocks {
        if blocks_same_path(blocks_parent_of(item.path), target) {
          let r = rects[i]
          mark_w = r.size.width
          if seen == d.to {
            mark_y = Some(r.origin.y - 3.0)
          }
          seen = seen + 1
        }
        i = i + 1
      }
      if seen == d.to && seen > 0 {
        // 落到最后一个兄弟之后：线画在其底缘下方
        let mut i2 = 0
        for item in blocks {
          if blocks_same_path(blocks_parent_of(item.path), target) {
            let r = rects[i2]
            mark_y = Some(r.origin.y + r.size.height + 3.0)
          }
          i2 = i2 + 1
        }
      }
      // **空容器**：目标列表一条语句都没有（如刚插入的「如果」的 then 体）。
      // 这是 Scratch 最经典的手势——把块拖进空着的洞里——但按兄弟扫描算不出
      // 任何 y（`seen == 0`），早先的 `seen > 0` 守卫会让它返回 `None`，
      // 于是**拖进空体时完全没有插入线**，用户以为拖不进去。
      //
      // 空容器没有「兄弟」可参照，改为锚在**容器头**上：头是那条拥有这个
      // 列表的语句（`target` 去掉最后一段就是它的路径），线画在头的底缘下方
      // ——正是空体的第一行该出现的位置。
      if seen == 0 && d.to == 0 && target.length() > 0 {
        let owner_path : Array[Int] = []
        let mut k = 0
        while k < target.length() - 1 {
          owner_path.push(target[k])
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
      match mark_y {
        Some(y) => Some((y, mark_w, d.valid))
        None => None
      }
    }
  }
}

///|
/// 拼图块绘制计划：逐块 = 体 + 文本 +（行相邻时）顶卯与底榫 +
/// 选中/聚光灯描边 + 落槽指示线。display_texts 与 blocks 一一对应
/// （控制流块的本地化标签由调用方预渲染，draw 闭包拿不到翻译器）。
/// `insert_mark` 是**本画布本地坐标**的指示线（调用方已按段换算）。
pub fn blocks_draw_plan(
  blocks : Array[@blk.BlockItem],
  display_texts : Array[String],
  rects : Array[@geometry.Rect],
  selected : Int,
  spotlight : String,
  insert_mark : (Double, Double, Bool)?,
  dx : Double,
  dy : Double,
  measure? : (String) -> Double = no_text_measure,
  lead_texts? : Array[String] = [],
  hat_top? : Bool = false,
) -> Array[BlocksDrawOp] {
  let ops : Array[BlocksDrawOp] = []
  // C 左壁的长度 = **视觉高 − 基础行高**。不另算一份弧高：`blocks_visual_rects`
  // 已经把它加进了 `h`，这里减回去就是壁长。两处各算一份就会分叉
  // （画布上的壁与矩形对不上）。
  //
  // 基础行高只能从**基础矩形**取，所以这里要拿到同一组基础矩形。调用方
  // （壳侧画布）传进来的 `rects` 是视觉矩形，其中行距与基础行距
  // 相同（只有顶行被拉高），所以「基础行高」用常量 `block_height` 即可——
  // 不需要重算整组矩形（重算就要再传一次 avail_width，多一个可漂移的入参）。
  // `rects` 此处是**视觉**矩形（顶行已拉高）；`blocks_c_arms` 只读各行的
  // `origin.y`（扩张不改顶边），所以传视觉矩形同样得到正确的弧高。
  let arms = blocks_c_arms(blocks, rects)
  match insert_mark {
    // 无效落点画成**红色拒收线**（比「什么都不画」明确：用户不会以为
    // 拖拽坏了）。有效落点是强调色插入线。
    Some((y, w, valid)) => ops.push(InsertMark(dx + 10.0, dy + y, w, valid))
    None => ()
  }
  let mut i = 0
  for item in blocks {
    let r = rects[i]
    let x = r.origin.x + dx
    let y = r.origin.y + dy
    let w = r.size.width
    let h = r.size.height
    let display = if i < display_texts.length() { display_texts[i] } else { "" }
    let is_selected = i == selected
    // 聚光灯只画描边（`BlockStroke`），不再加「▶ 」文字前缀：块宽现在
    // 随内容收紧，前缀会把高亮行挤出一个省略号（运行态文字跳变）。
    let is_spotlight = item.text != "" && item.text == spotlight
    // 单轮廓（M7②）：榫头/卯口在外轮廓里一次 fill+stroke——
    // **Scratch 咬合语义**：顶卯 = 有上一行（凹进块体），底榫 = 有下一行
    // （凸出块体）。链是连续行（行距 = 行高），按**视觉相邻**判定，
    // 不按 path 下标——装饰块（else/end）与普通行一样要和上下行咬合。
    // 脚本堆首行（hat_top）：Scratch 帽子圆顶剪影——圆顶在行框**上方**
    // （肩线 = 行顶），几何层零改动。
    // 只读数据行（枚举/结构声明）保持素块：它们不是语句，不参与堆叠。
    let is_hat = hat_top && i == 0
    let plain = item.kind is @blk.BkEnumDecl || item.kind is @blk.BkStructDecl
    let has_tab = i > 0 && !plain
    let has_notch = i < blocks.length() - 1 && !plain
    ops.push(BlockOutline(x, y, w, h, item.kind, has_tab, has_notch, is_hat))
    // **C 形左壁**：从顶块（帽）底边向下拉到收尾块顶边。帽本身保持一行高，
    // 壁与收尾块一起把子栈围成 C——「帽 + 左壁 + 底口」三段，缺一段就读成
    // 普通缩进。壁色跟顶块 kind（否则会读成另一块积木）。
    if item.depth >= 0 {
      match arms.get(i) {
        Some(len) =>
          if len > 0.0 {
            ops.push(
              // +2：壁的起点比帽底高 2pt（与帽重叠，接缝不露线），
              // 终点同理多伸 2pt 去接收尾块顶边——否则壁与底口之间
              // 会留一条 2pt 的缝，「包裹」就读断了。
              BlockArm(x, y + h - 2.0, block_arm_width, len + 2.0, item.kind),
            )
          }
        None => ()
      }
    }
    // 条件块（如果/否则如果/当）：标签前一枚「六角宝石」徽标——
    // 取值分支的视觉锚点（真实六角需要多边形绘制，圆角近似同位）。
    let badge = match item.kind {
      // 匹配帽与如果/当同族：取值分派的决策锚点
      @blk.BkIf | @blk.BkElseIf | @blk.BkWhile | @blk.BkMatch => {
        ops.push(BlockBadge(x + 8.0, y + 10.0, item.kind))
        true
      }
      _ => false
    }
    let label_x = if badge { x + 28.0 } else { x + 10.0 }
    // 标签按**块宽**截断（设计稿 .blk 是 `text-overflow: ellipsis` 口径）：
    // 块宽随内容收紧后，只有顶到画布预算的长语句才会截——用省略号收尾，
    // 让「这里有更多内容」是**看得见**的，而不是被画布边缘硬切掉一半。
    // 文字**左对齐**（TextStart）：插槽洞的游标正是从 label_x 起按段宽
    // 累加的，居中会让洞与字形整个错开（实测「如果」块上孤零零一枚黑洞）。
    let label_text = "\{blocks_row_arrow(item)}\{display}"
    let label_max = (w - (label_x - x) - 10.0).max(40.0)
    // **插槽凹槽**（reporter slot）：文本里可再塞一块积木的位置。
    //
    // 截断判定用**注入的真实度量**（与洞的位置同一把尺）。度量缺席（全 0）
    // 时保守跳过：宁可少画，也不要画在字形之外。
    // **洞必须画在文字之下**：先推洞、再推标签——绘制按 ops 顺序叠层，
    // 反过来洞会把字形盖掉（「洞里有字」读成「字被黑洞吃了」）。
    let measured_label = measure(label_text)
    let not_truncated = measured_label <= 0.0 ||
      measured_label <= label_max * @chrome.LABEL_WIDTH_SAFETY
    // 文字/插槽贴行顶下 8pt 排（圆顶在行框上方，行内不再为它让位——
    // 槽与字同一 y，绘制与命中天然对齐）。
    let label_y = y + 8.0
    if not_truncated {
      push_slot_holes(
        ops,
        blocks[i],
        label_x,
        label_y,
        label_max,
        measure,
        blocks_row_lead_width(
          item,
          if i < lead_texts.length() {
            lead_texts[i]
          } else {
            ""
          },
          measure,
        ),
      )
    }
    ops.push(
      BlockLabel(
        label_text,
        label_x,
        label_y,
        label_max,
        @chrome.fit_label(label_text, label_max),
      ),
    )
    if is_selected || is_spotlight {
      ops.push(BlockStroke(x, y, w, h, is_hat))
    }
    i = i + 1
  }
  ops
}

///|
pub(all) enum BlocksDrawOp {
  /// 单轮廓块体（M7②）：顶卯/底榫**画进外轮廓**（PathSpec 一次
  /// fill+stroke），替代贴片式三段（块体填充 + 榫头贴片 + 卯口挖色）。
  /// 第 8 位 `hat`：脚本堆首行的 Scratch 帽子圆顶剪影（圆顶从行顶
  /// 上方隆起，几何层零改动）。
  /// `(x, y, w, h, kind, has_tab, has_notch, hat)`。
  BlockOutline(Double, Double, Double, Double, @blk.BlockKind, Bool, Bool, Bool)
  /// C 形块的左壁：`(x, y, w, h, kind)`——从顶块底边向下延伸包住子栈。
  /// `kind` 决定壁色（与顶块同色，否则「包裹」会读成另一块积木）。
  BlockArm(Double, Double, Double, Double, @blk.BlockKind)
  BlockBadge(Double, Double, @blk.BlockKind)
  BlockLabel(String, Double, Double, Double, String)
  /// 脚本说明横幅：`(文本, x, y, 宽)`。画在积木链**上方**。
  ///
  /// 为什么画在画布上而不是只放右栏：Scratch 的「给这段脚本加注释」是
  /// **贴在积木旁边**的——用户读代码时看到它。只在右栏显示的话，读代码
  /// 的人根本看不到说明，那这条注释就失去了意义。
  ScriptNote(String, Double, Double, Double)
  /// 选中/聚光灯描边。第 5 位 `hat`：帽子行沿外轮廓描边（圆顶不能
  /// 用圆角矩形近似——描边会浮在剪影之外的空带里）。
  BlockStroke(Double, Double, Double, Double, Bool)
  InsertMark(Double, Double, Double, Bool)
  /// 插槽（reporter slot）的圆角凹槽：`(x, y, w, h, 是否有内容)`。
  /// 画在字形之下，读作「这里可以塞一块积木」。
  SlotHole(Double, Double, Double, Double, Bool, Bool)
}

///|
/// 逐段累加宽度，为**插槽段**产出凹槽矩形。
///
/// 段宽来自注入的 `measure`；`lead` 是**引导宽**（标签起始 x 到第一段
/// 字形的距离 = 箭头前缀 + 本地化标签宽，见 `blocks_row_lead_width`）。
/// 此前这里自己减「前缀宽」推游标，与命中层各算一份——两处一起偏，
/// 只测一边的用例发现不了。
///
/// 该函数按「行矩形 + 徽标占位」推 label_x = rect.x + (28 | 10)。
/// 这里的 `label_x` 已是绘制坐标，所以反推一个等价的行矩形交给它，
/// 避免把徽标判定再写一遍（写两遍就会分叉）。
fn push_slot_holes(
  ops : Array[BlocksDrawOp],
  item : @blk.BlockItem,
  label_x : Double,
  label_y : Double,
  label_max : Double,
  measure : (String) -> Double,
  lead : Double,
) -> Unit {
  let badge = match item.kind {
    @blk.BkIf | @blk.BkElseIf | @blk.BkWhile => true
    _ => false
  }
  let row_x = label_x - (if badge { 28.0 } else { 10.0 })
  let row = @geometry.Rect::new(
    x=row_x,
    y=label_y - 6.0,
    width=label_max + 40.0,
    height=20.0,
  )
  for entry in blocks_slot_rects(item, row, measure, lead~) {
    let hole = entry.1
    if hole.origin.x + hole.size.width <= label_x + label_max {
      ops.push(
        SlotHole(
          hole.origin.x,
          hole.origin.y,
          hole.size.width,
          hole.size.height,
          measure(entry.0.text) > 0.0,
          entry.0.pill,
        ),
      )
    }
  }
}

///|
/// 单轮廓 PathSpec（M7②）：块体外轮廓 = 圆角矩形 + 顶边**卯口**（凹进）+
/// 底边**榫头**（凸出），**一条路径**描述整块——Scratch 的拼图咬合语义：
/// 上一行的底榫插进本行的顶卯。
///
/// `tab`（有上一行）= 顶边凹口：路径在 `tab_l..tab_r` 区间**向下凹进块体**
/// `depth`；`notch`（有下一行）= 底边凸榫：路径在 `tab_l..tab_r` 区间
/// **向下凸出** `depth`。两行相邻（行距 = 行高）时榫头恰好填满卯口。
///
/// `hat`：Scratch 帽子剪影——圆顶从**行框上方**隆起（肩线 = 行顶，
/// 峰值 = 行顶 − dome），左半宽为圆顶、右半顶边沿肩线走。几何层
/// （行高/命中/插入）零改动：圆顶是纯装饰，伸进行框上方的留白里
/// （首行上方有 24pt 脚本原点留白或 22pt 说明横幅带，圆顶 9pt 放得下）。
pub fn block_outline_path(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  tab : Bool,
  notch : Bool,
  hat? : Bool = false,
) -> Array[@core.PathVerb] {
  let r = 6.0
  // 榫卯区间靠左对齐（Scratch 口径：紧贴左圆角），宽 24pt、深 6pt。
  let tab_l = x + r
  let tab_r = x + r + 24.0
  let depth = 6.0
  // 帽子圆顶：肩线 = 行顶 y，峰值 = y - dome，隆起占左半宽。
  let dome = 9.0
  let dome_x0 = x
  let dome_x1 = x + w * 0.5
  let dome_span = dome_x1 - dome_x0
  let verbs : Array[@core.PathVerb] = []
  if hat {
    // 顶边：左缘肩线 → 圆顶（两段二次贝塞尔：升到峰值、落回肩线）→
    // 右半肩线。帽行无顶卯（栈首）。
    verbs.push(@core.MoveTo(@core.Point::new(x=dome_x0, y~)))
    verbs.push(
      @core.QuadTo(
        @core.Point::new(x=dome_x0 + dome_span * 0.30, y=y - dome),
        @core.Point::new(x=dome_x0 + dome_span * 0.50, y=y - dome),
      ),
    )
    verbs.push(
      @core.QuadTo(
        @core.Point::new(x=dome_x0 + dome_span * 0.70, y=y - dome),
        @core.Point::new(x=dome_x1, y~),
      ),
    )
    verbs.push(@core.LineTo(@core.Point::new(x=x + w - r, y~)))
    // 右上圆角后右边下行。
    verbs.push(
      @core.QuadTo(
        @core.Point::new(x=x + w, y~),
        @core.Point::new(x=x + w, y=y + r),
      ),
    )
    verbs.push(@core.LineTo(@core.Point::new(x=x + w, y=y + h - r)))
    verbs.push(
      @core.QuadTo(
        @core.Point::new(x=x + w, y=y + h),
        @core.Point::new(x=x + w - r, y=y + h),
      ),
    )
    // 底边：右 → 左（底榫与普通块同一几何——下一行的顶卯照样咬合）。
    if notch {
      verbs.push(@core.LineTo(@core.Point::new(x=tab_r, y=y + h)))
      verbs.push(@core.LineTo(@core.Point::new(x=tab_r, y=y + h + depth)))
      verbs.push(@core.LineTo(@core.Point::new(x=tab_l, y=y + h + depth)))
      verbs.push(@core.LineTo(@core.Point::new(x=tab_l, y=y + h)))
    }
    verbs.push(@core.LineTo(@core.Point::new(x=x + r, y=y + h)))
    verbs.push(
      @core.QuadTo(
        @core.Point::new(x~, y=y + h),
        @core.Point::new(x~, y=y + h - r),
      ),
    )
    // 左边上行回到肩线起点（圆顶从左缘直接隆起，Scratch 帽子口径）。
    verbs.push(@core.LineTo(@core.Point::new(x~, y~)))
    verbs.push(@core.Close)
    return verbs
  }
  // 顶边：左 → 右（有上一行则中段凹进块体 = 顶卯）。
  verbs.push(@core.MoveTo(@core.Point::new(x=x + r, y~)))
  if tab {
    verbs.push(@core.LineTo(@core.Point::new(x=tab_l, y~)))
    verbs.push(@core.LineTo(@core.Point::new(x=tab_l, y=y + depth)))
    verbs.push(@core.LineTo(@core.Point::new(x=tab_r, y=y + depth)))
    verbs.push(@core.LineTo(@core.Point::new(x=tab_r, y~)))
  }
  verbs.push(@core.LineTo(@core.Point::new(x=x + w - r, y~)))
  verbs.push(
    @core.QuadTo(
      @core.Point::new(x=x + w, y~),
      @core.Point::new(x=x + w, y=y + r),
    ),
  )
  // 右边
  verbs.push(@core.LineTo(@core.Point::new(x=x + w, y=y + h - r)))
  verbs.push(
    @core.QuadTo(
      @core.Point::new(x=x + w, y=y + h),
      @core.Point::new(x=x + w - r, y=y + h),
    ),
  )
  // 底边：右 → 左（有下一行则中段向下凸出 = 底榫）。凸出端点的 y 是
  // **底边** y+h——写成 y~ 会抓到顶边 y，路径自交后填充出贯穿整行的
  // 楔形（实测缺陷）。
  if notch {
    verbs.push(@core.LineTo(@core.Point::new(x=tab_r, y=y + h)))
    verbs.push(@core.LineTo(@core.Point::new(x=tab_r, y=y + h + depth)))
    verbs.push(@core.LineTo(@core.Point::new(x=tab_l, y=y + h + depth)))
    verbs.push(@core.LineTo(@core.Point::new(x=tab_l, y=y + h)))
  }
  verbs.push(@core.LineTo(@core.Point::new(x=x + r, y=y + h)))
  verbs.push(
    @core.QuadTo(
      @core.Point::new(x~, y=y + h),
      @core.Point::new(x~, y=y + h - r),
    ),
  )
  // 左边
  verbs.push(@core.LineTo(@core.Point::new(x~, y=y + r)))
  verbs.push(
    @core.QuadTo(@core.Point::new(x~, y~), @core.Point::new(x=x + r, y~)),
  )
  verbs.push(@core.Close)
  verbs
}

///|
/// 单轮廓一次 fill+stroke：榫卯不再是贴片，块与块的「咬合」由轮廓
/// 几何直接表达（渲染器一次走带，无叠色缝）。
pub fn paint_block_outline(
  ctx : @views.PaintContext,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  kind : @blk.BlockKind,
  tab : Bool,
  notch : Bool,
  hat? : Bool = false,
) -> Unit {
  ctx.commands.push(
    @core.DrawPath(@core.PathSpec::{
      verbs: block_outline_path(x, y, w, h, tab, notch, hat~),
      fill: Some(@graphics.Brush::solid(@chrome.block_fill(kind))),
      stroke: Some(@graphics.Brush::solid(@chrome.block_outline_stroke())),
      stroke_width: 1.0,
    }),
  )
}
