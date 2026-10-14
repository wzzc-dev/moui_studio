///|
/// AI 浮动层 / 右栏 AI 页·壳薄投影（S4b 出壳）：纯视图在 plugins/ai，
/// 这里把 Model 的 AI 域状态 + 跨域读数投影成 AiViewParams，把动作映射成
/// Msg（含会话切片委托 AiSessionOp）。常量与高度函数在插件、壳侧转发。

///|
/// 浮动卡 / 钉底卡各段高度常量（转发插件；视图与测试同口径）。
pub const FOLD_BAR_HEIGHT : Double = @ai.FOLD_BAR_HEIGHT

///|
pub const AI_CARD_PAD : Double = @ai.AI_CARD_PAD

///|
pub const AI_DOCK_PAD_V : Double = @ai.AI_DOCK_PAD_V

///|
pub const AI_CARD_INSET : Double = @ai.AI_CARD_INSET

///|
pub const AI_CARD_ROW_GAP : Double = @ai.AI_CARD_ROW_GAP

///|
pub const AI_DOCK_GAP : Double = @ai.AI_DOCK_GAP

///|
pub const AI_SUBJECT_CHIP_HEIGHT : Double = @ai.AI_SUBJECT_CHIP_HEIGHT

///|
pub const POSTURE_HEIGHT : Double = @ai.POSTURE_HEIGHT

///|
/// 输入盒高度（转发插件；测试与布局计算共用）。
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
/// 把壳 Model 投影成 AI 视图参数。
fn ai_view_params(model : Model) -> @ai.AiViewParams[Msg] {
  let (subject_name, subject_kind) = side_subject_of(model, translator(model))
  let project_name = match active_project_of(model) {
    Some(record) => Some(record.module_name)
    None => None
  }
  {
    sessions: model.ai_sessions,
    available: model.ai_available,
    busy: model.ai_busy,
    streaming: model.ai_streaming,
    cards_folded: model.ai_ui.ai_cards_folded,
    center_perspective: model.perspective is PsAi,
    composer_mode: model.ai_ui.composer_mode,
    picker_open: model.ai_ui.composer_mode_picker_open,
    provider_model: model.ai_ui.provider_model,
    provider_key: model.ai_ui.provider_key,
    explanation: model.explanation,
    prompt_error: model.prompt_error,
    pending: model.pending,
    transcript_follow: model.ai_ui.transcript_follow,
    transcript_scroll: model.ai_ui.transcript_scroll,
    transcript_scroll_seq: model.ai_ui.transcript_scroll_seq,
    project_name,
    subject_name,
    subject_kind,
    on_noop: Noop,
    on_set_prompt: fn(value) { AiSessionOp(@ai.SetPromptDraft(value)) },
    on_run: ComposerRun,
    on_stop: StopGeneration,
    on_set_mode: fn(mode) { AiUiOp(@ai.SetComposerMode(mode)) },
    on_toggle_picker: AiUiOp(@ai.ToggleComposerModePicker),
    on_toggle_history: AiUiOp(@ai.ToggleAiHistory),
    on_accept: AcceptProposal,
    on_reject: RejectProposal,
    on_copy: fn(seq) { CopyAiMessage(seq) },
    on_edit: fn(seq) { EditUserPrompt(seq) },
    on_retry: fn(seq) { RetryUserPrompt(seq) },
    on_scroll: fn(offset) { AiUiOp(@ai.TranscriptScrolled(offset)) },
    on_scroll_bottom: AiUiOp(@ai.TranscriptScrollToBottom),
    on_toggle_fold: AiUiOp(@ai.ToggleCardsFold),
    on_pin: fn(index, pinned) { AiSessionOp(AiSessionPin(index, pinned)) },
    on_remove: fn(index) { AiSessionOp(AiSessionRemove(index)) },
    on_open_project: SetLeftView(LeftProject),
    on_settings: StudioCommandRun("studio.settings"),
    ghost_icon: fn(icon, tip, on_click) {
      ghost_icon_button(
        icon,
        tip,
        false,
        on_click,
        22.0,
        20.0,
        11.0,
        @chrome.ide_panel(),
      )
    },
  }
}

///|
/// AI 中心工作区（对白转录）。
pub fn ai_center(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  @ai.ai_center(ai_view_params(model), t, width, height)
}

///|
/// 右栏 AI 页。
pub fn ai_page(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  @ai.ai_page(ai_view_params(model), t, width, height)
}

///|
/// 右栏 AI 页钉底块高度（唯一来源）。
pub fn ai_docked_height(model : Model, width : Double) -> Double {
  @ai.ai_docked_height(ai_view_params(model), width)
}

///|
/// 决策条是否在场（布局测试与避让预算同口径）。
pub fn has_decision_content(model : Model) -> Bool {
  @ai.has_decision_content(ai_view_params(model))
}

///|
/// 决策条内容高（布局测试与避让预算同口径）。
pub fn decision_bar_height(model : Model) -> Double {
  @ai.decision_bar_height(ai_view_params(model))
}
