/// v4 IDE 壳控件库：顶栏、图标栏、面板头、树行、徽标、分段控件、状态栏、
/// toast。全部是 @views 既有控件的组合（不新增 core 视觉枚举），
/// 样式一律取 theme.mbt 的 IDE 角色色。
///
/// 尺寸口径来自设计稿：顶栏 40 / 图标栏 48 / 面板头 30 / 树行 24 /
/// 状态栏 22 / 输入 26。行高是硬编码的（IDE 壳不做响应式缩排）。

// ============================================================================
// 尺寸常量（设计稿口径，集中一处便于比对）
// ============================================================================

///|
/// 图标按钮：图标栏与工具条共用。选中态用强调色弱底 + 强调色图标。
/// 无 hover 回调（core 只暴露 hovered 状态给节点），所以只有「选中/未选中」
/// 两态——设计稿的悬停底色由内置按钮的 Ghost 样式自然给出。
/// `tile`：是否画**常驻选中底块**。活动栏走紧凑口径（裸字形，选中只有
/// 字形亮度一层）时传 `false`；面板头等工具条按钮保持默认的底块两态。
pub fn icon_button(
  icon : @style.IconName,
  tip : String,
  selected : Bool,
  on_click : Msg,
  width : Double,
  height : Double,
  icon_size : Double,
  tile? : Bool = true,
  hovered? : String = "",
) -> @moui.View[Msg] {
  // VS Code 活动栏口径：选中 = **深灰微高亮底 + 白色字形**（不是蓝底蓝字
  // ——蓝色块连排是「不协调」的主因）；未选中 = 灰字形裸露（底色与所在
  // 表面同色，即视觉透明）。`tile=false` 时选中也不画底块（颜色两态保留：
  // 亮字 = 活动态）。
  let tint = if selected {
    @chrome.ide_text()
  } else {
    @chrome.ide_text_muted()
  }
  let button = @views.container(
      @views.center(
        @views.icon(icon, size=icon_size, color=tint),
        width=width - 8.0,
        height=height - 8.0,
      ),
      background=if selected && tile {
        @chrome.ide_hover()
      } else {
        @chrome.ide_panel()
      },
      corner_radius=4.0,
      width~,
      height~,
      padding=0.0,
    )
    .accessibility_label(tip)
    // 悬停把说明写进状态栏（一站式提示）；同时在指针处弹框架浮层 tooltip。
    // tooltip 需调用方持有 visible 状态：`hovered` 由组合根传 `model.hover_hint`，
    // 与 `on_hover` 写状态同源——同一时刻只有被悬停的那个按钮可见。
    .on_hover(active => HoverHint(if active { tip } else { "" }))
    .on_tap(on_click)
  @views.tooltip(
    button,
    tip,
    visible=tip != "" && hovered == tip,
    theme=@chrome.studio_theme(),
  )
}

///|
/// Ghost 图标按钮：透明底（融入所在表面），选中态才点亮——现代 AI 面板
/// 的头部口径（Codex/ZCode）：标题行不留一排「小方块」，操作都在安静处。
/// `surface` 是所在表面的底色（ghost 态与它同色 = 视觉透明）。
pub fn ghost_icon_button(
  icon : @style.IconName,
  tip : String,
  selected : Bool,
  on_click : Msg,
  width : Double,
  height : Double,
  icon_size : Double,
  surface : @core.Color,
  hovered? : String = "",
) -> @moui.View[Msg] {
  let button = @views.container(
      @views.center(
        @views.icon(
          icon,
          size=icon_size,
          color=if selected {
            @chrome.ide_accent()
          } else if tip == "" {
            @chrome.ide_text_faint()
          } else {
            @chrome.ide_text_muted()
          },
        ),
        width~,
        height~,
      ),
      background=if selected { @chrome.ide_selection() } else { surface },
      corner_radius=6.0,
      width~,
      height~,
      padding=0.0,
    )
    .accessibility_label(tip)
    // 悬停把说明写进状态栏 + 指针处弹框架 tooltip（与 icon_button 同口径：
    // `hovered` 由组合根传 `model.hover_hint`，同一时刻只有被悬停者可见）。
    .on_hover(active => HoverHint(if active { tip } else { "" }))
    .on_tap(on_click)
  @views.tooltip(
    button,
    tip,
    visible=tip != "" && hovered == tip,
    theme=@chrome.studio_theme(),
  )
}

///|
/// 带键盘快捷键的图标按钮（撤销/重做这类「必须有键位」的动作）。
///
/// **为什么不用 `icon_button` + `.keyboard_shortcut(...)`**：runtime 的
/// 快捷键通路匹配后走的是 `activate_primary` → 给第一个子节点合成一个
/// **Enter 键盘事件**（`input_keyboard.mbt`），而 `on_tap` 只认 Pointer
/// 事件（`modifier_event.mbt` 的 `OnTapModifier` 分支）。所以
/// `keyboard_shortcut` 套在 `on_tap` 外壳上**永远不会触发**。
/// 这里改用真正的 `@views.button`——它的 event 分支显式处理
/// `Enter`/`Space`（`views/button/button.mbt`），是唯一对合成事件有反应的载体；
/// 图标盒由外层容器画，视觉与 `icon_button` 一致。
///
/// 快捷键徽标不进顶栏（24pt 高度放不下），键位在命令面板与快捷键表可见
/// ——IDEA 的口径也是标题栏图标不挂徽标。
pub fn shortcut_icon_button(
  icon : @style.IconName,
  tip : String,
  on_click : Msg,
  shortcut : @core.KeyboardShortcut,
  width : Double,
  height : Double,
  icon_size : Double,
  alt_shortcut? : @core.KeyboardShortcut? = None,
) -> @moui.View[Msg] {
  @views.stack([
    @views.container(
      @views.center(
        @views.icon(icon, size=icon_size, color=@chrome.ide_text_muted()),
        width~,
        height~,
      ),
      background=@chrome.ide_panel_alt(),
      corner_radius=4.0,
      width~,
      height~,
      padding=0.0,
    ),
    shortcut_button_shell(on_click, shortcut, alt_shortcut, width, height),
  ]).accessibility_label(tip)
}

///|
/// 快捷键按钮的载体：`@views.button`（唯一对合成 Enter 有反应的控件）+
/// 一条或两条 shortcut 链。两条覆盖 meta（macOS）与 control（Windows/Linux）。
fn shortcut_button_shell(
  on_click : Msg,
  shortcut : @core.KeyboardShortcut,
  alt_shortcut : @core.KeyboardShortcut?,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let base = @views.button(
    "",
    on_click~,
    variant=Ghost,
    theme=@chrome.studio_theme(),
    width~,
    height~,
  ).keyboard_shortcut(shortcut)
  match alt_shortcut {
    Some(alt) => base.keyboard_shortcut(alt)
    None => base
  }
}

///|
/// 圆形主行动按钮（发送）：实心强调色圆 + 箭头图标——Codex/ZCode 输入盒
/// 的收尾形态。`enabled=false` 时降为面板色 + 弱图标（忙碌态）。
pub fn round_send_button(
  tip : String,
  on_click : Msg,
  enabled : Bool,
  size : Double,
) -> @moui.View[Msg] {
  @views.container(
    @views.center(
      @views.icon(
        ArrowRight,
        size=(size - 12.0).max(10.0),
        color=if enabled {
          @chrome.studio_theme().palette.on_primary
        } else {
          @chrome.ide_text_faint()
        },
      ),
      width=size,
      height=size,
    ),
    background=if enabled {
      @chrome.ide_accent()
    } else {
      @chrome.ide_elevated()
    },
    corner_radius=size / 2.0,
    width=size,
    height=size,
    padding=0.0,
  )
  .accessibility_label(tip)
  .on_tap(on_click)
}

///|
/// 顶栏动作芯片：24pt 高、13pt 字。`primary` 是唯一主行动作（运行）——
/// 强调色填充；其余保持安静的面板二档底。`on_click` 为 None 时是禁用态
/// （弱文字、不可点）——诚实地表达「此动作当前不可用」而不是藏起来。
pub fn topbar_action(
  label : String,
  on_click : Msg?,
  primary : Bool,
  width : Double,
) -> @moui.View[Msg] {
  let enabled = on_click is Some(_)
  @views.container(
    @views.center(
      @views.text(
        label,
        theme=@chrome.studio_theme(),
        role=Caption,
        width=(width - 20.0).max(20.0),
        height=14.0,
      ).foreground(
        if primary {
          @chrome.studio_theme().palette.on_primary
        } else if enabled {
          @chrome.ide_text()
        } else {
          @chrome.ide_text_faint()
        },
      ),
      width~,
      height=@chrome.TOPBAR_ACTION_HEIGHT,
    ),
    background=if primary && enabled {
      @chrome.ide_accent()
    } else {
      @chrome.ide_panel_alt()
    },
    corner_radius=4.0,
    width~,
    height=@chrome.TOPBAR_ACTION_HEIGHT,
    padding=0.0,
  )
  .accessibility_label(label)
  .on_tap_with_frame(fn(_point, _frame) {
    match on_click {
      Some(message) => message
      None => Msg::Noop
    }
  })
}
