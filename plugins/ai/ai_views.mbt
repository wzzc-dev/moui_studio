///|
/// MoUI Studio AI 域·视图贡献(S4② 出壳,无状态视图先例):纯渲染件,
/// 状态以参数进入,行为以 on_*~ 回调注入。

///|
/// 「查看全部会话 →」：线程多了以后卡片区只能滚动看，给一个直达既有
/// AI 历史对话框的出口（设计稿 `#seeAll`）。宽度按内容算（中英文案差近半）。
pub fn[Msg] see_all_row(
  t : @i18n.Translator,
  width : Double,
  on_toggle~ : Msg,
) -> @moui.View[Msg] {
  let label = t.translate("app.ai.see_all")
  let label_width = (@chrome.text_estimate_width(label) * 1.05 + 20.0).max(64.0)
  @views.container(
    @views.padding_xy(
      @chrome.fill_row(
        [
          @views.spacer(min_length=0.0, weight=1.0),
          @views.container(
            @views.center(
              @views.text(
                label,
                theme=@chrome.studio_theme(),
                width=(label_width - 20.0).max(40.0),
                height=16.0,
              ).foreground(@chrome.ide_accent()),
              width=label_width,
              height=18.0,
            ),
            background=@chrome.ide_panel_alt(),
            corner_radius=4.0,
            width=label_width,
            height=18.0,
            padding=0.0,
          ).on_tap(on_toggle),
        ],
        (width - 16.0).max(120.0),
        4.0,
        Center,
      ),
      horizontal=8.0,
      vertical=1.0,
    ),
    width~,
    height=SEE_ALL_HEIGHT,
    padding=0.0,
  )
}

///|
/// 「查看全部会话 →」行高。
pub const SEE_ALL_HEIGHT : Double = 20.0
