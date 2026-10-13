///|
/// MoUI Studio 右栏的 **VS Code 侧面板（side panel）形态**回归。
///
/// 目标形态：面板头（标题 + ghost 动作簇）→ 页签行（扁平文字 + 活动态下划线）
/// → **单一滚动区**（AI 会话 / 积木编辑 / 当前页签 / 快速操作 / 运行时监视
/// 五个分区同一条 scroll_view）→ hairline → 钉底 composer（上下文芯片 + 输入盒
/// + 决策条）。
///
/// 为什么单独一个文件：`shell_layout_wbtest.mbt` 已到 1200 行硬上限附近
/// （`checks/source-file-policy.json`），新测试按仓规另开文件——与
/// `ai_bar_layout_wbtest.mbt` 当年从它拆出同一处置。共享的 shell 渲染助手
/// （`shell_draw` / `shell_texts` / `shell_find_text` / `apply_shell`）在同包
/// 的另一文件里。
///
/// 本文件钉住的契约：
/// 1. 输入面只有一个宿主 = 右栏底部（底栏没有 AI 页签）；
/// 2. 快速操作 / 运行时监视是滚动区里的**分区**，不再是固定块；
/// 3. 分区头在右栏最窄两档都不越界；
/// 4. 面板头 + 页签行 + 钉底块 + 100pt 正文装得进窗口；
/// 5. AI 会话分区按内容出现/消失，分区头可折叠；
/// 6. 页签行六格等宽、活动态有强调色下划线；
/// 7. AI 插件被禁用时不出 composer、不出 AI 分区；
/// 8. 上下文芯片如实显示当前选中对象。

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
fn right_panel_span(width : Double) -> (Double, Double) {
  let right = width
  let left = width - @chrome.RIGHTBAR_WIDTH - @chrome.SASH_WIDTH
  (left, right)
}

///|
/// 面板头 + 页签行 + 钉底块 + 100pt 正文必须装得进右栏高度。
///
/// 高度只有一个来源（`ai_docked_height`），视图层与这里都从它取——两处各算
/// 一份就会把 composer 顶出面板。
test "the right panel chrome fits the panel height" {
  let model = initial_model()
  for (width, height) in [(1280.0, 800.0), (1440.0, 900.0), (1024.0, 620.0)] {
    let chrome = shell_chrome_widths(model, width - @chrome.ICONBAR_WIDTH)
    let docked = ai_docked_height(model, chrome.right)
    let needed = @chrome.PANEL_HEAD_HEIGHT + RIGHT_TAB_HEIGHT + docked + 100.0
    // 右栏段高 = 状态栏与顶栏之下的内容行高
    let body_height = height - @chrome.STATUSBAR_HEIGHT - 1.0
    let lower_height = body_height - @chrome.TOPBAR_HEIGHT - 1.0
    assert_true(
      needed <= lower_height,
      msg="right panel chrome overflows the panel at \{width}x\{height}: need=\{needed} have=\{lower_height}",
    )
  }
}

///|
/// 右栏正文是**一条滚动区**：快速操作与运行时监视的分区头都在它里面。
///
/// 旧版这两块是面板级固定块（不吃滚动、也不随正文走），于是右栏底部被 56pt
/// 的快速操作条 + 150pt 的监视块钉死，正文只剩一小条。改成分区后它们与其它
/// 分区同一条 scroll_view。
///
/// 判据取**绘制位置**：两个分区头的 y 都必须落在正文滚动区的纵向范围内
/// （面板头 + 页签行之下、钉底块之上），且 x 与面板左缘对齐。
test "quick actions and watch are sections of one scroll region" {
  let model = load_template_program(initial_model(), 0)
  let commands = shell_draw(model, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let body_top = @chrome.TOPBAR_HEIGHT +
    1.0 +
    @chrome.PANEL_HEAD_HEIGHT +
    RIGHT_TAB_HEIGHT
  let body_bottom = 800.0 -
    @chrome.STATUSBAR_HEIGHT -
    1.0 -
    ai_docked_height(model, @chrome.RIGHTBAR_WIDTH)
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
  let model = load_template_program(initial_model(), 0)
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
/// AI 会话分区**按内容出现/消失**：没有线程卡时整个分区不画（检查器的视觉
/// 与改造前完全一致），有卡时才出现，且分区头给出待审计徽标。
test "the AI thread section appears only with thread cards" {
  let model = initial_model()
  // 空会话：没有分区
  let empty = shell_draw(model, 1280.0, 800.0)
  assert_false(shell_has_text(empty, "AI 会话"))
  // 有卡：分区头 + 待审计徽标
  let proposed = with_pending_roll_call(model)
  let commands = shell_draw(proposed, 1280.0, 800.0)
  assert_true(shell_has_text(commands, "AI 会话"))
  assert_true(shell_has_text(commands, "待审计 1"))
  // 分区在**页签内容之上**（VS Code「转录在正文顶部」的口径）
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let panel_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  guard shell_find_text_in_span(
      commands, "AI 会话", panel_left, panel_right, 0.0, panel_bottom,
    )
    is Some(thread_run) else {
    fail("AI thread section head missing")
  }
  guard shell_find_text_in_span(
      commands, "名称", panel_left, panel_right, 0.0, panel_bottom,
    )
    is Some(props_run) else {
    fail("props tab content missing under the thread section")
  }
  assert_true(
    thread_run.frame.origin.y < props_run.frame.origin.y,
    msg="the AI thread section must sit above the tab content",
  )
}

///|
/// AI 会话分区头**整条可点折叠**（复用既有 `ToggleAiCardsFold`）：折叠后
/// 只剩分区头，线程卡不画。
///
/// 分区头与旧 `fold_bar` 合体——旧实现在分区上面再堆一条 22pt 的折叠条，
/// 两条头上下相邻读作重复 chrome。
test "the AI thread section head folds the thread" {
  let model = with_pending_roll_call(initial_model())
  let folded = apply_shell(model, ToggleAiCardsFold)
  assert_true(folded.ai_cards_folded)
  let commands = shell_draw(folded, 1280.0, 800.0)
  // 分区头还在（折叠态仍有入口展开）
  assert_true(shell_has_text(commands, "AI 会话"))
  // 线程卡内容不画：提案摘要只剩决策条里那一处（线程卡那一份收起了）
  assert_eq(
    shell_count_text(commands, "随机点名"),
    1,
    msg="folded thread must not draw its cards",
  )
  // 展开后回来
  let expanded = apply_shell(folded, ToggleAiCardsFold)
  assert_false(expanded.ai_cards_folded)
  assert_true(shell_has_text(shell_draw(expanded, 1280.0, 800.0), "AI 会话"))
}

///|
/// 页签行六格：等宽、都在面板内、活动态有强调色下划线。
///
/// 等宽公式**必须把 5 个间隙与左右内垫一起算进去**——旧版只减了内垫忘了间隙，
/// 「依赖」页签正好顶到右边缘被切掉半个字（实测截图）。
test "the context tab row keeps six equal cells inside the panel" {
  let model = initial_model()
  let commands = shell_draw(model, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let tab_top = @chrome.TOPBAR_HEIGHT + 1.0 + @chrome.PANEL_HEAD_HEIGHT
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
/// AI 插件被禁用（教学版 profile / G7.3 插件管理）时：右栏**不出** composer、
/// 不出 AI 会话分区，正文吃满整高。
///
/// 这与活动栏 AI 模式、底栏 AI 页签走同一个谓词（`plugin_active`）——能力
/// 缺席时不出「点了必失败」的假按钮。
test "a disabled AI plugin leaves no composer in the right panel" {
  let model = { ..initial_model(), plugin_disabled: ["ai"], }
  let commands = shell_draw(model, 1280.0, 800.0)
  assert_false(shell_has_text(commands, "描述你想要的应用"))
  assert_false(shell_has_text(commands, "AI 会话"))
  assert_eq(shell_find_send_buttons(commands).length(), 0)
  // 正文仍完整：检查器的字段还在
  assert_true(shell_has_text(commands, "名称"))
}

///|
/// 上下文芯片如实显示当前选中对象（「AI 会针对谁」）。
///
/// 没有选中对象时显式说「未选中对象」，不静默显示上一个对象——与面板头
/// 同一口径。
test "the composer context chip names the current subject" {
  let model = load_template_program(initial_model(), 0)
  // 选中模板里的第一个控件（名字随模板变，不写死）
  let target = model.program.controls[0].name
  let named = apply_shell(model, SelectControl(target))
  assert_eq(named.selected_control, target)
  let commands = shell_draw(named, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  // 只在**钉底块**里找：控件名同时出现在面板头标题与左栏结构树，
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
  // 芯片在输入盒**上方**（钉底块的顶段）： composer 的占位文字在它下面
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
  // 「没有选中对象时如实说未选中」由 `side_subject_of` 单一判据保证（与面板头
  // 同源），该性质在 pane_lifecycle_wbtest 的「clearing the selection leaves
  // nothing selected」里已有覆盖。
}

///|
/// 右栏**自上而下读作 VS Code 侧面板**：页签行 → 快速操作 → 运行时监视 →
/// 钉底 composer。
///
/// 这条是「形态」而不是「某一项在不在」：四个标志物的纵向顺序错了（比如分区跑
/// 到 composer 下面、或页签行掉到正文里），上面那些逐项断言仍然可能全绿。
///
/// 用**没有线程卡**的模型：有卡时 AI 会话分区会把下面的分区推出视口，被推出
/// 的内容仍在绘制流里但 y 已越过面板底边，拿来比顺序会误报。AI 分区的位置
/// 由「按内容出现」那条单独钉（它在页签内容之上）。
test "the right panel reads top to bottom in the side-panel order" {
  let model = load_template_program(initial_model(), 0)
  let commands = shell_draw(model, 1280.0, 800.0)
  let (panel_left, panel_right) = right_panel_span(1280.0)
  let panel_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  let markers = [
    "属性", "快速操作", "运行时监视", "描述你想要的应用",
  ]
  let mut previous_y = -1.0
  for marker in markers {
    guard shell_find_text_in_span(
        commands, marker, panel_left, panel_right, 0.0, panel_bottom,
      )
      is Some(run) else {
      fail("marker missing from the right panel: " + marker)
    }
    assert_true(
      run.frame.origin.y > previous_y,
      msg=marker + " is out of order (y=" + run.frame.origin.y.to_string() + ")",
    )
    previous_y = run.frame.origin.y
  }
}
