///|
/// AI 决策条（待采纳提案的采纳/拒绝 + 讲解/错误文本）。
///
/// 从 `ide_ai_views.mbt` 拆出（该文件已触 1416 行棘轮）：决策条是**独立
/// 的一段**——「有没有内容 / 渲染什么 / 占多高」三件事自成一体，且与
/// 转录时间线、composer 没有共享状态（只读 `AiViewParams` 的 pending /
/// explanation / prompt_error 三个字段）。
///
/// 高度纪律：`decision_bar_footprint` 是钉底块预算的唯一来源，
/// `ai_docked_height` 从它取——视图与预算两处各算一份就会把输入盒顶出
/// 宿主（`ai_bar_layout_wbtest` 的高度回归钉住这条）。

///|
/// 决策条是否在场：有真内容（待采纳提案 / 讲解 / 错误）才渲染。
pub fn[Msg] has_decision_content(p : AiViewParams[Msg]) -> Bool {
  p.pending is Some(_) || p.explanation != "" || p.prompt_error != ""
}

///|
/// 决策条：待采纳提案摘要 + 采纳/拒绝；无提案时显示讲解/错误文本。
fn[Msg] decision_bar(
  p : AiViewParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  if !has_decision_content(p) {
    return @views.container(
      @views.text("", width=1.0, height=1.0),
      width~,
      height=0.0,
      padding=0.0,
    )
  }
  let rows : Array[@moui.View[Msg]] = []
  match p.pending {
    Some(pending) => {
      rows.push(
        @views.text(
          pending.summary,
          theme=@chrome.studio_theme(),
          width=(width - 16.0).max(60.0),
          height=18.0,
          align=TextStart,
        ).foreground(
          if pending.valid {
            @chrome.ide_success()
          } else {
            @chrome.ide_danger()
          },
        ),
      )
      if !pending.valid {
        for error in pending.errors {
          rows.push(
            @views.text(
              @chrome.fit_label("· \{error}", (width - 24.0).max(60.0)),
              theme=@chrome.studio_theme(),
              width=(width - 16.0).max(60.0),
              height=16.0,
              align=TextStart,
            ).foreground(@chrome.ide_danger()),
          )
        }
      }
      rows.push(
        @chrome.fill_row(
          [
            @chrome.action_chip(
              t.translate("app.ai.accept"),
              p.on_accept,
              @chrome.Primary,
              24.0,
            ),
            @chrome.action_chip(
              t.translate("app.ai.reject"),
              p.on_reject,
              @chrome.Quiet,
              24.0,
            ),
            @chrome.action_chip(
              t.translate("app.ai.history"),
              p.on_toggle_history,
              @chrome.Ghost,
              24.0,
            ),
          ],
          (width - 16.0).max(80.0),
          6.0,
          Center,
        ),
      )
    }
    None => {
      if p.explanation != "" {
        rows.push(
          @views.text(
            p.explanation,
            theme=@chrome.studio_theme(),
            width=(width - 16.0).max(60.0),
            height=54.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_muted()),
        )
      }
      if p.prompt_error != "" {
        rows.push(
          @views.text(
            p.prompt_error,
            theme=@chrome.studio_theme(),
            width=(width - 16.0).max(60.0),
            height=16.0,
            align=TextStart,
          ).foreground(@chrome.ide_danger()),
        )
      }
    }
  }
  @views.container(
    @views.padding_xy(
      @views.column(rows, spacing=4.0).frame(
        width=(width - 16.0).max(80.0),
        height=decision_bar_height(p),
      ),
      horizontal=8.0,
      vertical=6.0,
    ),
    background=@chrome.ide_panel(),
    width~,
    height=decision_bar_height(p) + 12.0,
    padding=0.0,
  )
}

///|
/// 决策条内容高。
pub fn[Msg] decision_bar_height(p : AiViewParams[Msg]) -> Double {
  if !has_decision_content(p) {
    return 0.0
  }
  match p.pending {
    Some(_) => 24.0 + 4.0 + 24.0
    None => {
      let mut height = 0.0
      if p.explanation != "" {
        height = height + 4.0 + 54.0
      }
      if p.prompt_error != "" {
        height = height + 4.0 + 16.0
      }
      height
    }
  }
}
