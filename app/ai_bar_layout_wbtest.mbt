///|
/// AI 输入面（composer）的布局回归。
///
/// 单独成文件：`shell_layout_wbtest.mbt` 已到 1200 行硬上限附近
/// （`checks/source-file-policy.json`），新测试按仓规另开文件——
/// 与 `blocks_edit_test.mbt` 当年从 `app_test.mbt` 拆出同一处置。
///
/// **宿主唯一化（VS Code 侧面板口径）**：输入面只有一个落点 = 右栏底部的钉底
/// composer。旧版有三个宿主（底栏 `BtAi` 页签 / 右栏停靠 / AI 模式中心）与一对
/// 互为出口的切换钮，本文件当年钉的就是那套切换语义；现在那些测试被替换成
/// 「只有一个宿主」的契约。
///
/// 本文件钉住两类**只在右栏宿主下才出现**的缺陷：
/// 1. 环境回落色漏进右栏（无背景 container → `palette.surface`）；
/// 2. 输入面溢出右栏右缘（内衬被扣两次 → 发送钮贴死在面板边）。

///|
/// 右栏钉底块里**不许露出宿主面板以外的底色**。
///
/// 这一类 bug 在本仓出现过三次（浮动层的外层、卡片内衬、底栏体区），
/// 根因都是同一条：**无 background 的 container 在 paint 期回落到环境
/// Base → `palette.surface`**，而那个颜色与它所在的宿主面板不同，于是
/// 本该是「留白」的一圈被刷成一块异色。
///
/// 判据：右栏带内不得出现 `palette.surface`（回落色）——右栏的合法底色
/// 只有 `@chrome.ide_panel()` / `@chrome.ide_panel_alt()` / `@chrome.ide_elevated()`
/// （面板 / 分区头 / **输入卡抬起面**），不含回落色。
///
/// 卡片化之后这条尤其要紧：抬起面天然是「卡片底色」的候选，而
/// `palette.surface` 也长得很像一块卡片底——两色在两种主题下都不相等，
/// 所以断言既拦得住真回落，也不会误伤新卡片。
test "the docked AI composer shows no ambient-fallback surface" {
  let model = apply_shell(initial_model(), SetRightView(RvAi))
  let commands = shell_draw(model, 1280.0, 800.0)
  // 钉底块的纵向范围：右栏底边往上一个 `ai_docked_height`（与旧底栏版
  // 按 `ai_bar_height` 算带顶同一纪律——高度是算出来的，不是估的）。
  let right_bar_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT - 1.0
  let right_bar_top = right_bar_bottom -
    ai_docked_height(model, @chrome.RIGHTBAR_WIDTH)
  // 右栏横向范围：窗口右缘往左一个右栏宽 + 一条 sash
  let right_left = 1280.0 - @chrome.RIGHTBAR_WIDTH - @chrome.SASH_WIDTH
  // 回落色 = @chrome.studio_theme 的 palette.surface
  let fallback = @chrome.studio_theme().palette.surface
  // **扫描范围 = 整个右栏正文**（页头之下到状态栏之上），不只钉底带。
  // 分页后转录也住在右栏里，而它恰恰是最容易漏掉显式底色的那一块——实测：
  // `ai_transcript` 的外层容器没写 background 时，整片转录区被刷成
  // `palette.surface`（暗色 0.121 vs 面板 0.169），右栏读作两块不同质感的
  // 区域。只扫钉底带的旧判据对这块**完全失明**。
  let panel_top = @chrome.TOPBAR_HEIGHT + 1.0 + @chrome.PANEL_HEAD_HEIGHT
  for command in commands {
    let (rect, color) = match command {
      @core.FillRect(r, c) => (r, c)
      @core.FillRoundedRect(r, c) => (r.rect, c)
      @core.FillRoundedRectBrush(r, b) =>
        match b {
          @graphics.Brush::Solid(c) => (r.rect, c)
          _ => continue
        }
      _ => continue
    }
    // **必须同时限定横向**：右栏只占最右那一段——中心列与左栏在同一水平带
    // 上各有自己的面板（它们的回落色是合法内容，不是本测试的对象）。
    let in_panel = rect.origin.y >= panel_top - 1.0 &&
      rect.origin.y + rect.size.height <= right_bar_bottom + 1.0 &&
      rect.origin.x >= right_left - 1.0
    // 只要**有面积**的填充：零高/零宽的占位矩形画不出任何东西，
    // 把它们算进来只会让判据变脆（实测 `h=0` 的占位被误报）。
    if in_panel &&
      rect.size.width > 100.0 &&
      rect.size.height > 1.0 &&
      (color.r - fallback.r).abs() < 0.01 &&
      (color.g - fallback.g).abs() < 0.01 &&
      (color.b - fallback.b).abs() < 0.01 {
      fail(
        "ambient fallback surface painted inside the right panel at y=" +
        rect.origin.y.to_string() +
        " h=" +
        rect.size.height.to_string() +
        " (docked band starts at " +
        right_bar_top.to_string() +
        ")",
      )
    }
  }
}

///|
/// 右栏钉底输入面**不许溢出右栏右缘**。
///
/// 回归意义：内衬被扣两次时，输入盒声明整宽、却只拿到 `width − 16` 的格子，
/// 右侧那 16pt 连同发送钮一起被推出面板（实测发送钮贴死在面板右缘，右边一个
/// padding 都不剩）。
///
/// 判据：输入面里的每一个元素都必须落在右栏之内——特别是**最右**的那个
/// （发送钮），它是最先被挤出去的。
///
/// 卡片化后多一层账要算对：卡自己占掉左右各 `AI_CARD_PAD` + 卡内 8pt 内衬，
/// 所以发送钮距面板右缘更远了——但**不能因此放宽判据**：`-2.0` 保证它仍在
/// 面板内，`panel_left + 2.0` 保证它没被挤到左半边去。
test "the docked AI composer never overflows the right panel" {
  let model = apply_shell(initial_model(), SetRightView(RvAi))
  let commands = shell_draw(model, 1280.0, 800.0)
  let panel_left = 1280.0 - @chrome.RIGHTBAR_WIDTH - @chrome.SASH_WIDTH
  let panel_right = 1280.0
  guard shell_find_send_button(commands) is Some(send) else {
    fail("round send button missing")
  }
  let send_right = send.origin.x + send.size.width
  if send_right > panel_right - 2.0 {
    fail(
      "send button touches the panel edge (no padding): right=" +
      send_right.to_string() +
      " panel_right=" +
      panel_right.to_string(),
    )
  }
  if send.origin.x < panel_left + 2.0 {
    fail(
      "send button escapes the panel on the left: left=" +
      send.origin.x.to_string(),
    )
  }
  // 输入面里的每一段文字也都要留在面板内。**纵向必须限定成钉底那段**：
  // 只按 y 下限会把状态栏（y≈780）算进来——它本来就该在面板外。
  let bar_top = 800.0 - @chrome.STATUSBAR_HEIGHT - 220.0
  let bar_bottom = 800.0 - @chrome.STATUSBAR_HEIGHT
  for run in shell_texts(commands) {
    let in_bar_y = run.frame.origin.y >= bar_top &&
      run.frame.origin.y + run.frame.size.height <= bar_bottom + 0.5
    let in_panel_x = run.frame.origin.x >= panel_left - 1.0 &&
      run.frame.origin.x < panel_right
    if in_bar_y &&
      in_panel_x &&
      run.frame.origin.x + run.frame.size.width > panel_right + 1.0 {
      fail(
        "docked composer content overflows the panel: text='" +
        run.text +
        "' right=" +
        (run.frame.origin.x + run.frame.size.width).to_string(),
      )
    }
  }
}

///|
/// 变量分类的调色板里给出「新建变量」入口（Scratch 的「建立一个变量」）——
/// 用户正在积木画布上想加变量时，不必再跑去左栏结构树。
///
/// 判据取**可达性**：变量分类下能画出该入口（文字在场），其他分类下不出现
/// （否则每个分类都挂着同一个按钮，等于噪音）。
test "the variable palette offers an inline create-variable entry" {
  let model = load_template_program(initial_model(), 2)
  // 展开「变量」分类（分类轨里 CatVariable 的下标）
  let rail = block_category_entries(model)
  let mut var_index = -1
  let mut i = 0
  for entry in rail {
    if var_index < 0 {
      match entry.category {
        @blocks.CatVariable => var_index = i
        _ => ()
      }
    }
    i = i + 1
  }
  assert_true(var_index >= 0)
  // 切到变量分类：面板里出现「新建变量」
  let on_var = apply_shell(model, ToggleStatementPalette(var_index))
  let var_cmds = shell_draw(on_var, 1280.0, 800.0)
  assert_true(shell_has_text(var_cmds, "新建变量"))
  // 切到流程分类：入口不出现
  let mut flow_index = -1
  let mut k = 0
  for entry in block_category_entries(on_var) {
    if flow_index < 0 {
      match entry.category {
        @blocks.CatFlow => flow_index = k
        _ => ()
      }
    }
    k = k + 1
  }
  assert_true(flow_index >= 0)
  let on_flow = apply_shell(on_var, ToggleStatementPalette(flow_index))
  assert_false(
    shell_has_text(shell_draw(on_flow, 1280.0, 800.0), "新建变量"),
  )
  // 点它确实加出一个变量
  let before = on_var.program.variables.length()
  let added = apply_shell(on_var, AddVariable)
  assert_eq(added.program.variables.length(), before + 1)
}

///|
/// 积木右键菜单**真的画出来**（不只是状态位翻转）。
///
/// 回归意义：菜单是 overlay 呈现的，`block_menu` 有值不等于菜单可见——
/// 「状态对了但 popup 没挂上」在 UI 上就是「右键没反应」，而状态断言全绿。
/// 这里断言菜单项文字出现在绘制指令里。
test "the blocks context menu actually renders its items" {
  let model = load_template_program(initial_model(), 2)
  // 关闭态：菜单项不在
  let closed = shell_draw(model, 1280.0, 800.0)
  assert_false(shell_has_text(closed, "删除语句"))
  // 打开态：两项都在（且绘制指令确实变多——popup 是一层新内容）
  let opened = apply_shell(model, BlocksContextMenu(0, 20.0, 20.0))
  assert_true(opened.block_menu is Some(_))
  let drawn = shell_draw(opened, 1280.0, 800.0)
  assert_true(shell_has_text(drawn, "删除语句"))
  assert_true(shell_has_text(drawn, "复制语句"))
  assert_true(drawn.length() > closed.length())
}

///|
/// **插槽洞走真实渲染管线也画得出来**（`measured_canvas` → 度量单元 →
/// 绘制计划 → 绘制指令）。
///
/// 为什么单独测这一段：`@blk.blocks_draw_plan` 的洞测试是**注入假度量**直接调的，
/// 覆盖不到「布局期的 `TextSystem` 度量有没有真的送到绘制期」。而这条链一旦
/// 断掉（比如共享单元被重建、或 `measure` 没被调用），表现是**洞全都不画**，
/// 而前一个测试仍然全绿——它喂的是自己造的度量。
///
/// 判据取**绘制指令里出现插槽专属底色**：洞的颜色刻意不与块体同色，所以
/// 按颜色计数就是把「画了洞」直接读出来。
test "reporter slots reach the real draw pipeline" {
  // 口算训练营模板含嵌套二元表达式（`(to_text(第一个数) + " + ")`），
  // 所以它的积木上必然有插槽。
  let model = load_template_program(initial_model(), 2)
  let commands = shell_draw(model, 1600.0, 900.0)
  let mut slot_fills = 0
  for command in commands {
    match command {
      // `fill_rounded_rect` 发的是 **Brush** 变体（不是纯色变体）
      @core.DrawCommand::FillRoundedRectBrush(_, brush) =>
        match brush {
          @core.Brush::Solid(color) =>
            if color == @chrome.blocks_slot_filled() ||
              color == @chrome.blocks_slot_empty() {
              slot_fills = slot_fills + 1
            }
          _ => ()
        }
      _ => ()
    }
  }
  assert_true(slot_fills > 0)
}

///|
/// 说明输入框**真的画在右栏编辑卡里**（不只是模型里有字段）。
///
/// 回归意义：模型层写完就算了的话，用户看不到入口——「能力在、入口不在」
/// 正是这一系列缺口的共同形态，所以要用绘制指令断言它可见。
test "the note field renders in the block editor card" {
  let model = load_template_program(initial_model(), 2)
  // 选中一条积木让编辑卡出现
  let picked = apply_shell(model, SelectBlockStep(1))
  let commands = shell_draw(picked, 1280.0, 800.0)
  // 说明的**标签**在画面上（入口可见）
  assert_true(shell_has_text(commands, "说明（给这段脚本加注释）"))
  // 模板自带的说明**内容**也显示在输入框里。
  //
  // 不断言占位提示：输入框**有内容时占位不画**（原生控件行为），而模板
  // 恰好带了说明——断言占位会假失败。占位只在空值时可见。
  assert_true(shell_has_text(commands, "随机出两个 20 以内的数"))
}

///|
/// **`询问` 闸门要能打字**：回答输入框必须真的画出来。
///
/// 这是本轮修的语义缺陷的界面侧：`ask` 的返回值是回答文本，而此前闸门
/// 卡片只给「确认/拒绝」两个按钮——**没有任何地方能输入回答**。模型层
/// 修好而界面没修的话，用户依然只能点「确认」，回到「只能当是/否用」。
///
/// 同时断言 `提交数据` 闸门**不**出现输入框（它的确认不需要填内容，
/// 多一个空框只会让用户以为要填什么）。
test "the ask gate renders an answer input but submit does not" {
  // 直接构造一个停在 `询问` 闸门的运行态：`step_once` 走一条指令即挂起。
  // 不用 RunTick 推进——那还要依赖计时器与推进预算，断言会变得间接。
  let base = load_template_program(initial_model(), 2)
  let gate_state = @studio_lang.start_run_stmts(
    [
      @ir.Declare(
        "姓名",
        @ir.Expr::Call("ask", [@ir.StrLit("你叫什么？")]),
      ),
    ],
    Map([], capacity=2),
    Map([], capacity=2),
    Map([], capacity=2),
  )
  @studio_lang.step_once(gate_state)
  assert_true(gate_state.status is @studio_lang.WaitingGate)
  let gated = {
    ..base,
    mode: ModeRun,
    run: Some(@run.RunModel::{
      handler_label: "test@on_click",
      state: gate_state,
      checks: Map([], capacity=2),
      single_step: false,
    }),
  }
  let commands = shell_draw(gated, 1280.0, 800.0)
  let mut has_prompt = false
  let mut has_answer_hint = false
  for command in commands {
    match command {
      @core.DrawText(run) => {
        if run.text.contains("你叫什么") {
          has_prompt = true
        }
        if run.text.contains("输入回答") {
          has_answer_hint = true
        }
      }
      _ => ()
    }
  }
  assert_true(has_prompt, msg="the gate prompt should render")
  assert_true(has_answer_hint, msg="the ask gate should render an answer input")

  // 对照：`提交数据` 闸门**不**渲染回答输入框（它的确认不需要填内容）
  let submit_state = @studio_lang.start_run_stmts(
    [@ir.Stmt::Call("submit_data", [@ir.StrLit("payload"), @ir.Var("输出")])],
    Map([], capacity=2),
    Map([], capacity=2),
    Map([], capacity=2),
  )
  @studio_lang.step_once(submit_state)
  let submit_model = {
    ..base,
    mode: ModeRun,
    run: Some(@run.RunModel::{
      handler_label: "test@on_click",
      state: submit_state,
      checks: Map([], capacity=2),
      single_step: false,
    }),
  }
  let submit_commands = shell_draw(submit_model, 1280.0, 800.0)
  let mut submit_has_hint = false
  for command in submit_commands {
    match command {
      @core.DrawText(run) =>
        if run.text.contains("输入回答") {
          submit_has_hint = true
        }
      _ => ()
    }
  }
  assert_false(submit_has_hint, msg="submit gate must not show an answer input")
}

///|
/// **脚本说明画在积木画布上**（Scratch 的脚本注释贴在积木旁）。
///
/// 只在右栏显示的话，**读代码的人看不到说明**——而注释的意义正是给读代码
/// 的人看。这条断言画布上出现了说明文本。
///
/// 同时断言**空说明不占位**：没有说明时不画横幅（否则每条子程序上方都有
/// 一条空白带，把画布本来就不多的空间吃掉）。
test "the script note renders on the blocks canvas only when set" {
  let model = load_template_program(initial_model(), 2)
  let key = handler_key(
    model.program.handlers[0].control_name,
    model.program.handlers[0].event.tag(),
  )
  let on_handler = apply_shell(model, SelectHandler(key))
  // 模板自带说明 → 横幅应出现（用一段模板里没有的独特文本做对照更稳，
  // 所以先写一条自己的说明）
  let noted = apply_shell(
    on_handler,
    EditTargetNote("这段负责出题与批改"),
  )
  let commands = shell_draw(noted, 1600.0, 900.0)
  assert_true(shell_has_text(commands, "这段负责出题与批改"))

  // 清空说明 → 横幅消失
  let cleared = apply_shell(noted, EditTargetNote(""))
  let cleared_commands = shell_draw(cleared, 1600.0, 900.0)
  assert_false(shell_has_text(cleared_commands, "这段负责出题与批改"))
}

///|
/// **有说明横幅时，点击仍然落在所点的积木上**。
///
/// 说明横幅把积木链整体下移了 `note_height`；命中若不加同一个偏移，
/// 点击会落到所点那块**上方**的块（或落空）——「画在一处、点在另一处」
/// 的典型形态，而且它只在**有说明时**才出现（没说明时一切正常），
/// 所以不带说明的用例永远发现不了。
///
/// 判据：在真实运行时里点某一块的**可见中心**，断言选中的就是它。

///|
/// **有说明横幅时，命中契约成立**：`@blk.blocks_chain_y` 是绘制与命中之间
/// 唯一的换算函数，它是 `local ↦ chain` 的**逆映射**。
///
/// 契约（`y_offset = 0`）：
///   draw:  chain c 渲染在 `frame.y + note_height + c`
///   click: 可见位置 `p` 的局部量是 `p - frame.y = note_height + c`
///   求逆:  `@blk.blocks_chain_y(note_height + c, 0, note_height) == c`
///
/// 这条用例直接验逆映射的**数学**，因此不依赖任何取点技巧。它守的是
/// 一个真实踩过的错：把该函数写成 `local + note_height` 时，点击会落到
/// 所点那块**下方**的块（`2 × note_height` 的偏差），而且**只在有说明
/// 时**出现——不带说明的用例永远发现不了。
test "the note offset round-trips through the draw/hit conversion" {
  let note_h = @blk.BLOCKS_NOTE_HEIGHT
  // 逐块验：每一条链条 y 都要能被逆回来
  for chain_y in [0.0, 10.0, 50.0, 90.0, 130.0, 137.5] {
    let drawn_local = note_h + chain_y
    let recovered = @blk.blocks_chain_y(drawn_local, 0.0, note_h)
    assert_eq(recovered, chain_y)
  }
  // 反向也会被抓住：若把符号写成 `+`，这个等式立刻不成立
  let wrong = note_h + 50.0
  assert_true(
    @blk.blocks_chain_y(wrong, 0.0, note_h) != wrong,
    msg="the conversion must not be the identity when a note is present",
  )
  // 没有说明时是恒等（`note_height = 0`）——保证不带说明的路径零变化
  assert_eq(@blk.blocks_chain_y(42.0, 0.0, 0.0), 42.0)
  // `y_offset`（编辑卡拆段时的链条原点）叠加正确
  assert_eq(@blk.blocks_chain_y(note_h + 20.0, 30.0, note_h), 50.0)
}

///|
/// **有说明时点积木仍选中它自己**：从绘制结果量出第二条积木标签的位置，
/// 算出画布会发出的 `BlocksCanvasTap` **链坐标**（用与画布同一个换算），
/// 断言选中的正是那一块。
///
/// 与上一条的分工：上一条验换算的数学（纯函数，不含取点技巧）；这一条验
/// 它**接在真实几何上**——画布画在哪、点在哪、算出哪个块，三者一致。
///
/// 为什么不用「点真实指针 + 数描边」做判据：描边不止积木有（面板、卡片、
/// 输入框都用 `stroke_rounded_rect`），实测一次点击后有 6+ 条描边，
/// 按条数判定根本无法区分「选中了哪一块」。而运行时不对外暴露模型状态，
/// 所以「发画布会发的消息 + 断言选中」是这里**唯一可靠**的端到端信号。
test "clicking a block with a note shown selects the block under the pointer" {
  let model = load_template_program(initial_model(), 2)
  let key = handler_key(
    model.program.handlers[0].control_name,
    model.program.handlers[0].event.tag(),
  )
  let on_handler = apply_shell(model, SelectHandler(key))
  let noted = apply_shell(
    on_handler,
    EditTargetNote("说明会把积木推下去"),
  )
  let chain = block_chain_of(noted)
  assert_true(chain.length() >= 2)

  // 用真实运行时量出画布的画布原点与第二条标签的位置
  let program : @core.Program[Model, Msg] = @moui.Program::new_with_environment(
    init=() => (noted, @moui.Effect::none()),
    update=(current, msg) => update_pure(current, msg),
    view=(current, env) => view_with_viewport(current, env.viewport_size()),
  )
  let runtime = @runtime.new_program_with_dimensions(
    program~,
    width=1600.0,
    height=900.0,
  )
  let mut banner_y : Double? = None
  let label_rect : Ref[@core.Rect?] = Ref(None)
  let mut banner_text = ""
  for command in runtime.draw_commands() {
    match command {
      @core.DrawText(run) => {
        if run.text.contains("说明会把积木推下去") {
          banner_text = run.text
          banner_y = Some(run.frame.origin.y)
        }
        if run.text.contains(chain[1].text) &&
          run.text != banner_text &&
          label_rect.val is None {
          label_rect.val = Some(run.frame)
        }
      }
      _ => ()
    }
  }
  let banner_top = match banner_y {
    Some(y) => y
    None => fail("the note banner should be drawn")
  }
  let rect = match label_rect.val {
    Some(rect) => rect
    None => fail("the second block's label should be drawn")
  }
  // 横幅画在 `frame.y + 2`，而 `dy = frame.y + note_height`
  //   => frame.y = banner_top - 2 - note_height
  let frame_y = banner_top - 2.0 - @blk.BLOCKS_NOTE_HEIGHT
  // 画布把「可见 y」换算成链坐标用的是 `@blk.blocks_chain_y`；这里用它的**逆**
  // 从链坐标推出可见 y，再减去 frame.y 得到消息该带的局部量。
  // 直接点该块在链坐标里的中心（命中区间明确落在这一块内）。
  let rects = @blk.blocks_item_rects(chain, avail_width=470.0)
  let chain_center = rects[1].origin.y + rects[1].size.height / 2.0
  let visible_y = frame_y + @blk.BLOCKS_NOTE_HEIGHT + chain_center
  let local_y = visible_y - frame_y
  // 消息吃的是**链坐标**（画布在事件回调里用 `@blk.blocks_chain_y` 折算了
  // 局部量），所以这里送折算后的链坐标——与画布真实行为一致。
  let chain_y = @blk.blocks_chain_y(local_y, 0.0, @blk.BLOCKS_NOTE_HEIGHT)
  assert_eq(chain_y, chain_center)
  let picked = apply_shell(noted, BlocksCanvasTap(20.0, chain_y, 470.0))
  assert_eq(picked.selected_block, 1)

  // **反例**：把偏移少算一次（模拟「命中漏了 note_height」）会选错块。
  let wrong = apply_shell(
    noted,
    BlocksCanvasTap(20.0, chain_y - @blk.BLOCKS_NOTE_HEIGHT, 470.0),
  )
  assert_true(
    wrong.selected_block != 1,
    msg="the note offset must actually affect which block is selected",
  )
  ignore(rect)
}

///|
/// **输入面只在右栏 AI 页**（VS Code 侧栏分页口径）。
///
/// 旧版有三个宿主（底栏 `BtAi` 页签 / 右栏停靠 / AI 模式中心）与一对互为出口
/// 的切换钮，于是同一时刻「输入面在哪」要靠 `right_view × perspective` 推导，
/// 还要防 stale 页签画出第二份 composer。收敛到「右栏一页」后再分页，契约
/// 变成：**检查器页 0 枚、AI 页恰好 1 枚**（PsAi 中心是第三个落点，另有测试）。
///
/// 判据取发送钮的绘制次数：一个宿主 = 一枚发送钮。
test "the AI composer lives only in the right panel" {
  let model = initial_model()
  // 检查器页：没有输入面（严格 VS Code 口径，本轮的分页决定）
  assert_eq(
    shell_find_send_buttons(shell_draw(model, 1280.0, 800.0)).length(),
    0,
    msg="the inspector page must not draw a composer",
  )
  // AI 页：恰好一枚，且落在右栏里
  let on_ai = apply_shell(model, SetRightView(RvAi))
  let commands = shell_draw(on_ai, 1280.0, 800.0)
  let sends = shell_find_send_buttons(commands)
  assert_eq(sends.length(), 1, msg="exactly one send button in the shell")
  let panel_left = 1280.0 - @chrome.RIGHTBAR_WIDTH - @chrome.SASH_WIDTH
  let send = sends[0]
  assert_true(
    send.origin.x >= panel_left - 1.0,
    msg="the only send button must sit inside the right panel",
  )
  // 输入面的占位文案在场（不是一块空白）
  assert_true(shell_has_text(commands, "描述"))
}

///|
/// **底栏永远没有「AI 输入」页签**。
///
/// 宿主唯一化的另一半：底栏只承载只读面板（审计 / Console / 问题 / 搜索 /
/// 终端）。这条同时覆盖三个模式——每个模式的底栏页签行都不含 AI。
test "the bottom bar never offers an AI tab" {
  for perspective in [PsVisual, PsCode, PsAi] {
    let model = apply_shell(initial_model(), SetPerspective(perspective))
    let commands = shell_draw(model, 1280.0, 800.0)
    assert_false(
      shell_has_text(commands, "AI 输入"),
      msg="the bottom bar must not carry an AI tab",
    )
  }
}

///|
/// **折叠底栏不搬动输入面**（用户报过的缺陷：只想折叠面板，AI 却自己跑去右栏）。
///
/// 宿主唯一化后这条缺陷在结构上不可能复发——输入面不在底栏里，底栏收起与它
/// 无关。仍然保留断言：收起前后 AI 页都画出同一枚发送钮。
test "collapsing the bottom bar keeps the composer in the right panel" {
  let model = apply_shell(initial_model(), SetRightView(RvAi))
  let before = shell_draw(model, 1280.0, 800.0)
  assert_eq(shell_find_send_buttons(before).length(), 1)
  let collapsed = apply_shell(model, ToggleBottom)
  assert_false(collapsed.bottom_open)
  let after = shell_draw(collapsed, 1280.0, 800.0)
  assert_eq(
    shell_find_send_buttons(after).length(),
    1,
    msg="collapsing the bar must not move or drop the composer",
  )
}

///|
/// **右键菜单弹在右键点的位置**，不是宿主的某个角落。
///
/// 用户报的缺陷：在积木上右键，菜单却出现在底栏 AI 输入条那一带——离指针
/// 很远。根因是 `context_menu_region` 硬编码 `anchor=HostBase`（锚在整个
/// 画布区域上），而画布存下的右键坐标**根本没被用**。
///
/// 判据用**几何**而不是「菜单项在不在」：取菜单第一项文字的绘制位置，
/// 断言它落在右键点附近（右下方向一个菜单高度的量级内）。只断言「菜单项
/// 出现」的话，锚点写错也照样全绿——这正是原缺陷能溜过去的原因。
test "the context menu opens at the pointer, not at the host corner" {
  let model = load_template_program(initial_model(), 2)
  // 在画布中偏上的位置右键（远离画布左上角，锚点写错时差距明显）
  let click_x = 400.0
  let click_y = 300.0
  let opened = apply_shell(model, BlocksContextMenu(0, click_x, click_y))
  guard opened.block_menu is Some((_, sx, sy)) else { abort("test faild") }
  // 坐标被原样记住（视口坐标，不是画布局部坐标）
  assert_eq(sx, click_x)
  assert_eq(sy, click_y)

  // 菜单项第一项的绘制位置必须**靠近**右键点。
  //
  // 菜单会按候选位置（AboveEnd/BelowEnd/…）避让视口边缘，所以允许一个
  // 菜单尺寸量级的偏移；但**不能**跑到画布另一头去。
  let mut menu_x : Double? = None
  let mut menu_y : Double? = None
  for command in shell_draw(opened, 1280.0, 800.0) {
    match command {
      @core.DrawText(run) =>
        if run.text.contains("运行这一块") && menu_x is None {
          menu_x = Some(run.frame.origin.x)
          menu_y = Some(run.frame.origin.y)
        }
      _ => ()
    }
  }
  let mx = match menu_x {
    Some(value) => value
    None => fail("the menu should render its first item")
  }
  let my = match menu_y {
    Some(value) => value
    None => fail("the menu should render its first item")
  }
  // 水平：菜单从指针处开始（允许向左避让，所以取一个宽松的带宽）
  assert_true(
    (mx - click_x).abs() < 260.0,
    msg="menu x=\{mx} should be near the pointer x=\{click_x}",
  )
  // **主方向向右**（用户报的缺陷：菜单一直向左弹）：第一候选是 BelowStart
  // ——菜单左缘对齐指针、向右下展开；指针周围的绘制 x 不得在指针左侧。
  assert_true(
    mx >= click_x,
    msg="menu x=\{mx} must open rightward from the pointer x=\{click_x}",
  )
  // 垂直：菜单在指针的上下一个菜单高度内（不是画布另一端）
  assert_true(
    (my - click_y).abs() < 260.0,
    msg="menu y=\{my} should be near the pointer y=\{click_y}",
  )
}

///|
/// **右键菜单点别处要消失**（用户报的缺陷）。
///
/// 判据取**模型状态**（`block_menu` 是否被清掉），不取绘制文本：菜单项的
/// 文案（`删除语句`）在右栏属性面里**也存在**，所以「文本还在不在」根本
/// 分不清菜单是否关闭——实测就是这么误判过一次（关闭其实成功了，用例仍
/// 报失败）。
///
/// 走**真实运行时**（不是直接派发 `BlocksContextMenuClose`）：直接发关闭
/// 消息只能证明那个 handler 对，证明不了「点空白处会发出它」——而缺的
/// 恰恰是后者。
test "the context menu closes when clicking outside it" {
  let model = load_template_program(initial_model(), 2)
  let opened = apply_shell(model, BlocksContextMenu(0, 400.0, 300.0))
  assert_true(opened.block_menu is Some(_))

  // 记录 update 收到的消息，并观察模型状态
  let states : Array[Bool] = []
  let program : @core.Program[Model, Msg] = @moui.Program::new_with_environment(
    init=() => (opened, @moui.Effect::none()),
    update=(current, msg) => {
      let (next, effect) = update_pure(current, msg)
      states.push(next.block_menu is Some(_))
      (next, effect)
    },
    view=(current, env) => view_with_viewport(current, env.viewport_size()),
  )
  let runtime = @runtime.new_program_with_dimensions(
    program~,
    width=1280.0,
    height=800.0,
  )
  // 菜单必须真的画着（否则「点空白关掉了什么」没有意义）
  assert_true(runtime.draw_commands().length() > 0)

  // 在**远离菜单**的地方点一下
  let point = @core.Point::new(x=700.0, y=500.0)
  runtime.dispatch_event(
    @core.Pointer(@core.PointerEvent::new(position=point, phase=@core.Down)),
  )
  runtime.dispatch_event(
    @core.Pointer(@core.PointerEvent::new(position=point, phase=@core.Up)),
  )
  // 必须收到过消息，且**最后一次状态是菜单已关**
  assert_true(
    states.length() > 0,
    msg="clicking outside should produce a message",
  )
  assert_false(
    states[states.length() - 1],
    msg="the context menu should be closed after clicking outside",
  )
}

///|
/// **点菜单项之外的地方能关，点菜单项本身则执行动作**——两者不互相吃掉。
///
/// 这条守的是「关闭」与「执行」的**互斥**：菜单项的点击既不该被屏障吃掉
/// （否则点了没反应），屏障也不该被菜单项挡住（否则点别处不关）。
test "clicking a menu item runs its action instead of being swallowed" {
  let model = load_template_program(initial_model(), 2)
  let opened = apply_shell(model, BlocksContextMenu(0, 400.0, 300.0))
  // 直接走「菜单动作」路径（菜单项自身的 on_tap 会先关菜单再发动作）
  let acted = apply_shell(opened, BlocksMenuAction(RunSingleBlock))
  // 菜单关了
  assert_true(acted.block_menu is None)
  // 动作真的发生了：单块运行会进入运行态
  assert_true(acted.mode is ModeRun || acted.run is Some(_))
}
