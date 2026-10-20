///|
/// Markdown 插件·.md 文件面板（G3）。
///
/// 无状态视图贡献：面板状态（草稿/脏标记/光标）住在壳的
/// `open_project_file`，本插件不复制状态切片（terminal 插件先例——状态由
/// 壳消息驱动）。渲染基于 `wzzc-dev/moui_richtext` 的 `markdown_editor`
/// （MoMark 编辑面同款引擎）：受控、块级格式渲染，`on_input` 把新文本
/// 送回壳的草稿通道（EditProjectFile → 脏 ● → SaveProjectFile 写盘）。
///
/// 零 app 依赖：字体/颜色全部由壳注入;零 app 引用（插件互不 import 纪律）。

///|
/// `.md` 文件的 Markdown 编辑面。高度 = 内容全高（经
/// `markdown_editor_format` + `rich_text_document_height` 估算）与宿主
/// 视口取大——外层滚动由壳的 scroll_view 承担（工程文件编辑器同款方案,
/// 受控编辑器的内部滚轮路径不可靠是既有实测结论）。
pub fn[Msg] markdown_file_view(
  content~ : String,
  on_input~ : (String) -> Msg,
  width~ : Double,
  height~ : Double,
  font~ : @text.FontSpec,
  foreground~ : @graphics.Color,
  placeholder_color~ : @graphics.Color,
  background~ : @graphics.Brush,
  cursor_color~ : @graphics.Color,
  key~ : String = "studio-markdown-editor",
) -> @moui.View[Msg] {
  let editor_width = (width - 32.0).max(80.0)
  let content_height = markdown_content_height(
    content~,
    width=editor_width,
    font~,
  ).max(height)
  @richtext.markdown_editor(
    value=content,
    placeholder="",
    size=@geometry.Size::new(width=editor_width, height=content_height),
    font~,
    foreground~,
    placeholder_color~,
    background~,
    cursor_color~,
    on_input=Some(on_input),
    accepts_tab_input=false,
    key=Some(key),
  )
}

///|
/// `.md` 文件的 MoMark session 编辑面（与 momark 编辑面同款引擎档位）：
/// 持久 `MarkdownDocumentSession` 提供块级结构渲染——光标所在 span 的
/// 标记就地 reveal（`**粗体**` 显示为粗体）、focus mode、软换行一致的
/// 高度测量、Enter 拆段/列表续行/表格键等真编辑事务。事务经壳消息
/// 回写模型里的会话与草稿（受控往返,插件不持有状态）。
pub fn[Msg] markdown_session_file_view(
  session~ : @richtext.MarkdownDocumentSession,
  selection~ : @richtext.MarkdownEditorSelection,
  on_transaction~ : (@richtext.MarkdownEditTransaction) -> Msg,
  on_selection_change~ : (Int32, @core.TextRange?) -> Msg,
  width~ : Double,
  height~ : Double,
  font~ : @text.FontSpec,
  foreground~ : @graphics.Color,
  placeholder_color~ : @graphics.Color,
  background~ : @graphics.Brush,
  cursor_color~ : @graphics.Color,
  key~ : String = "studio-markdown-session-editor",
) -> @moui.View[Msg] {
  let editor_width = (width - 32.0).max(80.0)
  let content_height = session
    .estimated_content_height(base=font, content_width=editor_width)
    .max(height)
  @richtext.controlled_markdown_session_editor(
    session~,
    selection~,
    on_transaction~,
    placeholder="",
    size=@geometry.Size::new(width=editor_width, height=content_height),
    font~,
    foreground~,
    placeholder_color~,
    background~,
    cursor_color~,
    accepts_tab_input=false,
    on_selection_change=Some(on_selection_change),
    key=Some(key),
  )
}

///|
/// Markdown 内容的渲染全高估算：整篇源码格式化为富文本文档后量高度
/// （块级边距未计入,以 +24pt 呼吸位兜底）。
pub fn markdown_content_height(
  content~ : String,
  width~ : Double,
  font~ : @text.FontSpec,
) -> Double {
  let document = @richtext.markdown_editor_format(content, base=font)
  @richtext.rich_text_document_height(document, font, block_width=width) + 24.0
}

///|
/// === 会话查找/替换适配（moui_markdown 0.2.2 起）===
///
/// Studio `.md` 面板不再自建第二份匹配语义：查找/替换全部走
/// `wzzc-dev/moui_markdown` 的公共 chrome 内核。下面这组适配器把
/// 「会话快照 + 选区 + 选项」翻译成 `MarkdownEditTransaction`，由壳走既有
/// `ProjectFileMarkdownTransaction` 通道回写（与 MoMark 同一条事务链）。
///
/// 视图侧同理：`markdown_find_bar_view` / `markdown_outline_panel_view` /
/// `markdown_document_info_panel_view` / `markdown_format_palette_view` 是
/// `@mdchrome` Msg-generic 面板的 Studio 中文默认文案转发。

///|
/// 在给定源码上按查询/选项取全部命中（供查找栏状态与跳转共用）。
pub fn markdown_session_find_matches(
  source~ : String,
  query~ : String,
  options~ : @mdchrome.MarkdownFindOptions,
) -> Array[@core.TextRange] {
  @mdchrome.markdown_find_matches(source, query, options~)
}

///|
/// 查找栏状态文案（"Ready" / "Invalid regex" / "No match" / "n/m"）。
pub fn markdown_session_find_status(
  query~ : String,
  matches~ : Array[@core.TextRange],
  selection~ : @richtext.MarkdownEditorSelection,
  options~ : @mdchrome.MarkdownFindOptions,
) -> String {
  @mdchrome.markdown_find_status_label(query, matches, selection, options~)
}

///|
/// 替换选区语义：start == end（替换文本为空）时不保留选区。
fn markdown_replacement_selection(
  start : Int32,
  end : Int32,
) -> @core.TextRange? {
  if start == end {
    None
  } else {
    Some(@core.TextRange::new(start~, end~))
  }
}

///|
/// 替换「当前命中」：优先与选区完全重合的命中，否则取选区之后的下一命中
/// （环形）。返回可 apply 到会话的事务；无命中或源码不变时返回 None。
/// 替换后选区落在新文档的下一命中上，没有下一命中则落在替换文本之后
/// （与 MoMark 的 replace-current 行为一致）。
pub fn markdown_session_replace_current(
  session~ : @richtext.MarkdownDocumentSession,
  selection~ : @richtext.MarkdownEditorSelection,
  query~ : String,
  replacement~ : String,
  options~ : @mdchrome.MarkdownFindOptions,
) -> @richtext.MarkdownEditTransaction? {
  let source = session.source()
  let matches = @mdchrome.markdown_find_matches(source, query, options~)
  if matches.length() == 0 {
    return None
  }
  let active = @mdchrome.markdown_find_active_index(matches, selection)
  let index = if active >= 0 {
    active
  } else {
    @mdchrome.markdown_find_next_index(matches, selection)
  }
  let range = matches[index]
  let next_source = @mdchrome.markdown_replace_source_range(
    source, range, replacement,
  )
  if next_source == source {
    return None
  }
  let end = range.start + @richtext.markdown_editor_text_length(replacement)
  let next_matches = @mdchrome.markdown_find_matches(
    next_source,
    query,
    options~,
  )
  match
    @mdchrome.markdown_next_match_after_replacement(
      next_matches,
      range.start,
      end,
    ) {
    Some(next_range) =>
      Some(
        @richtext.MarkdownEditTransaction::from_sources(
          source,
          next_source,
          caret=next_range.end,
          selection=Some(next_range),
          reason=@richtext.MarkdownEditReason::ReplaceEdit,
        ),
      )
    None =>
      Some(
        @richtext.MarkdownEditTransaction::from_sources(
          source,
          next_source,
          caret=end,
          selection=markdown_replacement_selection(range.start, end),
          reason=@richtext.MarkdownEditReason::ReplaceEdit,
        ),
      )
  }
}

///|
/// 替换全部命中：单趟重写整篇源码，选区落在首处替换文本上（替换文本为空
/// 时无选区）。无命中或源码不变时返回 None。
pub fn markdown_session_replace_all(
  session~ : @richtext.MarkdownDocumentSession,
  query~ : String,
  replacement~ : String,
  options~ : @mdchrome.MarkdownFindOptions,
) -> @richtext.MarkdownEditTransaction? {
  let source = session.source()
  let matches = @mdchrome.markdown_find_matches(source, query, options~)
  if matches.length() == 0 {
    return None
  }
  let next_source = @mdchrome.markdown_replace_all_matches(
    source, matches, replacement,
  )
  if next_source == source {
    return None
  }
  let start = matches[0].start
  let end = start + @richtext.markdown_editor_text_length(replacement)
  Some(
    @richtext.MarkdownEditTransaction::from_sources(
      source,
      next_source,
      caret=end,
      selection=markdown_replacement_selection(start, end),
      reason=@richtext.MarkdownEditReason::ReplaceEdit,
    ),
  )
}

///|
/// 会话文档统计（字数/字符/块级与行内计数），供文档信息面板使用。
pub fn markdown_session_document_info(
  session~ : @richtext.MarkdownDocumentSession,
) -> @mdchrome.MarkdownDocumentInfo {
  @mdchrome.markdown_document_info_from_session(session)
}

///|
/// 查找/替换栏（Studio 中文默认文案）。`status_label` 通常由
/// `markdown_session_find_status` 生成。
pub fn[Msg] markdown_find_bar_view(
  theme~ : @moui.Theme,
  query~ : String,
  replace_text~ : String,
  options~ : @mdchrome.MarkdownFindOptions,
  status_label~ : String,
  on_query_input~ : (String) -> Msg,
  on_replace_input~ : (String) -> Msg,
  on_submit_query~ : Msg,
  on_submit_replace~ : Msg,
  on_toggle_case_sensitive~ : Msg,
  on_toggle_whole_word~ : Msg,
  on_toggle_regex~ : Msg,
  on_previous~ : Msg,
  on_next~ : Msg,
  on_replace_current~ : Msg,
  on_replace_all~ : Msg,
  on_close~ : Msg,
  width~ : Double,
) -> @moui.View[Msg] {
  @mdchrome.markdown_find_bar(
    theme~,
    query~,
    replace_text~,
    options~,
    status_label~,
    on_query_input~,
    on_replace_input~,
    on_submit_query~,
    on_submit_replace~,
    on_toggle_case_sensitive~,
    on_toggle_whole_word~,
    on_toggle_regex~,
    on_previous~,
    on_next~,
    on_replace_current~,
    on_replace_all~,
    on_close~,
    width~,
    find_label="查找",
    replace_label="替换",
    search_placeholder="搜索 Markdown",
    replacement_placeholder="替换为",
    replace_button_label="替换",
    replace_all_button_label="全部",
    match_case_tooltip="区分大小写",
    whole_word_tooltip="全词匹配",
    regex_tooltip="正则表达式",
    previous_tooltip="上一个匹配",
    next_tooltip="下一个匹配",
    close_tooltip="关闭查找栏",
    key_prefix="studio-markdown",
  )
}

///|
/// 大纲面板（ Studio 中文默认文案）。折叠状态与跳转/折叠意图由宿主持有。
pub fn[Msg] markdown_outline_panel_view(
  theme~ : @moui.Theme,
  outline~ : Array[@richtext.MarkdownEditorOutlineItem],
  folded_starts~ : Array[Int32],
  caret~ : Int32,
  on_jump~ : (Int32) -> Msg,
  on_toggle_fold~ : (Int32) -> Msg,
  height~ : Double,
  width~ : Double = 240.0,
) -> @moui.View[Msg] {
  @mdchrome.markdown_outline_panel(
    theme~,
    outline~,
    folded_starts~,
    caret~,
    on_jump~,
    on_toggle_fold~,
    height~,
    width~,
    title="大纲",
    empty_label="无标题",
  )
}

///|
/// 文档信息面板（Studio 中文默认文案）。
pub fn[Msg] markdown_document_info_panel_view(
  theme~ : @moui.Theme,
  info~ : @mdchrome.MarkdownDocumentInfo,
  word_count~ : Int32,
  line_count~ : Int32,
  reading_time_label~ : String,
  height~ : Double,
  width~ : Double = 240.0,
) -> @moui.View[Msg] {
  @mdchrome.markdown_document_info_panel(
    theme~,
    info~,
    word_count~,
    line_count~,
    reading_time_label~,
    height~,
    width~,
    title="文档信息",
    words_label="字数",
    characters_label="字符",
    lines_label="行数",
    reading_label="阅读",
    headings_label="标题",
    paragraphs_label="段落",
    list_items_label="列表项",
    tasks_label="任务",
    quotes_label="引用",
    code_blocks_label="代码块",
    tables_label="表格",
    links_label="链接",
    images_label="图片",
    footnotes_label="脚注",
  )
}

///|
/// 快速格式面板（Studio 中文默认文案）。`items` 通常来自
/// `@mdchrome.markdown_format_palette_filtered_items(query)`。
pub fn[Msg] markdown_format_palette_view(
  theme~ : @moui.Theme,
  query~ : String,
  items~ : Array[@mdchrome.MarkdownPaletteItem],
  on_query_input~ : (String) -> Msg,
  on_submit~ : Msg,
  on_action~ : (String) -> Msg,
  on_done~ : Msg,
  width~ : Double,
) -> @moui.View[Msg] {
  @mdchrome.markdown_format_palette(
    theme~,
    query~,
    items~,
    on_query_input~,
    on_submit~,
    on_action~,
    on_done~,
    width~,
    title="快速格式",
    filter_placeholder="筛选",
    done_label="完成",
    empty_label="无匹配命令",
    key_prefix="studio-markdown",
  )
}
