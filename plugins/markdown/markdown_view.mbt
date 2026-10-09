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
  key? : String = "studio-markdown-editor",
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
  on_selection_change~ : (Int, @core.TextRange?) -> Msg,
  width~ : Double,
  height~ : Double,
  font~ : @text.FontSpec,
  foreground~ : @graphics.Color,
  placeholder_color~ : @graphics.Color,
  background~ : @graphics.Brush,
  cursor_color~ : @graphics.Color,
  key? : String = "studio-markdown-session-editor",
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
