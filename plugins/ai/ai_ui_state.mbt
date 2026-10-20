///|
/// AI 右栏工作区页签（与 ai_workspace_panel 双页签同源）。
pub(all) enum RightPanelTab {
  RpChanges
  RpFiles
} derive(Eq)

///|
pub extend RightPanelTab with Eq::{not_equal, equal}

///|
/// AI 域 UI 状态切片（S4d 状态切片，ADR 0038/0039/0040）：
/// composer 模式/下拉、provider 配置、右栏工作区页签、对白转录受控滚动、
/// 左栏会话列表的搜索/悬停/改名草稿、设置/历史对话框开合、工作卡折叠态。
///
/// 纯界面偏好与瞬态，零副作用、零 IR 真源触碰；生成/采纳/会话 CRUD/存储
/// 等跨域或服务臂仍住壳（契约 3）。视图经壳投影，本切片只持有状态。
pub(all) struct AiUiState {
  composer_mode : ComposerMode
  composer_mode_picker_open : Bool
  right_panel_tab : RightPanelTab
  provider_endpoint : String
  provider_model : String
  /// 模型候选清单（composer 里的下拉芯片列它）。
  ///
  /// **不从网络发现**：没有 `/models` 端点协议，假装能发现是谎言。来源只有
  /// `.config.json` 的 `provider.models`（缺省 = 只有当前 model 一项，
  /// 即今天的行为）。壳在装配时宽松读取（缺字段不报错）。
  provider_models : Array[String]
  /// composer 模型下拉是否展开（与 `composer_mode_picker_open` 同形态：
  /// 原位展开一行候选芯片，不引 popover 依赖）。
  provider_model_picker_open : Bool
  provider_key : String
  provider_key_revealed : Bool
  /// AI 页「已工作 N」折叠组是否收起（右栏 AI 页与 PsAi 中心共用）。
  ai_cards_folded : Bool
  /// 时间线受控滚动（终端同款）。
  mut transcript_scroll : @geometry.Point
  mut transcript_scroll_seq : Int32
  mut transcript_follow : Bool
  /// 左栏会话列表：搜索过滤行开合 + 查询 + 悬停行下标。
  ai_sessions_search_open : Bool
  ai_sessions_query : String
  ai_session_hover : Int32
  /// 行内改名编辑态：(下标, 草稿)；Start/Commit 需读会话或触发存储，住壳，
  /// 切片只承接草稿编辑（Draft）与清空（ClearRename 由壳在提交/取消后调用）。
  mut session_rename : (Int32, String)?
  /// 设置 / AI 历史对话框开合。
  settings_open : Bool
  ai_history_open : Bool
}

///|
/// 切片初始态：provider 配置来自组合根注入的 .config.json（缺省空串）。
pub fn AiUiState::new(
  endpoint : String,
  model : String,
  api_key : String,
  models : Array[String],
) -> AiUiState {
  {
    composer_mode: ComposeEdit,
    composer_mode_picker_open: false,
    right_panel_tab: RpChanges,
    provider_endpoint: endpoint,
    provider_model: model,
    // 候选清单为空时退化为「只有当前模型一项」——下拉仍可用（显示一个
    // 候选 + 一个「去设置」入口），不会出现空列表。
    provider_models: if models.length() > 0 {
      models
    } else {
      [model]
    },
    provider_model_picker_open: false,
    provider_key: api_key,
    provider_key_revealed: false,
    ai_cards_folded: false,
    transcript_scroll: @geometry.Point::new(x=0.0, y=0.0),
    transcript_scroll_seq: 0,
    transcript_follow: true,
    ai_sessions_search_open: false,
    ai_sessions_query: "",
    ai_session_hover: -1,
    session_rename: None,
    settings_open: false,
    ai_history_open: false,
  }
}

///|
/// AI 域 UI 子消息：纯界面偏好与瞬态，零副作用。
pub(all) enum AiUiMsg {
  SetComposerMode(ComposerMode)
  SetRightPanelTab(RightPanelTab)
  ToggleComposerModePicker
  SetProviderEndpoint(String)
  SetProviderModel(String)
  /// 设置模型候选清单（装配期一次性注入；空 = 退化为当前模型一项）。
  SetProviderModels(Array[String])
  /// 切换 composer 模型下拉的开合（选模型即收起）。
  ToggleProviderModelPicker
  SetProviderKey(String)
  ToggleProviderKeyReveal
  ToggleCardsFold
  TranscriptScrolled(@geometry.Point)
  TranscriptScrollToBottom
  ToggleSessionSearch
  SetSessionsQuery(String)
  SessionHover(Int32, Bool)
  SetRenameDraft(String)
  ClearRename
  ToggleSettings
  ToggleAiHistory
}

///|
/// AI UI 切片 update：纯状态转移，零副作用。
pub fn update_ai_ui(
  state : AiUiState,
  msg : AiUiMsg,
) -> (AiUiState, @moui.Effect[AiUiMsg]) {
  let none = @moui.Effect::none()
  match msg {
    // 选模式即收起下拉（V4）。
    SetComposerMode(mode) =>
      (
        { ..state, composer_mode: mode, composer_mode_picker_open: false, },
        none,
      )
    SetRightPanelTab(tab) => ({ ..state, right_panel_tab: tab, }, none)
    ToggleComposerModePicker =>
      (
        {
          ..state,
          composer_mode_picker_open: !state.composer_mode_picker_open,
        },
        none,
      )
    SetProviderEndpoint(value) => ({ ..state, provider_endpoint: value, }, none)
    SetProviderModel(value) =>
      (
        { ..state, provider_model: value, provider_model_picker_open: false, },
        none,
      )
    SetProviderModels(value) =>
      if value.length() > 0 {
        ({ ..state, provider_models: value, }, none)
      } else {
        (state, none)
      }
    ToggleProviderModelPicker =>
      (
        {
          ..state,
          provider_model_picker_open: !state.provider_model_picker_open,
        },
        none,
      )
    // 掩码态下 on_input 送来星号串：未展开时忽略编辑，避免写穿真值。
    SetProviderKey(value) =>
      if state.provider_key_revealed {
        ({ ..state, provider_key: value, }, none)
      } else {
        (state, none)
      }
    ToggleProviderKeyReveal =>
      ({ ..state, provider_key_revealed: !state.provider_key_revealed, }, none)
    ToggleCardsFold =>
      ({ ..state, ai_cards_folded: !state.ai_cards_folded, }, none)
    // 受控滚动：上滚关自动跟随（出现「回到底部」），下滚恢复跟随。
    TranscriptScrolled(offset) => {
      let was = state.transcript_scroll.y
      state.transcript_scroll = offset
      if offset.y < was - 2.0 {
        state.transcript_follow = false
      } else if offset.y > was + 2.0 {
        state.transcript_follow = true
      }
      (state, none)
    }
    // 强制贴底：恢复跟随 + 自增 seq（scroll 容器强制滚到底）。
    TranscriptScrollToBottom => {
      state.transcript_follow = true
      state.transcript_scroll_seq = state.transcript_scroll_seq + 1
      (state, none)
    }
    // 左栏会话搜索：关闭时清空查询。
    ToggleSessionSearch => {
      let opening = !state.ai_sessions_search_open
      (
        {
          ..state,
          ai_sessions_search_open: opening,
          ai_sessions_query: if opening {
            state.ai_sessions_query
          } else {
            ""
          },
        },
        none,
      )
    }
    SetSessionsQuery(value) => ({ ..state, ai_sessions_query: value, }, none)
    SessionHover(index, entered) =>
      ({ ..state, ai_session_hover: if entered { index } else { -1 }, }, none)
    SetRenameDraft(value) =>
      match state.session_rename {
        Some((index, _)) =>
          ({ ..state, session_rename: Some((index, value)), }, none)
        None => (state, none)
      }
    ClearRename => ({ ..state, session_rename: None, }, none)
    ToggleSettings => ({ ..state, settings_open: !state.settings_open, }, none)
    ToggleAiHistory =>
      ({ ..state, ai_history_open: !state.ai_history_open, }, none)
  }
}

///|
/// AI UI 域 Feature：view 域刻意 abort（视图由壳组装，与 ai_sessions/project
/// 同口径）。
pub fn ai_ui_feature() -> @moui.Feature[AiUiState, AiUiMsg] {
  @moui.Feature::new(
    init=() => (AiUiState::new("", "", "", []), @moui.Effect::none()),
    update=fn(state, message) { update_ai_ui(state, message) },
    view=_state => abort("ai ui views are composed by the parent shell"),
  )
}
