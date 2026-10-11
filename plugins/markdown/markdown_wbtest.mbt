///|
/// G3:markdown 面板渲染管线测试——迷你程序渲染一次 draw 命令,断言
/// 内容文本出现且 `#` 标记被格式渲染消费;内容增长 → 高度增长。

///|
/// 渲染辅助：以给定视图建迷你程序,draw 一次取命令流。
fn[Msg] draw_view(
  view : @moui.View[Msg],
  width : Double,
  height : Double,
) -> Array[@core.DrawCommand] {
  let program : @core.Program[Int, Msg] = @moui.Program::new_with_environment(
    init=() => (0, @moui.Effect::none()),
    update=(current, _) => (current, @moui.Effect::none()),
    view=(_, _) => view,
  )
  @runtime.new_program_with_dimensions(program~, width~, height~).draw_commands()
}

///|
fn md_font() -> @text.FontSpec {
  @text.FontSpec::new(size=13.0)
}

///|
fn md_colors() -> (@graphics.Color, @graphics.Brush) {
  let foreground = @graphics.Color::rgba(r=0.88, g=0.88, b=0.9)
  (foreground, @graphics.Brush::solid(foreground))
}

///|
test "markdown 面板:标题文本渲染,标记被消费" {
  let (foreground, background) = md_colors()
  let view = markdown_file_view(
    content="# 安装指南\n\n先安装工具链。",
    on_input=_ => 0,
    width=600.0,
    height=400.0,
    font=md_font(),
    foreground~,
    placeholder_color=foreground,
    background~,
    cursor_color=foreground,
  )
  let commands = draw_view(view, 600.0, 400.0)
  let mut heading_found = false
  let mut marker_leaked = false
  for command in commands {
    match command {
      @core.DrawText(run) => {
        if run.text.contains("安装指南") {
          heading_found = true
        }
        if run.text.contains("# 安装指南") {
          marker_leaked = true
        }
      }
      _ => ()
    }
  }
  assert_true(heading_found, msg="标题文本应被渲染")
  assert_false(marker_leaked, msg="行内 `#` 标记应被格式渲染消费")
}

///|
test "markdown 内容高度随内容增长" {
  let short = markdown_content_height(
    content="一行",
    width=600.0,
    font=md_font(),
  )
  let long = markdown_content_height(
    content="一行\n\n两行\n\n三行\n\n四行\n\n五段更长的内容会继续向下延展渲染高度。",
    width=600.0,
    font=md_font(),
  )
  assert_true(
    long > short,
    msg="更多内容应量出更高渲染高度:\{short} vs \{long}",
  )
}

///|
test "查找:匹配/状态与选项开关可构造" {
  let options = {
    ..@mdchrome.MarkdownFindOptions::default(),
    case_sensitive: true,
  }
  let matches = markdown_session_find_matches(
    source="Cat cat CAT",
    query="cat",
    options~,
  )
  assert_eq(matches.length(), 1)
  assert_eq(
    markdown_session_find_status(
      query="cat",
      matches~,
      selection=@richtext.MarkdownEditorSelection::{
        caret: 0,
        selection: None,
      },
      options~,
    ),
    "0/1",
  )
  // 选区与命中重合 → 活动命中为第 1 个
  assert_eq(
    markdown_session_find_status(
      query="cat",
      matches~,
      selection=@richtext.MarkdownEditorSelection::{
        caret: 3,
        selection: Some(matches[0]),
      },
      options~,
    ),
    "1/1",
  )
  let insensitive = markdown_session_find_matches(
    source="Cat cat CAT",
    query="cat",
    options=@mdchrome.MarkdownFindOptions::default(),
  )
  assert_eq(insensitive.length(), 3)
}

///|
test "替换当前命中:事务可 apply,选区跳到下一命中" {
  let source = "cat dog cat"
  let session = @richtext.MarkdownDocumentSession::new(source)
  let options = @mdchrome.MarkdownFindOptions::default()
  // 光标在第 2 个 cat 上（start=8,end=11）→ 替换它
  let selection = @richtext.MarkdownEditorSelection::{
    caret: 11,
    selection: Some(@core.TextRange::new(start=8, end=11)),
  }
  let transaction = match
    markdown_session_replace_current(
      session~,
      selection~,
      query="cat",
      replacement="fox",
      options~,
    ) {
    Some(transaction) => transaction
    None => fail("应有替换事务")
  }
  assert_eq(transaction.source, "cat dog fox")
  let next_session = session.apply(transaction)
  // 替换后光标/选区指向下一命中（环回第 1 个 cat:0-3）
  assert_eq(transaction.selection, Some(@core.TextRange::new(start=0, end=3)))
  assert_eq(next_session.source(), "cat dog fox")
}

///|
test "替换全部:一次重写,选区落在首处理位置" {
  let source = "cat dog cat"
  let session = @richtext.MarkdownDocumentSession::new(source)
  let transaction = match
    markdown_session_replace_all(
      session~,
      query="cat",
      replacement="fox",
      options=@mdchrome.MarkdownFindOptions::default(),
    ) {
    Some(transaction) => transaction
    None => fail("应有全部替换事务")
  }
  assert_eq(transaction.source, "fox dog fox")
  assert_eq(transaction.selection, Some(@core.TextRange::new(start=0, end=3)))
  assert_eq(transaction.caret, 3)
  assert_eq(session.apply(transaction).source(), "fox dog fox")
}

///|
test "无命中或空替换:不产生事务" {
  let session = @richtext.MarkdownDocumentSession::new("cat dog")
  let selection = @richtext.MarkdownEditorSelection::{
    caret: 0,
    selection: None,
  }
  assert_true(
    markdown_session_replace_current(
      session~,
      selection~,
      query="zzz",
      replacement="fox",
      options=@mdchrome.MarkdownFindOptions::default(),
    )
    is None,
  )
}

///|
test "面板转发:查找栏/大纲/文档信息渲染中文文案" {
  let theme = @views.theme()
  let options = @mdchrome.MarkdownFindOptions::default()
  let find_view : @moui.View[Int] = markdown_find_bar_view(
    theme~,
    query="cat",
    replace_text="fox",
    options~,
    status_label="1/1",
    on_query_input=_ => 0,
    on_replace_input=_ => 0,
    on_submit_query=1,
    on_submit_replace=2,
    on_toggle_case_sensitive=3,
    on_toggle_whole_word=4,
    on_toggle_regex=5,
    on_previous=6,
    on_next=7,
    on_replace_current=8,
    on_replace_all=9,
    on_close=10,
    width=1120.0,
  )
  let find_commands = draw_view(find_view, 1120.0, 64.0)
  let mut found_label = false
  for command in find_commands {
    match command {
      @core.DrawText(run) =>
        if run.text.contains("查找") {
          found_label = true
        }
      _ => ()
    }
  }
  assert_true(found_label, msg="查找栏应有中文标签")

  let snapshot = @richtext.MarkdownEditorSnapshot::parse(
    "# 标题一\n\n## 标题二",
  )
  let outline_view : @moui.View[Int] = markdown_outline_panel_view(
    theme~,
    outline=snapshot.outline,
    folded_starts=[],
    caret=0,
    on_jump=_ => 0,
    on_toggle_fold=_ => 0,
    height=480.0,
  )
  let outline_commands = draw_view(outline_view, 240.0, 480.0)
  let info_view : @moui.View[Int] = markdown_document_info_panel_view(
    theme~,
    info=markdown_session_document_info(
      session=@richtext.MarkdownDocumentSession::new(snapshot.source),
    ),
    word_count=snapshot.word_count,
    line_count=snapshot.line_count,
    reading_time_label="<1 min",
    height=480.0,
  )
  let info_commands = draw_view(info_view, 240.0, 480.0)
  let mut outline_title = false
  for command in outline_commands {
    match command {
      @core.DrawText(run) => if run.text == "大纲" { outline_title = true }
      _ => ()
    }
  }
  let mut info_title = false
  for command in info_commands {
    match command {
      @core.DrawText(run) => if run.text == "文档信息" { info_title = true }
      _ => ()
    }
  }
  assert_true(outline_title, msg="大纲面板应有中文标题")
  assert_true(info_title, msg="文档信息面板应有中文标题")
}
