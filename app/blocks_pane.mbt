///|
/// 积木窗格：分类轨 + 积木画布（选中块处就地展开编辑卡）。
///
/// 从 `workspace.mbt` 拆出来（该文件已到 1200 行硬上限）：积木窗格与代码
/// 窗格是两条独立的展示路径，按「窗格」拆文件比按「视图/辅助」拆更贴近
/// 阅读顺序。

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
/// 分类条点分类滚动到该类首块（选中分类记忆在 model.selected_category）。
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
        hovered=model.hover_hint,
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
        hovered=model.hover_hint,
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
  let hat_row = onstart_hat_row(model, t, width)
  let catbar = category_rail(model, t, body_height)
  // 语句插入面板：分类轨点开时，在轨与画布之间插一列骨架卡片（240pt）。
  // 宽度必须从 canvas_width **扣**：画布是自适应测量节点，让它先占满再把
  // 面板塞进去，面板会被挤到窗格外。顺序不能反（先算宽度、再建画布）。
  let palette_open = model.statement_palette_open &&
    model.selected_category >= 0 &&
    category_at(model.selected_category) is Some(_)
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
      let mark = @blk.blocks_insert_mark(blocks, rects, model.block_drag)
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
      let canvas_height = (rects.length().to_double() * BLOCK_ROW_HEIGHT +
        24.0 +
        note_height)
        .max(body_height)
        .max(120.0)
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
          canvas_width,
          canvas_height,
          text(t, "app.blocks.canvas"),
          palette_drag=model.palette_drag is Some(_),
          expr_drag=model.expr_drag is Some(_),
          script_note~,
          note_height~,
          lead_texts~,
        ),
        width=canvas_width,
        height=body_height,
        // **受控滚动**：偏移来自模型，拖到边缘时由 `BlocksAutoScroll`
        // 推进。不受控的话自动滚动无处落笔（滚动位置是控件内部状态，
        // update 层看不到也改不了）。
        offset=@core.Point::new(x=0.0, y=model.blocks_scroll_y),
        // 手动滚动要回报，否则下一次重渲会把用户滚到的位置弹回模型值。
        on_scroll=Some(offset => BlocksScrolled(offset.y)),
        shows_indicator=true,
      )
    }
  }
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
      [head, hat_row, declaration_strip(model, width), body],
      spacing=0.0,
    ).frame(width~, height~),
    background=@chrome.ide_editor_background(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 积木画布可用高度：头 + 画布（编辑卡嵌在链条里，不再占窗格高度）。
pub fn blocks_body_height(model : Model, height : Double) -> Double {
  let _ = model
  (height - @chrome.PANEL_HEAD_HEIGHT - 2.0).max(80.0)
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
      model.selected_category < 0,
      SelectBlockCategory(-1),
    ),
  ]
  let mut index = 0
  for entry in entries {
    let selected = model.selected_category == index
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
        ToggleStatementPalette(index),
      ),
    )
    index = index + 1
  }
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
/// 语句插入面板：分类轨旁边拉出的一列骨架卡片。
///
/// 它是「没有 AI 也能写程序」的入口——选中一条骨架即插入到当前块之后。
/// 分类为空（事件分类：事件头由控件决定，不能凭空插入）时给一行明确说明，
/// 而不是留一片空白。
pub fn statement_palette_panel(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let category = category_at(model.selected_category)
  let templates = match category {
    None => ([] : Array[StatementTemplate])
    Some(category) => templates_for_category(category)
  }
  let rows : Array[@moui.View[Msg]] = [
    @views.padding_xy(
      @views.text(
        @chrome.fit_label(statement_palette_title(t), width - 28.0),
        theme=@chrome.studio_theme(),
        width=(width - 24.0).max(60.0),
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
  if category is Some(@blocks.CatVariable) {
    rows.push(
      @views.container(
        @views.padding_xy(
          @views.text(
            @chrome.fit_label(text(t, "app.variable.new"), width - 24.0),
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
      .on_tap(AddVariable)
      .accessibility_label(text(t, "app.variable.new")),
    )
  }
  // **报告块**（运算分类）：这些是**表达式**，只作为洞里的内容。
  //
  // 与语句骨架分开渲染的理由：报告块不能「插一行」（`1 + 1` 单独成句在
  // 语言里非法），所以它们没有点击插入，只有拖拽——面板上给出这条提示，
  // 否则用户点了没反应会以为坏了。
  if category is Some(@blocks.CatExpression) {
    rows.push(
      @views.padding_xy(
        @chrome.hint_lines_view(
          text(t, "app.expr.palette.hint"),
          width - 24.0,
          @chrome.ide_text_faint(),
          2,
        ),
        horizontal=8.0,
        vertical=0.0,
      ),
    )
    let mut expr_index = 0
    for template in expression_templates() {
      let label = text(t, template.label_key)
      rows.push(
        @views.container(
          @views.padding_xy(
            @views.text(
              @chrome.fit_label(label, width - 24.0),
              theme=@chrome.studio_theme(),
              width=(width - 20.0).max(60.0),
              height=18.0,
              align=TextStart,
            ).foreground(@chrome.ide_text()),
            horizontal=8.0,
            vertical=0.0,
          ),
          background=@chrome.ide_panel_alt(),
          corner_radius=4.0,
          width=(width - 12.0).max(60.0),
          height=28.0,
          padding=0.0,
        )
        // 只可拖，不可点：表达式不能单独成句。拖动时记下模板下标，
        // 落点（哪个洞）由画布侧按指针算。
        .on_drag(_event => PaletteExprDragStart(expr_index))
        .accessibility_label(label),
      )
      expr_index = expr_index + 1
    }
  }
  if templates.length() == 0 {
    rows.push(
      @views.padding_xy(
        @chrome.hint_lines_view(
          text(t, "app.stmt.palette.empty"),
          width - 24.0,
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
      let label = text(t, template.label_key)
      rows.push(
        @views.container(
          @views.padding_xy(
            @views.text(
              @chrome.fit_label(label, width - 24.0),
              theme=@chrome.studio_theme(),
              width=(width - 20.0).max(60.0),
              height=18.0,
              align=TextStart,
            ).foreground(@chrome.ide_text()),
            horizontal=8.0,
            vertical=0.0,
          ),
          background=@chrome.ide_panel_alt(),
          corner_radius=4.0,
          width=(width - 12.0).max(60.0),
          height=28.0,
          padding=0.0,
        )
        .on_tap(InsertStatement(model.selected_category, index))
        // 拖动 = 从调色板拖到画布（Scratch 的字面手势）。这里只记下
        // 「拖动源」，落点由画布侧按指针算——两个视图互相看不到对方的帧。
        .on_drag(_event => PaletteDragStart(model.selected_category, index))
        .accessibility_label(label),
      )
      index = index + 1
    }
    rows.push(
      @views.padding_xy(
        @chrome.hint_lines_view(
          text(t, "app.stmt.palette.hint"),
          width - 24.0,
          @chrome.ide_text_faint(),
          2,
        ),
        horizontal=8.0,
        vertical=0.0,
      ),
    )
  }
  @views.container(
    @views.column(rows, spacing=6.0).frame(width~, height~),
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 分类轨宽度（设计稿 `#catbar` 86pt）。
pub const CATEGORY_RAIL_WIDTH : Double = 86.0

///|
/// 语句插入面板的最小宽度（保证骨架标签不被截成一个字）。
pub const STATEMENT_PALETTE_MIN_WIDTH : Double = 132.0

///|
/// 积木画布的最小宽度。低于这个值块内文字必然被裁，不如让面板更窄。
pub const CANVAS_MIN_WIDTH : Double = 120.0

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
/// 积木右键菜单（Scratch/IDE 口径）。
///
/// 动作全部复用**既有消息**——`DuplicateBlock` / `DeleteBlock` 已经是右栏
/// 编辑卡上的按钮载体，这里只是把同一批动作搬到指针处。**不新开执行路径**：
/// 菜单是「同一动作的第二个入口」，不是第二套语义。
///
/// 每一项都先发 `BlocksContextMenuClose`（见各行的 `on_tap` 串联）——
/// 点完不关菜单，用户会以为没生效。
pub fn block_context_menu(
  model : Model,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let has_block = model.selected_block >= 0
  let rows : Array[@moui.View[Msg]] = []
  if has_block {
    // 「运行这一块」放最前：Scratch 里点击积木的直接动作就是运行。
    rows.push(
      menu_action_row(
        text(t, "app.run.single"),
        @chrome.ide_success(),
        RunSingleBlock,
        true,
      ),
    )
    rows.push(
      menu_action_row(
        text(t, "app.block.duplicate"),
        @chrome.ide_text(),
        DuplicateBlock,
        true,
      ),
    )
    rows.push(
      menu_action_row(
        text(t, "app.block.delete"),
        @chrome.ide_danger(),
        DeleteBlock,
        true,
      ),
    )
  } else {
    // 点空白处：给画布级动作（至少要有可插入语句的入口，否则菜单是空的）
    rows.push(
      menu_action_row(
        text(t, "app.blocks.rail.hint"),
        @chrome.ide_text_muted(),
        ToggleStatementPalette(model.selected_category),
        true,
      ),
    )
  }
  @views.container(
    @views.column(rows, spacing=0.0),
    background=@chrome.ide_panel_alt(),
    corner_radius=6.0,
    width=168.0,
    padding=0.0,
  )
}

///|
/// 菜单行：文字 + 点击派发。动作后**先关菜单**再执行——菜单留着会挡住
/// 结果（删除后菜单还悬在那里，用户以为没删掉）。
fn menu_action_row(
  label : String,
  color : @core.Color,
  action : Msg,
  enabled : Bool,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_xy(
      @views.text(
        @chrome.fit_label(label, 140.0),
        theme=@chrome.studio_theme(),
        width=140.0,
        height=18.0,
        align=TextStart,
      ).foreground(if enabled { color } else { @chrome.ide_text_faint() }),
      horizontal=12.0,
      vertical=0.0,
    ),
    height=28.0,
    width=168.0,
    padding=0.0,
  ).on_tap(
    // 禁用项也要能点（关掉菜单），所以包一层而不是挂 Noop。
    if enabled {
      BlocksMenuAction(action)
    } else {
      BlocksContextMenuClose
    },
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
/// 启动 hat 行（G7.1.1）：积木视图顶部的窗体级脚本入口。
/// 显示一个「⚡ 启动」胶囊——有 OnStart handler 时高亮并可切换到它，
/// 没有时点击即创建（无需在设计器选中控件）。用户由此可以在积木
/// 视图里直接写纯逻辑程序，不需要依赖设计器的任何控件。
fn onstart_hat_row(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let exists = @ir.find_handler(model.program, "", @ir.OnStart) is Some(_)
  let is_active = model.selected_handler == handler_key("", @ir.OnStart.tag())
  let label = text(t, "app.blocks.hat.onstart")
  let chip_width = @chrome.text_estimate_width(label) + 32.0
  @views.container(
    @views.row(
      [
        @views.container(
          @views.row(
            [
              @views.text(
                "⚡",
                theme=@chrome.studio_theme(),
                width=16.0,
                height=18.0,
                align=TextCenter,
              ).foreground(
                if is_active {
                  @chrome.ide_text()
                } else {
                  @chrome.ide_text_faint()
                },
              ),
              @views.text(
                label,
                theme=@chrome.studio_theme(),
                width=chip_width - 36.0,
                height=18.0,
                align=TextStart,
              ).foreground(
                if is_active {
                  @chrome.ide_text()
                } else {
                  @chrome.ide_text_faint()
                },
              ),
            ],
            spacing=4.0,
            align=Center,
          ),
          background=if is_active {
            @chrome.ide_selection()
          } else {
            @chrome.ide_panel()
          },
          width=chip_width,
          height=24.0,
          padding=0.0,
        ).on_tap(
          if exists {
            SelectHandler(handler_key("", @ir.OnStart.tag()))
          } else {
            CreateHandler("", @ir.OnStart)
          },
        ),
      ],
      spacing=0.0,
      align=Start,
    ),
    width~,
    height=28.0,
    padding=0.0,
  )
}

///|
/// 画布视图：绘制 + 点选/拖拽事件转 typed Msg。
/// `y_offset`：本段画布在**链条坐标**里的纵向原点。编辑卡把链条拆成
/// 上下两段后，下段画布的本地 y 要加上偏移才能与 update 里的链条矩形
/// （命中/落槽计算空间）对齐；整链画布传 0 即可。
pub fn blocks_canvas(
  blocks : Array[@blocks.BlockItem],
  display_texts : Array[String],
  selected : Int,
  spotlight : String,
  insert_mark : (Double, Double, Bool)?,
  width : Double,
  height : Double,
  semantics_label : String,
  y_offset? : Double = 0.0,
  palette_drag? : Bool = false,
  expr_drag? : Bool = false,
  script_note? : String = "",
  note_height? : Double = 0.0,
  lead_texts? : Array[String] = [],
) -> @moui.View[Msg] {
  // 文本度量：**布局期**量好、**绘制期**取用。
  //
  // 为什么必须跨这两个阶段：插槽洞的位置 = 前面所有段的宽度之和，而
  // 段宽只有 `TextSystem` 能给；`TextSystem` 挂在**布局上下文**上，
  // 绘制回调拿到的 `PaintContext` 刻意只装绘制指令（框架设计如此），
  // 量不了文本。所以用一格共享单元把结果从布局带到绘制——这也是
  // `measured_canvas` 存在的理由。
  let metrics : Ref[Map[String, Double]] = Ref(Map([]))
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
        let dx = frame.origin.x
        // 有说明横幅时，积木链整体**下移** `note_height`，让横幅占住
        // 上方预留的空间（而不是叠在第一块积木上）。
        // 链坐标 → 画布局部：减去横幅偏移（`@blk.blocks_chain_y` 的逆）。
        let dy = frame.origin.y + note_height
        let base = @blk.blocks_item_rects(
          blocks,
          avail_width=width,
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
        )
        // **脚本说明横幅**：画在积木链上方（Scratch 的脚本注释贴在积木旁）。
        // 只在有说明时占位——空说明不画，否则每条子程序上方都会有一条
        // 空白带，把画布本来就不多的空间吃掉。
        // `note_height` 是调用方为横幅**预留**的高度：积木链整体下移，
        // 横幅画在空出来的上方。不用「画在积木上」的做法——那会遮住第一块
        // 积木的文本。调用方（`blocks_pane`）把同一数值加进画布高度，
        // 两处一致才不会让横幅被裁掉或与积木重叠。
        if script_note != "" {
          ops.push(
            ScriptNote(
              @chrome.fit_label(script_note, (width - 24.0).max(60.0)),
              dx + 10.0,
              dy + 2.0,
              (width - 24.0).max(60.0),
            ),
          )
        }
        for op in ops {
          match op {
            BlockOutline(x, y, w, h, kind, tab, notch) =>
              // 单轮廓（M7②）：一次 fill+stroke，榫卯在轮廓里
              @blk.paint_block_outline(ctx, x, y, w, h, kind, tab, notch)
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
            BlockStroke(x, y, w, h) =>
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
      },
      semantics_label~,
    )
    // 右键：命中测试与左键同一套几何（含真实 avail_width），把链下标
    // 交给 update 开菜单。**与左键共用 `@blk.blocks_hit_index`**——两处各算一份
    // 命中就会「点得中但右键点不中」。
    .on_secondary_tap_with_frame(fn(position, frame) {
      let lx = position.x - frame.origin.x
      // 画布局部 → 链坐标：与 draw 共用 `@blk.blocks_chain_y`（单一来源）。
      let ly = @blk.blocks_chain_y(
        position.y - frame.origin.y,
        y_offset,
        note_height,
      )
      let hit = @blk.blocks_hit_index(
        blocks,
        lx,
        ly,
        avail_width=width,
        display_texts~,
      )
      // **存视口坐标**（`position` 就是），不是画布局部坐标：菜单要锚在
      // 指针所在的那一点上，而 `context_menu_region` 的 `Viewport` 锚点
      // 吃的是视口坐标。存局部坐标的话菜单会按画布原点的偏移弹出来，
      // 滚动或换行后位置就偏了。
      Msg::BlocksContextMenu(hit, position.x, position.y)
    })
    .on_tap_with_frame(fn(position, frame) {
      let lx = position.x - frame.origin.x
      // 画布局部 → 链坐标：与 draw 共用 `@blk.blocks_chain_y`（单一来源）。
      let ly = @blk.blocks_chain_y(
        position.y - frame.origin.y,
        y_offset,
        note_height,
      )
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
        avail_width=width,
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
      let lx = event.position.x - frame.origin.x
      // 同上：与 draw 共用同一个换算。
      let ly = @blk.blocks_chain_y(
        event.position.y - frame.origin.y,
        y_offset,
        note_height,
      )
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
          Msg::BlocksAutoScroll(-1)
        } else if ly > height - @blk.BLOCKS_EDGE_ZONE {
          Msg::BlocksAutoScroll(1)
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
            avail_width=width,
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
        if event.phase == @views.DragGesturePhase::Ended {
          Msg::PaletteDrop(lx, ly, width)
        } else {
          auto
        }
      } else if event.phase == @views.DragGesturePhase::Started {
        Msg::BlocksCanvasPress(lx, ly, width)
      } else if event.phase == @views.DragGesturePhase::Changed {
        // 边缘时优先滚动（否则长链拖不到头）；不在边缘才是普通拖动。
        match auto {
          Msg::BlocksAutoScroll(_) => auto
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
