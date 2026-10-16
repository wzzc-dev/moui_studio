///|
/// 积木窗格：分类轨 + 积木画布（选中块处就地展开编辑卡）。
///
/// 从 `workspace.mbt` 拆出来（该文件已到 1200 行硬上限）：积木窗格与代码
/// 窗格是两条独立的展示路径，按「窗格」拆文件比按「视图/辅助」拆更贴近
/// 阅读顺序。

// 包级视图构造器：积木画布/选中描边的自绘原语（原随 canvas.mbt 的 using
// 引入，设计画布几何出壳 plugins/design 后由本文件承接，wbtest 亦可见）。
// `push_transform`/`pop_transform`：自由画布的缩放在绘制期表达——
// 几何函数保持链坐标，缩放由这一次 transform 统一作用于绘制层。
using @views {
  draw_text,
  fill_rounded_rect,
  stroke_rounded_rect,
  push_transform,
  pop_transform,
}

// 自由画布的坐标换算与脚本原点（plugins/blocks 出壳的几何层）。
// `type ScriptOrigin` 带进作用域是为了 `script_origin_of` 的构造与返回
// 类型不必写 `@blk.` 限定名——该文件已近 1200 行硬上限，限定名折行会顶穿。
// `blocks_to_chain` 同理：三处手势入口都要除回 zoom/原点。

///|
using @blk {blocks_to_chain, type ScriptOrigin}

///|
/// 积木行的**展示文本**与**引导文本**（一份产出，两处消费）：
/// - 展示 = 引导 + 语句文本——画布上的整行文字；
/// - 引导 = 本地化标签 + 两个空格——插槽洞的游标从它的宽度之后开始累加
///   段宽，所以洞要落在字形上就必须与展示**同源**（两处各拼会错位）。
///   语句文本为空的行（装饰块）没有段，引导为空串。
///
/// 画布绘制（`blocks_canvas` 的 `display_texts`/`lead_texts`）与 update 层
/// 的命中测试（`@blk.blocks_hit_index` 的 `display_texts`）都必须吃这一份。
pub fn block_row_texts(
  t : @i18n.Translator,
  blocks : Array[@blocks.BlockItem],
) -> (Array[String], Array[String]) {
  let display : Array[String] = []
  let lead : Array[String] = []
  for item in blocks {
    let label = text(t, @blocks.block_label_key(item.kind))
    if item.text == "" {
      display.push(label)
      lead.push("")
    } else {
      display.push("\{label}  \{item.text}")
      lead.push("\{label}  ")
    }
  }
  (display, lead)
}

///|
/// 积木窗格：分类条 + 积木画布（选中块处就地展开编辑卡）。
/// 分类条点分类滚动到该类首块（选中分类记忆在 model.blocks_ui.selected_category）。
pub fn blocks_pane(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let handler_label = match current_handler(model) {
    None => text(t, "app.handler.none")
    Some(handler) =>
      "\{handler.control_name} . \{text(t, "event.\{handler.event.tag()}")}"
  }
  // 「IR 映射 · 与代码同步」走 `tail` 槽：它的宽度由 `pane_head_layout` 与
  // 标题/副标题/两个动作一起分配。**不要在这里自己算宽度**——同一行两处
  // 各算一份预算，口径一不同就会溢出（实测第一版在 1440 宽度上尾巴画到
  // 1253.2，而窗格右缘只有 1166）。
  let head = pane_head(
    text(t, "app.pane.blocks"),
    handler_label,
    width,
    [
      icon_button(
        Columns,
        if model.pane_live {
          text(t, "app.pane.hide_live")
        } else {
          text(t, "app.pane.show_live")
        },
        model.pane_live,
        TogglePaneLive,
        24.0,
        22.0,
        13.0,
      ),
      // 隐藏此窗格（设计稿 #btnHideBlocks）
      icon_button(
        Close,
        text(t, "app.pane.hide"),
        false,
        TogglePaneBlocks,
        24.0,
        22.0,
        13.0,
      ),
    ],
    tail=text(t, "app.pane.blocks.sub"),
  )
  // 分类轨**永远**在（没有选中子程序时全灰）：它是画布左侧的固定列，
  // 「今天没有块」本身就是分类轨要传达的信息之一。它并排在画布左侧
  // （设计稿 #catbar），而不是压在画布上方——积木视图纵向最紧，把分类
  // 移到画布旁边的空白里等于白赚 30pt 画布高。
  let body_height = blocks_body_height(model, height)
  // 启动 hat（G7.1.1）：积木视图顶部的窗体级脚本入口——用户无需在
  // 设计器选中控件即可创建/切换到 OnStart 子程序（纯逻辑程序入口）
  let hat_row = onstart_hat_row(model, t)
  let catbar = category_rail(model, t, body_height)
  // 语句插入面板：分类轨点开时，在轨与画布之间插一列骨架卡片（240pt）。
  // 宽度必须从 canvas_width **扣**：画布是自适应测量节点，让它先占满再把
  // 面板塞进去，面板会被挤到窗格外。顺序不能反（先算宽度、再建画布）。
  let palette_open = model.blocks_ui.statement_palette_open &&
    model.blocks_ui.selected_category >= 0 &&
    @blk.category_at(model.blocks_ui.selected_category) is Some(_)
  // 面板宽度**自适应**：积木窗格常是中心列的两个窗格之一（实测 1280 窗口
  // 下只有 ~374pt），固定 240pt 会把画布挤到 ~44pt（内容全被裁）。
  // 取可用宽的一半并双向夹取，保证画布永远有可用的最小宽度。
  let available = (width - CATEGORY_RAIL_WIDTH - 4.0).max(0.0)
  let palette_width = if palette_open {
    (available * 0.5).max(STATEMENT_PALETTE_MIN_WIDTH).min(240.0)
  } else {
    0.0
  }
  let canvas_width = if palette_open {
    (available - palette_width).max(CANVAS_MIN_WIDTH)
  } else {
    (width - CATEGORY_RAIL_WIDTH - 2.0).max(CANVAS_MIN_WIDTH)
  }
  let canvas = match current_handler(model) {
    None =>
      @views.container(
        @chrome.empty_hint(
          text(t, "app.handler.none"),
          canvas_width,
          body_height - 20.0,
        ),
        width=canvas_width,
        height=body_height,
        padding=0.0,
      )
    Some(handler) => {
      let blocks = @blocks.block_chain(handler.body)
      let (display_texts, lead_texts) = block_row_texts(t, blocks)
      // 落槽指示线一次算好（链条坐标）。矩形必须与画布绘制**同一组入参**
      // （真实画布宽 + 展示文本）：块宽随内容收紧后，宽度进了几何，
      // 两处各算一份宽度，指示线与块体就对不上了。
      let rects = @blk.blocks_item_rects(
        blocks,
        avail_width=canvas_width,
        display_texts~,
      )
      // **落槽指示线有两个来源**：
      // 1. 栈内重排（`block_drag`，既有）——拖动已有块；
      // 2. **调色板拖入**（`palette_drag`，本轮新增）——从面板拖骨架进来。
      //
      // 后者是「拖拽全程看得见落点」的关键（旧实现只有松手才算，拖进去是
      // 盲拖）。画布在 drag 分支里已把指针换算成**链坐标**（zoom/origin
      // 的逆都在那一步做完），随 `PaletteDragMoved` 回报回来，这里直接用
      // 同一套矩形算线——两处必须同坐标系，否则线画在别处。
      let palette_mark = match model.blocks_ui.palette_drag {
        Some((_, _, pointer)) =>
          @blk.blocks_drop_mark_at(blocks, rects, pointer.x, pointer.y)
        None => None
      }
      // 两个来源同一时刻只有一个在场（调色板拖入时不会同时拖已有块）。
      // `blocks_drop_mark_at` 返回非可选（它自己判「不在任何行上」并返回
      // None），`blocks_insert_mark` 返回可选——统一成可选再传给画布。
      let mark : (Double, Double, Bool)? = match palette_mark {
        Some(m) => Some(m)
        None => @blk.blocks_insert_mark(blocks, rects, model.block_drag)
      }
      let spotlight = current_spotlight(model)
      let sel = model.selected_block
      // **选中不再在链条里插编辑卡**（旧版做法）：卡片夹在上下两段之间，
      // 把画布硬切成三段，块多的时候整条链被挤得只剩几行可见——用户读到
      // 的就是「点积木后下面内容显示不全」。编辑面移到右栏 Context（见
      // ide_context.mbt 的 context_block_editor），画布保持**一条连续的链**：
      // 选中只体现在块的描边上，几何零变化，滚动位置也不跳。
      //
      // 代价是「编辑入口离选中远了一步」——用右栏自动切到属性页签 + 画布
      // 选中描边两个信号补回来（成熟 IDE 的检查器同样是「选中在画布、
      // 编辑在侧栏」，IDEA 的 Properties 面板就是这个分工）。
      // **脚本说明横幅**：有说明时在积木链上方留出一条，并把同一高度
      // 加进画布高度——两处不一致会让横幅被裁掉（画布太矮）或与第一块
      // 积木重叠（偏移与高度不匹配）。
      let script_note = target_note(model)
      let note_height = if script_note == "" {
        0.0
      } else {
        @blk.BLOCKS_NOTE_HEIGHT
      }
      // **脚本摆放原点**（自由画布）：当前 handler 的脚本在画布上的位置。
      // 键 = handler_key（与 `script_origins` 表一致），缺省左上留白。
      // 绘制与命中**都从这一处取**——两处各算一份原点，画布上的块与
      // 可点区域就会错开，而且只在用户搬过脚本后出现。
      let origin = script_origin_of(model, handler)
      // **画布内容尺寸 = 脚本实际占位 + 余量**（不是固定大场）。
      //
      // 为什么不是固定 2400×3200：那会让默认状态下画布也有 5 屏滚动范围
      // ——用户滚过去是一片空白，且滚动指示器常驻（实测把
      // right_panel_wbtest 的「右栏头不弹浮层」打成 1 条 overlay）。
      // 内容尺寸跟随脚本走：链高 + 原点 + 余量，链短时内容 ≈ 视口，
      // 滚动范围只在脚本真的摆得远/长到超出视口时才出现。
      //
      // **这两个量只进 `scroll_view`，不进几何**：块宽仍按**可见列宽**
      // （`canvas_width`）收紧，否则 2400 的预算会让每块都长到 2400 宽，
      // 实测把「块宽随内容」的回归打成 668pt（shell_layout_wbtest）。
      let chain_height = rects.length().to_double() * BLOCK_ROW_HEIGHT +
        24.0 +
        note_height
      let content_height = (chain_height + origin.y + 24.0)
        .max(body_height)
        .max(120.0)
      let content_width = (canvas_width + origin.x + 24.0).max(canvas_width)
      // **画布不再自带上下文菜单宿主**：菜单改由**顶层**
      // `studio_overlay_host`（viewport 大小）承载。
      //
      // 为什么必须搬到顶层：`context_menu_region` 用的是 `popup_host`
      // （`BaseSized`），宿主只有**窗格那么大**（实测屏障 233×536），
      // 于是「点别处关闭」的屏障最多只盖住这一个窗格——在窗口其它任何
      // 地方点，指针根本到不了屏障，菜单**永远不消失**（用户报的缺陷）。
      // 屏障要覆盖整个窗口，宿主就必须是 viewport 大小的那一层。
      @views.scroll_view(
        blocks_canvas(
          blocks,
          display_texts,
          sel,
          spotlight,
          mark,
          content_width,
          content_height,
          text(t, "app.blocks.canvas"),
          avail_width=canvas_width,
          palette_drag=model.blocks_ui.palette_drag is Some(_),
          expr_drag=model.blocks_ui.expr_drag is Some(_),
          script_note~,
          note_height~,
          lead_texts~,
          zoom=model.blocks_ui.canvas_zoom,
          grid=model.blocks_ui.canvas_grid,
          origin~,
          // 自由画布的脚本堆首行戴 Scratch 帽子圆顶（每个脚本从事件头开始）。
          hat_top=true,
        )
        // **锚点键**：布局期登记画布内容节点的**布局帧**（随滚动移动，
        // 与画布手势收到的 frame 同一值）。调色板拖拽的指针换算
        // （视口 → 链）经组合根注入的锚点回调按这个键取帧——没有它，
        // 行手势里拿不到画布的位置，落点永远算不出来。
        .key("blocks-canvas"),
        width=canvas_width,
        height=body_height,
        // **受控滚动**：偏移来自模型，拖到边缘时由 `BlocksAutoScroll`
        // 推进。不受控的话自动滚动无处落笔（滚动位置是控件内部状态，
        // update 层看不到也改不了）。
        //
        // **双轴**：内容尺寸（`content_*`）大于视口时横纵都能滚，
        // `scroll_view` 的 offset 是 Point 且对两轴分别钳制——平移就是
        // 滚动，不新造手势（保住滚动指示器与受控滚动回执）。
        offset=model.blocks_ui.blocks_scroll,
        // 手动滚动要回报，否则下一次重渲会把用户滚到的位置弹回模型值。
        on_scroll=Some(offset => BlocksUiOp(@blk.CanvasScrolled(offset))),
        shows_indicator=true,
      )
    }
  }
  // 「适应屏幕」的目标倍率：内容包围盒（画布预算宽/链高 + 摆放原点）÷
  // 画布视口，取两轴小者——绘制 transform 与命中逆映射共用同一 zoom，
  // 这里只算倍率，落库与夹取交给 SetCanvasZoom（同一口径，不另设算式）。
  let fit_zoom = match current_handler(model) {
    None => 1.0
    Some(handler) => {
      let origin = script_origin_of(model, handler)
      let fit_blocks = @blocks.block_chain(handler.body)
      let (fit_texts, _fit_lead) = block_row_texts(t, fit_blocks)
      let fit_rects = @blk.blocks_item_rects(
        fit_blocks,
        avail_width=canvas_width,
        display_texts=fit_texts,
      )
      let content_w = (canvas_width + origin.x + 24.0).max(canvas_width)
      let content_h = (fit_rects.length().to_double() * BLOCK_ROW_HEIGHT +
      24.0 +
      origin.y).max(120.0)
      (canvas_width / content_w)
      .min(body_height / content_h)
      .max(@blk.BLOCKS_UI_ZOOM_MIN)
    }
  }
  // 画布工具条：撤销/重做 + 缩放组 + 网格 + 新事件头（对标图顶部浮动条）。
  // 高度从 body 里扣，不额外占窗格——窗格总高是调用方给的定值。
  let toolbar = blocks_canvas_toolbar(model, t, width, fit_zoom~)
  let body = if palette_open {
    @views.row(
      [
        catbar,
        @views.divider(axis=Vertical, color=@chrome.ide_border()),
        statement_palette_panel(model, t, palette_width, body_height),
        @views.divider(axis=Vertical, color=@chrome.ide_border()),
        canvas,
      ],
      spacing=0.0,
      align=Start,
    )
  } else {
    @views.row([catbar, canvas], spacing=0.0, align=Start)
  }
  @views.container(
    @views.column(
      // 成熟画布工具（Scratch/Figma）不在画布上放常驻用法提示：旧版的
      // 脚注提示与编辑条空态提示两条 24-30pt 的截断文字是纯噪音，删掉后
      // 高度还给画布。交互说明留给空态提示与控件 tooltip。
      // 数据声明区（M7①）在画布上方：有 enum/struct 声明才占高度。
      [head, hat_row, declaration_strip(model, width), toolbar, body],
      spacing=0.0,
    ).frame(width~, height~),
    background=@chrome.ide_editor_background(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 积木画布工具条（壳薄包装）：纯视图在 plugins/blocks，这里只把 Model
/// 投影成参数、把动作映射成 Msg。与 `ide_ai_views.mbt` 同形态。
pub fn blocks_canvas_toolbar(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  fit_zoom~ : Double,
) -> @moui.View[Msg] {
  let zoom = model.blocks_ui.canvas_zoom
  @blk.blocks_canvas_toolbar(
    {
      zoom,
      grid: model.blocks_ui.canvas_grid,
      zoom_at_min: zoom <= @blk.BLOCKS_UI_ZOOM_MIN,
      zoom_at_max: zoom >= @blk.BLOCKS_UI_ZOOM_MAX,
      has_start_handler: @ir.find_handler(model.program, "", @ir.OnStart)
      is Some(_),
      on_undo: Undo,
      on_redo: Redo,
      on_zoom_out: BlocksUiOp(@blk.ZoomCanvas(-1)),
      on_zoom_in: BlocksUiOp(@blk.ZoomCanvas(1)),
      on_zoom_reset: BlocksUiOp(@blk.SetCanvasZoom(1.0)),
      on_zoom_fit: BlocksUiOp(@blk.SetCanvasZoom(fit_zoom)),
      on_toggle_grid: BlocksUiOp(@blk.ToggleCanvasGrid),
      on_new_script: CreateHandler("", @ir.OnStart),
      // `icon_button` 是 app 本地助手（ide_chrome），插件不反向依赖 app——
      // 按「视图由父组装」把构造器注入，与 plugins/ai 的 ghost_icon 同形态。
      icon_button: fn(icon, tip, selected, on_click) {
        icon_button(icon, tip, selected, on_click, 28.0, 24.0, 13.0)
      },
    },
    t,
    width,
  )
}

///|
/// 积木画布可用高度：头 + 画布（编辑卡嵌在链条里，不再占窗格高度）。
pub fn blocks_body_height(model : Model, height : Double) -> Double {
  let _ = model
  (height - @chrome.PANEL_HEAD_HEIGHT - 2.0).max(80.0)
}

///|
/// 当前 handler 的**脚本摆放原点**（自由画布）。
///
/// 从 `blocks_ui.script_origins` 取；没搬过 = 左上留白
/// （`BLOCKS_SCRIPT_MARGIN`）。绘制与命中共用这一处取值——两处各算一份
/// 原点，块体与可点区域就会错开，而且只在用户搬过脚本后出现。
///
/// 原点只进 `script_origins` 表，**不写 IR**：搬脚本是视图偏好，
/// 撤销栈不记（与「挪控件」不同级）。
pub fn script_origin_of(model : Model, handler : @ir.Handler) -> ScriptOrigin {
  let key = handler_key(handler.control_name, handler.event.tag())
  match model.blocks_ui.script_origins.get(key) {
    Some(origin) => origin
    None =>
      ScriptOrigin::{
        x: @blk.BLOCKS_SCRIPT_MARGIN,
        y: @blk.BLOCKS_SCRIPT_MARGIN,
      }
  }
}

///|
/// 分类轨宽度（设计稿 `#catbar` 86pt）。
pub const CATEGORY_RAIL_WIDTH : Double = 86.0

///|
/// 语句插入面板的最小宽度（保证骨架标签不被截成一个字）。
/// 转发插件常量：面板本体已出壳，这里只留壳侧的宽度预算引用点。
pub const STATEMENT_PALETTE_MIN_WIDTH : Double = @blk.STATEMENT_PALETTE_MIN_WIDTH

///|
/// 积木画布的最小宽度。低于这个值块内文字必然被裁，不如让面板更窄。
pub const CANVAS_MIN_WIDTH : Double = 120.0

///|
/// 「自制积木」在分类轨里的下标（五个内置分类之后）。
/// `category_at` 只认 0..4，所以这一格在插件侧单独判。
pub const CATEGORY_INDEX_CUSTOM : Int = 5

///|
/// 用户自定义函数的条数（自制积木组的点亮判据）。
pub fn custom_function_count(model : Model) -> Int {
  model.program.functions.length()
}

///|
/// 自制积木组的条目投影：`program.functions` → (名字, 形参个数)。
/// 顺序与 IR 一致（用户建函数的顺序），不排序——排序会让「刚建的那个」
/// 在列表里跳位置。
pub fn custom_entries_of(model : Model) -> Array[@blk.CustomEntry] {
  let entries : Array[@blk.CustomEntry] = []
  for func in model.program.functions {
    entries.push(@blk.CustomEntry::{
      name: func.name,
      arity: func.params.length(),
    })
  }
  entries
}

///|
/// 积木分类轨（设计稿 `#catbar`）：**竖排**在画布左侧的 86pt 分类栏，
/// 每行 = 分类色点 + 名称，选中项左侧有一条 2pt 强调边。
///
/// 原来是横排芯片条，改竖排有两个理由：① 设计稿就是这个形态；② 横排会
/// 和画布抢纵向空间（积木视图纵向最紧），竖排把分类放到画布旁边的空白里，
/// 一举两得。
///
/// 「全部」永远可点；具体分类只有**本子程序真的有这类块**时才点亮——灰显
/// 但可点（点了会选中一个空分类，诚实地反映「这里没有块」）。
pub fn category_rail(
  model : Model,
  t : @i18n.Translator,
  height : Double,
) -> @moui.View[Msg] {
  let entries = block_category_entries(model)
  let rows : Array[@moui.View[Msg]] = [
    category_rail_row(
      text(t, "app.blocks.cat.all"),
      @chrome.ide_text_muted(),
      model.blocks_ui.selected_category < 0,
      BlocksUiOp(@blk.SelectCategory(-1)),
    ),
  ]
  let mut index = 0
  for entry in entries {
    let selected = model.blocks_ui.selected_category == index
    let has_blocks = entry.first_index >= 0
    rows.push(
      category_rail_row(
        text(t, block_category_label_key(entry.category)),
        if has_blocks {
          @chrome.block_category_fill(entry.category)
        } else {
          @chrome.ide_border()
        },
        selected,
        // 点分类 = 打开该分类的**语句插入面板**（此前只改一个高亮标志位，
        // 画布纹丝不动——分类轨长得像 Scratch 的积木调色板却点不出东西）。
        // 「全部」仍是纯过滤（它没有可插入的语义）。
        BlocksUiOp(@blk.ToggleStatementPalette(index)),
      ),
    )
    index = index + 1
  }
  // **自制积木组**（`app.blocks.palette.group.custom`）：用户自定义函数。
  // 它是第 6 格（下标 5）——五个内置分类之外的新轨位，选中后 palette
  // 走 `CatCustom` 分支列函数名（不是 StatementTemplate 表）。
  //
  // 为什么值得单列一格：函数是「用户自己造的积木」，与内置语句是两类东西
  // （内置的插入即用，函数的调用要点名 + 传参）。混在「命令」分类里，
  // 用户分不清哪条是内建、哪条是自己写的。
  //
  // 点亮判据 = `program.functions` 非空（灰显但可点，与内置分类同口径：
  // 点了看到空态说明，而不是点不动）。
  rows.push(
    category_rail_row(
      text(t, "app.blocks.palette.group.custom"),
      if custom_function_count(model) > 0 {
        @chrome.block_category_fill(@blocks.CatCommand)
      } else {
        @chrome.ide_border()
      },
      model.blocks_ui.selected_category == CATEGORY_INDEX_CUSTOM,
      BlocksUiOp(@blk.ToggleStatementPalette(CATEGORY_INDEX_CUSTOM)),
    ),
  )
  let rail = @views.column(rows, spacing=0.0).frame(
    width=CATEGORY_RAIL_WIDTH,
    height~,
  )
  @views.container(
    rail,
    background=@chrome.ide_panel(),
    width=CATEGORY_RAIL_WIDTH,
    height~,
    padding=0.0,
  )
}

///|
/// 调色板行拖拽手势 → 消息。**行是拖拽事件的唯一接收者**（runtime 的
/// 捕获语义：发起手势的元素持有指针捕获，画布的手势收不到移动/松手），
/// 所以由行按相位派发：
/// - Started = 抓起骨架（blocks_ui 切片记录拖拽源）；
/// - Changed = 上报**视口坐标**指针（PaletteDragPointer——行不知道画布帧，
///   视口 → 链的换算在 update，那里经组合根注入的锚点回调拿画布布局帧）；
/// - Ended = 松手（PaletteDropAt——update 换算后落槽或取消）；
/// - Cancelled = 取消。
fn palette_drag_event_msg(
  category : Int,
  index : Int,
  canvas_width : Double,
  event : @core.DragGestureEvent,
) -> Msg {
  match event.phase {
    @views.DragGesturePhase::Started =>
      BlocksUiOp(@blk.PaletteDragStart(category, index))
    @views.DragGesturePhase::Changed => PaletteDragPointer(event.position)
    @views.DragGesturePhase::Ended =>
      PaletteDropAt(event.position, canvas_width)
    _ => BlocksUiOp(@blk.PaletteDragCancel)
  }
}

///|
/// 表达式（报告块）行的拖拽手势：Started 记拖拽源；移动/松手与语句
/// 拖拽同一条视口上报路径（update 按 `expr_drag` 在场与否分流到洞命中）。
fn palette_expr_drag_event_msg(
  index : Int,
  canvas_width : Double,
  event : @core.DragGestureEvent,
) -> Msg {
  match event.phase {
    @views.DragGesturePhase::Started =>
      BlocksUiOp(@blk.PaletteExprDragStart(index))
    @views.DragGesturePhase::Changed => PaletteDragPointer(event.position)
    @views.DragGesturePhase::Ended =>
      PaletteDropAt(event.position, canvas_width)
    _ => BlocksUiOp(@blk.PaletteDragCancel)
  }
}

///|
/// 语句插入面板（壳薄包装）：纯视图在 plugins/blocks，这里只把 Model
/// 投影成参数、把动作映射成 Msg。
pub fn statement_palette_panel(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let category = model.blocks_ui.selected_category
  @blk.statement_palette_panel(
    {
      category_index: category,
      query: model.blocks_ui.palette_query,
      language: model.language.dsl_language(),
      on_insert: index => InsertStatement(category, index),
      on_drag_event: fn(index, event) {
        palette_drag_event_msg(category, index, width, event)
      },
      on_query: value => BlocksUiOp(@blk.SetPaletteQuery(value)),
      on_new_variable: AddVariable,
      on_expr_drag_event: fn(index, event) {
        palette_expr_drag_event_msg(index, width, event)
      },
      // 自制积木组：从 `program.functions` 投影「名字 + 形参个数」。
      // 插入/拖放都复用既有 `InsertStatement`（parse → insert_stmt_at），
      // 不新开写入路径。
      custom_entries: custom_entries_of(model),
      on_insert_custom: index => InsertCustomFunction(index),
      on_drag_custom_event: fn(index, event) {
        palette_drag_event_msg(CATEGORY_INDEX_CUSTOM, index, width, event)
      },
    },
    t,
    width,
    height,
  )
}

///|
/// 分类轨的一行：2pt 左侧强调边 + 色点 + 名称。
/// 强调边用 `padding_edges` 而不是 border——core 没有单边描边，垫一层
/// 窄容器画背景是这里唯一能表达「左边一条线」的方式。
fn category_rail_row(
  label : String,
  swatch : @core.Color,
  selected : Bool,
  on_click : Msg,
) -> @moui.View[Msg] {
  let content = @chrome.fill_row(
    [
      @views.container(
        @views.text("", width=1.0, height=1.0),
        background=swatch,
        corner_radius=4.0,
        width=8.0,
        height=8.0,
        padding=0.0,
      ),
      @views.text(
        label,
        theme=@chrome.studio_theme(),
        width=(CATEGORY_RAIL_WIDTH - 20.0 - 12.0).max(20.0),
        height=16.0,
        align=TextStart,
      ).foreground(
        if selected {
          @chrome.ide_text()
        } else {
          @chrome.ide_text_muted()
        },
      ),
    ],
    (CATEGORY_RAIL_WIDTH - 14.0).max(40.0),
    7.0,
    Center,
  )
  let inner = @views.padding_edges(
    @views.padding_xy(content, horizontal=8.0, vertical=0.0),
    left=2.0,
  )
  @views.container(
    // 选中：左侧 2pt 强调边铺满行高
    @views.row(
      [
        @views.container(
          @views.text("", width=1.0, height=1.0),
          background=if selected {
            @chrome.ide_accent()
          } else {
            @chrome.ide_panel()
          },
          width=2.0,
          height=24.0,
          padding=0.0,
        ),
        inner,
      ],
      spacing=0.0,
      align=Center,
    ),
    background=if selected {
      @chrome.ide_selection()
    } else {
      @chrome.ide_panel()
    },
    height=24.0,
    width=CATEGORY_RAIL_WIDTH,
    padding=0.0,
  ).on_tap(on_click)
}

///|
/// 积木右键菜单（壳薄包装）：纯视图在 plugins/blocks，这里只把「有没有
/// 选中块」投影成参数、把动作映射成 Msg。
pub fn block_context_menu(
  model : Model,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  @blk.block_context_menu(
    {
      has_block: model.selected_block >= 0,
      on_run_single: BlocksMenuAction(RunSingleBlock),
      on_duplicate: BlocksMenuAction(DuplicateBlock),
      on_delete: BlocksMenuAction(DeleteBlock),
      on_open_palette: BlocksMenuAction(
        BlocksUiOp(
          @blk.ToggleStatementPalette(model.blocks_ui.selected_category),
        ),
      ),
    },
    t,
  )
}

///|
/// 数据声明区（M7①）：enum/struct 声明块投影——**只读行**。声明的真源
/// 在代码工程层（handlers/form 同源派生），不参与积木命中/编辑/榫卯，
/// 画布索引因此零耦合。没有声明时不占任何高度（存量程序零布局影响）。
pub fn declaration_strip(model : Model, width : Double) -> @moui.View[Msg] {
  let decls = @blocks.declaration_chain(model.program)
  if decls.length() == 0 {
    @views.container(
      @views.text("", width=1.0, height=1.0),
      width~,
      height=0.0,
      padding=0.0,
    )
  } else {
    let rows : Array[@moui.View[Msg]] = []
    for item in decls {
      rows.push(
        @views.container(
          @views.text(
            item.text,
            theme=@chrome.studio_theme(),
            width=(width - 34.0).max(80.0),
            height=22.0,
          ).foreground(@chrome.block_text_color()),
          background=@chrome.block_fill(item.kind),
          corner_radius=@chrome.block_corner_radius(item.kind),
          width=(width - 24.0).max(80.0),
          height=26.0,
          padding=0.0,
        ),
      )
    }
    @views.container(
      @views.column(rows, spacing=4.0),
      width~,
      height=decls.length().to_double() * 30.0 + 6.0,
      padding=0.0,
    )
  }
}

///|
/// 启动 hat 行（壳薄包装）：纯视图在 plugins/blocks。
pub fn onstart_hat_row(model : Model, t : @i18n.Translator) -> @moui.View[Msg] {
  @blk.onstart_hat_row(
    {
      exists: @ir.find_handler(model.program, "", @ir.OnStart) is Some(_),
      is_active: model.selected_handler == handler_key("", @ir.OnStart.tag()),
      on_select: SelectHandler(handler_key("", @ir.OnStart.tag())),
      on_create: CreateHandler("", @ir.OnStart),
    },
    t,
  )
}

///|
/// 画布视图：绘制 + 点选/拖拽事件转 typed Msg。
/// `y_offset`：本段画布在**链条坐标**里的纵向原点。编辑卡把链条拆成
/// 上下两段后，下段画布的本地 y 要加上偏移才能与 update 里的链条矩形
/// （命中/落槽计算空间）对齐；整链画布传 0 即可。
/// `zoom`：画布缩放倍率（绘制期 transform，命中走 `blocks_to_chain` 逆映射）。
/// `grid`：点阵网格开关。
/// `origin`：脚本在画布上的摆放原点（`script_origin_of` 的输出）。
/// `avail_width`：**几何**用的可见列宽。与 `width`（画布节点自身尺寸，
/// 即内容宽）分开：自由画布下画布节点要比可见列宽（否则横向滚不动），
/// 而块体仍按可见列宽收紧（否则每块都长到内容宽）。0 = 用 `width`。
pub fn blocks_canvas(
  blocks : Array[@blocks.BlockItem],
  display_texts : Array[String],
  selected : Int,
  spotlight : String,
  insert_mark : (Double, Double, Bool)?,
  width : Double,
  height : Double,
  semantics_label : String,
  avail_width? : Double = 0.0,
  y_offset? : Double = 0.0,
  palette_drag? : Bool = false,
  expr_drag? : Bool = false,
  script_note? : String = "",
  note_height? : Double = 0.0,
  lead_texts? : Array[String] = [],
  zoom? : Double = 1.0,
  grid? : Bool = true,
  origin? : ScriptOrigin = ScriptOrigin::{ x: 24.0, y: 24.0, },
  hat_top? : Bool = false,
) -> @moui.View[Msg] {
  // 文本度量：**布局期**量好、**绘制期**取用。
  //
  // 为什么必须跨这两个阶段：插槽洞的位置 = 前面所有段的宽度之和，而
  // 段宽只有 `TextSystem` 能给；`TextSystem` 挂在**布局上下文**上，
  // 绘制回调拿到的 `PaintContext` 刻意只装绘制指令（框架设计如此），
  // 量不了文本。所以用一格共享单元把结果从布局带到绘制——这也是
  // `measured_canvas` 存在的理由。
  let metrics : Ref[Map[String, Double]] = Ref(Map([]))
  // 几何用的可见列宽（见 `avail_width` 参数的注释）：0 = 退回 `width`。
  let column = if avail_width > 0.0 { avail_width } else { width }
  @views.container(
    @views.measured_canvas(
      measure=fn(_constraints, text_system) {
        // 量本画布会用到的所有段（字面段 + 插槽段）、标签前缀与整行标签。
        // 逐段量而不是量整行：洞的位置正是逐段宽度的累加；整行与引导文本
        // 也要量——截断判定（`not_truncated`）与洞的起点（引导宽）读它们。
        let cache : Map[String, Double] = Map([])
        let measure_into = fn(text : String, cache : Map[String, Double]) {
          if !cache.contains(text) {
            let font = @text.FontSpec::new(size=12.0)
            let measured = text_system.measure_text(
              @core.TextLayoutInput::new(text~, font~),
            )
            cache[text] = measured.size.width
          }
        }
        let mut index = 0
        for item in blocks {
          match item.segments {
            None => ()
            Some(segments) =>
              for segment in segments {
                measure_into(segment.text, cache)
              }
          }
          // 引导文本（箭头前缀 + 本地化标签）：洞的起点 = 它的宽度
          let lead_text = if index < lead_texts.length() {
            lead_texts[index]
          } else {
            ""
          }
          measure_into("\{@blk.blocks_row_arrow(item)}\{lead_text}", cache)
          // 整行标签：截断判定的实尺
          let display = if index < display_texts.length() {
            display_texts[index]
          } else {
            ""
          }
          measure_into("\{@blk.blocks_row_arrow(item)}\{display}", cache)
          index = index + 1
        }
        metrics.val = cache
        // 宽度必须由调用方给定：scroll_view 给子节点的是无界约束
        // （纵向滚动、横向不滚），画布自己量不出视口宽——写死 470 会
        // 在窄窗格里溢出到隔壁面板。高度不设下限（旧的 160pt 下限是给
        // 整链画布的；编辑卡拆段后上段只有 ~50pt，下限会在块与编辑卡
        // 之间凭空垫出一段空白），调用方传的高度就是段的真实高度。
        @geometry.Size::new(width=width.max(160.0), height=height.max(1.0))
      },
      draw=fn(ctx, frame) {
        // **三层坐标的绘制侧**：
        // - 链坐标：`blocks_item_rects` 的输出，脚本内部；
        // - 画布内容坐标：`chain × zoom + script_origin`；
        // - 视口坐标：`frame.origin` 是画布在窗口里的位置。
        // 绘制把 (脚本原点 ÷ zoom + note_height) 折进 transform 的平移项
        // （`push_transform(translation) ∘ push_transform(scale)`），
        // 与命中侧 `blocks_to_chain` 的 `(local − origin)/zoom` 严格互逆。
        let dx = frame.origin.x
        // 有说明横幅时，积木链整体**下移** `note_height`，让横幅占住
        // 上方预留的空间（而不是叠在第一块积木上）。
        // 链坐标 → 画布局部：减去横幅偏移（`@blk.blocks_chain_y` 的逆）。
        let dy = frame.origin.y + note_height
        let base = @blk.blocks_item_rects(
          blocks,
          avail_width=column,
          display_texts~,
        )
        // C 形包裹：顶行的矩形向下扩张，把子栈**包在里面**（Scratch 的核心
        // 视觉语义）。绘制用扩张后的矩形，落槽仍用基础行高——插入位置按
        // 「行」算，视觉包裹按「弧」算，两者刻意分开。基础矩形只算一次。
        let rects = @blk.blocks_visual_rects(blocks, base)
        let cache = metrics.val
        let measure = fn(text : String) -> Double {
          match cache.get(text) {
            Some(value) => value
            None => 0.0
          }
        }
        // **点阵网格**：画在积木之下（先画点，块体随后盖住自己内部的点）。
        // 与设计舞台同型（`plugins/design/design_stage.mbt` 的网格段）：
        // 间距随 zoom 走，点径也随 zoom 走（缩到 0.5 时点不能缩成不可见）。
        // 网格**不随** script_origin 平移：它是画布的底，不是脚本的内容——
        // 否则搬一次脚本整张网格跟着跑，读作「网格属于那个脚本」。
        if grid {
          let step = 32.0 * zoom
          let dot = (2.0 * zoom).max(1.0)
          let right = frame.origin.x + frame.size.width
          let bottom = frame.origin.y + frame.size.height
          // 点阵按「画布坐标里 step 的整数倍」对齐，起点取**不大于画布左缘
          // 的第一个倍数**。
          //
          // 旧写法把 `frame.origin.x` 加了两遍（`gx = floor(origin.x/step)`
          // 之后又算 `origin.x + gx*step`），点阵整体右移了一个 `origin.x`：
          // 画布左半边**一格都没有**，只有右侧一条有网格（实测画布 578 逻辑
          // 宽时点阵从 708 才开始，左侧 352 全是空的）。与
          // `plugins/design/design_stage.mbt` 的网格段同型——那里用
          // `ox + mx*spacing` 且 `mx = floor((frame.origin.x - ox)/spacing)`，
          // 两者相减刚好抵消 frame 偏移，所以是对的。
          let mut px = (frame.origin.x / step).floor() * step
          while px < right {
            let mut py = (frame.origin.y / step).floor() * step
            while py < bottom {
              fill_rounded_rect(
                ctx,
                @graphics.RoundedRect::new(
                  rect=@geometry.Rect::new(x=px, y=py, width=dot, height=dot),
                  radius=dot / 2.0,
                ),
                @graphics.Brush::solid(@chrome.studio_grid_line()),
              )
              py = py + step
            }
            px = px + step
          }
        }
        // **缩放：绘制期 transform**，组合成「平移 → 缩放」：
        // - 先在**链坐标**里平移脚本原点与横幅偏移（`origin/zoom` 与
        //   `note_height`——都是链坐标量，见 dx/dy 的推导）；
        // - 再 `scale(zoom)` 把整块积木层放大到画布尺寸。
        // `Transform2D` 是裸矩阵（a,b,c,d,tx,ty），`concat` 把新矩阵作用在
        // 已有点上，所以先 translate 后 push scale = 点在链坐标里被搬到
        // 脚本位置，再一次性放大。
        // 命中侧 `blocks_to_chain` 的 `(local − origin)/zoom` 正是它的逆，
        // 两处共用同一个 zoom 与 origin，才不会「画在这点在那」。
        // 几何函数（item_rects / slot_rects / …）的输出全程保持链坐标。
        push_transform(
          ctx,
          @core.Transform2D::translation(
            dx=(origin.x / zoom).max(0.0),
            dy=(origin.y / zoom + note_height).max(0.0),
          ),
        )
        push_transform(ctx, @core.Transform2D::scale(sx=zoom, sy=zoom))
        let ops = @blk.blocks_draw_plan(
          blocks,
          display_texts,
          rects,
          selected,
          spotlight,
          insert_mark,
          dx,
          dy,
          measure~,
          lead_texts~,
          hat_top~,
        )
        // **脚本说明横幅**：画在积木链上方（Scratch 的脚本注释贴在积木旁）。
        // 只在有说明时占位——空说明不画，否则每条子程序上方都会有一条
        // 空白带，把画布本来就不多的空间吃掉。
        // `note_height` 是调用方为横幅**预留**的高度：积木链整体下移，
        // 横幅画在空出来的上方。不用「画在积木上」的做法——那会遮住第一块
        // 积木的文本。调用方（`blocks_pane`）把同一数值加进画布高度，
        // 两处一致才不会让横幅被裁掉或与积木重叠。
        if script_note != "" {
          // 横幅画在**变换空间**里（与积木同一层），所以它的屏幕位置还要
          // 加上 `origin.x`：右缘 = dx + origin.x + 10 + w。宽必须把
          // origin.x 扣掉，否则横幅长出可见列、右端被裁剪区切掉
          // （实测 1280 下右缘 968 > 裁剪 934，shell_responsive 报警）。
          let note_w = (column - origin.x - 22.0).max(60.0)
          ops.push(
            ScriptNote(
              @chrome.fit_label(script_note, note_w),
              dx + 10.0,
              dy + 2.0,
              note_w,
            ),
          )
        }
        for op in ops {
          match op {
            BlockOutline(x, y, w, h, kind, tab, notch, hat) =>
              // 单轮廓（M7②）：一次 fill+stroke，榫卯在轮廓里；
              // hat = 脚本堆首行的 Scratch 帽子圆顶剪影。
              @blk.paint_block_outline(ctx, x, y, w, h, kind, tab, notch, hat~)
            BlockArm(x, y, w, h, kind) =>
              fill_rounded_rect(
                ctx,
                @graphics.RoundedRect::new(
                  rect=@geometry.Rect::new(x~, y~, width=w, height=h),
                  radius=2.0,
                ),
                @graphics.Brush::solid(@chrome.block_fill(kind)),
              )
            BlockBadge(x, y, kind) =>
              fill_rounded_rect(
                ctx,
                @graphics.RoundedRect::new(
                  rect=@geometry.Rect::new(x~, y~, width=14.0, height=14.0),
                  radius=4.0,
                ),
                @graphics.Brush::solid(@chrome.block_badge_color(kind)),
              )
            BlockLabel(_text, x, y, maxw, fitted) =>
              // **左对齐**：插槽洞的游标从 frame.x 起按段宽累加，文字居中
              // 会让洞与字形整个错开（实测「如果」块上孤零零一枚黑洞——
              // 用户报的「积木上的黑块」）。
              draw_text(
                ctx,
                @text.TextRun::new(
                  text=fitted,
                  frame=@geometry.Rect::new(x~, y~, width=maxw, height=20.0),
                  font=@text.FontSpec::new(size=12.0),
                  color=@chrome.block_text_color(),
                  align=TextStart,
                ),
              )
            BlockStroke(x, y, w, h, hat) =>
              if hat {
                // 帽子行沿外轮廓描边：圆顶不是矩形的一部分，圆角矩形
                // 描边会浮在剪影外的空带里（下缘与左缘也不贴合）。
                ctx.commands.push(
                  @core.DrawPath(@core.PathSpec::{
                    verbs: @blk.block_outline_path(
                      x - 1.5,
                      y - 1.5,
                      w + 3.0,
                      h + 3.0,
                      false,
                      false,
                      hat=true,
                    ),
                    fill: None,
                    stroke: Some(@graphics.Brush::solid(@chrome.ide_accent())),
                    stroke_width: 2.0,
                  }),
                )
              } else {
                stroke_rounded_rect(
                  ctx,
                  @graphics.RoundedRect::new(
                    rect=@geometry.Rect::new(
                      x=x - 2.0,
                      y=y - 2.0,
                      width=w + 4.0,
                      height=h + 4.0,
                    ),
                    radius=8.0,
                  ),
                  @graphics.Brush::solid(@chrome.ide_accent()),
                  2.0,
                )
              }
            InsertMark(x, y, w, valid) =>
              fill_rounded_rect(
                ctx,
                @graphics.RoundedRect::new(
                  rect=@geometry.Rect::new(
                    x~,
                    y~,
                    width=w,
                    height=if valid { 3.0 } else { 2.0 },
                  ),
                  radius=1.5,
                ),
                @graphics.Brush::solid(
                  if valid {
                    @chrome.ide_accent()
                  } else {
                    @chrome.ide_danger()
                  },
                ),
              )
            // 说明用**斜体式的弱化色**画在浅底上，与积木文本区分开：
            // 注释不该和代码抢注意力（Scratch 的注释也是灰底灰字）。
            ScriptNote(text_value, x, y, w) => {
              fill_rounded_rect(
                ctx,
                @graphics.RoundedRect::new(
                  rect=@geometry.Rect::new(x~, y~, width=w, height=16.0),
                  radius=3.0,
                ),
                @graphics.Brush::solid(@chrome.blocks_note_background()),
              )
              draw_text(
                ctx,
                @text.TextRun::new(
                  text=text_value,
                  frame=@geometry.Rect::new(x~, y~, width=w, height=16.0),
                  font=@text.FontSpec::new(size=11.0),
                  color=@chrome.blocks_note_text(),
                  // **左对齐**：`TextRun::new` 的默认是 `TextCenter`，横幅
                  // 只有一句话、宽度又是列宽时，居中会让它悬在横幅中间，
                  // 与下方左对齐的积木文本（`TextStart`）完全对不齐——
                  // 读起来像标题，而不是「注释贴在积木旁」。
                  align=TextStart,
                ),
              )
            }
            SlotHole(x, y, w, h, filled, pill) =>
              // 插槽：**浅色内凹**读作「这里可以塞一块积木」。
              // 有内容时底色更亮一点（内容块坐上去），空槽更暗（等一块进来）。
              // 颜色取自画布栈的既有色阶，不新引入 token——插槽是积木的
              // 内部结构，不是独立表面。
              // 字段访问胶囊（M7②）：全圆角（h/2），数据读取的专属形态。
              fill_rounded_rect(
                ctx,
                @graphics.RoundedRect::new(
                  rect=@geometry.Rect::new(x~, y~, width=w, height=h),
                  radius=if pill { h / 2.0 } else { 6.0 },
                ),
                @graphics.Brush::solid(
                  if filled {
                    @chrome.blocks_slot_filled()
                  } else {
                    @chrome.blocks_slot_empty()
                  },
                ),
              )
          }
        }
        // 与两个 push_transform 配对（LIFO：先弹 scale，再弹平移）。
        // **少弹一个不只是错位**：本闭包在 scroll_view 的 clip 作用域内，
        // 泄漏的 Transform 会让 scroll_view 的 PopClip 在渲染器侧类型不匹配
        // （`pop_canvas_scope` 拒绝恢复），clip 从此对本帧不再关闭——画布之后
        // 绘制的一切（底栏、右栏、状态栏）被永远裁进积木画布视口，真机表现
        // 就是「积木界面下右栏/底栏/状态栏全部不显示」。
        pop_transform(ctx)
        pop_transform(ctx)
      },
      semantics_label~,
    )
    // 右键：命中测试与左键同一套几何（含真实 avail_width），把链下标
    // 交给 update 开菜单。**与左键共用 `@blk.blocks_hit_index`**——两处各算一份
    // 命中就会「点得中但右键点不中」。
    .on_secondary_tap_with_frame(fn(position, frame) {
      // 画布视口坐标 → 链坐标：**先**除回 zoom/原点，**再**过 blocks_chain_y
      // （脚本说明横幅的下移量与 y_offset 的逆）。两件事正交：zoom 属于画布，
      // note 属于脚本链。合成一步之外的任何形式都会在 zoom≠1 时系统性偏移。
      let (cx, cy) = blocks_to_chain(
        position.x - frame.origin.x,
        position.y - frame.origin.y,
        zoom,
        origin,
      )
      let lx = cx
      // 画布局部 → 链坐标：与 draw 共用 `@blk.blocks_chain_y`（单一来源）。
      let ly = @blk.blocks_chain_y(cy, y_offset, note_height)
      let hit = @blk.blocks_hit_index(
        blocks,
        lx,
        ly,
        avail_width=column,
        display_texts~,
      )
      // **存视口坐标**（`position` 就是），不是画布局部坐标：菜单要锚在
      // 指针所在的那一点上，而 `context_menu_region` 的 `Viewport` 锚点
      // 吃的是视口坐标。存局部坐标的话菜单会按画布原点的偏移弹出来，
      // 滚动或换行后位置就偏了。
      Msg::BlocksContextMenu(hit, position.x, position.y)
    })
    .on_tap_with_frame(fn(position, frame) {
      let (cx, cy) = blocks_to_chain(
        position.x - frame.origin.x,
        position.y - frame.origin.y,
        zoom,
        origin,
      )
      let lx = cx
      // 画布局部 → 链坐标：与 draw 共用 `@blk.blocks_chain_y`（单一来源）。
      let ly = @blk.blocks_chain_y(cy, y_offset, note_height)
      // **点值就地编辑**优先于整行选中：值格子（叶子段）比整行小得多，
      // 用户点在数字上就是想改那个数字。用与绘制同一份几何判定
      // （`@blk.blocks_value_hit`），保证「画在哪就点在哪」。
      let cache = metrics.val
      let measure = fn(text : String) -> Double {
        match cache.get(text) {
          Some(value) => value
          None => 0.0
        }
      }
      let base = @blk.blocks_item_rects(
        blocks,
        avail_width=column,
        display_texts~,
      )
      let visual = @blk.blocks_visual_rects(blocks, base)
      match
        @blk.blocks_value_hit(
          blocks,
          visual,
          lx,
          ly,
          measure,
          y_offset~,
          lead_texts~,
        ) {
        Some(hit) => Msg::EditBlockValue(hit.block_index, hit.expr_path)
        None =>
          // 宽度随消息带上：命中必须用与绘制同一组矩形（见 Msg 上的注释）。
          Msg::BlocksCanvasTap(lx, ly, width)
      }
    })
    .on_drag_with_frame(fn(event, frame) {
      // 同上：与 draw 共用同一个换算（zoom 逆映射 + 链坐标）。
      let (cx, cy) = blocks_to_chain(
        event.position.x - frame.origin.x,
        event.position.y - frame.origin.y,
        zoom,
        origin,
      )
      let lx = cx
      let ly = @blk.blocks_chain_y(cy, y_offset, note_height)
      // **从调色板拖进来的骨架**：画布这一侧才拿得到指针的落点。
      // 松手时按指针算出目标容器与位置，派发 DropStatement。
      // 调色板拖动期间：只有**松手**才产生消息（落点由这里算），
      // 移动过程不发消息——拖动中的高亮是调色板侧的事，画布不需要
      // 每个指针采样都过一次 update（那只是无谓的重渲）。
      // **拖到边缘自动滚动**：长链条拖拽的必需项——不自动滚就只能拖到
      // 可视区内，链尾的块永远拖不动。判据用指针在画布内的 y 位置：
      // 上缘 24pt 内向上滚、下缘 24pt 内向下滚。
      // 只在**拖动中**触发（`Changed`），松手后不再滚。
      let auto = if event.phase == @views.DragGesturePhase::Changed {
        if ly < @blk.BLOCKS_EDGE_ZONE {
          Msg::BlocksUiOp(@blk.BlocksAutoScroll(-1))
        } else if ly > height - @blk.BLOCKS_EDGE_ZONE {
          Msg::BlocksUiOp(@blk.BlocksAutoScroll(1))
        } else {
          Msg::Noop
        }
      } else {
        Msg::Noop
      }
      let _ = auto
      if expr_drag {
        // 报告块拖动：松手时按指针找**洞**（段级命中）。
        //
        // 解析放在这里而不是 update：洞的位置 = 逐段文本宽度累加，需要
        // `TextSystem`；它只在布局上下文里（`metrics` 已在布局期量好），
        // update 拿不到。与绘制读**同一份** `metrics`，才保证画哪点哪。
        if event.phase == @views.DragGesturePhase::Ended {
          let cache = metrics.val
          let measure = fn(text : String) -> Double {
            match cache.get(text) {
              Some(value) => value
              None => 0.0
            }
          }
          let base = @blk.blocks_item_rects(
            blocks,
            avail_width=column,
            display_texts~,
          )
          let visual = @blk.blocks_visual_rects(blocks, base)
          match
            @blk.blocks_slot_hit(
              blocks,
              visual,
              lx,
              ly,
              measure,
              y_offset~,
              lead_texts~,
            ) {
            Some(hit) => Msg::ExpressionDrop(hit.block_index, hit.expr_path)
            None =>
              // 没落在洞上：明确拒绝（松手毫无反应会让用户以为拖坏了）
              Msg::ExpressionDrop(-1, [])
          }
        } else {
          auto
        }
      } else if palette_drag {
        // **拖动中持续回报指针（链坐标）**：画布据此算插入线，用户全程
        // 看得见「会落在哪」——这是与目标图最大的手感差（旧实现只有松手
        // 才知道落点，拖进去是盲拖）。
        //
        // 回报 `lx/ly`（**已除回 zoom/原点**的链坐标）而不是 `event.position`
        // （视口坐标）：`blocks_pane` 算插入线时只有链坐标系可用——它拿不到
        // 画布帧原点。与 `PaletteDrop(lx, ly, ..)` 松手时同一组量，两条路径
        // 不会分叉。
        if event.phase == @views.DragGesturePhase::Changed {
          Msg::BlocksUiOp(
            @blk.PaletteDragMoved(@geometry.Point::new(x=lx, y=ly)),
          )
        } else if event.phase == @views.DragGesturePhase::Ended {
          Msg::PaletteDrop(lx, ly, width)
        } else {
          auto
        }
      } else if event.phase == @views.DragGesturePhase::Started {
        Msg::BlocksCanvasPress(lx, ly, width)
      } else if event.phase == @views.DragGesturePhase::Changed {
        // 边缘时优先滚动（否则长链拖不到头）；不在边缘才是普通拖动。
        match auto {
          Msg::BlocksUiOp(@blk.BlocksAutoScroll(_)) => auto
          _ => Msg::BlocksCanvasDragTo(lx, ly, width)
        }
      } else {
        Msg::BlocksCanvasRelease
      }
    }),
    // 画布底板**显式钉住**：这个容器此前没有 background，回落到环境 Base →
    // `palette.surface`，于是画布底与相邻的 AI 保留带完全同色（实测同为
    // `#22262C`），两段之间的边界整个消失——同一条水平结构线，左半（窗格
    // 脚注 → 带）看得见、右半（画布 → 带）看不见。`@chrome.blocks_canvas_background`
    // 因此曾经是一个零调用者的死函数，这里把它激活：积木画布与壳面板是两套
    // 配色纪律，画布底由积木域自己钉，不借邻居的回落色。
    background=@chrome.blocks_canvas_background(),
    padding=0.0,
  )
}
