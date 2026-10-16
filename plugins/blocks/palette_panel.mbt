///|
/// 语句插入面板（积木调色板）：让**没有 AI、没有模板**的用户也能从零写出
/// 程序逻辑。
///
/// 为什么需要它：积木画布原有的三条写回路径（`commit_block` 替换、
/// `duplicate_block` 克隆、`delete_block` 删除）都**要求语句已存在**
/// ——`commit_block` 遇到空 path 直接 return。于是从零开始的用户只有
/// 「让 AI 生成」「手打代码草稿」「打开模板」三条路，积木视图本身**加不出
/// 一行逻辑**。分类轨虽然可点，但只改一个高亮标志位。
///
/// 本模块把分类轨点击变成真正的入口：点分类 → 列出该分类可插入的语句骨架
/// → 点骨架 → 插入到选中块之后（无选中则末尾）。
///
/// **零新语义**：骨架是 DSL 文本，插入路径复用 `parse_handler_body` 校验
/// 与 `@blk.insert_stmt_at` 手术，与既有编辑链完全同一条。
///
/// 从 `app/blocks_pane.mbt` 迁出（该文件已触 1200 行硬上限）：本视图与 Msg
/// 无关，按「视图由父组装」出壳——壳投影 `PalettePanelParams`，动作经
/// on_* 回壳（与 plugins/ai 同形态）。

///|
/// 「自制积木」在分类轨里的下标（五个内置分类之后）。
/// 与 app 侧 `CATEGORY_INDEX_CUSTOM` 同一口径——两处各写一个数就会
/// 「点第 6 格出现第 5 格的骨架」。
pub const CATEGORY_INDEX_CUSTOM : Int = 5

///|
/// 自定义函数的插入骨架展示名：`名字(0, 0)`（占位实参按形参个数生成）。
/// 用 `0` 而不是 `参数名`：占位符要**可解析**（`0` 是字面量，任何形参
/// 类型都吃得下），而形参名可能与程序里的变量重名、解析出来是另一回事。
pub fn custom_call_label(entry : CustomEntry) -> String {
  let buf = StringBuilder()
  buf.write_string(entry.name)
  buf.write_string("(")
  let mut i = 0
  while i < entry.arity {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string("0")
    i = i + 1
  }
  buf.write_string(")")
  buf.to_string()
}

///|
/// 面板最小宽度（保证骨架标签不被截成一个字）。
pub const STATEMENT_PALETTE_MIN_WIDTH : Double = 132.0

///|
/// 搜索框行高（`@views.text_field` 的 24 口径 + 上下各 4 内垫）。
pub const STATEMENT_SEARCH_HEIGHT : Double = 32.0

///|
/// 拖放引导行高（一行说明文字）。
pub const STATEMENT_DRAG_HINT_HEIGHT : Double = 20.0

///|
/// 面板参数：读数 + 动作（不读壳 Model）。
pub(all) struct PalettePanelParams[Msg] {
  /// 当前选中分类下标（-1 = 全部；面板由壳在分类非空时才建）。
  category_index : Int
  /// 搜索查询（"" = 无过滤）。
  query : String
  language : @studio_lang.Language
  on_insert : (Int) -> Msg
  /// 拖拽手势**全程**（含相位与视口坐标）。行是拖拽的发起者，也是
  /// runtime 捕获语义下唯一收得到移动/松手事件的元素——把事件整个交回
  /// 壳侧，由壳按相位派发开始/移动/松手消息（视口 → 链的换算在 update，
  /// 那里才拿得到画布的布局帧）。
  on_drag_event : (Int, @core.DragGestureEvent) -> Msg
  on_query : (String) -> Msg
  on_new_variable : Msg
  /// 报告块（表达式）拖动源：落点（哪个洞）由画布侧按指针算。
  on_expr_drag_event : (Int, @core.DragGestureEvent) -> Msg
  /// 自制积木组的函数条目（名字 + 形参个数）；空 = 该组显示空态说明。
  /// 由壳从 `program.functions` 投影（插件不读壳 Model）。
  custom_entries : Array[CustomEntry]
  /// 点/拖一条自定义函数（下标 = `custom_entries` 的下标）。
  on_insert_custom : (Int) -> Msg
  on_drag_custom_event : (Int, @core.DragGestureEvent) -> Msg
}

///|
/// 自制积木组的一条：函数名 + 形参个数。
///
/// 只带「名字 + 参数个数」而不带整个 `FuncDef`：面板只需要拼出可插入的
/// 调用骨架（`名字(0, 0)`），形参名/函数体是右栏编辑卡的事。少带字段
/// 也少一处「壳结构改了插件跟着改」的耦合。
pub(all) struct CustomEntry {
  name : String
  arity : Int
}

///|
/// 过滤后的骨架表：查询为空 = 全量；否则按**展示名与骨架文本**做子串匹配
/// （双语都查——界面语言与骨架语言可能不同，只查一边会漏）。
///
/// 判据取子串而非前缀：用户记不全「初始化小灯珠」时打「灯珠」也该命中。
///
/// 纯函数（与 Msg 无关）：写成 `fn[Msg]` 会让 wbtest 无法推断类型参数——
/// 调用处只给 `Translator` 与 `Array[StatementTemplate]`，没有任何
/// `View[Msg]` 参与推导，编译器只能把 `Msg` 默认成 Unit 然后报 unknown type。
pub fn filtered_templates(
  templates : Array[StatementTemplate],
  query : String,
  t : @i18n.Translator,
  language : @studio_lang.Language,
) -> Array[StatementTemplate] {
  let needle = query.trim().to_owned()
  if needle == "" {
    return templates
  }
  let matched : Array[StatementTemplate] = []
  for template in templates {
    let label = t.translate(template.label_key)
    let skeleton = template.skeleton(language)
    if label.contains(needle) || skeleton.contains(needle) {
      matched.push(template)
    }
  }
  matched
}

///|
/// 块形预览行：面板里的骨架以**真实块形**
/// 呈现——单轮廓榫卯剪影 + 分类配色 + 标签，拖出去长什么样、拖之前
/// 就长什么样。`hat = 事件族预览戴帽子圆顶`（与画布脚本头同一剪影）。
/// 点按/拖拽手势由外层容器承接，预览只负责「看起来是块积木」。
fn[Msg] palette_block_row(
  label : String,
  category : @blk.BlockCategory,
  width : Double,
  tap_msg? : Msg? = None,
  drag_event~ : (@core.DragGestureEvent) -> Msg,
  acc_label? : String = "",
) -> @moui.View[Msg] {
  let w = (width - 12.0).max(60.0)
  // 预览行的块形与画布同一剪影：事件族戴帽子圆顶——圆顶在**行框上方**
  // 隆起（见 `block_outline_path`），所以帽行块体下移 9pt 给圆顶留位；
  // 底榫向下凸 6pt，容器 36pt 高把它包住。
  let is_hat = category is @blk.CatEvent
  let row = @views.container(
    @views.measured_canvas(
      measure=fn(_constraints, _text_system) {
        @geometry.Size::new(width=w, height=36.0)
      },
      draw=fn(ctx, frame) {
        let block_y = frame.origin.y + (if is_hat { 11.0 } else { 5.0 })
        ctx.commands.push(
          @core.DrawPath(@core.PathSpec::{
            // 调色板是「新块」：只有底榫、没有顶卯（Scratch 口径）。
            verbs: block_outline_path(
              frame.origin.x + 2.0,
              block_y,
              frame.size.width - 20.0,
              22.0,
              false,
              true,
              hat=is_hat,
            ),
            fill: Some(
              @graphics.Brush::solid(@chrome.block_category_fill(category)),
            ),
            stroke: Some(@graphics.Brush::solid(@chrome.block_outline_stroke())),
            stroke_width: 1.0,
          }),
        )
        @views.draw_text(
          ctx,
          @text.TextRun::new(
            text=@chrome.fit_label(label, frame.size.width - 46.0),
            frame=@geometry.Rect::new(
              x=frame.origin.x + 22.0,
              y=block_y + 2.0,
              width=frame.size.width - 46.0,
              height=18.0,
            ),
            font=@text.FontSpec::new(size=12.0),
            color=@chrome.block_category_text(),
            align=TextStart,
          ),
        )
      },
    ),
    background=@chrome.ide_panel(),
    width=w,
    height=36.0,
    padding=0.0,
  )
  let row = match tap_msg {
    Some(msg) => row.on_tap(msg)
    None => row
  }
  row.on_drag(event => drag_event(event)).accessibility_label(acc_label)
}

///|
pub fn[Msg] statement_palette_panel(
  p : PalettePanelParams[Msg],
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  // **「全部」= 下标 < 0**：列**所有**分类的骨架。
  //
  // 这条分支漏了会把默认分类变成死路：分类轨默认停在「全部」（-1），
  // `category_at(-1)` 返回 None，若 None 一律当空处理，用户一进来就看到
  // 「这个分类没有可插入的语句」——从零写程序的人**一块也插不进去**，
  // 整条调色板（本模块存在的理由）等于不存在。
  //
  // 「自制积木」（下标 5）同样返回 None，但它的骨架在自定义段单独渲染：
  // 两个 None 必须分开，否则「自制积木」分类会混进全部内置语句。
  let category = category_at(p.category_index)
  let all = match category {
    None =>
      if p.category_index < 0 {
        statement_templates()
      } else {
        ([] : Array[StatementTemplate])
      }
    Some(category) => templates_for_category(category)
  }
  let templates = filtered_templates(all, p.query, t, p.language)
  let inner = (width - 24.0).max(60.0)
  let rows : Array[@moui.View[Msg]] = [
    // 搜索框：本地即时过滤（不查程序、不查网络——调色板本来就是本地表）。
    @views.padding_xy(
      @views.text_field(
        p.query,
        on_input=value => (p.on_query)(value),
        placeholder=t.translate("app.blocks.palette.search"),
        variant=Outline,
        width=inner,
        height=24.0,
      ),
      horizontal=8.0,
      vertical=4.0,
    ),
    // 拖放引导：点按与拖放都是入口，说出来才有人发现拖放这条路。
    @views.padding_xy(
      @views.text(
        @chrome.fit_label(t.translate("app.blocks.palette.drag_hint"), inner),
        theme=@chrome.studio_theme(),
        role=Caption,
        width=inner,
        height=14.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
      horizontal=8.0,
      vertical=2.0,
    ),
    @views.padding_xy(
      @views.text(
        @chrome.fit_label(statement_palette_title(t), inner),
        theme=@chrome.studio_theme(),
        width=inner,
        height=18.0,
        align=TextStart,
      ).foreground(@chrome.ide_text()),
      horizontal=8.0,
      vertical=0.0,
    ),
  ]
  // **变量分类里给出「新建变量」入口**（Scratch 的「建立一个变量」按钮）。
  //
  // 为什么必须在这里：此前新建变量只能去左栏结构树的「+」——而用户此刻
  // 正在积木画布上想加一个变量，视线与心智都在这里。Scratch 把入口放在
  // 变量分类底部正是这个理由。复用既有的 `AddVariable`（自动命名、过撤销
  // 点），不新开一条创建路径。
  if category is Some(@blk.CatVariable) {
    rows.push(
      @views.container(
        @views.padding_xy(
          @views.text(
            @chrome.fit_label(t.translate("app.variable.new"), inner),
            theme=@chrome.studio_theme(),
            width=(width - 20.0).max(60.0),
            height=18.0,
            align=TextStart,
          ).foreground(@chrome.ide_accent()),
          horizontal=8.0,
          vertical=0.0,
        ),
        background=@chrome.ide_panel_alt(),
        corner_radius=4.0,
        width=(width - 12.0).max(60.0),
        height=28.0,
        padding=0.0,
      )
      .on_tap(p.on_new_variable)
      .accessibility_label(t.translate("app.variable.new")),
    )
  }
  // **报告块**（运算分类）：这些是**表达式**，只作为洞里的内容。
  //
  // 与语句骨架分开渲染的理由：报告块不能「插一行」（`1 + 1` 单独成句在
  // 语言里非法），所以它们没有点击插入，只有拖拽——面板上给出这条提示，
  // 否则用户点了没反应会以为坏了。
  if category is Some(@blk.CatExpression) {
    rows.push(
      @views.padding_xy(
        @chrome.hint_lines_view(
          t.translate("app.expr.palette.hint"),
          inner,
          @chrome.ide_text_faint(),
          2,
        ),
        horizontal=8.0,
        vertical=0.0,
      ),
    )
    let mut expr_index = 0
    for template in expression_templates() {
      let label = t.translate(template.label_key)
      // 只可拖，不可点：表达式不能单独成句。拖动时记下模板下标，
      // 落点（哪个洞）由画布侧按指针算。块形预览 = 运算青。
      rows.push(
        palette_block_row(
          label,
          @blk.CatExpression,
          width,
          drag_event=event => (p.on_expr_drag_event)(expr_index, event),
          acc_label=label,
        ),
      )
      expr_index = expr_index + 1
    }
  }
  // **自制积木组**（分类下标 5）：列用户自定义函数。与内置骨架分开渲染
  // ——函数的调用要点名 + 传参，插入的骨架是 `名字(0, 0, …)`（占位实参按
  // 形参个数生成），用户随后在右栏编辑卡里改成真实参数。
  //
  // **不新开插入路径**：仍走 `InsertStatement` 的 `parse_handler_body`
  // 校验链——解析失败就什么都不做（绝不把非法表达式塞进 IR）。
  if p.category_index == CATEGORY_INDEX_CUSTOM {
    if p.custom_entries.length() == 0 {
      rows.push(
        @views.padding_xy(
          @chrome.hint_lines_view(
            t.translate("app.blocks.palette.custom_empty"),
            inner,
            @chrome.ide_text_faint(),
            3,
          ),
          horizontal=8.0,
          vertical=0.0,
        ),
      )
    } else {
      let mut ci = 0
      for entry in p.custom_entries {
        let label = custom_call_label(entry)
        // 自制积木 = 命令族的调用块预览（与插入骨架同一形态）。
        rows.push(
          palette_block_row(
            label,
            @blk.CatCommand,
            width,
            tap_msg=Some((p.on_insert_custom)(ci)),
            drag_event=event => (p.on_drag_custom_event)(ci, event),
            acc_label=label,
          ),
        )
        ci = ci + 1
      }
      rows.push(
        @views.padding_xy(
          @chrome.hint_lines_view(
            t.translate("app.stmt.palette.hint"),
            inner,
            @chrome.ide_text_faint(),
            2,
          ),
          horizontal=8.0,
          vertical=0.0,
        ),
      )
    }
    return @views.container(
      @views.scroll_view(
        @views.column(rows, spacing=6.0).frame(width~),
        width~,
        height~,
        shows_indicator=true,
      ),
      background=@chrome.ide_panel(),
      width~,
      height~,
      padding=0.0,
    )
  }
  if templates.length() == 0 {
    // 空态分两种：有查询 = 没匹配到（搜索空态）；无查询 = 该分类没有骨架
    // （既有诚实口径）。混成一句话用户会以为面板坏了。
    let empty_key = if p.query.trim().to_owned() != "" {
      "app.blocks.palette.search_empty"
    } else {
      "app.stmt.palette.empty"
    }
    rows.push(
      @views.padding_xy(
        @chrome.hint_lines_view(
          t.translate(empty_key),
          inner,
          @chrome.ide_text_faint(),
          2,
        ),
        horizontal=8.0,
        vertical=0.0,
      ),
    )
  } else {
    let mut index = 0
    for template in templates {
      let label = t.translate(template.label_key)
      // 拖动 = 从调色板拖到画布（Scratch 的字面手势）。这里只记下
      // 「拖动源」，落点由画布侧按指针算——两个视图互相看不到对方的帧。
      rows.push(
        palette_block_row(
          label,
          template.category,
          width,
          tap_msg=Some((p.on_insert)(index)),
          drag_event=event => (p.on_drag_event)(index, event),
          acc_label=label,
        ),
      )
      index = index + 1
    }
    rows.push(
      @views.padding_xy(
        @chrome.hint_lines_view(
          t.translate("app.stmt.palette.hint"),
          inner,
          @chrome.ide_text_faint(),
          2,
        ),
        horizontal=8.0,
        vertical=0.0,
      ),
    )
  }
  @views.container(
    @views.scroll_view(
      @views.column(rows, spacing=6.0).frame(width~),
      width~,
      height~,
      shows_indicator=true,
    ),
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}
