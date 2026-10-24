///|
/// v4 IDE 壳顶层装配：顶栏 / 图标栏 / 左栏 / 中心工作区 / 右栏 /
/// 底栏 / 状态栏 / AI 浮动层 / 对话框与 toast。
///
/// 布局纪律（踩过的坑，逐条注释在对应位置）：
/// 1. 含竖直分隔线的行必须钳高——竖直 divider 按可用高度测量。
/// 2. 交互画布子树不用 .flexible()——加权子树会在 tight 重排下丢手势。
/// 3. 浮动层用 stack + align + offset 绝对摆放，保留带（reserve）按底栏
///    展开态补偿——不做 DOM 式测量（core 没有测量回环）。

///|
/// 顶层视图：壳 + 内容。运行/帮助/预览三个全屏页仍走旧视图（执行与只读
/// 场景不属于工作区编排），其余走 v4 工作区。
pub fn view(model : Model) -> @moui.View[Msg] {
  view_with_viewport(model, default_viewport_size())
}

///|
/// 视口未知时的回退尺寸：1280×800 与两个平台入口一致（macos_skia /
/// web_wasm 都以它开窗）。真实运行走 view_with_viewport，测试与
/// 无环境入口用这个。
pub fn default_viewport_size() -> @core.Size {
  @core.Size::new(width=1280.0, height=800.0)
}

///|
/// 带视口的顶层视图：壳的各列宽/行高都按真实视口算（顶栏铺满、
/// 中心列吃掉剩余宽度、底栏按视口宽铺）。这是 v4 IDE 壳能自适应窗口的
/// 唯一入口——写死 1280 会在别的窗口尺寸下把右侧栏挤出屏幕。
pub fn view_with_viewport(
  model : Model,
  viewport : @core.Size,
) -> @moui.View[Msg] {
  let t = translator(model)
  let width = if viewport.width > 0.0 { viewport.width } else { 1280.0 }
  let height = if viewport.height > 0.0 { viewport.height } else { 800.0 }
  let base = shell_view(model, t, width, height)
  // 命令面板 / 设置 / AI 历史三个模态共用一个 overlay_host（顶层唯一宿主）：
  // 多个宿主会各自维护 layer_stack，Escape 的「最上层优先」就失效了。
  studio_overlay_host(base, model, t).theme(@chrome.studio_theme())
}

///|
/// 壳主体（不含模态）：顶栏 + 内容行 + 底栏 + 状态栏 + AI 层。
fn shell_view(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let fullscreen = match model.mode {
    ModePreview | ModeHelp | ModeRun => true
    _ => false
  }
  // 底栏高：展开时按**内容**算，收起时**整个隐藏**（页签行也隐藏——重开走
  // 标题栏的底栏开关 / J 键 / 命令面板，VS Code 面板口径）。写成「模型里那个
  // 数」会让面板被算成固定高而内容装不下——高度是算出来的，不是存下来的
  // （`bottom_height` 只作为用户拖拽的下限）。
  //
  // AI 输入面**不在底栏**：它只有一个宿主 = 右栏底部（见 `ide_right_panel`）。
  // 旧版在这里按 `bottom_tab is BtAi` 给底栏加高以装下线程卡，那个分支随
  // 底栏 AI 页签一并消失。
  let bottom_height = if model.bottom_open { model.bottom_height } else { 0.0 }
  let window_bar = if model.immersive {
    @chrome.WINDOW_CHROME_HEIGHT - @chrome.TOPBAR_HEIGHT
  } else {
    0.0
  }
  // VS Code 骨架：**活动栏全高贯通左侧**（从窗口顶到状态栏），状态栏
  // 横贯整个底边。右列（顶栏+内容+底栏面板）在活动栏右侧。
  let body_height = (height - @chrome.STATUSBAR_HEIGHT - 1.0).max(200.0)
  let chrome = @chrome.TOPBAR_HEIGHT + bottom_height + window_bar + 2.0
  let content_height = (body_height - chrome).max(200.0)
  let content = if fullscreen {
    // 全屏页（预览/帮助/运行）：两侧栏收起，内容居中占满
    @views.container(
      center_panel(model, t),
      background=@chrome.ide_editor_background(),
      width=(width - @chrome.ICONBAR_WIDTH).max(120.0),
      height=content_height,
      padding=0.0,
    )
  } else {
    // 非全屏的正文在下方 main_col 里装配（工作区 + 底栏面板 + 全高右栏）；
    // 这里只放一个占位，保持 content 类型完整。
    @views.text("", width=1.0, height=1.0)
  }
  // 右列各段高度**全部显式**：顶栏带（沉浸 32 / 普通 40）+ 发丝线 +
  // 内容段 + 底栏面板。`height~` 在这套嵌套里不按剩余空间填充——
  // 实测它会撑到外层 body 高，把底栏面板推出窗口（「点运行没反应」轮次
  // 的 12 个布局回归全是它）。
  let topbar_height = if model.immersive {
    @chrome.WINDOW_CHROME_HEIGHT
  } else {
    @chrome.TOPBAR_HEIGHT
  }
  let side_width = (width - @chrome.ICONBAR_WIDTH).max(120.0)
  let lower_height = (body_height - topbar_height - 1.0).max(200.0)
  let pane_height = (lower_height - bottom_height).max(200.0)
  // VS Code 骨架第三轮：**左栏也全高**（顶栏之下直抵状态栏），底栏面板
  // 只铺中心列（左缘 = 左栏右缘，右缘 = 右栏左缘）。lower_row 从左到右：
  // [左栏全高段 | 竖发丝线 | 中心列(工作区+底栏面板) | 竖发丝线 | 右栏全高段]。
  // AI 停靠时右栏段顶上 340 是 AI 卡。
  let chrome_widths = shell_chrome_widths(model, side_width)
  let center_width = chrome_widths.center
  let workspace_seg = if fullscreen {
    content
  } else {
    @views.container(
      workspace_content(model, t, center_width, pane_height),
      background=@chrome.ide_editor_background(),
      width=center_width,
      height=pane_height,
      padding=0.0,
    )
  }
  // 底栏高度拖拽 sash（M8 用户反馈③）：拖动条映射为 SetBottomHeight
  //（拖到哪栏顶就到哪，绝对映射；视图层按窗口高度钳制，update 兜底）
  // 收起态连拖拽手柄一起隐藏（没有可调的东西;重开走标题栏开关）
  let bottom_sash = if model.bottom_open {
    @views.container(
      @views.empty(),
      background=@chrome.ide_border_soft(),
      width~,
      height=@chrome.SASH_WIDTH,
      padding=0.0,
    ).on_drag_with_frame(fn(event, _frame) {
      match event.phase {
        @views.DragGesturePhase::Started | @views.DragGesturePhase::Changed =>
          Msg::SetBottomHeight(
            (height - event.position.y).clamp(min=100.0, max=1200.0),
          )
        _ => Msg::Noop
      }
    })
  } else {
    // 收起态:零高手柄（无可调对象）
    @views.container(@views.empty(), width~, height=0.0, padding=0.0)
  }
  let main_col = @views.column(
    [
      // **结构行子元素全部显式 key**(P1 根因修复):这些格子随工作台
      // 形态增删(组合 = 左栏+中心+底栏;积木/设计台 = 无左栏)。无键
      // 同 kind 容器按「下标+kind」复用,成员一变就整体错位一格——左栏
      // 面板被 main_col 复用、右栏被旧中心复用,幽灵子树与黑区并存
      // (真机:积木台态右栏/底栏/状态条不绘制)。key 让 reconcile 按
      // 身份匹配,增删各自成 remover/mounter。
      workspace_seg.key("shell-workspace"),
      bottom_sash.key("shell-bottom-sash"),
      // 底栏宽度跟随 main_col：全屏页（运行/预览/帮助）没有左右栏，
      // 若仍用 `center_width`（按「左栏+右栏都在」分配的宽），底栏只铺
      // 左半段，右侧留一条空白（实测运行页 AI 栏右侧全空）。
      ide_bottom_bar(
        model,
        t,
        if fullscreen {
          side_width
        } else {
          center_width
        },
        bottom_height,
      ).key("shell-bottom-bar"),
    ],
    spacing=0.0,
  ).frame(
    width=if fullscreen { side_width } else { center_width },
    height=lower_height,
  )
  let lower_cells : Array[@moui.View[Msg]] = []
  // sash 拖拽的宽度界限：**另一侧面板 + 两条 sash + 中心下限**之外都是
  // 自己的余量。界限在视图构建期算好闭进闭包（拖拽期间窗口不变，界限
  // 是常量），update 只兜底夹静态界限。
  let left_drag_max = (side_width -
    (if chrome_widths.right > 0.0 {
      chrome_widths.right + @chrome.SASH_WIDTH
    } else {
      0.0
    }) -
    320.0)
    .max(@chrome.LEFTBAR_MIN_WIDTH)
    .min(@chrome.LEFTBAR_MAX_WIDTH)
  let right_drag_max = (side_width -
    (match chrome_widths.left {
      Some(left_width) => left_width + @chrome.SASH_WIDTH
      None => 0.0
    }) -
    320.0)
    .max(@chrome.RIGHTBAR_MIN_WIDTH)
    .min(@chrome.RIGHTBAR_MAX_WIDTH)
  if !fullscreen {
    match chrome_widths.left {
      Some(left_width) => {
        lower_cells.push(
          ide_left_panel(model, t, left_width, lower_height).key(
            "shell-left-panel",
          ),
        )
        lower_cells.push(
          v_sash(
            fn(x) {
              ResizeLeftPanel(
                (x - @chrome.ICONBAR_WIDTH - @chrome.SASH_WIDTH / 2.0).clamp(
                  min=@chrome.LEFTBAR_MIN_WIDTH,
                  max=left_drag_max,
                ),
              )
            },
            lower_height,
          ).key("shell-left-sash"),
        )
      }
      None => ()
    }
  }
  lower_cells.push(main_col.key("shell-main-col"))
  if !fullscreen && chrome_widths.right > 0.0 {
    lower_cells.push(
      v_sash(
        fn(x) {
          ResizeRightPanel(
            (width - x - @chrome.SASH_WIDTH / 2.0).clamp(
              min=@chrome.RIGHTBAR_MIN_WIDTH,
              max=right_drag_max,
            ),
          )
        },
        lower_height,
      ).key("shell-right-sash"),
    )
    // 右列只有两个宿主：AI 工作台模式（PsAi）= 更改/文件双页签面板；
    // 其余 = 检查器 + 钉底 composer（VS Code 侧面板口径，见
    // `ide_right_panel`）。AI 输入面**只有一个家**——右栏底部；底栏不再
    // 承载它，也就不再需要「停靠右栏 / 放到底栏」这对互为出口的切换钮。
    lower_cells.push(
      (if model.right_view is RvWorkspace {
        ai_workspace_panel(model, t, chrome_widths.right, lower_height)
      } else {
        ide_right_panel(model, t, chrome_widths.right, lower_height)
      }).key("shell-right-panel"),
    )
  }
  let lower_row = @views.row(lower_cells, spacing=0.0, align=Stretch).frame(
    width=side_width,
    height=lower_height,
  )
  let right_side = @views.column(
    [ide_top_bar(model, t, side_width), @chrome.hairline(), lower_row],
    spacing=0.0,
  ).frame(width=side_width, height=body_height)
  // VS Code 骨架终稿：**活动栏通到窗口最底边**（状态栏不再从它下方穿过，
  // 设置图标随之贴住窗口底边）；**状态栏从活动栏右缘铺到窗口右缘**，
  // 其上发丝线同样止于活动栏右缘——左缘即活动栏，无空隙。
  @views.container(
    @views.row(
      [
        ide_icon_bar(model, t, height),
        @views.column(
          [right_side, @chrome.hairline(), ide_status_bar(model, t, side_width)],
          spacing=0.0,
        ).frame(width=side_width, height~),
      ],
      spacing=0.0,
      align=Stretch,
    ).frame(width~, height~),
    background=@chrome.studio_window_background(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 竖直 sash：三列之间**可拖拽的分隔区**（VS Code 口径）。
///
/// - 视觉：`@chrome.SASH_WIDTH`（4pt）的竖带，底色 `@chrome.ide_border_soft`——比两侧
///   面板略亮一档，读作「这里是分隔」，又不抢过发丝线的克制。
/// - 交互：拖拽把指针 x 经 `on_drag_x` 换算成目标宽度（界限由调用方
///   闭包夹取）。**绝对映射**——指针在哪面板就到哪，不需要拖拽起点状态，
///   来回拖也不会漂。
/// - 捕获：拖拽激活期手势持有指针捕获（runtime 对捕获元素在指针出界时
///   照常派发），所以 sash 自己随面板移动也不丢事件——与积木画布拖拽
///   同一机制。
fn v_sash(on_drag_x : (Double) -> Msg, height : Double) -> @moui.View[Msg] {
  @views.container(
    @views.empty(),
    background=@chrome.ide_border_soft(),
    width=@chrome.SASH_WIDTH,
    height~,
    padding=0.0,
  ).on_drag_with_frame(fn(event, _frame) {
    match event.phase {
      @views.DragGesturePhase::Started | @views.DragGesturePhase::Changed =>
        on_drag_x(event.position.x)
      _ => Msg::Noop
    }
  })
}

///|
/// 三列宽度：窗口宽 − 图标栏后由左/中/右分配。
pub(all) struct ShellChromeWidths {
  left : Double?
  center : Double
  /// 右栏宽。`0.0` 表示右栏收起（不占宽、不画分隔线）。
  right : Double
}

///|
/// 三列宽度分配。**左/右栏宽度是用户可调的**（列间 sash 拖拽，存
/// `model.left_width`/`right_width`，默认 = LEFTBAR/@chrome.RIGHTBAR_WIDTH）；
/// 中心列吃剩余。分隔区是 4pt 的 sash（`@chrome.SASH_WIDTH`），预算按它显式扣。
///
/// 中心列有 320 的下限（三工作区都在这个宽度下仍然可用）。当用户宽度
/// + 中心下限放不下时（窗口太小），**右栏紧急收缩到 232**、仍不够则
/// **左栏让位**（返回 None）——与旧的设计稿定宽行为同构，只是把定宽
/// 换成了用户可调宽。`right` 返回 0.0 有两种来源（用户收起 / 让位），
/// 调用方不必区分。
fn shell_chrome_widths(model : Model, width : Double) -> ShellChromeWidths {
  // `width` = 活动栏右侧的可用宽（调用方已扣除活动栏）。
  let sash = @chrome.SASH_WIDTH
  let usable = width.max(120.0)
  let center_min = 320.0
  let wants_left = !(model.left_view is LeftHidden)
  let wants_right = !(model.right_view is RvHidden)
  let left_want = model.left_width.clamp(
    min=@chrome.LEFTBAR_MIN_WIDTH,
    max=@chrome.LEFTBAR_MAX_WIDTH,
  )
  let right_want = model.right_width.clamp(
    min=@chrome.RIGHTBAR_MIN_WIDTH,
    max=@chrome.RIGHTBAR_MAX_WIDTH,
  )
  if !wants_right {
    // 右栏收起：中心吃满「可用 − 左栏 − 左 sash」
    let left_room = if wants_left { left_want + sash } else { 0.0 }
    return ShellChromeWidths::{
      left: if wants_left {
        Some(left_want)
      } else {
        None
      },
      center: (usable - left_room).max(center_min),
      right: 0.0,
    }
  }
  if usable >= left_want + right_want + sash * 2.0 + center_min {
    // 宽窗口：用户的宽度原样生效，中心吃剩余
    ShellChromeWidths::{
      left: if wants_left {
        Some(left_want)
      } else {
        None
      },
      center: usable -
      (if wants_left { left_want + sash } else { 0.0 }) -
      right_want -
      sash,
      right: right_want,
    }
  } else {
    // 窄窗口紧急收缩：右栏压到 232（仍放得下 5 个页签与读数），中心吃
    // 剩下的；再不够左栏让位。
    let right_shrunk = right_want.min(232.0).max(170.0)
    let room = usable - right_shrunk - sash
    let needed_left = left_want + sash
    if wants_left && room >= needed_left + center_min {
      ShellChromeWidths::{
        left: Some(left_want),
        center: room - needed_left,
        right: right_shrunk,
      }
    } else {
      // 左栏让位：中心拿满「可用 − 右栏 − sash」
      ShellChromeWidths::{
        left: None,
        center: (usable - right_shrunk - sash).max(center_min),
        right: right_shrunk,
      }
    }
  }
}

///|
/// 中心内容：统一编辑区（全局文档 tab + provider 渲染）。
///
/// M3 起中心不再由透视直接分派：PSDesign/PsBlocks/预览/代码都只是常驻
/// Studio 文档的 provider，文件文档则由 `file.markdown` / `file.text`
/// 认领。AI 模式仍独占中心（会话流），文件 tab 在该模式下隐藏但状态保留。
fn workspace_content(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  if model.perspective is PsAi {
    return ai_center(model, t, width, height)
  }
  @wb.editor_area(
    model.workbench,
    { model, t, },
    editor_providers(),
    preferred_provider(model),
    msg => WorkbenchOp(msg),
    SaveProjectFile,
    width,
    height,
  )
}

///|
/// 页签行高：与面板头同节奏（30pt），单独一个常量——高度预算只有一处来源。
pub const RIGHT_TAB_HEIGHT : Double = 30.0

///|
/// 右栏主体（VS Code 侧栏形态，**分页**）。
///
/// 两页共用一个 30pt 面板头（页块切换器 + 动作簇，见 `context_head`），正文
/// 各归其位：
///
/// - `RvContext`（检查器页）：页签行 30 + 单一滚动区（对象条 / 积木编辑卡 /
///   当前页签 / 快速操作 / 运行时监视）。**没有钉底块**——分页的意义正在于此：
///   检查器不必为聊天让出 148pt。
/// - `RvAi`（AI 页）：会话转录 + 钉底输入卡（`ai_page` 自己算高度）。
/// - `RvWorkspace` 由 `ide_root` 的调用方分派给 `ai_workspace_panel`
///   （那是另一个产品面，不属侧栏分页体系）。
///
/// 列必须显式定尺，否则容器盒会把整列居中（右栏头会掉到中间）。
///
/// AI 插件被禁用（教学版 profile / G7.3 插件管理）时 AI 页整块不存在：
/// 页块不画、`RvAi` 被 `normalize_disabled_plugins` 归一化回检查器页——
/// 与活动栏 AI 模式、底栏终端页签走同一条「能力缺席就不留空页」的纪律。
pub fn ide_right_panel(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let head = context_head(model, t, width)
  if model.right_view is RvAi {
    return @views.container(
      @views.column(
        [head, ai_page(model, t, width, height - @chrome.PANEL_HEAD_HEIGHT)],
        spacing=0.0,
      ).frame(width~, height~),
      background=@chrome.ide_panel(),
      width~,
      height~,
      padding=0.0,
    )
  }
  let tabs = context_tabs(model, t, width)
  let body_height = (height - @chrome.PANEL_HEAD_HEIGHT - RIGHT_TAB_HEIGHT).max(
    100.0,
  )
  @views.container(
    @views.column(
      [
        head,
        tabs,
        @views.container(
          @views.scroll_view(
            context_sections(model, t, width),
            width~,
            height=body_height,
            shows_indicator=true,
          ),
          background=@chrome.ide_panel(),
          width~,
          height=body_height,
          padding=0.0,
        ),
      ],
      spacing=0.0,
    ).frame(width~, height~),
    background=@chrome.ide_panel(),
    width~,
    height~,
    padding=0.0,
  )
}

///|
/// 检查器页正文分区序列（单一滚动区的内容）。顺序即优先级：
///
/// 1. **对象条**（`object_strip`）——身份与「清空选中」的出口。分页后它从
///    面板头下移到正文首段：头部最右端是「关闭整个右栏」的 ✕（2026-09-30
///    事故的修正结论），而头部还要放页块切换器，两件事不能挤在一起。
/// 2. **积木编辑卡**（仅当有选中积木）——「当前选中积木」的编辑面，与下面
///    几个「当前选中控件」的切面是两个对象，所以不做成第七个页签（页签是
///    同一对象的不同切面），而是常驻在正文里——选中积木时立刻可见、无需再点。
/// 3. **当前页签内容**——不加分区头：页签行已经是它的标签（VS Code 的视图
///    切换器下方也不重复一行同名标题）。
/// 4. **快速操作** / 5. **运行时监视**——面板级固定块改成的分区。
///
/// **AI 会话已不在这一页**：转录归 AI 页（`ai_page`）。检查器因此不再被聊天
/// 内容整体下移，「有 AI 内容时检查器变形」的旧形态一并消失。
fn context_sections(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let sections : Array[@moui.View[Msg]] = [object_strip(model, t, width)]
  match context_block_editor(model, t, width) {
    Some(editor) => sections.push(editor)
    None => ()
  }
  sections.push(
    match model.ctx_tab {
      CtxProps => context_props(model, t, width)
      CtxState => context_state(model, t, width)
      CtxData => context_data(model, t, width)
      CtxActions => context_actions(model, t, width)
      CtxDeps => context_deps(model, t, width)
      CtxRuntime => context_runtime(model, t, width)
    },
  )
  sections.push(quick_actions(model, t, width))
  sections.push(watch_pane(model, t, width))
  @views.column(sections, spacing=0.0)
}

///|
/// 模态宿主：命令面板 / 设置 / AI 历史。
/// 三个都是 Modal + Dialog：Dialog 自动居中，Modal 给遮罩与背景语义隐藏，
/// Escape/点击外部由 dismiss.message 收敛回各自的开关键。
fn studio_overlay_host(
  base : @moui.View[Msg],
  model : Model,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let specs : Array[@views.PresentationSpec[Msg]] = [
    @views.PresentationSpec::new(
      id="studio-command-palette",
      kind=@views.PresentationKind::Dialog,
      content=command_palette_dialog(model, t),
      modality=@views.PresentationModality::Modal,
      dismiss=@views.PresentationDismissPolicy::new(
        outside_tap=true,
        message=Some(CommandPaletteClose),
      ),
      presented=model.command_palette_open,
    ),
    @views.PresentationSpec::new(
      id="studio-settings",
      kind=@views.PresentationKind::Dialog,
      content=settings_dialog(model, t),
      modality=@views.PresentationModality::Modal,
      dismiss=@views.PresentationDismissPolicy::new(
        outside_tap=true,
        message=Some(AiUiOp(@ai.ToggleSettings)),
      ),
      presented=model.ai_ui.settings_open,
    ),
    @views.PresentationSpec::new(
      id="studio-ai-history",
      kind=@views.PresentationKind::Dialog,
      content=ai_history_dialog(model, t),
      modality=@views.PresentationModality::Modal,
      dismiss=@views.PresentationDismissPolicy::new(
        outside_tap=true,
        message=Some(AiUiOp(@ai.ToggleAiHistory)),
      ),
      presented=model.ai_ui.ai_history_open,
    ),
    // **积木右键菜单**：挂在**顶层**宿主上（viewport 大小），而不是画布
    // 窗格里。
    //
    // 为什么必须在顶层：菜单要「点别处关闭」，而关闭靠的是浮层屏障接住
    // 菜单之外的按下。屏障的覆盖范围 = 宿主的范围——挂在窗格里就只有窗格
    // 那么大（实测 233×536），在窗口其它地方点根本到不了屏障，菜单
    // **永远不消失**。顶层宿主铺满视口，屏障才盖得住整个窗口。
    //
    // 锚点用 `block_menu` 里存的**视口坐标**（右键点），所以菜单弹在指针处。
    @views.PresentationSpec::new(
      id="studio-block-menu",
      kind=@views.PresentationKind::ContextMenu,
      content=block_context_menu(model, t),
      anchor=match model.blocks_ui.block_menu {
        Some((_, x, y)) =>
          @views.PresentationAnchor::Viewport(@core.Point::new(x~, y~))
        None => @views.PresentationAnchor::HostBase
      },
      placement=Some(
        @views.PresentationPlacement::new(
          // 候选顺序 = 右键菜单的方向偏好。锚点是**零尺寸**的指针点，
          // `…End` 会把菜单**右缘**对齐到指针（向左展开）、`…Start` 把
          // **左缘**对齐到指针（向右展开）。此前 BelowEnd 打头，菜单
          // 永远向左弹（用户报的缺陷）；成熟菜单（macOS/Windows/Scratch）
          // 的主方向都是「向右下展开」，仅在视口边缘翻转：
          // 先右下 → 右上（贴底时）→ 左下（贴右缘时）→ 左上（角落）。
          candidates=[
            @views.PresentationPlacementCandidate::BelowStart,
            @views.PresentationPlacementCandidate::AboveStart,
            @views.PresentationPlacementCandidate::BelowEnd,
            @views.PresentationPlacementCandidate::AboveEnd,
          ],
          viewport_insets=@core.Insets::all(8.0),
        ),
      ),
      dismiss=@views.PresentationDismissPolicy::new(
        outside_tap=true,
        escape=true,
        message=Some(BlocksUiOp(@blk.BlocksContextMenuClose)),
      ),
      presented=model.blocks_ui.block_menu is Some(_),
    ),
    // 破坏性操作确认卡：Escape / 点外部 = 取消（confirm.mbt 纪律）。
    @views.PresentationSpec::new(
      id="studio-confirm",
      kind=@views.PresentationKind::Dialog,
      content=confirm_dialog(model, t),
      modality=@views.PresentationModality::Modal,
      dismiss=@views.PresentationDismissPolicy::new(
        outside_tap=true,
        message=Some(ConfirmDismissed),
      ),
      presented=model.pending_confirm is Some(_),
    ),
  ]
  // toast 单独一层（非模态，最上层）：它不该拦输入，也不参与 Escape 顺序
  let with_modals = @views.overlay_host(base, specs)
  toast_host(with_modals, model)
}

///|
/// AI 工作区面板壳薄包装（S4c 出壳）：纯视图在 @ai 插件，这里把右栏状态
/// 投影成参数，把工程树视图作为「文件」页签插槽注入。
fn ai_workspace_panel(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let inner = (width - 8.0).max(80.0)
  let tab_h = (height - @ai.AI_WS_HEAD_HEIGHT).max(80.0)
  let files_view = @views.container(
    project_explorer(model, t, inner, tab_h),
    width=inner,
    padding=0.0,
  )
  let pending = match model.pending {
    Some(prop) => Some((prop.summary, prop.diff))
    None => None
  }
  @ai.ai_workspace_panel(
    {
      show_changes: model.ai_ui.right_panel_tab is RpChanges,
      history: model.ai_sessions.current().proposal_history,
      pending,
      files_view,
      on_select_changes: AiUiOp(@ai.SetRightPanelTab(RpChanges)),
      on_select_files: AiUiOp(@ai.SetRightPanelTab(RpFiles)),
      on_accept: AcceptProposal,
      on_reject: RejectProposal,
    },
    t,
    width,
    height,
  )
}
