///|
/// 上下文芯片行高（无芯片时不占位）。
pub const CHIPS_HEIGHT : Double = 26.0

///|
/// 输入盒高：两行文本域 + 盒内脚注一行（模式胶囊 | ghost 操作 | 圆形发送）
/// + 盒内垫。Codex/ZCode 口径——输入区是两行高的「书写区」，不是单行框。
/// 高度必须给 `lines × line_height + 16`：text_area 内部有 8pt×2 垂直内垫，
/// 只传 `lines=2` 时可见文本区只剩一行——这就是「输入区还是一行」的根因。
/// 这里 lines=3 × 20 = 60 → 可见 44 = 两整行（长 prompt 折行可读）。
pub const COMPOSER_HEIGHT : Double = 88.0

///|
/// 输入盒高度唯一计算源（视图层与 card_chrome_height 共用——两处各算
/// 一份就会把 composer 顶出卡片）。
/// `picker_open`：模型候选行是否展开（展开时 composer 内部多一行 22pt 的
/// 候选芯片）。**分态**是因为钉底块的高度预算从这一处取——两处各算一份
/// 就会把输入盒顶出宿主（`ai_bar_layout_wbtest` 的高度回归会红）。
pub fn composer_height(width : Double, picker_open? : Bool = false) -> Double {
  ignore(width)
  if picker_open {
    COMPOSER_HEIGHT + MODEL_PICKER_ROW_HEIGHT
  } else {
    COMPOSER_HEIGHT
  }
}

///|
/// 模型候选行高（composer 内部多出来的那一行）。
pub const MODEL_PICKER_ROW_HEIGHT : Double = 22.0

///|
/// composer 信息层（对白转录）：工程芯片（有 active 工程才在）+ 模型芯片
/// （离线/真实读数恒在）。只在宽卡（≥420）显示——右栏停靠/窄底栏放不下，
/// 强行显示会把脚注挤出面板。
pub fn context_chips_height(width : Double) -> Double {
  if width >= 420.0 {
    CHIPS_HEIGHT + 2.0
  } else {
    0.0
  }
}

///|
/// composer 块高 = 输入盒 + 上方上下文芯片行 + 空会话提示头条（仅中心态）。
/// 中心态与紧凑宿主的高度预算都从这里取——两处各算一份，芯片行/提示条
/// 就会把输入盒顶出宿主。
pub fn composer_block_height(
  width : Double,
  picker_open? : Bool = false,
) -> Double {
  composer_height(width, picker_open~) + context_chips_height(width)
}

///|
/// 线程区高度(卡片数驱动,280 上限;折叠 = 0)。S4② 出壳。

///|
/// 线程区高度：`ai_card_body` 的 scroll_view 用它，`ai_card_height` 也用它。
/// **只能有一处算**——视图层和高度预算各算一份，卡片就会裁掉自己的内容
/// （或反过来留一块空白）。
pub fn thread_area_height(sessions : AiSessions, cards_folded : Bool) -> Double {
  if sessions.current().cards.length() == 0 || cards_folded {
    0.0
  } else {
    // 线程区有 280 的上限（见 ai_card_body 的 scroll_view）
    (6.0 * sessions.current().cards.length().to_double() + 40.0).min(280.0)
  }
}
