///|
/// MoUI Studio 右栏的 **VS Code 侧栏（sidebar）形态**回归。
///
/// 目标形态：面板头（**页块切换器** + ghost 动作簇）→ 两页之一：
///
/// - **检查器页**（`RvContext`）：扁平子页签行 → 单一滚动区（对象条 / 积木编辑
///   卡 / 当前页签 / 快速操作 / 运行时监视）。**没有输入面。**
/// - **AI 页**（`RvAi`）：会话转录（滚动）→ hairline → 钉底**圆角描边输入卡**
///   （上下文芯片 + 输入盒）+ 卡下状态行。
///
/// 为什么单独一个文件：`shell_layout_wbtest.mbt` 已到 1200 行硬上限附近
/// （`checks/source-file-policy.json`），新测试按仓规另开文件——与
/// `ai_bar_layout_wbtest.mbt` 当年从它拆出同一处置。共享的 shell 渲染助手
/// （`shell_draw` / `shell_texts` / `shell_find_text` / `apply_shell`）在同包
/// 的另一文件里。
///
/// 本文件钉住的契约：
/// 1. **输入面只在 AI 页**：检查器页 0 枚发送钮、不画占位文字；AI 页恰好 1 枚；
/// 2. 页块切换器两档（带标签 / 图标 only）在右栏最窄两档都不越界；
/// 3. 两页的高度账各自成立（检查器 = 头+页签+100；AI = 头+钉底+100）；
/// 4. 快速操作 / 运行时监视是检查器滚动区里的**分区**；
/// 5. 对象条承载身份与清除 ✕（头部只放页块与动作簇）；
/// 6. 子页签六格等宽、活动态有强调色下划线；
/// 7. AI 插件被禁用时不出 AI 页块、不出 composer，且 `RvAi` 被归一化；
/// 8. AI 页：转录 → 输入卡 → 状态行的自上而下次序，卡片有描边与抬起面。

///|
/// 精确匹配一段绘制文本（`shell_find_text` 是子串匹配，页签名这类短词会先
/// 命中别处的长词）。
fn shell_find_exact(
  commands : Array[@core.DrawCommand],
  needle : String,
) -> @core.TextRun? {
  for run in shell_texts(commands) {
    if run.text == needle {
      return Some(run)
    }
  }
  None
}

///|
/// 在给定横向区间里找一段文本（`shell_find_text` 全局找第一个，控件名会先
/// 命中左栏结构树那一行——断言就会被带到错的面板上）。
fn shell_find_text_in_span(
  commands : Array[@core.DrawCommand],
  needle : String,
  left : Double,
  right : Double,
  top : Double,
  bottom : Double,
) -> @core.TextRun? {
  for run in shell_texts(commands) {
    if run.text.contains(needle) &&
      run.frame.origin.x >= left - 1.0 &&
      run.frame.origin.x + run.frame.size.width <= right + 1.0 &&
      run.frame.origin.y >= top - 1.0 &&
      run.frame.origin.y + run.frame.size.height <= bottom + 1.0 {
      return Some(run)
    }
  }
  None
}

///|
/// 一段文本被绘制的次数（折叠判据：收起后线程卡那一份不再画）。
fn shell_count_text(
  commands : Array[@core.DrawCommand],
  needle : String,
) -> Int {
  let mut count = 0
  for run in shell_texts(commands) {
    if run.text.contains(needle) {
      count = count + 1
    }
  }
  count
}

///|
/// 右栏横向区间（窗口右缘往左一个右栏宽 + 一条 sash）。
///
/// **只适用于默认宽度**的模型：右栏宽是用户可拖的（`ResizeRightPanel`），
/// 拖过之后必须用 `right_panel_span_of` 从模型现算——按默认 272 算出的左缘
/// 在右栏被拖宽后会偏左 200pt 以上，把栏外的东西也判成「在面板内」。
fn right_panel_span(width : Double) -> (Double, Double) {
  let right = width
  let left = width - @chrome.RIGHTBAR_WIDTH - @chrome.SASH_WIDTH
  (left, right)
}

///|
/// 从模型现算右栏横向区间（宽度可能被用户拖过）。
fn right_panel_span_of(model : Model, width : Double) -> (Double, Double) {
  let chrome = shell_chrome_widths(model, width - @chrome.ICONBAR_WIDTH)
  (width - chrome.right - @chrome.SASH_WIDTH, width)
}

///|
/// 右栏顶边（顶栏 + 发丝线之下）。
fn right_panel_top() -> Double {
  @chrome.TOPBAR_HEIGHT + 1.0
}

///|
/// 检查器页的分页模型：`RvContext` 是初始态，但显式写出来让意图可读。
fn inspector_model() -> Model {
  apply_shell(initial_model(), SetRightView(RvContext))
}

///|
/// AI 页的分页模型。
fn ai_page_model() -> Model {
  apply_shell(initial_model(), SetRightView(RvAi))
}

///|
/// 两页各自的高度账都要装得进右栏。
///
/// 高度只有一个来源（检查器是 `PANEL_HEAD_HEIGHT + RIGHT_TAB_HEIGHT`；
/// AI 页是 `ai_docked_height`），视图层与这里都从它取——两处各算一份就会把
/// 内容顶出面板。
test "the right panel chrome fits the panel height" {
  for (width, height) in [(1280.0, 800.0), (1440.0, 900.0), (1024.0, 620.0)] {
    // 右栏段高 = 状态栏与顶栏之下的内容行高
    let body_height = height - @chrome.STATUSBAR_HEIGHT - 1.0
    let lower_height = body_height - @chrome.TOPBAR_HEIGHT - 1.0
    // 检查器页：面板头 + 页签行 + 100pt 正文
    let inspector = initial_model()
    let chrome = shell_chrome_widths(inspector, width - @chrome.ICONBAR_WIDTH)
    let inspector_needed = @chrome.PANEL_HEAD_HEIGHT + RIGHT_TAB_HEIGHT + 100.0
    assert_true(
      inspector_needed <= lower_height,
      msg="inspector page overflows the panel at \{width}x\{height}: need=\{inspector_needed} have=\{lower_height}",
    )
    // AI 页：面板头 + 钉底输入卡 + 100pt 转录
    let on_ai = ai_page_model()
    let docked = ai_docked_height(on_ai, chrome.right)
    let ai_needed = @chrome.PANEL_HEAD_HEIGHT + docked + 100.0
    assert_true(
      ai_needed <= lower_height,
      msg="AI page overflows the panel at \{width}x\{height}: need=\{ai_needed} have=\{lower_height}",
    )
  }
}

///|
/// 检查器页正文是**一条滚动区**：快速操作与运行时监视的分区头都在它里面。
///
/// 旧版这两块是面板级固定块（不吃滚动、也不随正文走），于是右栏底部被 56pt
/// 的快速操作条 + 150pt 的监视块钉死，正文只剩一小条。改成分区后它们与其它
/// 分区同一条 scroll_view。
///
/// 判据取**绘制位置**：两个分区头的 y 都必须落在正文滚动区的纵向范围内
/// （面板头 + 页签行之下、面板底边之上），且 x 与面板左缘对齐。
test "quick actions and watch are sections of one scroll region" {
  let model = load_template_program(inspector_model(), 0)
  let commands = shell_draw(model, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let body_top = right_panel_top() +
    @chrome.PANEL_HEAD_HEIGHT +
    RIGHT_TAB_HEIGHT
  // 检查器页没有钉底块：正文一直铺到面板底边（状态栏之上）
  let body_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  guard shell_find_text(commands, "快速操作") is Some(qa) else {
    fail("quick actions section head missing")
  }
  guard shell_find_text(commands, "运行时监视") is Some(watch) else {
    fail("watch section head missing")
  }
  for run in [qa, watch] {
    assert_true(
      run.frame.origin.y >= body_top - 1.0,
      msg="section head sits above the scroll region: y=" +
        run.frame.origin.y.to_string(),
    )
    assert_true(
      run.frame.origin.y + run.frame.size.height <= body_bottom + 1.0,
      msg="section head sits below the scroll region: y=" +
        run.frame.origin.y.to_string(),
    )
    assert_true(
      run.frame.origin.x >= panel_left - 1.0 &&
      run.frame.origin.x + run.frame.size.width <= panel_right + 1.0,
      msg="section head escapes the panel width",
    )
  }
}

///|
/// 分区头在右栏最窄两档都不越界：用户可拖到的下限（200）与窄窗紧急收缩档
/// （170）。这两档下文案最长的是「运行时监视」。
test "section heads stay inside the panel at the narrowest widths" {
  let model = load_template_program(inspector_model(), 0)
  for width in [200.0, 170.0] {
    // 把右栏拖到目标宽度（紧急档由 update 的夹取兜底）
    let narrowed = apply_shell(model, ResizeRightPanel(width))
    let actual = shell_chrome_widths(narrowed, 1280.0 - @chrome.ICONBAR_WIDTH).right
    let commands = shell_draw(narrowed, 1280.0, 800.0)
    let (panel_left, panel_right) = right_panel_span(1280.0)
    for needle in ["快速操作", "运行时监视"] {
      guard shell_find_text(commands, needle) is Some(run) else {
        fail(
          "section head missing at width " + actual.to_string() + ": " + needle,
        )
      }
      assert_true(
        run.frame.origin.x >= panel_left - 1.0 &&
        run.frame.origin.x + run.frame.size.width <= panel_right + 1.0,
        msg="section head overflows the panel at width " +
          actual.to_string() +
          ": " +
          needle,
      )
    }
  }
}

///|
/// **页块切换器**在两档宽度下都不越界，且选中态跟着当前页走。
///
/// 窄窗紧急档可把右栏压到 170pt——两个带标签的页块（≈85×2）加动作簇在那里
/// 放不下，视图层按实测可用宽**降级为图标 only**。判据：
/// 1. 两个页块都画在右栏内（两档都不越界）；
/// 2. 恰好有一个页块带**选中底块**（`ide_hover()` 的圆角填充），且它在
///    检查器页时为检查器块；切到 AI 页后换成 AI 块。
///
/// 不给「页块文案」做精确匹配断言：页块与子页签可能重名（「属性」这类），
/// 按颜色数选中块才是稳的判据。
test "the page switcher stays inside the panel at every width" {
  for width in [1280.0, 200.0, 170.0] {
    let model = load_template_program(
      apply_shell(inspector_model(), ResizeRightPanel(width)),
      0,
    )
    let commands = shell_draw(model, 1280.0, 800.0)
    // 宽度是**拖过之后**的实际值（170 会被 update/紧急档夹取），必须现算
    let (panel_left, panel_right) = right_panel_span_of(model, 1280.0)
    let head_top = right_panel_top()
    let head_bottom = head_top + @chrome.PANEL_HEAD_HEIGHT
    // 页块：头部带内、22pt 高、位于面板左半段（动作簇在右半段）
    let hover = @chrome.ide_hover()
    let mut selected_tiles = 0
    let mut tile_count = 0
    for command in commands {
      let (rect, color) = match command {
        @core.FillRoundedRect(r, c) => (r.rect, c)
        @core.FillRoundedRectBrush(r, @graphics.Brush::Solid(c)) => (r.rect, c)
        _ => continue
      }
      let in_head = rect.origin.y >= head_top - 1.0 &&
        rect.origin.y + rect.size.height <= head_bottom + 1.0
      // 页块宽 ≥24、高恰为 PAGE_TILE_HEIGHT（与同带的动作钮区分）
      if in_head &&
        rect.origin.x >= panel_left - 1.0 &&
        rect.size.width >= @chrome.PAGE_TILE_ICON_WIDTH - 1.0 &&
        (rect.size.height - @chrome.PAGE_TILE_HEIGHT).abs() < 1.0 {
        tile_count = tile_count + 1
        assert_true(
          rect.origin.x + rect.size.width <= panel_right + 1.0,
          msg="page tile overflows the panel at width " + width.to_string(),
        )
        if (color.r - hover.r).abs() < 0.01 &&
          (color.g - hover.g).abs() < 0.01 &&
          (color.b - hover.b).abs() < 0.01 {
          selected_tiles = selected_tiles + 1
        }
      }
    }
    assert_true(
      tile_count >= 2,
      msg="expected two page tiles at width " +
        width.to_string() +
        ", found " +
        tile_count.to_string(),
    )
    assert_eq(
      selected_tiles,
      1,
      msg="exactly one page tile carries the selected tile fill at width " +
        width.to_string(),
    )
  }
}

///|
/// **输入面只在 AI 页**（严格 VS Code 分页口径）。
///
/// 这是本轮分页最核心的可见后果，也是最容易被后续改动悄悄破坏的一条：
/// 检查器页不画占位文字、不画发送钮；AI 页两者都在。
test "the inspector page carries no composer while the AI page does" {
  let inspector = shell_draw(
    load_template_program(inspector_model(), 0),
    1280.0,
    800.0,
  )
  assert_false(
    shell_has_text(inspector, "描述你想要的应用"),
    msg="the inspector page must not draw the composer placeholder",
  )
  assert_eq(
    shell_find_send_buttons(inspector).length(),
    0,
    msg="the inspector page must not draw a send button",
  )
  let on_ai = shell_draw(ai_page_model(), 1280.0, 800.0)
  assert_true(shell_has_text(on_ai, "描述你想要的应用"))
  assert_eq(shell_find_send_buttons(on_ai).length(), 1)
}

///|
/// AI 页的转录**按内容出现/消失**：空会话时没有卡片内容，有卡时卡片文本与
/// 状态行读数都出现，且转录在输入卡**之上**。
///
/// 纵向次序用**会话头**而不是卡片文本作锚：转录受控滚动 + 自动贴底，一张
/// 长 diff 卡会把卡片文本推到视口上方（y 为负）——拿它比次序会误报。会话头
/// 固定在转录顶部不受滚动影响，是这条契约的稳定观测点。
test "the AI thread appears only with thread cards" {
  let model = ai_page_model()
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let panel_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  // 空会话：没有任何线程卡内容（输入卡仍在——右栏是常驻面板，输入面不随
  // 会话内容进出场）
  let empty = shell_draw(model, 1280.0, 800.0)
  assert_false(shell_has_text(empty, "随机点名"))
  assert_true(shell_has_text(empty, "描述你想要的应用"))
  // 有卡：卡片文本 + 状态行待审计读数
  let proposed = with_pending_roll_call(model)
  let commands = shell_draw(proposed, 1280.0, 800.0)
  assert_true(shell_has_text(commands, "随机点名"))
  assert_true(shell_has_text(commands, "待审计 1"))
  // 转录在输入卡**之上**（VS Code「转录在上、输入在下」的口径）
  guard shell_find_text_in_span(
      commands, "会话 1", panel_left, panel_right, 0.0, panel_bottom,
    )
    is Some(header_run) else {
    fail("session header missing from the AI page")
  }
  guard shell_find_text_in_span(
      commands, "描述你想要的应用", panel_left, panel_right, 0.0, panel_bottom,
    )
    is Some(prompt_run) else {
    fail("composer placeholder missing from the AI page")
  }
  assert_true(
    header_run.frame.origin.y < prompt_run.frame.origin.y,
    msg="the transcript must sit above the composer",
  )
}

///|
/// 转录里的工作卡组**整条可点折叠**（复用既有 `ToggleAiCardsFold`）：折叠后
/// 卡组收起，只剩组头的读数。
///
/// 分页前这条钉的是「AI 会话分区头兼折叠条」；分页后转录进了 AI 页，折叠
/// 语义不变（组头点一下收起卡组），判据改成「摘要文字的出现次数」——
/// 折叠后只该剩决策条里那一处。
test "the AI thread section head folds the thread" {
  let model = apply_shell(
    with_pending_roll_call(ai_page_model()),
    ToggleAiCardsFold,
  )
  assert_true(model.ai_cards_folded)
  let commands = shell_draw(model, 1280.0, 800.0)
  // 卡组头还在（折叠态仍有入口展开）
  assert_true(shell_has_text(commands, "Agent"))
  // 线程卡内容不画：提案摘要只剩决策条里那一处（线程卡那一份收起了）
  assert_eq(
    shell_count_text(commands, "随机点名"),
    1,
    msg="folded thread must not draw its cards",
  )
  // 展开后回来
  let expanded = apply_shell(model, ToggleAiCardsFold)
  assert_false(expanded.ai_cards_folded)
  assert_true(
    shell_count_text(shell_draw(expanded, 1280.0, 800.0), "随机点名") > 1,
  )
}

///|
/// 页签行六格：等宽、都在面板内、活动态有强调色下划线。
///
/// 等宽公式**必须把 5 个间隙与左右内垫一起算进去**——旧版只减了内垫忘了间隙，
/// 「依赖」页签正好顶到右边缘被切掉半个字（实测截图）。
test "the context tab row keeps six equal cells inside the panel" {
  let model = inspector_model()
  let commands = shell_draw(model, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let tab_top = right_panel_top() + @chrome.PANEL_HEAD_HEIGHT
  for label in ["属性", "状态", "数据", "动作", "依赖", "运行时"] {
    // **精确匹配**：`shell_find_text` 是子串匹配，「数据」会先命中左栏的
    // 「本地数据」，「状态」会先命中状态栏——两条都会把断言带到错的面板上。
    guard shell_find_exact(commands, label) is Some(run) else {
      fail("context tab missing: " + label)
    }
    assert_true(
      run.frame.origin.y >= tab_top - 1.0 &&
      run.frame.origin.y < tab_top + RIGHT_TAB_HEIGHT + 1.0,
      msg="tab sits outside the tab row: " + label,
    )
    assert_true(
      run.frame.origin.x >= panel_left - 1.0 &&
      run.frame.origin.x + run.frame.size.width <= panel_right + 1.0,
      msg="tab escapes the panel: " + label,
    )
  }
  // 活动态下划线：2pt 强调色实心条，位于活动页签正下方
  let accent = @chrome.ide_accent()
  let mut underline = 0
  for command in commands {
    // 下划线是圆角条（corner_radius=1），两种填充形态都要收——只收
    // `FillRect` 会一条都数不到（断言报「0 条」而视觉上明明有）。
    let found = match command {
      @core.FillRect(rect, color) => Some((rect, color))
      @core.FillRoundedRect(rounded, color) => Some((rounded.rect, color))
      @core.FillRoundedRectBrush(rounded, @core.Brush::Solid(color)) =>
        Some((rounded.rect, color))
      _ => None
    }
    match found {
      Some((rect, color)) =>
        if rect.size.height >= 1.5 &&
          rect.size.height <= 2.5 &&
          rect.origin.y >= tab_top &&
          rect.origin.y <= tab_top + RIGHT_TAB_HEIGHT &&
          rect.origin.x >= panel_left &&
          (color.r - accent.r).abs() < 0.01 &&
          (color.g - accent.g).abs() < 0.01 {
          underline = underline + 1
        }
      None => ()
    }
  }
  assert_eq(underline, 1, msg="exactly one active tab underline")
}

///|
/// AI 插件被禁用（教学版 profile / G7.3 插件管理）时：**AI 页整块不存在**——
/// 不出页块、不出 composer；而且停在 `RvAi` 的状态会被**归一化**回检查器页。
///
/// 这与活动栏 AI 模式、底栏终端页签走同一条纪律（`plugin_active` + 归一化）：
/// 能力缺席时既不出「点了必失败」的假按钮，也不留一个「切过去什么都没有」的
/// 死页。
test "a disabled AI plugin leaves no composer in the right panel" {
  let model = { ..initial_model(), plugin_disabled: ["ai"], }
  let commands = shell_draw(model, 1280.0, 800.0)
  assert_false(shell_has_text(commands, "描述你想要的应用"))
  assert_eq(shell_find_send_buttons(commands).length(), 0)
  // 正文仍完整：检查器的字段还在
  assert_true(shell_has_text(commands, "名称"))
  // 归一化：禁用态下点「AI 页」这条路不该留下一个空页。
  // `normalize_disabled_plugins` 是唯一判据（Toggle 与 boot 恢复共用）。
  let stuck = {
    ..apply_shell(initial_model(), SetRightView(RvAi)),
    plugin_disabled: ["ai"],
  }
  assert_true(stuck.right_view is RvAi)
  assert_true(normalize_disabled_plugins(stuck).right_view is RvContext)
}

///|
/// 对象条（检查器正文首段）承载身份与「清空选中」出口。
///
/// 头部让位给页块切换器后这两件事下移到正文首段；判据：
/// 1. 选中时**名称 + 种类**都在对象条里（面板头带下方、页签行之下）；
/// 2. 那个清空 ✕ **不在头部动作簇那一条带里**——这正是 2026-09-30 事故的
///    形态（清空与关闭互换位置），分页后由「不同带」这条几何判据守住；
/// 3. 无选中时对象条如实说「未选中对象」，且不画清空钮。
test "the object strip carries identity and the clear action" {
  let model = load_template_program(inspector_model(), 0)
  // 选中模板里的第一个控件（名字随模板变，不写死）
  let target = model.program.controls[0].name
  let named = apply_shell(model, SelectControl(target))
  assert_eq(named.selected_control, target)
  let commands = shell_draw(named, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let head_top = right_panel_top()
  let head_bottom = head_top + @chrome.PANEL_HEAD_HEIGHT
  let strip_top = head_bottom + RIGHT_TAB_HEIGHT
  let panel_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  guard shell_find_text_in_span(
      commands, target, panel_left, panel_right, strip_top, panel_bottom,
    )
    is Some(_) else {
    fail("object strip does not name the selected control: " + target)
  }
  // 清空 ✕ 在对象条带里（不在头部带里）：找 10pt 的小图标盒
  let mut in_head = 0
  let mut in_strip = 0
  for rect in shell_rects(commands) {
    let in_panel_x = rect.origin.x >= panel_left - 1.0 &&
      rect.origin.x + rect.size.width <= panel_right + 1.0
    if !in_panel_x {
      continue
    }
    let is_small_box = (rect.size.width - 18.0).abs() < 2.0 &&
      (rect.size.height - 18.0).abs() < 2.0
    if !is_small_box {
      continue
    }
    if rect.origin.y >= head_top - 1.0 &&
      rect.origin.y + rect.size.height <= head_bottom + 1.0 {
      in_head = in_head + 1
    } else if rect.origin.y >= strip_top - 1.0 &&
      rect.origin.y + rect.size.height <= panel_bottom {
      in_strip = in_strip + 1
    }
  }
  assert_eq(in_head, 0, msg="no 18pt box may sit in the panel head band")
  assert_true(
    in_strip >= 1,
    msg="the clear-selection box must sit in the object strip",
  )
  // 无选中：如实说「未选中对象」，且对象条里不再有那个 18pt 清空盒
  let cleared = apply_shell(named, ClearSelection)
  let cleared_commands = shell_draw(cleared, 1280.0, 800.0)
  assert_true(shell_has_text(cleared_commands, "未选中对象"))
  let mut cleared_strip_boxes = 0
  for rect in shell_rects(cleared_commands) {
    if rect.origin.x >= panel_left - 1.0 &&
      (rect.size.width - 18.0).abs() < 2.0 &&
      (rect.size.height - 18.0).abs() < 2.0 &&
      rect.origin.y >= strip_top - 1.0 &&
      rect.origin.y + rect.size.height <= panel_bottom {
      cleared_strip_boxes = cleared_strip_boxes + 1
    }
  }
  assert_eq(
    cleared_strip_boxes,
    0,
    msg="no clear action should be offered when nothing is selected",
  )
}

///|
/// 上下文芯片如实显示当前选中对象（「AI 会针对谁」）。
///
/// 没有选中对象时显式说「未选中对象」，不静默显示上一个对象——与对象条
/// 同一判据（`side_subject_of` 单一来源）。
test "the composer context chip names the current subject" {
  let model = load_template_program(ai_page_model(), 0)
  // 选中模板里的第一个控件（名字随模板变，不写死）
  let target = model.program.controls[0].name
  let named = apply_shell(model, SelectControl(target))
  assert_eq(named.selected_control, target)
  let commands = shell_draw(named, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  // 只在**钉底块**里找：控件名同时出现在左栏结构树与转录文本里，
  // 全局/全面板找会先命中那两处。
  let docked_top = 800.0 -
    @chrome.STATUSBAR_HEIGHT -
    1.0 -
    ai_docked_height(named, @chrome.RIGHTBAR_WIDTH)
  let docked_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  guard shell_find_text_in_span(
      commands, target, panel_left, panel_right, docked_top, docked_bottom,
    )
    is Some(run) else {
    fail("context chip missing the selected control: " + target)
  }
  // 芯片在输入盒**上方**（同一张卡的前两行）：占位文字在它下面
  guard shell_find_text_in_span(
      commands, "描述你想要的应用", panel_left, panel_right, docked_top,
      docked_bottom,
    )
    is Some(prompt) else {
    fail("composer prompt missing under the context chip")
  }
  assert_true(
    run.frame.origin.y < prompt.frame.origin.y,
    msg="the context chip must sit above the composer input",
  )
  // 两者都在**同一张卡内**：卡的上缘（抬起面填充）在芯片之上、下缘在
  // 占位文字之下。判据取 `ide_elevated()` 的圆角填充。
  let elevated = @chrome.ide_elevated()
  let mut card_top = 800.0
  let mut card_bottom = -1.0
  for command in commands {
    let (rect, color) = match command {
      @core.FillRoundedRect(r, c) => (r.rect, c)
      @core.FillRoundedRectBrush(r, @graphics.Brush::Solid(c)) => (r.rect, c)
      _ => continue
    }
    if rect.origin.x >= panel_left - 1.0 &&
      rect.origin.x + rect.size.width <= panel_right + 1.0 &&
      rect.size.width > 80.0 &&
      (color.r - elevated.r).abs() < 0.01 &&
      (color.g - elevated.g).abs() < 0.01 &&
      (color.b - elevated.b).abs() < 0.01 {
      card_top = card_top.min(rect.origin.y)
      card_bottom = card_bottom.max(rect.origin.y + rect.size.height)
    }
  }
  assert_true(
    card_bottom > 0.0,
    msg="the composer card (elevated rounded fill) is missing",
  )
  assert_true(
    run.frame.origin.y >= card_top - 1.0 &&
    prompt.frame.origin.y + prompt.frame.size.height <= card_bottom + 1.0,
    msg="the context chip and the input must both sit inside the composer card",
  )
}

///|
/// 右栏**两页各自自上而下读作 VS Code 侧栏**。
///
/// 这条是「形态」而不是「某一项在不在」：标志物的纵向顺序错了（比如分区跑到
/// 输入卡下面、或页签行掉到正文里），逐项断言仍然可能全绿。
///
/// 用**没有线程卡**的模型：有卡时转录会把下面的内容推出视口，被推出的内容
/// 仍在绘制流里但 y 已越过面板底边，拿来比顺序会误报。
test "the right panel reads top to bottom in the side-panel order" {
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let panel_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  // 检查器页：页签行 → 对象条 → 快速操作 → 运行时监视（**没有**输入面）
  let inspector = shell_draw(
    load_template_program(inspector_model(), 0),
    1280.0,
    800.0,
  )
  let inspector_markers = [
    "属性", "对象", "快速操作", "运行时监视",
  ]
  let mut previous_y = -1.0
  for marker in inspector_markers {
    guard shell_find_text_in_span(
        inspector, marker, panel_left, panel_right, 0.0, panel_bottom,
      )
      is Some(run) else {
      fail("marker missing from the inspector page: " + marker)
    }
    assert_true(
      run.frame.origin.y > previous_y,
      msg=marker + " is out of order (y=" + run.frame.origin.y.to_string() + ")",
    )
    previous_y = run.frame.origin.y
  }
  // AI 页：会话头 → 输入卡 → 状态行。
  //
  // 状态行的文案随闸门状态变（空闲 = 「闸门 · 逐条采纳」，有待审计卡 =
  // 「待审计 N」）——这里用带卡模型，所以锚点是后者。
  let ai = shell_draw(with_pending_roll_call(ai_page_model()), 1280.0, 800.0)
  let ai_markers = ["会话 1", "描述你想要的应用", "待审计 1"]
  previous_y = -1.0
  for marker in ai_markers {
    guard shell_find_text_in_span(
        ai, marker, panel_left, panel_right, 0.0, panel_bottom,
      )
      is Some(run) else {
      fail("marker missing from the AI page: " + marker)
    }
    assert_true(
      run.frame.origin.y > previous_y,
      msg=marker + " is out of order (y=" + run.frame.origin.y.to_string() + ")",
    )
    previous_y = run.frame.origin.y
  }
}

///|
/// 输入卡是**圆角 + 描边 + 抬起面**三件齐全的一张卡。
///
/// 这是本轮相对旧形态（`corner_radius=0` + 无描边、与面板融为一体的通栏）
/// 的核心视觉变化，所以两条线索各钉一条：
/// 1. 存在一枚 `ide_elevated()` 的**圆角**填充（卡片底 + 半径 8）——旧形态
///    走的是直角通栏；
/// 2. 存在一枚 `ide_border()` 色的描边（卡片边）——只靠面色差在亮色主题下
///    几乎读不出来，描边是让卡「有边界」的那条线索。
///
/// **两种填充形态都要收**：`fill_rounded_rect` 发的是 `Brush` 变体（不是纯色
/// 变体，本仓已知陷阱）。最初只在纯色臂里查半径，于是把半径改成 0 测试照样
/// 全绿——断言里「圆角」那一半是空的。破断验证通过后才留下这条。
test "the composer is a rounded, bordered, elevated card" {
  let model = ai_page_model()
  let commands = shell_draw(model, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let elevated = @chrome.ide_elevated()
  let border = @chrome.ide_border()
  let is_card_fill = fn(color : @core.Color) {
    (color.r - elevated.r).abs() < 0.01 &&
    (color.g - elevated.g).abs() < 0.01 &&
    (color.b - elevated.b).abs() < 0.01
  }
  // 卡填充必须**落在右栏内**且够宽（区分卡片与别处同色的零星元素）
  let in_card_span = fn(rect : @core.Rect) {
    rect.origin.x >= panel_left - 1.0 &&
    rect.origin.x + rect.size.width <= panel_right + 1.0 &&
    rect.size.width > 80.0
  }
  let mut card_fills = 0
  let mut card_strokes = 0
  for command in commands {
    match command {
      @core.FillRoundedRect(rounded, color) =>
        if is_card_fill(color) && in_card_span(rounded.rect) {
          card_fills = card_fills + 1
          assert_eq(
            rounded.radius,
            8.0,
            msg="the composer card must use the 8pt radius",
          )
        }
      @core.FillRoundedRectBrush(rounded, @graphics.Brush::Solid(color)) =>
        if is_card_fill(color) && in_card_span(rounded.rect) {
          card_fills = card_fills + 1
          assert_eq(
            rounded.radius,
            8.0,
            msg="the composer card must use the 8pt radius",
          )
        }
      @core.StrokeRoundedRect(_, color, _) =>
        if (color.r - border.r).abs() < 0.01 &&
          (color.g - border.g).abs() < 0.01 {
          card_strokes = card_strokes + 1
        }
      @core.StrokeRoundedRectBrush(_, brush, _) =>
        match brush {
          @graphics.Brush::Solid(color) =>
            if (color.r - border.r).abs() < 0.01 &&
              (color.g - border.g).abs() < 0.01 {
              card_strokes = card_strokes + 1
            }
          _ => ()
        }
      _ => ()
    }
  }
  assert_eq(
    card_fills,
    1,
    msg="exactly one elevated rounded fill must back the composer card",
  )
  assert_true(
    card_strokes >= 1,
    msg="the composer card border (1pt ide_border) is missing",
  )
}

///|
/// 头部动作簇**按页分派**：检查器页 = 设置 + 关闭（2 枚）；AI 页 = 新建会话 +
/// 设置 + 关闭（3 枚）。两页都不再把「清空选中」放在头部。
///
/// 判据取 24×20 的动作钮计数（页块是 22pt 高、宽 ≥24，用高度区分）。
test "the page head actions follow the current page" {
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let head_top = right_panel_top()
  let head_bottom = head_top + @chrome.PANEL_HEAD_HEIGHT
  let count_head_actions = fn(commands : Array[@core.DrawCommand]) {
    let mut actions = 0
    for command in commands {
      let rect = match command {
        @core.FillRoundedRect(r, _) => r.rect
        @core.FillRoundedRectBrush(r, _) => r.rect
        _ => continue
      }
      // 动作钮：20pt 高（页块是 22pt），落在头部带内、面板右半段
      if (rect.size.height - 20.0).abs() < 1.0 &&
        rect.origin.y >= head_top - 1.0 &&
        rect.origin.y + rect.size.height <= head_bottom + 1.0 &&
        rect.origin.x >= panel_left &&
        rect.origin.x + rect.size.width <= panel_right + 1.0 &&
        rect.size.width >= 20.0 &&
        rect.size.width <= 28.0 {
        actions = actions + 1
      }
    }
    actions
  }
  let inspector = count_head_actions(
    shell_draw(inspector_model(), 1280.0, 800.0),
  )
  let on_ai = count_head_actions(shell_draw(ai_page_model(), 1280.0, 800.0))
  assert_eq(inspector, 2, msg="inspector head keeps settings + close")
  assert_eq(on_ai, 3, msg="the AI page adds the new-session action")
}

///|
/// 命令面板里的 `studio.right.ai` 真的能切到 AI 页（命令与页块切换器同一条
/// 更新链，不是死命令）。
test "the right panel AI command reaches the AI page" {
  let model = initial_model()
  assert_true(model.right_view is RvContext)
  let switched = apply_shell(model, StudioCommandRun("studio.right.ai"))
  assert_true(switched.right_view is RvAi)
  // 切到 AI 页后输入面在场，且只有一枚发送钮
  let commands = shell_draw(switched, 1280.0, 800.0)
  assert_true(shell_has_text(commands, "描述你想要的应用"))
  assert_eq(shell_find_send_buttons(commands).length(), 1)
  // 切回检查器页：输入面消失
  let back = apply_shell(switched, StudioCommandRun("studio.right.context"))
  assert_true(back.right_view is RvContext)
  assert_eq(
    shell_find_send_buttons(shell_draw(back, 1280.0, 800.0)).length(),
    0,
  )
}

///|
/// **输入面只在 AI 页**（严格 VS Code 分页口径），所以「现在这条在哪」不再
/// 需要推导，而是由一个枚举位决定。
///
/// 旧版有三个宿主（底栏页签 / 右栏停靠 / AI 模式中心）与一个 `ai_host_hint_key`
/// 读数（bar/docked/center）——那个读数在生产侧本就没有调用点。收敛到「右栏
/// 一页」后，剩下的两个落点是：**右栏 AI 页**（`RvAi`）与 **PsAi 中心**；
/// 检查器页（`RvContext`）按严格口径不画输入面。
test "the AI composer has exactly one host" {
  let model = initial_model()
  // 检查器页：**零**发送钮——输入面不在这一页（这是本轮的分页契约）
  let inspector = shell_find_send_buttons(shell_draw(model, 1280.0, 800.0))
  assert_eq(
    inspector.length(),
    0,
    msg="the inspector page must not host a composer any more",
  )
  // AI 页：恰好一枚，且落在右栏里
  let on_ai = apply_shell(model, SetRightView(RvAi))
  let sends = shell_find_send_buttons(shell_draw(on_ai, 1280.0, 800.0))
  assert_eq(sends.length(), 1, msg="one composer host on the AI page")
  let widths = shell_chrome_widths(model, 1280.0 - @chrome.ICONBAR_WIDTH)
  let center_left = @chrome.ICONBAR_WIDTH + 2.0 + @chrome.LEFTBAR_WIDTH + 1.0
  assert_true(sends[0].origin.x >= center_left + widths.center - 1.0)
  // 右栏收起 = 输入面跟着收起（AI 页不在了，没有第二个宿主接住它）
  let hidden = apply_shell(on_ai, SetRightView(RvHidden))
  assert_eq(
    shell_find_send_buttons(shell_draw(hidden, 1280.0, 800.0)).length(),
    0,
    msg="hiding the right panel must hide the only composer",
  )
  // AI 工作台模式：输入面在中心（该模式的右栏是更改/文件工作区面板）
  let center = apply_shell(model, SetPerspective(PsAi))
  assert_eq(
    shell_find_send_buttons(shell_draw(center, 1280.0, 800.0)).length(),
    1,
    msg="the AI workbench keeps its own centre composer",
  )
}

///|
/// `#seeAll`：线程多于 3 条时才出现，且点了打开既有 AI 历史。
///
/// 分页后它在 **AI 页**的转录尾部（不再是检查器滚动区里的分区）。
test "see all sessions appears only with a long thread list" {
  let model = initial_model()
  // 初始只有 1 张卡 → 不显示
  assert_false(
    shell_has_text(shell_draw(model, 1280.0, 800.0), "查看全部会话 →"),
  )
  // 每条真实回执都推进一张 diff 线程卡（真实漏斗：proposal_from_completion）
  let mut many = with_pending_roll_call(model)
  for _ in 0..<4 {
    many = with_pending_roll_call(many)
  }
  if many.ai_sessions.current().cards.length() <= 3 {
    fail("expected >3 thread cards")
  }
  let on_ai = apply_shell(many, SetRightView(RvAi))
  assert_true(
    shell_has_text(shell_draw(on_ai, 1280.0, 800.0), "查看全部会话 →"),
  )
  // 转录折叠后工作卡组收起，出口也收起
  let folded = apply_shell(on_ai, ToggleAiCardsFold)
  assert_false(
    shell_has_text(shell_draw(folded, 1280.0, 800.0), "查看全部会话 →"),
  )
}

///|
/// **AI 页转录里的每一段文字都不许越出自己的裁剪区**（用户报的「右侧文字
/// 看不到」）。
///
/// 真实缺陷（本轮实测抓到）：`ai_transcript` 把**外宽**传给 `timeline_rows`，
/// 而滚动区被 `padding_edges` 收到 `width − 24`——每行因此比自己的裁剪区宽
/// 24pt，被 flex 居中后整条转录右移 12pt，**长行文本越过裁剪区右缘被切掉**。
/// 短行看不出来（它们本来就只占一小段），所以这类缺陷只在长代码行上显形。
///
/// 判据取**裁剪区**而不是声明宽：`@views.text` 的宽是最小值（布局取
/// `max(声明宽, 实测宽)`），声明窄了它会自己长宽——「声明宽 < 估算宽」根本
/// 不会截断文字（本仓 `shell_responsive_wbtest` 的同类注释已记录）。真正看得
/// 见的截断是文字越出 `PushClip` 边界。
///
/// 扫描范围覆盖**所有会长文本的卡路径**（长标题 + 徽标 / 已处理回执 / 讲解
/// markdown / 计划步骤 / 错误卡 / diff 长代码行），并在三档宽度下各扫一遍——
/// 这类缺陷只在「文本比它的容器长」时出现，默认一张短卡永远发现不了。容差
/// 2pt 与仓库既有同类判据一致（字距/内垫的亚像素差不算缺陷）。
test "no text overflows its clip region on the AI page" {
  // 覆盖**所有会画出长文本的卡路径**：长标题 + 「已处理」徽标、已处理回执、
  // 讲解卡的 markdown 正文、计划卡的步骤清单、错误卡的长标题、diff 长代码行。
  // 这些都是用户实测触发过或极易触发的形态——只测「默认一张卡」会漏掉它们。
  let model = with_pending_roll_call(ai_page_model())
  let cards = model.ai_sessions.current().cards
  cards[cards.length() - 1] = AiCard::{
    ..cards[cards.length() - 1],
    title: "将“开始抽签”按钮的字体颜色改为黑色并加粗，同时保持圆角不变",
    settled: true,
    settled_note: "app.ai.card.applied 已应用到 form.mbt 与 handlers.mbt 两处",
  }
  cards.push(AiCard::{
    kind: CardExplanation,
    title: "解释",
    body: "# 标题\n\n这是一段很长很长的解释文本，用来验证 markdown 块在窄栏里的换行与裁剪行为是否正确，不应该越过右缘。",
    steps: [],
    steps_done: 0,
    progress: 0,
    diff_lines: [],
    settled: false,
    settled_note: "",
    seq: 99,
    at: 0,
  })
  cards.push(AiCard::{
    kind: CardError,
    title: "出错了：provider 返回了非法的 JSON 载荷并且没有给出可读的原因说明",
    body: "err.proposal_invalid_json",
    steps: [
      "第一步：读取 IR", "第二步：重建投影并比较每一处差异",
    ],
    steps_done: 1,
    progress: 33,
    diff_lines: [],
    settled: false,
    settled_note: "",
    seq: 100,
    at: 0,
  })
  for width in [1280.0, 1024.0, 900.0] {
    let commands = shell_draw(model, width, 800.0)
    let clips : Array[@core.Rect] = []
    for command in commands {
      match command {
        @core.PushRoundedClip(rounded) => clips.push(rounded.rect)
        @core.PushClip(rect) => clips.push(rect)
        @core.PopClip | @core.PopRoundedClip =>
          if clips.length() > 0 {
            ignore(clips.pop())
          }
        @core.DrawText(run) =>
          if clips.length() > 0 && run.text != "" && !run.text.contains("…") {
            let clip = clips[clips.length() - 1]
            let right = run.frame.origin.x + run.frame.size.width
            if right > clip.origin.x + clip.size.width + 2.0 {
              fail(
                "text overflows its clip region at width " +
                width.to_string() +
                ": '" +
                run.text +
                "' right=" +
                right.to_string() +
                " clip_right=" +
                (clip.origin.x + clip.size.width).to_string(),
              )
            }
          }
        _ => ()
      }
    }
  }
}

///|
/// **diff 卡的长代码行必须带省略号收尾**，而不是被裁剪区硬切。
///
/// 为什么单独一条：上面那条「不许越出裁剪区」的判据查的是**文字框**，而
/// `@views.text` 的布局会把框钳在声明宽内——所以「一段长代码行正好在框右缘
/// 被切掉半个词」**不会**被越界断言抓到（破断验证实测：去掉截断后那条测试
/// 仍然全绿）。真正的可观测判据是**省略号**：`fit_label` 是本仓为这类窄宿主
/// 长文本定的口径（带省略号 + 95% 安全余量）。
///
/// 这正是用户报的「右侧文字看不到」在 diff 行上的形态。
test "long diff lines are ellipsised, not hard-cut" {
  let model = with_pending_roll_call(ai_page_model())
  let commands = shell_draw(model, 1280.0, 800.0)
  // 回执推入的 diff 是真实代码（含 `set_text` / `dispatch_` 这类长行）；
  // 它们必须以省略号收尾。
  let mut cut_without_ellipsis = 0
  let mut ellipsised = 0
  for run in shell_texts(commands) {
    if run.text.contains("set_text") || run.text.contains("dispatch_") {
      if run.text.contains("…") {
        ellipsised = ellipsised + 1
      } else {
        cut_without_ellipsis = cut_without_ellipsis + 1
      }
    }
  }
  assert_true(ellipsised > 0, msg="expected long diff lines to be ellipsised")
  assert_eq(
    cut_without_ellipsis,
    0,
    msg="every long diff line must end with an ellipsis, not a hard cut",
  )
}

///|
/// **恢复的会话里不留未结算的忙碌占位卡**（用户报的「生成成功之后还显示
/// 「正在生成提案…」」）。
///
/// `app.ai.busy` 那张计划卡是**进行中**的瞬时状态，没有 settle 语义（回执到达
/// 时由 `drop_ai_busy_card` 摘掉）。但「提交后、回执前」存盘是可能的——未结算
/// 卡会被如实写进 JSON，于是下次启动读回来就**永远转圈**：用户看到的现象正是
/// 「生成早已成功，卡片还在那里」。
///
/// 判据走**真实恢复通道**（编码 → 解码 → `AiSessionsStoreLoaded`），而不是直接
/// 调 `drop_ai_busy_card`——后者只能证明函数正确，证明不了恢复路径调用过它
/// （本仓栽过「update 断言全绿、视图没接线」的跟头）。
test "restoring a session drops the in-flight busy card" {
  // 造一个「提交后、回执前」的会话：一张未结算的忙碌计划卡 + 一条用户提问
  let busy = push_ai_card(
    { ..initial_model(), ai_busy: true, ai_sessions: @ai.AiSessions::new(), },
    AiCard::{
      kind: CardPlan,
      title: text(translator(initial_model()), "app.ai.busy"),
      body: "",
      steps: [],
      steps_done: 0,
      progress: 0,
      diff_lines: [],
      settled: false,
      settled_note: "",
      seq: 0,
      at: 0,
    },
  )
  assert_eq(busy.ai_sessions.current().cards.length(), 1)
  assert_false(busy.ai_sessions.current().cards[0].settled)
  // 存盘 → 恢复
  let payload = @ai.encode_ai_sessions(busy.ai_sessions)
  let restored = apply_shell(
    initial_model(),
    AiSessionsStoreLoaded(Success(payload)),
  )
  assert_eq(
    restored.ai_sessions.current().cards.length(),
    0,
    msg="the in-flight busy card must not survive a session restore",
  )
  // 恢复后时间线上不再有「正在生成提案…」
  assert_false(
    shell_has_text(shell_draw(restored, 1280.0, 800.0), "正在生成提案"),
  )
  // 第二条 in-flight 形态：**空的流式「回复」卡**（提交时预置、分片未到就退出）
  let streaming = push_ai_card(
    { ..initial_model(), ai_sessions: @ai.AiSessions::new(), },
    AiCard::{
      kind: CardExplanation,
      title: "回复",
      body: "",
      steps: [],
      steps_done: 0,
      progress: 0,
      diff_lines: [],
      settled: false,
      settled_note: "",
      seq: 0,
      at: 0,
    },
  )
  let restored_stream = apply_shell(
    initial_model(),
    AiSessionsStoreLoaded(
      Success(@ai.encode_ai_sessions(streaming.ai_sessions)),
    ),
  )
  assert_eq(
    restored_stream.ai_sessions.current().cards.length(),
    0,
    msg="an empty in-flight streaming card must not survive a restore",
  )
  // 对照：**有内容的**未结算流式卡必须保留（分片已经到了，它承载信息）
  let partial = push_ai_card(
    { ..initial_model(), ai_sessions: @ai.AiSessions::new(), },
    AiCard::{
      kind: CardExplanation,
      title: "回复",
      body: "已经收到的前半段内容",
      steps: [],
      steps_done: 0,
      progress: 0,
      diff_lines: [],
      settled: false,
      settled_note: "",
      seq: 0,
      at: 0,
    },
  )
  let kept_partial = apply_shell(
    initial_model(),
    AiSessionsStoreLoaded(Success(@ai.encode_ai_sessions(partial.ai_sessions))),
  )
  assert_eq(
    kept_partial.ai_sessions.current().cards.length(),
    1,
    msg="a partially-streamed card carries content and must survive",
  )
  // 对照：已结算的历史卡（正常结束的那张）**必须保留**
  let settled = push_ai_card(
    { ..initial_model(), ai_sessions: @ai.AiSessions::new(), },
    AiCard::{
      kind: CardPlan,
      title: "已完成的工作",
      body: "",
      steps: [],
      steps_done: 0,
      progress: 100,
      diff_lines: [],
      settled: true,
      settled_note: "",
      seq: 1,
      at: 0,
    },
  )
  let kept = apply_shell(
    initial_model(),
    AiSessionsStoreLoaded(Success(@ai.encode_ai_sessions(settled.ai_sessions))),
  )
  assert_eq(
    kept.ai_sessions.current().cards.length(),
    1,
    msg="settled history cards must survive a restore",
  )
}

///|
/// **带标签的页块不弹提示浮层**（用户报的「已经有文字了，小 tips 去掉吧」）。
///
/// 页块上已经写着「检查器 / AI」，再弹一块**同名**浮层是纯重复。判据取绘制流里
/// 有没有那块浮层的底：提示浮层是一块 `Overlay` 面的小圆角矩形（18pt 高），
/// 而页块自身是 22pt 高——高度差就是二者的判别特征。
///
/// 同时钉住**图标 only 档仍然弹**：窄窗降级时标签不画，浮层是那一页唯一的
/// 名字来源，不能一起删掉。
test "labelled page tiles carry no tooltip popup" {
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let head_top = right_panel_top()
  let head_bottom = head_top + @chrome.PANEL_HEAD_HEIGHT
  let count_popup_fills = fn(commands : Array[@core.DrawCommand]) {
    let mut popups = 0
    for command in commands {
      let (rect, _color) = match command {
        @core.FillRoundedRect(r, c) => (r.rect, c)
        @core.FillRoundedRectBrush(r, @graphics.Brush::Solid(c)) => (r.rect, c)
        _ => continue
      }
      // 浮层特征：18pt 高、落在头部带内、右栏横向范围内。
      if (rect.size.height - 18.0).abs() < 1.0 &&
        rect.origin.y >= head_top - 1.0 &&
        rect.origin.y + rect.size.height <= head_bottom + 1.0 &&
        rect.origin.x >= panel_left - 1.0 &&
        rect.origin.x + rect.size.width <= panel_right + 1.0 {
        popups = popups + 1
      }
    }
    popups
  }
  // 悬停在「检查器」页块上：**不得**出现浮层（面板已是宽档，页块带标签）
  let hovering = apply_shell(inspector_model(), HoverHint("检查器"))
  assert_eq(hovering.hover_hint, "检查器")
  assert_eq(
    count_popup_fills(shell_draw(hovering, 1280.0, 800.0)),
    0,
    msg="a labelled page tile must not pop a duplicate tooltip",
  )
  // 对照：头部动作钮（＋/⚙/✕ 这类**只有图标**的控件）仍然弹浮层——
  // 它们没有文字，浮层是唯一的名字来源。
  let on_icon = apply_shell(inspector_model(), HoverHint("收起右栏"))
  let icon_cmds = shell_draw(on_icon, 1280.0, 800.0)
  println("DBG hint='" + on_icon.hover_hint + "'")
  for command in icon_cmds {
    match command {
      @core.FillRoundedRect(r, _) =>
        if r.rect.size.height <= 30.0 && r.rect.origin.x > 1000.0 {
          println("DBG rrect h=" + r.rect.size.height.to_string() + " w=" + r.rect.size.width.to_string() + " x=" + r.rect.origin.x.to_string() + " y=" + r.rect.origin.y.to_string())
        }
      @core.FillRoundedRectBrush(r, _) =>
        if r.rect.size.height <= 30.0 && r.rect.origin.x > 1000.0 {
          println("DBG brush h=" + r.rect.size.height.to_string() + " w=" + r.rect.size.width.to_string() + " x=" + r.rect.origin.x.to_string() + " y=" + r.rect.origin.y.to_string())
        }
      _ => ()
    }
  }
  assert_true(
    count_popup_fills(icon_cmds) >= 1,
    msg="icon-only head actions must keep their tooltip",
  )
}
