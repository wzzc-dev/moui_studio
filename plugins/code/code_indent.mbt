///|
/// DSL 换行缩进（S7c 自壳移入代码插件）：当前行前导空白为基，块首关键字
/// +2，块尾关键字 -2。纯文本计算，不依赖壳模型/视图；调用方按当前 DSL
/// 语言传 Language（壳侧经 UiLanguage::dsl_language() 换转）。
pub fn dsl_indent_for_newline(
  language : @studio_lang.Language,
  source : String,
  caret : Int,
) -> String {
  let chars = source.to_array()
  let pos = caret.clamp(min=0, max=chars.length())
  let mut line_start = pos
  while line_start > 0 && chars[line_start - 1] != '\n' {
    line_start = line_start - 1
  }
  let indent : Array[Char] = []
  let mut index = line_start
  while index < pos && (chars[index] == ' ' || chars[index] == '\t') {
    indent.push(chars[index])
    index = index + 1
  }
  // 行内容（去前导空白后）的第一个词
  let mut end = pos
  while end < chars.length() && chars[end] != '\n' {
    end = end + 1
  }
  let trimmed = String::from_array(chars[index:end])
  let word = StringBuilder()
  for c in trimmed {
    if ({
        let code = c.to_int()
        code >= 0x80 ||
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F
      }) {
      word.write_char(c)
    } else {
      break
    }
  }
  let keywords = @studio_lang.keywords_for(language)
  let deeper = match
    @studio_lang.classify_stmt_keyword(word.to_string(), keywords) {
    KwIf | KwCountLoop | KwWhile => 2
    _ => 0
  }
  // 块尾关键字回退：结束/跳出循环（双语）
  let closes = trimmed == keywords.end_kw || trimmed == keywords.break_kw
  let width = indent.length() + deeper * 2 - (if closes { 2 } else { 0 })
  let spaces = StringBuilder()
  for _ in 0..<width.max(0) {
    spaces.write_char(' ')
  }
  spaces.to_string()
}
