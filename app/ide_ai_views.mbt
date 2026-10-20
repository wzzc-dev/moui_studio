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
pub fn composer_height(width : Double, picker_open~ : Bool = false) -> Double {
  @ai.composer_height(width, picker_open~)
}

///|
pub fn context_chips_height(width : Double) -> Double {
  @ai.context_chips_height(width)
}

///|
pub fn composer_block_height(
  width : Double,
  picker_open~ : Bool = false,
) -> Double {
  @ai.composer_block_height(width, picker_open~)
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
    provider_models: model.ai_ui.provider_models,
    model_picker_open: model.ai_ui.provider_model_picker_open,
    plan_block_count: plan_block_count_of(model),
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
    on_toggle_model_picker: AiUiOp(@ai.ToggleProviderModelPicker),
    on_select_model: fn(name) { AiUiOp(@ai.SetProviderModel(name)) },
    on_toggle_history: AiUiOp(@ai.ToggleAiHistory),
    on_accept: AcceptProposal,
    on_reject: RejectProposal,
    on_copy: fn(seq) { CopyAiMessage(seq) },
    on_copy_code: fn(seq, index) { CopyAiCodeBlock(seq, index) },
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
/// 模型候选行是否展开（高度预算与视图共用的判据单点来源）。
pub fn model_picker_open_of(model : Model) -> Bool {
  model.ai_ui.provider_model_picker_open
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

///|
/// 计划卡的**积木计数**：这一轮提案 apply 后程序里共有多少块积木。
///
/// 取「全部 handler 的 block_chain 行数之和」而不是「当前 handler」：
/// 一次提案可能同时改多个子程序（`ComposeGenerate` 更是从零重建整个程序），
/// 只数当前那个会少报。None = 没有待审计提案（不显示芯片）。
///
/// **只在有 pending 提案时给值**：计划卡是「AI 打算做什么」的记录，
/// 计数是那个打算的规模；没有 pending 时给 0 会读作「AI 什么都不会做」。
pub fn plan_block_count_of(model : Model) -> Int32? {
  match model.pending {
    None => None
    Some(_) => {
      let mut total = 0
      for handler in model.program.handlers {
        total = total + @blocks.block_chain(handler.body).length()
      }
      Some(total)
    }
  }
}
