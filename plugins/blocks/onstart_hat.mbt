///|
/// 启动 hat 行（G7.1.1）：积木视图顶部的窗体级脚本入口。
/// 显示一个「⚡ 启动」胶囊——有 OnStart handler 时高亮并可切换到它，
/// 没有时点击即创建（无需在设计器选中控件）。用户由此可以在积木
/// 视图里直接写纯逻辑程序，不需要依赖设计器的任何控件。
///
/// 从 `app/blocks_pane.mbt` 迁出（该文件已触 1200 行硬上限）：本行与壳
/// Model 只有两个耦合点（有没有 OnStart / 当前选中的是不是它），按
/// 「视图由父组装」投影成参数即可。

///|
pub const ONSTART_HAT_HEIGHT : Double = 28.0

///|
pub(all) struct OnStartHatParams[Msg] {
  /// 程序里已有 OnStart handler（有 → 高亮；无 → 点击即创建）。
  exists : Bool
  /// 当前选中的就是 OnStart（高亮判据）。
  is_active : Bool
  on_select : Msg
  on_create : Msg
}

///|
pub fn[Msg] onstart_hat_row(
  p : OnStartHatParams[Msg],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let label = t.translate("app.blocks.hat.onstart")
  let chip_width = @chrome.text_estimate_width(label) + 32.0
  @views.container(
    @views.row(
      [
        @views.container(
          @views.row(
            [
              @views.text(
                "⚡",
                theme=@chrome.studio_theme(),
                width=16.0,
                height=18.0,
                align=TextCenter,
              ).foreground(
                if p.is_active {
                  @chrome.ide_text()
                } else {
                  @chrome.ide_text_faint()
                },
              ),
              @views.text(
                label,
                theme=@chrome.studio_theme(),
                width=chip_width - 36.0,
                height=18.0,
                align=TextStart,
              ).foreground(
                if p.is_active {
                  @chrome.ide_text()
                } else {
                  @chrome.ide_text_faint()
                },
              ),
            ],
            spacing=4.0,
            align=Center,
          ),
          background=if p.is_active {
            @chrome.ide_selection()
          } else {
            @chrome.ide_panel()
          },
          width=chip_width,
          height=24.0,
          padding=0.0,
        ).on_tap(if p.exists { p.on_select } else { p.on_create }),
      ],
      spacing=0.0,
      align=Start,
    ),
    // hat 行是**定尺**容器：宽由外层列拉伸（`width~` 在壳侧已由窗格给过，
    // 这里不按内容长——胶囊多宽不影响行占多宽），高固定 28。
    height=ONSTART_HAT_HEIGHT,
    padding=0.0,
  )
}
