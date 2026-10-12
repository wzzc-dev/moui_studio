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
pub fn composer_height(width : Double) -> Double {
  ignore(width)
  COMPOSER_HEIGHT
}

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
pub fn composer_block_height(width : Double) -> Double {
  composer_height(width) + context_chips_height(width)
}
