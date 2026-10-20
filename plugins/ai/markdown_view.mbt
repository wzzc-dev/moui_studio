///|
/// Markdown 块模型 → Studio 视图（M4）：AI 会话卡的 body 用块模型渲染。
///
/// v1 口径（诚实边界，注释即契约）：
/// - 行内片段渲染为**相邻文本视图**（按估宽排一行，超出宿主宽即裁）——
///   不做富文本流式排版；粗体=亮色、斜体=暗色、行内代码=Mono+强调色。
/// - 代码块 = Mono 行列 + 编辑器底色（M6 接高亮服务前先 plain mono）。
/// - 列表项每项一行；标题按级别用字号/角色区分；分隔线 = 发丝线。
/// - `on_copy_code` 非空时代码块带**语言标签 + 复制钮**（块级复制：
///   一次回复产多块代码时，整卡复制会把叙述一起拷走）。

///|
pub fn[Msg] markdown_blocks_view(
  blocks : Array[@markdown.MarkdownBlock],
  width : Double,
  t : @i18n.Translator,
  on_copy_code~ : ((Int32) -> Msg)? = None,
) -> @moui.View[Msg] {
  let rows : Array[@moui.View[Msg]] = []
  // 代码块序号（复制钮按块下标回调；markdown 里代码块的顺序即下标）
  let mut code_index = 0
  let t_default_label = t.translate("app.ai.code.lang_default")
  let t_copy_label = t.translate("app.ai.action.copy_code")
  for block in blocks {
    match block {
      MbHeading(level, text) => {
        let height = match level {
          1 => 28.0
          2 => 24.0
          _ => 20.0
        }
        rows.push(
          @views.text(
            text,
            theme=@chrome.studio_theme(),
            role=if level == 1 { Title } else { Subtitle },
            width=(width - 16.0).max(60.0),
            height~,
          ).foreground(@chrome.ide_text()),
        )
      }
      MbParagraph(pieces) => rows.push(markdown_inline_row(pieces, width))
      MbBulletList(items) =>
        for item in items {
          rows.push(
            @views.row(
              [markdown_inline_row(item, (width - 20.0).max(60.0))],
              spacing=0.0,
              align=Center,
            ).frame(width~, height=18.0),
          )
        }
      MbOrderedList(items) =>
        for item in items {
          rows.push(
            @views.row(
              [markdown_inline_row(item, (width - 20.0).max(60.0))],
              spacing=0.0,
              align=Center,
            ).frame(width~, height=18.0),
          )
        }
      MbCodeBlock(lang, code) => {
        let lines = @code.split_line_texts(code)
        let inner = (width - 24.0).max(60.0)
        // **语言标签行**：``` 后面的语言名（空 = `app.ai.code.lang_default`）。
        // 复制钮在这一行的右端——与语言标签同行的理由是「这个钮作用于
        // 下面这一整块」，分两行会让它看起来作用于别的东西。
        let label = if lang == "" { t_default_label } else { lang }
        let label_row : Array[@moui.View[Msg]] = [
          @views.text(
            @chrome.fit_label(label, inner * 0.6),
            theme=@chrome.studio_theme(),
            role=Caption,
            width=(inner * 0.6).max(40.0),
            height=14.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_faint()),
          @views.spacer(min_length=6.0, weight=1.0),
        ]
        match on_copy_code {
          Some(copy) =>
            label_row.push(
              @chrome.action_chip(
                t_copy_label,
                copy(code_index),
                @chrome.Ghost,
                16.0,
              ),
            )
          None => ()
        }
        rows.push(
          @views.container(
            @chrome.fill_row(label_row, inner, 4.0, Center),
            background=@chrome.ide_panel_alt(),
            corner_radius=4.0,
            width~,
            height=18.0,
            padding=0.0,
          ),
        )
        for line in lines {
          rows.push(
            @views.container(
              @views.padding_edges(
                @views.text(
                  if line == "" {
                    " "
                  } else {
                    // **每行截断**：`@views.text` 的宽是最小值，长行会自己
                    // 长宽越过裁剪区（与 `@chrome.diff_row` 同纪律）。
                    @chrome.fit_label(line, inner)
                  },
                  theme=@chrome.studio_theme(),
                  role=Mono,
                  width=inner,
                  height=16.0,
                  align=TextStart,
                ).foreground(@chrome.code_plain_color()),
                left=8.0,
                right=8.0,
              ),
              background=@chrome.ide_editor_background(),
              width~,
              height=24.0,
              padding=0.0,
            ),
          )
        }
        code_index = code_index + 1
      }
      MbRule => rows.push(@chrome.hairline())
    }
  }
  @views.column(rows, spacing=4.0)
}

///|
/// 行内片段行：相邻文本视图（估宽），样式用颜色/角色区分。
///
/// **行内代码（`MiCode`）渲染成胶囊**（目标图右栏的彩色芯片）：底
/// `ide_panel_alt` + 4pt 圆角 + 强调色字。此前它是「Mono + 强调色」的裸
/// 文本——在一段中文叙述里读不出「这是一块积木/一个名字」。改成一处
/// 渲染，全部 AI 消息与讲解卡同时受益（`CardExplanation` 的 body 与
/// `ai_message_row` 都走这里）。
///
/// 解析侧零改动：`MiCode` 仍是 markdown 的行内代码（反引号），只是画法
/// 从「着色文本」升级成「胶囊」。
fn[Msg] markdown_inline_row(
  pieces : Array[@markdown.MarkdownInline],
  width : Double,
) -> @moui.View[Msg] {
  let cells : Array[@moui.View[Msg]] = []
  for piece in pieces {
    let text = match piece {
      MiText(text) => text
      MiBold(text) => text
      MiItalic(text) => text
      MiCode(text) => text
    }
    let color = match piece {
      MiBold(_) => @chrome.ide_text()
      MiItalic(_) => @chrome.ide_text_muted()
      MiCode(_) => @chrome.ide_accent()
      MiText(_) => @chrome.ide_text()
    }
    let piece_width = @chrome.text_estimate_width(text).max(4.0)
    match piece {
      // 胶囊：底 + 圆角 + 左右各 4pt 内垫（高度与同行文本齐：18）。
      // 宽度按估宽 + 8（内垫）+ 2（圆角处的视觉余量）算——与
      // `@chrome.text_chip` 同口径，不另立一个宽度公式。
      MiCode(_) =>
        cells.push(
          @views.container(
            @views.center(
              @views.text(
                text,
                theme=@chrome.studio_theme(),
                role=Mono,
                width=piece_width,
                height=14.0,
                align=TextCenter,
              ).foreground(color),
              width=piece_width + 8.0,
              height=18.0,
            ),
            background=@chrome.ide_panel_alt(),
            corner_radius=4.0,
            width=piece_width + 10.0,
            height=18.0,
            padding=0.0,
          ),
        )
      _ =>
        cells.push(
          @views.text(
            text,
            theme=@chrome.studio_theme(),
            role=Body,
            width=piece_width,
            height=18.0,
            align=TextStart,
          ).foreground(color),
        )
    }
  }
  @views.row(cells, spacing=0.0, align=Center).frame(width~, height=18.0)
}
