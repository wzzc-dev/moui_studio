///|
/// AI 浮动层 / 右栏 AI 页纯视图（S4b 出壳）：锚点 + 药丸收起 + 线程卡 +
/// 计划卡 + diff 待审计 + 副作用确认 + 上下文芯片 + 输入条 + 决策条。
///
/// 纯视图：不读壳 Model，状态走 `AiViewParams[Msg]`，动作走 on_* 回调；
/// 跨域读数（当前工程名 / 选中对象 / 待审计卡数）由壳投影后注入。
///
/// 定位方式：`align` + `offset` 在 stack 里做绝对摆放（卡片尺寸由内容
/// 决定，用 stack「整帧」语义 + align，不用 StageLayout）。

// ============================================================================
// 各段高度常量（视图与避让预算同源，避免两处各写字面量）
// ============================================================================

pub const FOLD_BAR_HEIGHT : Double = 27.0

///|
pub const AI_CARD_PAD : Double = 8.0

///|
pub const AI_DOCK_PAD_V : Double = 6.0

///|
pub const AI_CARD_INSET : Double = 6.0

///|
pub const AI_CARD_ROW_GAP : Double = 2.0

///|
pub const AI_DOCK_GAP : Double = 2.0

///|
pub const AI_SUBJECT_CHIP_HEIGHT : Double = 22.0

///|
pub const POSTURE_HEIGHT : Double = 20.0

///|
const AI_DECISION_MAX_HEIGHT : Double = 220.0

///|
/// AI 视图参数：壳把 AI 域状态与跨域读数投影进来，动作经回调回壳。
pub(all) struct AiViewParams[Msg] {
  sessions : AiSessions
  available : Bool
  busy : Bool
  streaming : Bool
  cards_folded : Bool
  /// 中心态（PsAi）：输入卡圆角浮起；嵌入态扁平。
  center_perspective : Bool
  composer_mode : ComposerMode
  picker_open : Bool
  provider_model : String
  provider_key : String
  /// 模型候选清单（composer 下拉列它；空 = 只有当前模型一项）。
  provider_models : Array[String]
  /// composer 模型下拉是否展开。
  model_picker_open : Bool
  /// 计划卡的积木计数（None = 不显示芯片）。由壳在提案 apply 后从
  /// `block_chain` 行数投影。
  plan_block_count : Int?
  explanation : String
  prompt_error : String
  pending : PendingProposal?
  transcript_follow : Bool
  transcript_scroll : @geometry.Point
  transcript_scroll_seq : Int
  /// 当前工程名（None = 默认工程标签）。
  project_name : String?
  /// 上下文芯片选中对象读数（name / kind；name 可能为「未选中对象」）。
  subject_name : String
  subject_kind : String
  // 动作回调
  on_noop : Msg
  on_set_prompt : (String) -> Msg
  on_run : Msg
  on_stop : Msg
  on_set_mode : (ComposerMode) -> Msg
  on_toggle_picker : Msg
  /// 模型下拉：开合 + 选一个（`on_select_model` 收模型名，壳映射成
  /// `AiUiOp(SetProviderModel(..))`）。
  on_toggle_model_picker : Msg
  on_select_model : (String) -> Msg
  on_toggle_history : Msg
  on_accept : Msg
  on_reject : Msg
  on_copy : (Int) -> Msg
  /// 块级复制（代码块的复制钮）：(卡 seq, 块下标)。
  on_copy_code : (Int, Int) -> Msg
  on_edit : (Int) -> Msg
  on_retry : (Int) -> Msg
  on_scroll : (@geometry.Point) -> Msg
  on_scroll_bottom : Msg
  on_toggle_fold : Msg
  on_pin : (Int, Bool) -> Msg
  on_remove : (Int) -> Msg
  on_open_project : Msg
  on_settings : Msg
  /// 幽灵图标按钮（历史入口）：壳用 ghost_icon_button 构造（要发 HoverHint）。
  ghost_icon : (@style.IconName, String, Msg) -> @moui.View[Msg]
}

///|
/// 待审计卡数（diff / 副作用未处理）。
fn[Msg] pending_ai_cards(p : AiViewParams[Msg]) -> Int {
  let mut count = 0
  for card in p.sessions.current().cards {
    if !card.settled && (card.kind is CardDiff || card.kind is CardSideEffect) {
      count = count + 1
    }
  }
  count
}

///|
/// HH:MM 时间戳（按 UTC 秒；与壳 clock 同口径）。
fn hhmm_of_stamp(at : Int) -> String {
  let in_day = (at % 86400 + 86400) % 86400
  let hour = in_day / 3600
  let minute = in_day % 3600 / 60
  let hh = if hour < 10 { "0\{hour}" } else { "\{hour}" }
  let mm = if minute < 10 { "0\{minute}" } else { "\{minute}" }
  "\{hh}:\{mm}"
}

///|
/// 圆形发送按钮（壳无 @core 依赖面，就地画）。
fn[Msg] round_send_button(
  tip : String,
  on_click : Msg,
  enabled : Bool,
  size : Double,
) -> @moui.View[Msg] {
  @views.container(
    @views.center(
      @views.icon(
        ArrowRight,
        size=(size - 12.0).max(10.0),
        color=if enabled {
          @chrome.studio_theme().palette.on_primary
        } else {
          @chrome.ide_text_faint()
        },
      ),
      width=size,
      height=size,
    ),
    background=if enabled {
      @chrome.ide_accent()
    } else {
      @chrome.ide_elevated()
    },
    corner_radius=size / 2.0,
    width=size,
    height=size,
    padding=0.0,
  )
  .accessibility_label(tip)
  .on_tap(on_click)
}

///|
/// 下拉芯片（VS Code 智能体模式口径）：图标 + 文案 + ChevronDown。
fn[Msg] dropdown_chip(
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
/// 上下文芯片行：工程下拉芯片 + 模型下拉芯片。
fn[Msg] context_chips_row(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let cells : Array[@moui.View[Msg]] = []
  let project_label = match p.project_name {
    Some(name) => @chrome.fit_label(name, 160.0)
    None => t.translate("app.ai.group.default_project")
  }
  cells.push(dropdown_chip(FolderOpen, project_label, p.on_open_project))
  let model_label = if !p.available {
    t.translate("app.ai.unavailable")
  } else if p.provider_key == "" {
    t.translate("app.ai.disconnected")
  } else {
    @chrome.fit_label(p.provider_model, 160.0)
  }
  cells.push(dropdown_chip(Gear, model_label, p.on_settings))
  @views.container(
    @chrome.fill_row(cells, width, 6.0, Start),
    background=@chrome.ide_panel(),
    width~,
    height=CHIPS_HEIGHT,
    padding=0.0,
  )
}

///|
/// composer 四周留白（中心态两个分支共用）。
fn[Msg] ai_composer_framed(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let side = 16.0
  @views.padding_edges(
    composer(p, t, (width - side * 2.0).max(280.0)),
    left=side,
    right=side,
    bottom=8.0,
  )
}

///|
/// AI 中心工作区（对白转录）：空会话 composer 居中；有内容会话头 + 时间线
/// （滚动）+ composer 钉底。
pub fn[Msg] ai_center(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let cards = p.sessions.current().cards
  if cards.length() == 0 {
    @views.container(
      @views.column(
        [
          @views.spacer(min_length=0.0, weight=1.0),
          ai_composer_framed(p, t, width),
          @views.spacer(min_length=4.0, weight=1.0),
          ai_posture_row(p, t, width),
        ],
        spacing=0.0,
      ).frame(height~),
      background=@chrome.ide_editor_background(),
      width~,
      height~,
      padding=0.0,
    )
  } else {
    let transcript_h = (height -
    AI_SESSION_HEADER_HEIGHT -
    composer_block_height(width, picker_open=p.model_picker_open) -
    (if p.transcript_follow { 0.0 } else { 26.0 }) -
    POSTURE_HEIGHT).max(120.0)
    @views.container(
      @views.column(
        ai_conversation(p, t, width, transcript_h) +
        [ai_composer_framed(p, t, width), ai_posture_row(p, t, width)],
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
fn[Msg] ai_session_header(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let session = p.sessions.current()
  let index = p.sessions.active_index()
  let title = @chrome.fit_label(session.title, (width - 200.0).max(60.0))
  let pin_label = if session.pinned {
    t.translate("app.ai.unpin")
  } else {
    t.translate("app.ai.pin")
  }
  @views.container(
    @chrome.fill_row(
      [
        @views.text(
          title,
          theme=@chrome.studio_theme(),
          width=(@chrome.text_estimate_width(title) * 1.02 + 8.0)
            .min(width - 200.0)
            .max(40.0),
          height=18.0,
          align=TextStart,
        ).foreground(@chrome.ide_text()),
        @views.spacer(min_length=6.0, weight=1.0),
        @chrome.action_chip(
          pin_label,
          (p.on_pin)(index, !session.pinned),
          @chrome.Ghost,
          22.0,
        ),
        @chrome.action_chip(
          t.translate("app.ai.session.delete"),
          (p.on_remove)(index),
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
/// 「回到底部」芯片行：非自动跟随态才渲染。
fn[Msg] ai_scroll_to_bottom_row(
  p : AiViewParams[Msg],
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
          t.translate("app.ai.scroll_bottom"),
          p.on_scroll_bottom,
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
/// 全幅对白时间线（滚动）：受控滚动 + 自动贴底。
fn[Msg] ai_transcript(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let inner = (width - 24.0).max(120.0)
  let rows = timeline_rows(p, t, inner)
  @views.container(
    @views.padding_edges(
      @views.scroll_view(
        @views.column(rows, spacing=8.0).frame(width=inner),
        offset=p.transcript_scroll,
        on_scroll=Some(offset => (p.on_scroll)(offset)),
        request=@core.ScrollRequest::new(
          id=p.transcript_scroll_seq,
          offset=p.transcript_scroll,
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
/// 时间线行构建：连续 Agent 工作卡归组，用户气泡 / AI 消息 / 错误卡独立成行。
fn[Msg] timeline_rows(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> Array[@moui.View[Msg]] {
  let cards = p.sessions.current().cards
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
        rows.push(work_group_row(p, t, group, width))
        group = []
      }
      match card.kind {
        CardUserPrompt => rows.push(user_bubble_row(p, t, card, width))
        CardExplanation => rows.push(ai_message_row(p, t, card, width))
        _ => rows.push(ai_card_view(p, t, card, index, width - 24.0))
      }
    }
    index = index + 1
  }
  if group.length() > 0 {
    rows.push(work_group_row(p, t, group, width))
  }
  rows
}

///|
/// 「已工作」折叠组：可见记录；有未处理卡显示「待审计 N」，否则显示时长。
fn[Msg] work_group_row(
  p : AiViewParams[Msg],
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
    t.translate("app.ai.fold_pending", values=[("count", pending.to_string())])
  } else if duration >= 1 {
    let minutes = duration / 60
    let seconds = duration % 60
    t.translate("app.ai.work.trace", values=[
      (
        "duration",
        t.translate("app.ai.work.duration", values=[
          ("m", minutes.to_string()),
          ("s", seconds.to_string()),
        ]),
      ),
    ])
  } else {
    t.translate("app.ai.fold_idle")
  }
  let body : Array[@moui.View[Msg]] = [
    work_group_bar(p, label, inner, pending > 0),
  ]
  if !p.cards_folded {
    let mut card_index = 0
    for card in group {
      body.push(ai_card_view(p, t, card, card_index, inner))
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
/// 折叠组头：chevron + 标签，点击折叠/展开。
fn[Msg] work_group_bar(
  p : AiViewParams[Msg],
  label : String,
  width : Double,
  has_pending : Bool,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_xy(
      @views.row(
        [
          @views.icon(
            if p.cards_folded {
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
  ).on_tap(p.on_toggle_fold)
}

///|
/// 用户提问气泡：宽度钳 70%，动作行 = 复制 / 编辑 + HH:MM。
fn[Msg] user_bubble_row(
  p : AiViewParams[Msg],
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
            t.translate("app.ai.action.copy"),
            (p.on_copy)(card.seq),
            @chrome.Ghost,
            18.0,
          ),
          @chrome.action_chip(
            t.translate("app.ai.action.edit"),
            (p.on_edit)(card.seq),
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
/// AI 消息行：markdown 渲染 + 动作行（复制 / 重发）。
fn[Msg] ai_message_row(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  card : AiCard,
  width : Double,
) -> @moui.View[Msg] {
  let inner = (width - 24.0).max(120.0)
  let blocks = @markdown.parse_markdown(card.body)
  @views.container(
    @views.column(
      [
        markdown_blocks_view(
          blocks,
          inner,
          t,
          on_copy_code=Some(fn(index : Int) {
            (p.on_copy_code)(card.seq, index)
          }),
        ),
        message_actions_row(card, inner, [
          @chrome.action_chip(
            t.translate("app.ai.action.copy"),
            (p.on_copy)(card.seq),
            @chrome.Ghost,
            18.0,
          ),
          @chrome.action_chip(
            t.translate("app.ai.action.retry"),
            (p.on_retry)(card.seq),
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
/// 消息动作行：动作芯片 + HH:MM 时间戳。
fn[Msg] message_actions_row(
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
/// 决策条实际足迹（钉底块预算）。
fn[Msg] decision_bar_footprint(p : AiViewParams[Msg]) -> Double {
  if has_decision_content(p) {
    decision_bar_height(p) + 12.0
  } else {
    0.0
  }
}

///|
/// 右栏 AI 页钉底块高度（唯一来源）。
pub fn[Msg] ai_docked_height(p : AiViewParams[Msg], width : Double) -> Double {
  let fixed = AI_DOCK_PAD_V * 2.0 +
    AI_CARD_INSET * 2.0 +
    AI_SUBJECT_CHIP_HEIGHT +
    AI_CARD_ROW_GAP * 2.0 +
    // 模型候选行展开时 composer 多一行——预算必须跟着长，否则输入盒
    // 被钉底块顶出宿主（`ai_bar_layout_wbtest` 的高度回归钉住这条）。
    composer_block_height(width, picker_open=p.model_picker_open) +
    AI_DOCK_GAP +
    POSTURE_HEIGHT
  let decision_room = (AI_DECISION_MAX_HEIGHT - fixed).max(0.0)
  fixed + decision_bar_footprint(p).min(decision_room)
}

///|
/// 右栏 AI 页钉底块：圆角描边输入卡 + 卡下状态行。
pub fn[Msg] ai_docked_block(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let card_w = (width - AI_CARD_PAD * 2.0).max(80.0)
  let card = @views.container(
    @views.padding_edges(
      @views.column(
        [
          ai_subject_chip(p, t, (card_w - 16.0).max(60.0)),
          composer(p, t, card_w),
          decision_bar(p, t, card_w),
        ],
        spacing=AI_CARD_ROW_GAP,
      ).frame(width=card_w),
      left=8.0,
      right=8.0,
      top=AI_CARD_INSET,
      bottom=AI_CARD_INSET,
    ),
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
      @views.column([card, ai_posture_row(p, t, width)], spacing=AI_DOCK_GAP).frame(
        width~,
      ),
      left=AI_CARD_PAD,
      right=AI_CARD_PAD,
      top=AI_DOCK_PAD_V,
      bottom=AI_DOCK_PAD_V,
    ),
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 上下文芯片：当前选中对象 = 「AI 会针对谁」。
fn[Msg] ai_subject_chip(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let name = p.subject_name
  let kind = p.subject_kind
  let none = name == t.translate("app.ctx.none")
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
/// AI 页会话区（右栏 / 中心共用）：会话头 + 转录 + 回到底部 + 查看全部。
fn[Msg] ai_conversation(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
  transcript_h : Double,
) -> Array[@moui.View[Msg]] {
  let builder : Array[@moui.View[Msg]] = [
    ai_session_header(p, t, width),
    ai_transcript(p, t, width, transcript_h),
  ]
  let follow_h = if p.transcript_follow { 0.0 } else { 26.0 }
  builder.push(ai_scroll_to_bottom_row(p, t, width, follow_h))
  if p.sessions.current().cards.length() > 3 && !p.cards_folded {
    builder.push(
      see_all_row(t, (width - 16.0).max(80.0), on_toggle=p.on_toggle_history),
    )
  }
  builder
}

///|
/// 右栏 AI 页：会话转录 + 钉底输入卡。
pub fn[Msg] ai_page(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let docked_h = ai_docked_height(p, width)
  let follow_h = if p.transcript_follow { 0.0 } else { 26.0 }
  let transcript_h = (height - AI_SESSION_HEADER_HEIGHT - follow_h - docked_h).max(
    100.0,
  )
  @views.container(
    @views.column(
      ai_conversation(p, t, width, transcript_h) +
      [@chrome.hairline(), ai_docked_block(p, t, width, docked_h)],
      spacing=0.0,
    ).frame(width~, height~),
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
fn[Msg] ai_card_view(
  p : AiViewParams[Msg],
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
  let settled_badge = if card.settled {
    @chrome.count_badge(t.translate("app.ai.settled"), 1)
  } else {
    @views.text("", width=1.0, height=1.0)
  }
  let badge_w = if card.settled {
    (@chrome.text_estimate_width(t.translate("app.ai.settled")) * 1.02 + 12.0).max(
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
          @chrome.fit_label(t.translate(card.title), title_w),
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
    if card.kind is CardExplanation {
      rows.push(
        markdown_blocks_view(
          @markdown.parse_markdown(card.body),
          width,
          t,
          on_copy_code=Some(fn(index : Int) {
            (p.on_copy_code)(card.seq, index)
          }),
        ),
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
  if card.kind is CardPlan {
    // **积木计数芯片**（目标图右栏的「P1…P6」同构物）：这一轮提案会落下
    // 多少块积木。count 来自 apply 后的 `block_chain` 行数，由壳投影进
    // `plan_block_count`（视图层不读壳 Model）。
    //
    // 用 `block_category_fill(CatFlow)` 的语义色而不是 `count_badge` 的
    // 中性灰：它是「积木数」这个域事实，与「已处理 N」那种壳状态不同级。
    match p.plan_block_count {
      Some(count) =>
        rows.push(
          @views.container(
            @views.center(
              @views.text(
                t.translate("app.ai.block_chip", values=[
                  ("count", count.to_string()),
                ]),
                theme=@chrome.studio_theme(),
                role=Caption,
                width=64.0,
                height=14.0,
                align=TextCenter,
              ).foreground(@chrome.block_category_text()),
              width=68.0,
              height=20.0,
            ),
            background=@chrome.block_category_fill(@blocks.CatFlow),
            corner_radius=4.0,
            width=68.0,
            height=20.0,
            padding=0.0,
          ),
        )
      None => ()
    }
    rows.push(@chrome.progress_bar(card.progress, width - 16.0))
    // **编号步骤**（ 右栏的 4/5/6 蓝圈口径）：每步一枚圆形
    // 数字徽标——未完成 = 强调色底 + 主题字,已完成 = 弱底 + 淡字
    // （数字仍可读,步骤号是引用锚点:「第 4 步」）。步骤号从 1 起。
    let mut step_index = 0
    for step in card.steps {
      let done = step_index < card.steps_done
      rows.push(
        @views.row(
          [
            @views.container(
              @views.center(
                @views.text(
                  (step_index + 1).to_string(),
                  theme=@chrome.studio_theme(),
                  role=Mono,
                  width=10.0,
                  height=12.0,
                  align=TextCenter,
                ).foreground(
                  if done {
                    @chrome.ide_text_faint()
                  } else {
                    @chrome.studio_theme().palette.on_primary
                  },
                ),
                width=16.0,
                height=16.0,
              ),
              background=if done {
                @chrome.ide_panel_alt()
              } else {
                @chrome.ide_accent()
              },
              corner_radius=8.0,
              width=16.0,
              height=16.0,
              padding=0.0,
            ),
            @views.text(
              step,
              theme=@chrome.studio_theme(),
              width=(width - 16.0 - 22.0).max(60.0),
              height=16.0,
              align=TextStart,
            ).foreground(
              if done {
                @chrome.ide_success()
              } else {
                @chrome.ide_text()
              },
            ),
          ],
          spacing=6.0,
          align=Center,
        ),
      )
      step_index = step_index + 1
    }
  }
  for line in card.diff_lines {
    rows.push(@chrome.diff_row(line.0, line.1, width))
  }
  if !card.settled && (card.kind is CardDiff || card.kind is CardSideEffect) {
    rows.push(
      @views.row(
        [
          @chrome.action_chip(
            t.translate("app.ai.accept"),
            p.on_accept,
            @chrome.Primary,
            22.0,
          ),
          @chrome.action_chip(
            t.translate("app.ai.reject"),
            p.on_reject,
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
        t.translate(card.settled_note),
        theme=@chrome.studio_theme(),
        width=(width - 16.0).max(60.0),
        height=16.0,
        align=TextStart,
      ).foreground(@chrome.ide_success()),
    )
  }
  @chrome.inline_card(
    accent,
    @views.column(rows, spacing=4.0),
    width,
    card.settled,
  )
}

///|
/// 输入条：模式段 | 输入框 | 发送。窄卡折两行。
fn[Msg] composer(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  if !p.available {
    let total = composer_height(width) + context_chips_height(width)
    let box_width = (width - 16.0).max(120.0)
    return @views.container(
      @views.center(
        @views.text(
          t.translate("app.ai.unavailable"),
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
  let mode_cells : Array[@moui.View[Msg]] = if p.picker_open {
    [
      composer_mode_chip(p, t, ComposeEdit, "app.ai.mode.edit"),
      composer_mode_chip(p, t, ComposeGenerate, "app.ai.mode.generate"),
      composer_mode_chip(p, t, ComposeExplain, "app.ai.mode.explain"),
      composer_mode_chip(p, t, ComposeRepair, "app.ai.mode.repair"),
      composer_mode_chip(p, t, ComposeChat, "app.ai.mode.chat"),
    ]
  } else {
    [composer_mode_dropdown(p, t)]
  }
  let box_width = (width - 16.0).max(120.0)
  let inner_width = box_width - 16.0
  let busy = p.busy
  let send_msg = if busy { p.on_noop } else { p.on_run }
  let foot_cells : Array[@moui.View[Msg]] = [
    @views.row(mode_cells, spacing=3.0, align=Center),
    @views.spacer(min_length=6.0, weight=1.0),
  ]
  if inner_width >= 300.0 {
    foot_cells.push(
      (p.ghost_icon)(
        Clipboard,
        t.translate("app.ai.history"),
        p.on_toggle_history,
      ),
    )
  }
  if inner_width >= 300.0 {
    let model_label = if !p.available {
      t.translate("app.ai.unavailable")
    } else if p.provider_key == "" {
      t.translate("app.ai.disconnected")
    } else {
      @chrome.fit_label(p.provider_model, 140.0)
    }
    // **模型下拉芯片**（目标图底栏的模型选择器）：收起 = 当前模型名 +
    // ChevronDown；展开 = 一行候选芯片（最多 4 个 + 「去设置」收尾）。
    //
    // 为什么**不引 popover**：`app/moon.pkg` 未 import `moui/views/popover`，
    // 为一个模型选择器加依赖不划算；且 composer 内的原位展开与模式选择器
    // （`composer_mode_chip`）视觉同构——同一层里两种选择器长得不一样
    // 反而乱。展开行画在 composer **内部**（脚注行上方），不突破
    // `ai_docked_height` 的钉底预算。
    foot_cells.push(
      dropdown_chip(
        Gear,
        model_label,
        if p.available && p.provider_key != "" {
          p.on_toggle_model_picker
        } else {
          p.on_settings
        },
      ),
    )
  }
  if p.streaming {
    foot_cells.push(
      @chrome.action_chip(
        t.translate("app.ai.stop"),
        p.on_stop,
        @chrome.Quiet,
        24.0,
      ),
    )
  } else {
    foot_cells.push(
      round_send_button(t.translate("app.ai.send"), send_msg, !busy, 24.0),
    )
  }
  let foot = @chrome.fill_row(foot_cells, inner_width, 6.0, Center)
  // 模型候选行（展开态）：画在脚注行**上方**，是 composer 内部的第二行
  // （实现见 `composer_model_picker`）。
  let picker = composer_model_picker(p, t, inner_width)
  let field = @views.text_area(
    p.sessions.current().prompt_draft,
    on_input=value => (p.on_set_prompt)(value),
    placeholder=t.translate("app.ai.prompt"),
    lines=3,
    variant=Plain,
    width=inner_width,
    line_height=20.0,
    on_submit=Some(send_msg),
  )
  let box = @views.container(
    @views.padding_edges(
      @views.column(picker + [field, foot], spacing=2.0),
      left=8.0,
      right=8.0,
      top=2.0,
      bottom=3.0,
    ),
    background=@chrome.ide_panel(),
    corner_radius=if p.center_perspective { 10.0 } else { 0.0 },
    border=if p.center_perspective {
      Some(@core.BorderStyle::{
        brush: @core.Brush::Solid(@chrome.ide_border()),
        width: 1.0,
      })
    } else {
      None
    },
    width=box_width,
    height=composer_height(width, picker_open=p.model_picker_open),
    padding=0.0,
  )
  let chips_h = context_chips_height(width)
  if chips_h > 0.0 {
    @views.column([context_chips_row(p, t, box_width), box], spacing=2.0).frame(
      width=box_width,
      height=composer_height(width) + chips_h,
    )
  } else {
    box
  }
}

///|
/// 模式下拉芯片（收起态）。
fn[Msg] composer_mode_dropdown(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let label = match p.composer_mode {
    ComposeEdit => t.translate("app.ai.mode.edit")
    ComposeGenerate => t.translate("app.ai.mode.generate")
    ComposeExplain => t.translate("app.ai.mode.explain")
    ComposeRepair => t.translate("app.ai.mode.repair")
    ComposeChat => t.translate("app.ai.mode.chat")
  }
  let label_w = (@chrome.text_estimate_width(label) * 1.05 + 8.0).max(30.0)
  let chip_w = label_w + 26.0
  let open = p.picker_open
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
  ).on_tap(p.on_toggle_picker)
}

///|
/// 姿态读数行：无未处理卡 = 闸门弱读数；有卡 = 「待审计 N」警告色。
fn[Msg] ai_posture_row(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let pending = pending_ai_cards(p)
  let label = if pending > 0 {
    t.translate("app.ai.pending_chip", values=[("count", pending.to_string())])
  } else {
    t.translate("app.ai.posture.gate")
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
fn composer_chip_width(label : String) -> Double {
  (@chrome.text_estimate_width(label) * 1.05 + 14.0).max(36.0)
}

///|
/// 模式芯片：选中态强调色 + 底色区分。
fn[Msg] composer_mode_chip(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  mode : ComposerMode,
  key : String,
) -> @moui.View[Msg] {
  let selected = p.composer_mode == mode
  let label = t.translate(key)
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
  ).on_tap((p.on_set_mode)(mode))
}

///|
/// composer 的**模型候选行**（展开态）：画在脚注行上方，是 composer 内部的
/// 第二行。收起时返回空数组（不占高度）。
///
/// 上限 4 个候选 + 一枚「模型设置」收尾——超过 4 个说明清单该去设置里管，
/// 在 composer 里做滚动列表会把输入盒顶出宿主（钉底高度预算只够一行）。
///
/// 从 `composer` 里拆出来：composer 本体已近函数体上限，而候选行是独立的
/// 一段（可空、可单独测试），拆开后两处都读得动。
fn[Msg] composer_model_picker(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  inner_width : Double,
) -> Array[@moui.View[Msg]] {
  if !(p.model_picker_open && p.available && p.provider_key != "") {
    return []
  }
  let cells : Array[@moui.View[Msg]] = []
  let mut shown = 0
  for name in p.provider_models {
    if shown >= 4 {
      break
    }
    let selected = name == p.provider_model
    cells.push(
      @views.container(
        @views.center(
          @views.text(
            @chrome.fit_label(name, 110.0),
            theme=@chrome.studio_theme(),
            width=(composer_chip_width(name) - 14.0).max(20.0),
            height=16.0,
          ).foreground(
            if selected {
              @chrome.ide_accent()
            } else {
              @chrome.ide_text_muted()
            },
          ),
          width=composer_chip_width(name),
          height=20.0,
        ),
        background=if selected {
          @chrome.ide_selection()
        } else {
          @chrome.ide_panel()
        },
        corner_radius=10.0,
        width=composer_chip_width(name),
        height=20.0,
        padding=0.0,
      )
      .on_tap((p.on_select_model)(name))
      .accessibility_label(name),
    )
    shown = shown + 1
  }
  cells.push(@views.spacer(min_length=6.0, weight=1.0))
  cells.push(
    @chrome.action_chip(
      t.translate("app.ai.settings"),
      p.on_settings,
      @chrome.Ghost,
      20.0,
    ),
  )
  [
    @views.container(
      @chrome.fill_row(cells, inner_width, 4.0, Center),
      background=@chrome.ide_panel(),
      width=inner_width,
      height=22.0,
      padding=0.0,
    ),
  ]
}
