///|
/// v4 IDE 的 AI 浮动层：锚点（居中/左/右/停靠）+ 药丸收起 + 线程卡 +
/// 计划卡进度 + diff 待审计 + 副作用确认 + 上下文芯片 + 输入条。
///
/// 定位方式：`align` + `offset` 在 stack 里做绝对摆放。
/// 这里不用 StageLayout（那是给「按 IR 矩形摆真控件」用的）——浮动层是
/// 单个卡片，尺寸由内容决定，所以用 stack 的「整帧」语义 + align 定位，
/// 卡片自身用显式 width 收窄。align 的 x/y 会被钳到 [-1,1]。
///
/// 保留带（ai_reserve）：浮动层压在内容上会挡住底部——底栏展开时把锚点
/// 从「贴底」抬到「贴底 + reserve」。这是纯视图补偿，不做 DOM 式测量。

// ============================================================================
// 浮动层
// ============================================================================

///|
/// 浮动卡各段高度：视图层与避让预留（ai_reserve）都从这里取，
/// 两处各写一个字面量就会出现「预留了但还是被挡住」。
pub const FOLD_BAR_HEIGHT : Double = 27.0

///|
/// 下拉芯片（VS Code 智能体模式口径）：图标 + 文案 + ChevronDown，
/// 点击走真实命令（工程 → 打开资源管理器切换上下文；模型 → 设置）。

///|
/// 输入盒高度（转发插件版;测试与布局计算共用）。
pub fn composer_height(width : Double) -> Double {
  @ai.composer_height(width)
}

///|
pub fn context_chips_height(width : Double) -> Double {
  @ai.context_chips_height(width)
}

///|
pub fn composer_block_height(width : Double) -> Double {
  @ai.composer_block_height(width)
}

///|
fn dropdown_chip(
  icon : @style.IconName,
  label : String,
  on_click : Msg,
) -> @moui.View[Msg] {
  let label_w = (@chrome.text_estimate_width(label) * 1.05 + 8.0).max(24.0)
  let chip_w = label_w + 44.0
  @views.container(
    @views.center(
      @views.row(
        [
          @views.icon(icon, size=11.0, color=@chrome.ide_text_muted()),
          @views.text(
            label,
            theme=@chrome.studio_theme(),
            width=label_w,
            height=16.0,
          ).foreground(@chrome.ide_text_muted()),
          @views.icon(ChevronDown, size=10.0, color=@chrome.ide_text_faint()),
        ],
        spacing=4.0,
        align=Center,
      ).frame(width=chip_w - 16.0),
      width=chip_w,
      height=22.0,
    ),
    background=@chrome.ide_panel_alt(),
    corner_radius=11.0,
    width=chip_w,
    height=22.0,
    padding=0.0,
  ).on_tap(on_click)
}

///|
/// 上下文芯片行（VS Code 口径）：工程下拉芯片 + 模型下拉芯片。
fn context_chips_row(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let cells : Array[@moui.View[Msg]] = []
  let project_label = match active_project_of(model) {
    Some(record) => @chrome.fit_label(record.module_name, 160.0)
    None => text(t, "app.ai.group.default_project")
  }
  // 工程 → 打开资源管理器（切换工程上下文的既有通道）
  cells.push(dropdown_chip(FolderOpen, project_label, SetLeftView(LeftProject)))
  let model_label = if !model.ai_available {
    text(t, "app.ai.unavailable")
  } else if model.provider_key == "" {
    text(t, "app.ai.disconnected")
  } else {
    @chrome.fit_label(model.provider_model, 160.0)
  }
  cells.push(
    dropdown_chip(Gear, model_label, StudioCommandRun("studio.settings")),
  )
  // 外层容器必须显式给底色：无背景 container 在 paint 期回落到环境
  // Base 刷子（实测抓到的 ambient 回落缺陷），与输入盒同色读作一块。
  @views.container(
    @chrome.fill_row(cells, width, 6.0, Start),
    background=@chrome.ide_panel(),
    width~,
    height=@ai.CHIPS_HEIGHT,
    padding=0.0,
  )
}

///|
/// 提示头条：「提示: 」+ 着色关键词 + 其余；整行可点 = 打开提案历史
/// （给着色词真实行为,不做死链接）。带 @chrome.hairline 下边与输入区分隔。

///|
/// 信息芯片：小圆角读数。`on_click` 为 None = 纯信息展示（不可点）。
fn info_chip(
  label : String,
  background : @graphics.Color,
  foreground : @core.Color,
  on_click : Msg?,
) -> @moui.View[Msg] {
  let chip_w = (@chrome.text_estimate_width(label) * 1.05 + 16.0).max(36.0)
  let chip = @views.container(
    @views.center(
      @views.text(
        label,
        theme=@chrome.studio_theme(),
        width=(chip_w - 12.0).max(20.0),
        height=16.0,
      ).foreground(foreground),
      width=chip_w,
      height=20.0,
    ),
    background~,
    corner_radius=10.0,
    width=chip_w,
    height=20.0,
    padding=0.0,
  )
  match on_click {
    Some(msg) => chip.on_tap(msg)
    None => chip
  }
}

///|
/// composer 的四周留白（VS Code 智能体模式口径）：输入面浮在中心区里,
/// 与左右缘、底部各留一圈,不顶满。中心态两个分支共用（底栏/停靠宿主不套,
/// 面板内的输入面仍贴边）。
fn ai_composer_framed(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let side = 16.0
  @views.padding_edges(
    composer(model, t, (width - side * 2.0).max(280.0)),
    left=side,
    right=side,
    bottom=8.0,
  )
}

///|
/// AI 模式的中心工作区（对白转录）：
/// **空会话** = composer 垂直居中于大画布（「Pitch your idea」形态）；
/// **有内容** = 会话头 + 全幅对白时间线（滚动）+ composer 钉底。
///
/// 中心与右栏 AI 页（`ai_page`）**共用 `ai_conversation`**：同一份转录构建器、
/// 同一套「回到底部 / 查看全部会话」出口，两个宿主只在**内衬与输入面外壳**
/// 上不同（中心是浮起卡片，右栏是钉底卡）。两处各写一份转录，气泡样式与
/// 折叠组行为就会漂移——本仓为此付过代价（两处各算一份高度）。
pub fn ai_center(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let cards = model.ai_sessions.current().cards
  if cards.length() == 0 {
    // 空会话：视觉居中（50/50）——上下**等重加权 spacer**。列必须显式
    // `.frame(height=height)`：ContainerBox 会把「量出来比容器矮」的子节点
    // 垂直居中（布局陷阱①）,加权 spacer 在测量期只报 min_length,不钉高度
    // 列就会缩成内容高、整体偏下（真机实测缺陷）。钉死高度后 spacer 才
    // 拿得到 slack,列恰好铺满。
    @views.container(
      @views.column(
        [
          @views.spacer(min_length=0.0, weight=1.0),
          ai_composer_framed(model, t, width),
          @views.spacer(min_length=4.0, weight=1.0),
          ai_posture_row(model, t, width),
        ],
        spacing=0.0,
      ).frame(height~),
      background=@chrome.ide_editor_background(),
      width~,
      height~,
      padding=0.0,
    )
  } else {
    // 有内容：共用 `ai_conversation`（会话头 + 时间线 + 回到底部 + 查看全部），
    // 中心态只在它后面接**浮起**的输入面与姿态读数。转录细则因此与右栏 AI 页
    // 逐字同源——两处各写一份必然漂移（本仓的复发缺陷族）。
    let transcript_h = (height -
    AI_SESSION_HEADER_HEIGHT -
    composer_block_height(width) -
    (if model.transcript_follow { 0.0 } else { 26.0 }) -
    POSTURE_HEIGHT).max(120.0)
    @views.container(
      @views.column(
        ai_conversation(model, t, width, transcript_h) +
        [ai_composer_framed(model, t, width), ai_posture_row(model, t, width)],
        spacing=0.0,
      ),
      background=@chrome.ide_editor_background(),
      width~,
      height~,
      padding=0.0,
    )
  }
}

///|
/// 会话头：标题（截断）+ 置顶切换 + 删除当前会话。
///
/// **底色必须显式**：无背景 container 在 paint 期回落到环境 Base 刷子
/// （`palette.surface`）——右栏 AI 页上就是标题行比面板更暗一档，读作
/// 「另起一个区块」。AI 页与 PsAi 中心都铺 `ide_panel()`，所以这里也钉它。
fn ai_session_header(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let session = model.ai_sessions.current()
  let index = model.ai_sessions.active_index()
  let title = @chrome.fit_label(session.title, (width - 200.0).max(60.0))
  let title_w = (@chrome.text_estimate_width(title) * 1.02 + 8.0)
    .min(width - 200.0)
    .max(40.0)
  let pin_label = if session.pinned {
    text(t, "app.ai.unpin")
  } else {
    text(t, "app.ai.pin")
  }
  @views.container(
    @chrome.fill_row(
      [
        @views.text(
          title,
          theme=@chrome.studio_theme(),
          width=title_w,
          height=18.0,
          align=TextStart,
        ).foreground(@chrome.ide_text()),
        @views.spacer(min_length=6.0, weight=1.0),
        @chrome.action_chip(
          pin_label,
          AiSessionOp(AiSessionPin(index, !session.pinned)),
          @chrome.Ghost,
          22.0,
        ),
        @chrome.action_chip(
          text(t, "app.ai.session.delete"),
          AiSessionOp(AiSessionRemove(index)),
          @chrome.Ghost,
          22.0,
        ),
      ],
      width,
      6.0,
      Center,
    ),
    background=@chrome.ide_panel(),
    width~,
    height=AI_SESSION_HEADER_HEIGHT,
    padding=0.0,
  )
}

///|
/// 「回到底部」芯片行：非自动跟随态才渲染（跟随态 0 高不占位）。
/// 右对齐——与滚动位置语义一致（按钮把视口送回底部）。
fn ai_scroll_to_bottom_row(
  t : @i18n.Translator,
  width : Double,
  row_h : Double,
) -> @moui.View[Msg] {
  if row_h <= 0.0 {
    return @views.container(
      @views.text("", width=1.0, height=1.0),
      width~,
      height=0.0,
      padding=0.0,
    )
  }
  @views.container(
    @chrome.fill_row(
      [
        @views.spacer(min_length=0.0, weight=1.0),
        @chrome.action_chip(
          text(t, "app.ai.scroll_bottom"),
          TranscriptScrollToBottom,
          @chrome.Quiet,
          20.0,
        ),
      ],
      width,
      6.0,
      Center,
    ),
    width~,
    height=row_h,
    padding=0.0,
  )
}

///|
/// 全幅对白时间线（滚动）：用户气泡 / AI 消息 / 工作卡折叠组按序渲染。
/// 受控滚动 + 自动贴底与终端同一套机制（offset 回写 + ScrollRequest 钳底）。
///
/// **底色必须显式**：无背景 container 在 paint 期回落到环境 Base 刷子
/// （`palette.surface`，暗色下 0.121 而面板是 0.169）——右栏 AI 页上就是
/// 一整块比面板更暗的方格，「转录区」与「面板」被读成两块不同质感的区域。
/// 本仓的 `ai_bar_layout_wbtest` 有一条按颜色精确比对的回归专门抓这个回落
/// （它原本只扫钉底带，这轮把扫描范围扩到整个右栏正文——转录现在也在里面）。
///
/// **行必须按 `inner` 构建，不是按 `width`**：`padding_edges` 把滚动区收到
/// `width − 24`，列也钉在同一个 `inner` 上。早先这里把 `width`（外宽）传给
/// `timeline_rows`，于是每行都比自己的裁剪区宽 24pt、被 flex 居中——整条转录
/// 右移 12pt，长行文本因此**越过裁剪区右缘被切掉**（短行看不出，长代码行才
/// 明显，用户报的「右侧文字看不到」就是它）。宽与裁剪区必须同源。
fn ai_transcript(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let inner = (width - 24.0).max(120.0)
  let rows = timeline_rows(model, t, inner)
  @views.container(
    @views.padding_edges(
      @views.scroll_view(
        @views.column(rows, spacing=8.0).frame(width=inner),
        offset=model.transcript_scroll,
        on_scroll=Some(offset => TranscriptScrolled(offset)),
        request=@core.ScrollRequest::new(
          id=model.transcript_scroll_seq,
          offset=model.transcript_scroll,
        ),
        width~,
        height~,
        shows_indicator=true,
      ),
      left=12.0,
      right=12.0,
      top=4.0,
      bottom=4.0,
    ),
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 时间线行构建：连续的 Agent 工作卡（计划/diff/副作用）归入一组折叠区
/// （「已工作 N / 待审计 N」），用户气泡、AI 消息与错误卡独立成行。

///|
fn see_all_row(t : @i18n.Translator, width : Double) -> @moui.View[Msg] {
  @ai.see_all_row(t, width, on_toggle=ToggleAiHistory)
}

///|
fn timeline_rows(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> Array[@moui.View[Msg]] {
  let cards = model.ai_sessions.current().cards
  let rows : Array[@moui.View[Msg]] = []
  let mut group : Array[AiCard] = []
  let mut index = 0
  for card in cards {
    let is_work = card.kind is CardPlan ||
      card.kind is CardDiff ||
      card.kind is CardSideEffect
    if is_work {
      group.push(card)
    } else {
      if group.length() > 0 {
        rows.push(work_group_row(model, t, group, width))
        group = []
      }
      match card.kind {
        CardUserPrompt => rows.push(user_bubble_row(t, card, width))
        CardExplanation => rows.push(ai_message_row(model, t, card, width))
        _ => rows.push(ai_card_view(model, t, card, index, width - 24.0))
      }
    }
    index = index + 1
  }
  if group.length() > 0 {
    rows.push(work_group_row(model, t, group, width))
  }
  rows
}

///|
/// 「已工作」折叠组：连续工作卡的可见记录。有未处理卡显示「待审计 N」
/// （警告色），否则显示工作时长（≥1 秒）或中性「Agent 线程」。
fn work_group_row(
  model : Model,
  t : @i18n.Translator,
  group : Array[AiCard],
  width : Double,
) -> @moui.View[Msg] {
  let inner = (width - 24.0).max(120.0)
  let mut pending = 0
  for card in group {
    if !card.settled && (card.kind is CardDiff || card.kind is CardSideEffect) {
      pending = pending + 1
    }
  }
  let duration = (group[group.length() - 1].at - group[0].at).max(0)
  let label = if pending > 0 {
    text_with(t, "app.ai.fold_pending", [("count", pending.to_string())])
  } else if duration >= 1 {
    let minutes = duration / 60
    let seconds = duration % 60
    text_with(t, "app.ai.work.trace", [
      (
        "duration",
        text_with(t, "app.ai.work.duration", [
          ("m", minutes.to_string()),
          ("s", seconds.to_string()),
        ]),
      ),
    ])
  } else {
    text(t, "app.ai.fold_idle")
  }
  let body : Array[@moui.View[Msg]] = [
    work_group_bar(model, label, inner, pending > 0),
  ]
  if !model.ai_cards_folded {
    let mut card_index = 0
    for card in group {
      body.push(ai_card_view(model, t, card, card_index, inner))
      card_index = card_index + 1
    }
  }
  @views.container(
    @views.column(body, spacing=4.0).frame(width=inner),
    width~,
    padding=0.0,
  )
}

///|
/// 折叠组头：chevron + 标签（待审计 = 警告色），点击折叠/展开。
fn work_group_bar(
  model : Model,
  label : String,
  width : Double,
  has_pending : Bool,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_xy(
      @views.row(
        [
          @views.icon(
            if model.ai_cards_folded {
              ChevronRight
            } else {
              ChevronDown
            },
            size=12.0,
            color=@chrome.ide_text_muted(),
          ),
          @views.text(
            label,
            theme=@chrome.studio_theme(),
            width=(width - 60.0).max(60.0),
            height=16.0,
            align=TextStart,
          ).foreground(
            if has_pending {
              @chrome.ide_warning()
            } else {
              @chrome.ide_text_faint()
            },
          ),
        ],
        spacing=4.0,
        align=Center,
      ),
      horizontal=8.0,
      vertical=0.0,
    ),
    height=22.0,
    width~,
    padding=0.0,
  ).on_tap(ToggleAiCardsFold)
}

///|
/// 用户提问气泡（右对齐，强调色淡底）：宽度按内容估宽钳在 70% 行宽内，
/// 长 prompt 贪心折行；动作行 = 复制 / 编辑（回填草稿）+ HH:MM。
fn user_bubble_row(
  t : @i18n.Translator,
  card : AiCard,
  width : Double,
) -> @moui.View[Msg] {
  let inner = (width - 24.0).max(120.0)
  let max_w = (inner * 0.7).max(160.0)
  let est = (@chrome.text_estimate_width(card.body) + 20.0).min(max_w)
  let lines = @chrome.wrap_text_lines(card.body, est - 16.0)
  let line_h = 18.0
  let bubble_w = est
  let bubble_h = lines.length().to_double() * line_h + 16.0
  let lines_view : Array[@moui.View[Msg]] = []
  for line in lines {
    lines_view.push(
      @views.text(
        line,
        theme=@chrome.studio_theme(),
        width=bubble_w - 16.0,
        height=line_h,
        align=TextStart,
      ).foreground(@chrome.ide_text()),
    )
  }
  let bubble = @views.container(
    @views.column(lines_view, spacing=0.0).frame(width=bubble_w - 16.0),
    background=@chrome.ide_selection(),
    corner_radius=10.0,
    width=bubble_w,
    height=bubble_h,
    padding=8.0,
  )
  @views.container(
    @views.column(
      [
        @chrome.fill_row(
          [@views.spacer(min_length=0.0, weight=1.0), bubble],
          inner,
          0.0,
          Center,
        ),
        message_actions_row(card, inner, [
          @chrome.action_chip(
            text(t, "app.ai.action.copy"),
            CopyAiMessage(card.seq),
            @chrome.Ghost,
            18.0,
          ),
          @chrome.action_chip(
            text(t, "app.ai.action.edit"),
            EditUserPrompt(card.seq),
            @chrome.Ghost,
            18.0,
          ),
        ]),
      ],
      spacing=2.0,
    ).frame(width=inner),
    width~,
    padding=0.0,
  )
}

///|
/// AI 消息行（左对齐，无底色）：markdown 渲染 + 动作行（复制 / 重发）。
/// 重发 = 该轮用户提问回填并重跑（单一 ComposerRun 通道）。
fn ai_message_row(
  model : Model,
  t : @i18n.Translator,
  card : AiCard,
  width : Double,
) -> @moui.View[Msg] {
  ignore(model)
  let inner = (width - 24.0).max(120.0)
  let blocks = @markdown.parse_markdown(card.body)
  @views.container(
    @views.column(
      [
        markdown_blocks_view(blocks, inner),
        message_actions_row(card, inner, [
          @chrome.action_chip(
            text(t, "app.ai.action.copy"),
            CopyAiMessage(card.seq),
            @chrome.Ghost,
            18.0,
          ),
          @chrome.action_chip(
            text(t, "app.ai.action.retry"),
            RetryUserPrompt(card.seq),
            @chrome.Ghost,
            18.0,
          ),
        ]),
      ],
      spacing=4.0,
    ).frame(width=inner),
    width~,
    padding=0.0,
  )
}

///|
/// 消息动作行：动作芯片 + HH:MM 时间戳（mono、淡色）。
fn message_actions_row(
  card : AiCard,
  width : Double,
  chips : Array[@moui.View[Msg]],
) -> @moui.View[Msg] {
  let cells : Array[@moui.View[Msg]] = []
  for chip in chips {
    cells.push(chip)
  }
  cells.push(
    @views.text(
      hhmm_of_stamp(card.at),
      theme=@chrome.studio_theme(),
      role=Mono,
      width=44.0,
      height=14.0,
    ).foreground(@chrome.ide_text_faint()),
  )
  @views.container(
    @chrome.fill_row(cells, width, 4.0, Start),
    width~,
    height=20.0,
    padding=0.0,
  )
}

///|
/// 右栏钉底块的内衬：输入卡与面板边缘之间的呼吸缝（左右）。
///
/// 停靠块的宽度由右栏决定、高度由内容决定，所以内衬是**预算的一部分**
/// （`ai_docked_height` 要计入它），视图层再用 `padding` 把它留出来。
/// 两处同源，钉底块才不会裁掉自己的内容。
pub const AI_CARD_PAD : Double = 8.0

///|
/// 钉底块外衬的**上下**档（左右走 `AI_CARD_PAD`）。
///
/// 高度预算必须逐段对齐视图——上下内衬与左右不同值时，共用一个常量就会
/// 少算一段（本仓反复踩的双算账）。这里是那个上下值。
pub const AI_DOCK_PAD_V : Double = 6.0

///|
/// 输入卡**自己**的内衬（上下）：卡内内容与卡框之间的呼吸缝。
///
/// 卡片化新增的一段账：卡是带描边的抬起面，内容不再直接贴面板边，所以
/// 这份内衬必须进 `ai_docked_height`——漏算它就是「卡片裁掉自己的最后一行」
/// （实测：漏这 12pt 时状态行被顶出面板）。
pub const AI_CARD_INSET : Double = 6.0

///|
/// 卡内行距（芯片行 → 输入块 → 决策条）。
pub const AI_CARD_ROW_GAP : Double = 2.0

///|
/// 输入卡与卡下状态行之间的间距。
pub const AI_DOCK_GAP : Double = 2.0

///|
/// 上下文芯片高（右栏钉底口径）——VS Code 侧栏输入盒上方那行「＋ ≡ <上下文>」。
pub const AI_SUBJECT_CHIP_HEIGHT : Double = 22.0

///|
/// 钉底块高度上限：决策条的校验错误列表再长，也不把转录区吃穿。
/// 被截断的原因在审计日志里同样可见（`validate_program` 的结论不只一个出口）。
///
/// **夹取的是「决策条那一项」，不是整个钉底块**——这条区分是本轮实测修出来的：
/// 早先对 `natural` 整体取 `min`，于是「输入卡 + 状态行」的固定部分**也会被
/// 削掉**。待审计卡在场上时 `natural` = 224 而上限 220，被削掉的正是**最底下
/// 那条状态行**（它掉到面板底边之下，读起来像「UI 没画完」）。固定部分
/// （外衬 + 卡内衬 + 芯片 + 输入块 + 状态行）必须**无条件全额**，只有可变的
/// 决策条才受上限约束。
const AI_DECISION_MAX_HEIGHT : Double = 220.0

///|
/// 决策条的实际足迹：`decision_bar` 的容器高是 `decision_bar_height + 12`
/// （上下各 6pt 内衬）。预算必须逐段对齐视图——少算这 12pt，钉底块就会裁掉
/// 自己的决策条（本仓反复踩的双算账）。
fn decision_bar_footprint(model : Model) -> Double {
  if has_decision_content(model) {
    decision_bar_height(model) + 12.0
  } else {
    0.0
  }
}

///|
/// 右栏 AI 页钉底块高度（唯一来源）：外衬 + **输入卡**（卡内衬 + 上下文芯片
/// + composer 块 + 决策条）+ 卡下状态行。
///
/// 视图层（`ide_right_panel` 的 AI 页）与测试断言都从这里取；两处各算一份，
/// 输入卡就会被顶出右栏。逐段与 `ai_docked_block` 对齐——每一段都走上面那个
/// 具名常量，改一处不会漏另一处。
///
/// **固定段全额 + 决策条封顶**：输入卡与状态行是「永远在场」的骨架，任何情况
/// 下都要画全；决策条（摘要 + 采纳/拒绝 + 校验错误清单）才是会长的那一段，
/// 它吃 `AI_DECISION_MAX_HEIGHT` 的封顶。整体夹取会把状态行挤掉——见
/// `AI_DECISION_MAX_HEIGHT` 的注释。
///
/// 分页后它**只服务 AI 页**：检查器页没有钉底块，所以「检查器正文被 composer
/// 吃掉一块」的旧形态随分页消失；这条预算现在保护的是**转录区**。
pub fn ai_docked_height(model : Model, width : Double) -> Double {
  let fixed = AI_DOCK_PAD_V * 2.0 +
    AI_CARD_INSET * 2.0 +
    AI_SUBJECT_CHIP_HEIGHT +
    AI_CARD_ROW_GAP * 2.0 +
    composer_block_height(width) +
    AI_DOCK_GAP +
    POSTURE_HEIGHT
  // 决策条只吃「总额封顶里剩下的那一份」——骨架先占，剩下的才是它的。
  let decision_room = (AI_DECISION_MAX_HEIGHT - fixed).max(0.0)
  fixed + decision_bar_footprint(model).min(decision_room)
}

///|
/// 右栏 AI 页钉底块：**圆角描边输入卡**（上下文芯片 + composer + 决策条）
/// + 卡下状态行。
///
/// 卡片化是这一轮的形态决定（VS Code 侧栏聊天页口径：输入区是一张浮在面板
/// 上的圆角卡，而不是与面板融为一体的通栏）。三处细节都是刻意的：
///
/// 1. **上下文芯片进卡内**（不再悬在卡上方）——「AI 会针对谁」属于这次输入，
///    与输入框是同一张卡的两行，不是面板级信息。
/// 2. **卡底用 `ide_elevated()`，不用 `palette.surface`**。后者是「无背景
///    container 的 paint 期回落色」，钉底带内出现它正是 `ai_bar_layout_wbtest`
///    那条回归要抓的缺陷形态（回落色漏进右栏 → 露一块异色）。抬起的卡片色
///    在两种主题下都不等于 surface，语义与断言同时成立。
/// 3. **状态行在卡外**（`ai_posture_row`）——它是「这轮对话处于什么闸门状态」
///    的面板级读数，不是输入的一部分；放卡外也不会让卡片高度随待审计数跳变。
pub fn ai_docked_block(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let card_w = (width - AI_CARD_PAD * 2.0).max(80.0)
  let card = @views.container(
    @views.padding_edges(
      @views.column(
        [
          ai_subject_chip(model, t, (card_w - 16.0).max(60.0)),
          composer(model, t, card_w),
          decision_bar(model, t, card_w),
        ],
        spacing=AI_CARD_ROW_GAP,
      ).frame(width=card_w),
      left=8.0,
      right=8.0,
      top=AI_CARD_INSET,
      bottom=AI_CARD_INSET,
    ),
    // 抬起面 + 1pt 描边 + 8pt 圆角：卡与面板之间由「面色差 + 描边」两条
    // 线索共同界定（只靠面色差在亮色主题下几乎读不出来）。
    background=@chrome.ide_elevated(),
    border=Some(
      @graphics.BorderStyle::new(
        brush=@graphics.Brush::solid(@chrome.ide_border()),
        width=1.0,
      ),
    ),
    corner_radius=8.0,
    width=card_w,
    padding=0.0,
  )
  @views.container(
    @views.padding_edges(
      @views.column(
        [card, ai_posture_row(model, t, width)],
        spacing=AI_DOCK_GAP,
      ).frame(width~),
      left=AI_CARD_PAD,
      right=AI_CARD_PAD,
      top=AI_DOCK_PAD_V,
      bottom=AI_DOCK_PAD_V,
    ),
    // 底色必须显式：无背景 container 在 paint 期回落到环境 Base 刷子，
    // 与面板不同色就在钉底边界上露一条脏边。
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 上下文芯片（VS Code 侧栏口径）：当前选中对象 = 「AI 会针对谁」。
///
/// 纯信息、不可点——不出死按钮。没有选中对象时**如实**说「未选中对象」，
/// 不静默显示上一个对象（与面板头同一口径）。
fn ai_subject_chip(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let (name, kind) = side_subject_of(model, t)
  let none = name == text(t, "app.ctx.none")
  let tint = if none {
    @chrome.ide_text_faint()
  } else {
    @chrome.ide_text_muted()
  }
  let label_w = (width - 44.0).max(40.0)
  let label = if kind == "" {
    @chrome.fit_label(name, label_w)
  } else {
    @chrome.fit_label("\{name} · \{kind}", label_w)
  }
  @views.container(
    @views.center(
      @views.row(
        [
          @views.icon(Focus, size=11.0, color=tint),
          @views.text(
            label,
            theme=@chrome.studio_theme(),
            role=Caption,
            width=label_w,
            height=14.0,
            align=TextStart,
          ).foreground(tint),
        ],
        spacing=4.0,
        align=Center,
      ).frame(width=(width - 16.0).max(60.0)),
      width~,
      height=AI_SUBJECT_CHIP_HEIGHT,
    ),
    background=@chrome.ide_panel_alt(),
    corner_radius=11.0,
    width~,
    height=AI_SUBJECT_CHIP_HEIGHT,
    padding=0.0,
  )
}

///|
/// AI 页会话区（右栏 `RvAi` 与 PsAi 中心共用）：会话头 + 转录（滚动）+
/// 「回到底部」行 + 「查看全部会话 →」出口，**以行数组返回**。
///
/// 返回行而不是整列：两个宿主的**后续内容不同**（中心接浮起输入面 + 姿态行，
/// 右栏接钉底卡；且中心那列要有背景色、右栏没有），由调用方 `column(...)`
/// 拼装。共用的只有**内容**；输入面的外壳两处不同（中心是浮起卡片
/// `ai_composer_framed`，右栏是钉底卡 `ai_docked_block`），所以 composer
/// 不进这个函数。
///
/// **为什么必须共用**：转录（气泡 / 卡片 / 折叠组的样式与行为）是一整套细则，
/// 两个宿主各写一份必然漂移——本仓已有「两处各算一份高度」的复发缺陷族。
fn ai_conversation(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  transcript_h : Double,
) -> Array[@moui.View[Msg]] {
  let builder : Array[@moui.View[Msg]] = [
    ai_session_header(model, t, width),
    ai_transcript(model, t, width, transcript_h),
  ]
  let follow_h = if model.transcript_follow { 0.0 } else { 26.0 }
  builder.push(ai_scroll_to_bottom_row(t, width, follow_h))
  // 线程超过 3 条时给「查看全部会话 →」（跳既有 AI 历史对话框）。放转录
  // **之后**：它是转录的尾部出口，不是面板级动作。
  //
  // **折叠态不出**：卡组收起时转录内容已经不在场，再留一个「查看全部会话」
  // 会让「收起」读起来没生效（卡数没变、出口却还在）。
  if model.ai_sessions.current().cards.length() > 3 && !model.ai_cards_folded {
    builder.push(see_all_row(t, (width - 16.0).max(80.0)))
  }
  builder
}

///|
/// 右栏 AI 页（`RvAi`）：会话转录 + 钉底输入卡。
///
/// 与 PsAi 中心的差别是刻意的：**空会话也照常钉底**（不垂直居中）——右栏是
/// 常驻面板，输入面的位置不该随会话有没有内容上下跳；空会话在转录区显示
/// 一行弱化提示（`ai_transcript` 对空列表自然会给出空白区，这里补一句引导）。
///
/// 高度预算：`height - AI_SESSION_HEADER_HEIGHT - follow_h - ai_docked_height`。
/// 全部定尺、正文吃剩余——列不钉高会被 `ContainerBox` 垂直居中。
pub fn ai_page(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let docked_h = ai_docked_height(model, width)
  let follow_h = if model.transcript_follow { 0.0 } else { 26.0 }
  let transcript_h = (height - AI_SESSION_HEADER_HEIGHT - follow_h - docked_h).max(
    100.0,
  )
  @views.container(
    @views.column(
      ai_conversation(model, t, width, transcript_h) +
      [@chrome.hairline(), ai_docked_block(model, t, width, docked_h)],
      spacing=0.0,
    ).frame(width~, height~),
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
fn ai_card_view(
  model : Model,
  t : @i18n.Translator,
  card : AiCard,
  index : Int,
  width : Double,
) -> @moui.View[Msg] {
  let accent = match card.kind {
    CardUserPrompt => @chrome.ide_accent()
    CardPlan => @chrome.ide_accent()
    CardDiff => @chrome.ide_success()
    CardSideEffect => @chrome.ide_warning()
    CardExplanation => @chrome.ide_text_muted()
    CardError => @chrome.ide_danger()
  }
  // 标题行：标题按内容截断 + 可选的「已处理」徽标。
  //
  // **标题必须自己截断，且徽标宽必须进宽度账**：`@views.text` 的宽是最小值
  // （布局取 `max(声明宽, 实测宽)`），所以一段长标题会自己长宽、把右缘的徽标
  // **推出裁剪区**——用户实测看到的就是「已处」被切掉半个词。早先这里写死
  // 「预留 70pt」，而「已处理」徽标实测约 40pt、最长标题却可以任意长，两头都
  // 不成立。现在：徽标宽按内容算，标题宽 = 行宽 − 徽标宽 − 间距，再 `fit_label`。
  let settled_badge = if card.settled {
    @chrome.count_badge(text(t, "app.ai.settled"), 1)
  } else {
    @views.text("", width=1.0, height=1.0)
  }
  let badge_w = if card.settled {
    (@chrome.text_estimate_width(text(t, "app.ai.settled")) * 1.02 + 12.0).max(
      24.0,
    )
  } else {
    1.0
  }
  let title_w = (width - badge_w - 6.0).max(60.0)
  let rows : Array[@moui.View[Msg]] = [
    @chrome.fill_row(
      [
        @views.text(
          @chrome.fit_label(text(t, card.title), title_w),
          theme=@chrome.studio_theme(),
          width=title_w,
          height=18.0,
          align=TextStart,
        ).foreground(@chrome.ide_text()),
        settled_badge,
      ],
      width,
      4.0,
      Center,
    ),
  ]
  if card.body != "" {
    // M4：讲解/流式卡的 body 走 markdown 块渲染（子集 + 诚实降级）；
    // 其余卡保持单行摘要文本
    if card.kind is CardExplanation {
      rows.push(
        markdown_blocks_view(@markdown.parse_markdown(card.body), width),
      )
    } else {
      rows.push(
        @views.text(
          card.body,
          theme=@chrome.studio_theme(),
          width=(width - 16.0).max(60.0),
          height=18.0,
          align=TextStart,
        ).foreground(@chrome.ide_text_muted()),
      )
    }
  }
  // 计划卡：进度条 + 步骤清单
  if card.kind is CardPlan {
    rows.push(@chrome.progress_bar(card.progress, width - 16.0))
    let mut step_index = 0
    for step in card.steps {
      let done = step_index < card.steps_done
      rows.push(
        @views.text(
          (if done { "✓ " } else { "○ " }) + step,
          theme=@chrome.studio_theme(),
          width=(width - 16.0).max(60.0),
          height=16.0,
          align=TextStart,
        ).foreground(
          if done {
            @chrome.ide_success()
          } else {
            @chrome.ide_text_faint()
          },
        ),
      )
      step_index = step_index + 1
    }
  }
  // diff 卡：逐行 ±
  for line in card.diff_lines {
    rows.push(@chrome.diff_row(line.0, line.1, width))
  }
  // 副作用卡 / diff 卡：待审计时给采纳/拒绝。
  // 芯片严格 22 高——线程区预算按内容行算，36pt 的 @views.button 会撑爆。
  if !card.settled && (card.kind is CardDiff || card.kind is CardSideEffect) {
    rows.push(
      @views.row(
        [
          @chrome.action_chip(
            text(t, "app.ai.accept"),
            AcceptProposal,
            @chrome.Primary,
            22.0,
          ),
          @chrome.action_chip(
            text(t, "app.ai.reject"),
            RejectProposal,
            @chrome.Quiet,
            22.0,
          ),
          @views.text(
            "\{index + 1}",
            theme=@chrome.studio_theme(),
            role=Mono,
            width=20.0,
            height=16.0,
          ).foreground(@chrome.ide_text_faint()),
        ],
        spacing=6.0,
        align=Center,
      ),
    )
  } else if card.settled && card.settled_note != "" {
    rows.push(
      @views.text(
        text(t, card.settled_note),
        theme=@chrome.studio_theme(),
        width=(width - 16.0).max(60.0),
        height=16.0,
        align=TextStart,
      ).foreground(@chrome.ide_success()),
    )
  }
  ignore(model)
  @chrome.inline_card(
    accent,
    @views.column(rows, spacing=4.0),
    width,
    card.settled,
  )
}

///|
/// 输入条：单行 = 模式段 | 输入框 | 发送（成熟 AI 面板口径——旧版
/// 工具行 + 输入行 + 按钮行三层 chrome 占 ~100pt，且工具行与头部图标
/// 功能完全重复）。窄卡（放不下一行）折两行：输入独占一行。
/// 手搓模式段与发送而不用 @views.button：button 的 `width`/`height` 进的
/// 是 `min_size`，文字比声明的宽就会自己长大顶出卡片。

///|
fn composer(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  // AI 不可用（Web 入口）：显式降级——引导面板替换整个输入面，不出
  // 「点了必失败」的假按钮。高度预算与正常 composer 同源，宿主不塌陷。
  if !model.ai_available {
    let total = composer_height(width) + context_chips_height(width)
    let box_width = (width - 16.0).max(120.0)
    return @views.container(
      @views.center(
        @views.text(
          text(t, "app.ai.unavailable"),
          theme=@chrome.studio_theme(),
          width=(box_width - 24.0).max(80.0),
          height=16.0,
        ).foreground(@chrome.ide_text_muted()),
        width=box_width,
        height=composer_height(width),
      ),
      background=@chrome.ide_panel(),
      width=box_width,
      height=total,
      padding=0.0,
    )
  }
  // 脚注左端：模式选择（VS Code 的 Agent ⌄ 口径）。收起 = 单个「当前模式 ⌄」
  // 下拉芯片；展开 = 原位切回四选一胶囊行（SetComposerMode 后收起）——
  // 不引入浮层，88 预算内原位切换。
  let mode_cells : Array[@moui.View[Msg]] = if model.composer_mode_picker_open {
    [
      composer_mode_chip(model, t, ComposeEdit, "app.ai.mode.edit"),
      composer_mode_chip(model, t, ComposeGenerate, "app.ai.mode.generate"),
      composer_mode_chip(model, t, ComposeExplain, "app.ai.mode.explain"),
      composer_mode_chip(model, t, ComposeRepair, "app.ai.mode.repair"),
      composer_mode_chip(model, t, ComposeChat, "app.ai.mode.chat"),
    ]
  } else {
    [composer_mode_dropdown(model, t)]
  }
  // 输入盒（VS Code 智能体模式口径）：提示头条（空会话中心态）+ **两行**
  // 无边框文本域（Enter 直接发送）+ 盒内脚注（模式/模型靠左，ghost 与
  // 圆形发送靠右）。
  let box_width = (width - 16.0).max(120.0)
  let inner_width = box_width - 16.0
  let busy = model.ai_busy
  let send_msg = if busy { Msg::Noop } else { ComposerRun }
  // 盒内脚注的 ghost 操作：**只有一个宿主**（右栏钉底），所以脚注不再放
  // 「停靠右栏 / 放到底栏」这一对互为出口的切换钮——没有第二个落点可去，
  // 放一对就是死 UI。历史/provider 设置走命令面板（⌘K）与这里各一个入口。
  let ghost_surface = @chrome.ide_panel()
  let foot_cells : Array[@moui.View[Msg]] = [
    @views.row(mode_cells, spacing=3.0, align=Center),
    @views.spacer(min_length=6.0, weight=1.0),
  ]
  if inner_width >= 300.0 {
    foot_cells.push(
      ghost_icon_button(
        Clipboard,
        text(t, "app.ai.history"),
        false,
        ToggleAiHistory,
        22.0,
        20.0,
        11.0,
        ghost_surface,
        hovered=model.hover_hint,
      ),
    )
  }
  // 模型 chip（VS Code 的 ⚡模型 口径）：provider 读数，点击开设置。
  // 无推理档/上下文数据——不虚构「极高 · 1.1M」式读数。
  if inner_width >= 300.0 {
    let model_label = if !model.ai_available {
      text(t, "app.ai.unavailable")
    } else if model.provider_key == "" {
      text(t, "app.ai.disconnected")
    } else {
      @chrome.fit_label(model.provider_model, 140.0)
    }
    foot_cells.push(
      info_chip(
        model_label,
        @chrome.ide_panel(),
        @chrome.ide_text_muted(),
        Some(StudioCommandRun("studio.settings")),
      ),
    )
  }
  // 发送钮在模式行右端（**只有一个**——输入行内再放一个是实测的双钮缺陷）。
  // 流式生成进行中：发送换**停止**（截断入口，M4）——同一槽位两个互斥动作。
  if model.ai_streaming {
    foot_cells.push(
      @chrome.action_chip(
        text(t, "app.ai.stop"),
        StopGeneration,
        @chrome.Quiet,
        24.0,
      ),
    )
  } else {
    foot_cells.push(
      round_send_button(text(t, "app.ai.send"), send_msg, !busy, 24.0),
    )
  }
  // 实测反馈第四轮：**输入在上，模式胶囊 + 发送在下**；输入域可见
  // **两行**（text_area 内部有 8pt×2 垂直内垫——lines=3 才可见两整行，
  // 见 @ai.COMPOSER_HEIGHT 的注释）；整体扁平无阴影。
  // 输入域**直接作为列子项**（包定高容器或塞 row 都会让它不渲染，
  // text_area 的高度语义只在列布局下可靠，两轮实测确认）。
  let foot = @chrome.fill_row(foot_cells, inner_width, 6.0, Center)
  let field = @views.text_area(
    model.ai_sessions.current().prompt_draft,
    on_input=value => SetPrompt(value),
    placeholder=text(t, "app.ai.prompt"),
    lines=3,
    variant=Plain,
    width=inner_width,
    line_height=20.0,
    on_submit=Some(send_msg),
  )
  let box = @views.container(
    @views.padding_edges(
      @views.column([field, foot], spacing=2.0),
      left=8.0,
      right=8.0,
      top=2.0,
      bottom=3.0,
    ),
    background=@chrome.ide_panel(),
    // 中心态（AI 模式大画布）圆角浮起 + 1px 描边；右栏/底栏嵌入宿主
    // 维持扁平无描边（「与面板融为一体」的实测口径只适用于嵌入面板）。
    corner_radius=if model.perspective is PsAi { 10.0 } else { 0.0 },
    border=if model.perspective is PsAi {
      Some(@core.BorderStyle::{
        brush: @core.Brush::Solid(@chrome.ide_border()),
        width: 1.0,
      })
    } else {
      None
    },
    width=box_width,
    height=composer_height(width),
    padding=0.0,
  )
  // 信息层芯片行在输入盒**上方**（宽卡才显示）——块高走
  // composer_block_height，调用方的高度预算与这里同源。
  let chips_h = context_chips_height(width)
  if chips_h > 0.0 {
    @views.column([context_chips_row(model, t, box_width), box], spacing=2.0).frame(
      width=box_width,
      height=composer_height(width) + chips_h,
    )
  } else {
    box
  }
}

///|
/// 模式下拉芯片（收起态）：「当前模式 ⌄」——VS Code 的 Agent ⌄ 口径。
/// 点击展开 = 脚注原位切回四选一胶囊行（ToggleComposerModePicker）。
fn composer_mode_dropdown(
  model : Model,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let label = match model.composer_mode {
    ComposeEdit => text(t, "app.ai.mode.edit")
    ComposeGenerate => text(t, "app.ai.mode.generate")
    ComposeExplain => text(t, "app.ai.mode.explain")
    ComposeRepair => text(t, "app.ai.mode.repair")
    ComposeChat => text(t, "app.ai.mode.chat")
  }
  let label_w = (@chrome.text_estimate_width(label) * 1.05 + 8.0).max(30.0)
  let chip_w = label_w + 26.0
  let open = model.composer_mode_picker_open
  @views.container(
    @views.center(
      @views.row(
        [
          @views.text(
            label,
            theme=@chrome.studio_theme(),
            width=label_w,
            height=16.0,
          ).foreground(
            if open {
              @chrome.ide_accent()
            } else {
              @chrome.ide_text_muted()
            },
          ),
          @views.icon(ChevronDown, size=10.0, color=@chrome.ide_text_muted()),
        ],
        spacing=3.0,
        align=Center,
      ).frame(width=chip_w - 12.0),
      width=chip_w,
      height=20.0,
    ),
    background=if open { @chrome.ide_selection() } else { @chrome.ide_panel() },
    corner_radius=10.0,
    width=chip_w,
    height=20.0,
    padding=0.0,
  ).on_tap(ToggleComposerModePicker)
}

///|
/// 姿态读数行高（对白转录 V5：空态常驻,VS Code 的 Autopilot 行语义替换）。
pub const POSTURE_HEIGHT : Double = 20.0

///|
/// 姿态读数（闸门哲学常驻可见）：无未处理卡 = 「闸门 · 逐条采纳」弱读数；
/// 有卡 = 「待审计 N」警告色（pending_ai_cards）。右侧不放工作树/分支。
///
/// **底色必须显式**：无背景 container 在 paint 期回落到环境 Base 刷子
/// （`palette.surface`）——右栏 AI 页上就是状态行比面板更暗一档，读作一块
/// 异色带（本仓的 ambient 回落缺陷族；`ai_bar_layout_wbtest` 按颜色精确比对
/// 抓它）。中心态与右栏态都铺 `ide_panel()`，所以这里钉同一色。
fn ai_posture_row(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let pending = pending_ai_cards(model)
  let label = if pending > 0 {
    text_with(t, "app.ai.pending_chip", [("count", pending.to_string())])
  } else {
    text(t, "app.ai.posture.gate")
  }
  @views.container(
    @views.padding_edges(
      @chrome.fill_row(
        [
          @views.text(
            label,
            theme=@chrome.studio_theme(),
            width=(@chrome.text_estimate_width(label) + 4.0).max(40.0),
            height=14.0,
            align=TextStart,
          ).foreground(
            if pending > 0 {
              @chrome.ide_warning()
            } else {
              @chrome.ide_text_faint()
            },
          ),
          @views.spacer(min_length=6.0, weight=1.0),
        ],
        width,
        4.0,
        Start,
      ),
      left=8.0,
      right=8.0,
    ),
    background=@chrome.ide_panel(),
    width~,
    height=POSTURE_HEIGHT,
    padding=0.0,
  )
}

///|
/// composer 模式芯片宽：文案实测 × 1.05 + 两侧内垫 14，下限 36。
/// 段宽合计（composer）与芯片自身宽必须走同一函数——两处各算一份，
/// 输入框的剩余宽就会算错。
fn composer_chip_width(label : String) -> Double {
  (@chrome.text_estimate_width(label) * 1.05 + 14.0).max(36.0)
}

///|
/// 模式芯片：手搓（理由同 composer），选中态用强调色 + 底色区分。
fn composer_mode_chip(
  model : Model,
  t : @i18n.Translator,
  mode : ComposerMode,
  key : String,
) -> @moui.View[Msg] {
  let selected = model.composer_mode == mode
  let label = text(t, key)
  let chip_width = composer_chip_width(label)
  @views.container(
    @views.center(
      @views.text(
        label,
        theme=@chrome.studio_theme(),
        width=(chip_width - 14.0).max(20.0),
        height=16.0,
      ).foreground(
        if selected {
          @chrome.ide_accent()
        } else {
          @chrome.ide_text_muted()
        },
      ),
      width=chip_width,
      height=20.0,
    ),
    background=if selected {
      @chrome.ide_selection()
    } else {
      @chrome.ide_panel()
    },
    corner_radius=10.0,
    width=chip_width,
    height=20.0,
    padding=0.0,
  ).on_tap(SetComposerMode(mode))
}

///|
/// 决策条是否该在场：只有真内容（待采纳提案 / 讲解 / 错误）才渲染——
/// 旧版空闲态常驻一行「待命 | 提案历史」，是纯占位噪音（历史入口已在
/// 卡片头部，忙碌态由发送芯片表态）。
fn has_decision_content(model : Model) -> Bool {
  model.pending is Some(_) ||
  model.explanation != "" ||
  model.prompt_error != ""
}

///|
/// 决策条：待采纳提案摘要 + 采纳/拒绝；无提案时显示讲解/错误文本。
fn decision_bar(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  if !has_decision_content(model) {
    return @views.container(
      @views.text("", width=1.0, height=1.0),
      width~,
      height=0.0,
      padding=0.0,
    )
  }
  let rows : Array[@moui.View[Msg]] = []
  match model.pending {
    Some(pending) => {
      rows.push(
        @views.text(
          pending.summary,
          theme=@chrome.studio_theme(),
          width=(width - 16.0).max(60.0),
          height=18.0,
          align=TextStart,
        ).foreground(
          if pending.valid {
            @chrome.ide_success()
          } else {
            @chrome.ide_danger()
          },
        ),
      )
      // 校验失败时逐条列出原因（不静默丢弃，也不允许采纳）。
      // 错误文案是长句（英文 400pt+），按行宽截断——决策条高度是单点预算，
      // 折行会把预算撑爆。
      if !pending.valid {
        for error in pending.errors {
          rows.push(
            @views.text(
              @chrome.fit_label("· \{error}", (width - 24.0).max(60.0)),
              theme=@chrome.studio_theme(),
              width=(width - 16.0).max(60.0),
              height=16.0,
              align=TextStart,
            ).foreground(@chrome.ide_danger()),
          )
        }
      }
      rows.push(
        @chrome.fill_row(
          [
            @chrome.action_chip(
              text(t, "app.ai.accept"),
              AcceptProposal,
              @chrome.Primary,
              24.0,
            ),
            @chrome.action_chip(
              text(t, "app.ai.reject"),
              RejectProposal,
              @chrome.Quiet,
              24.0,
            ),
            @chrome.action_chip(
              text(t, "app.ai.history"),
              ToggleAiHistory,
              @chrome.Ghost,
              24.0,
            ),
          ],
          (width - 16.0).max(80.0),
          6.0,
          Center,
        ),
      )
    }
    None => {
      if model.explanation != "" {
        rows.push(
          @views.text(
            model.explanation,
            theme=@chrome.studio_theme(),
            width=(width - 16.0).max(60.0),
            height=54.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_muted()),
        )
      }
      if model.prompt_error != "" {
        rows.push(
          @views.text(
            model.prompt_error,
            theme=@chrome.studio_theme(),
            width=(width - 16.0).max(60.0),
            height=16.0,
            align=TextStart,
          ).foreground(@chrome.ide_danger()),
        )
      }
    }
  }
  @views.container(
    @views.padding_xy(
      @views.column(rows, spacing=4.0).frame(
        width=(width - 16.0).max(80.0),
        height=decision_bar_height(model),
      ),
      horizontal=8.0,
      vertical=6.0,
    ),
    background=@chrome.ide_panel(),
    width~,
    height=decision_bar_height(model) + 12.0,
    padding=0.0,
  )
}

///|
/// 决策条内容高：有提案时是「摘要 + 采纳/拒绝/历史」两行，否则是
/// 「空闲/忙碌」一行加可选的讲解与错误行。
/// 视图层与 `decision_bar_footprint`（钉底块预算）共用这一个来源——两处各写
/// 一份，避让预留就会和实际遮挡对不上。
pub fn decision_bar_height(model : Model) -> Double {
  if !has_decision_content(model) {
    return 0.0
  }
  match model.pending {
    // 两个 24pt 芯片行（采纳/拒绝/历史）。芯片严格等高，预算才准。
    Some(_) => 24.0 + 4.0 + 24.0
    None => {
      let mut height = 0.0
      if model.explanation != "" {
        height = height + 4.0 + 54.0
      }
      if model.prompt_error != "" {
        height = height + 4.0 + 16.0
      }
      height
    }
  }
}

// ============================================================================
// 药丸
// ============================================================================
