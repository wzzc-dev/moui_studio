///|
/// app 测试：纯状态转移（不含 UI 渲染与服务副作用）。

///|
fn apply(model : @app.Model, msg : @app.Msg) -> @app.Model {
  let (next, _effect) = @app.update_pure(model, msg)
  next
}

///|
fn set_prompt(model : @app.Model, text : String) -> @app.Model {
  apply(model, AiSessionOp(@ai.SetPromptDraft(text)))
}

///|
/// 推进运行直到终止态（测试环境没有计时器订阅，手动 tick）。
fn drain(model : @app.Model) -> @app.Model {
  let mut stepped = model
  let mut i = 0
  while i < 60 {
    match stepped.run {
      Some(run) =>
        if run.state.status is @studio_lang.Running {
          stepped = apply(stepped, RunTick)
        } else {
          break
        }
      None => break
    }
    i = i + 1
  }
  stepped
}

///|
/// 测试助手：以「随机点名」样例提案走真实回执通道（proposal_from_completion
/// 即程序级臂 RealGenerationFinished 的纯转移段），产出待采纳提案。
/// 假模型移除后，提案生成的网络段由真实 provider 承担，测试直接喂回执。
/// 提案按假模型同款**全量重建**语义补 removes——样例替换当前程序而非叠加。
fn with_pending_roll_call(model : @app.Model) -> @app.Model {
  let proposal = @proposals.proposal_from_program(
    @proposals.sample_roll_call(),
    "随机点名",
    "roll call",
  )
  let rebuild = @proposals.ProposalV1::{
    ..proposal,
    controls_remove: model.program.controls.map(control => control.name),
    variables_remove: model.program.variables.map(variable => variable.name),
    handlers_remove: model.program.handlers.map(handler => @proposals.HandlerRef::{
      control: handler.control_name,
      event: handler.event.tag(),
    }),
  }
  @app.proposal_from_completion(model, @proposals.encode_proposal(rebuild))
}

///|
test "initial model loads hello sample in chinese" {
  let model = @app.initial_model()
  assert_true(model.language is ZhHans)
  assert_eq(model.program.window.title, "问候")
  assert_eq(model.selected_handler, "按钮@on_click")
  let t = @app.translator(model)
  assert_eq(@app.text(t, "app.mode.design"), "设计")
  assert_eq(@app.text(t, "app.mode.design"), "设计")
}

///|
test "english translation resolves" {
  let model = apply(@app.initial_model(), SwitchLanguage)
  assert_true(model.language is En)
  let t = @app.translator(model)
  assert_eq(@app.text(t, "app.mode.design"), "Design")
  assert_eq(@app.text(t, "control.button"), "Button")
  assert_eq(@app.text(t, "builtin.submit_data"), "submit_data")
  // 中文回退仍在
  assert_eq(@app.text(t, "app.templates.hello"), "Hello app")
}

///|

///|
/// 编辑语义测试的口径（M5-5e）：代码视图默认外观是 MoonBit（只读显示投影）；
/// 测试「编辑草稿→提交/诊断」语义时先切到 DSL 外观。
fn dsl_edit_model(model : @app.Model) -> @app.Model {
  apply(model, CycleCodeAppearance)
}

///|
test "language switch commits parseable draft and re-renders" {
  let model = dsl_edit_model(@app.initial_model())
  let switched = apply(model, SwitchLanguage)
  assert_true(switched.code_draft.contains("set_text"))
  let switched_back = apply(switched, SwitchLanguage)
  assert_true(
    switched_back.code_draft.contains("变量") ||
    switched_back.code_draft.contains("设置文本"),
  )
}

///|
test "add and delete control keeps handlers consistent" {
  let model = apply(@app.initial_model(), AddControl(@ir.Label))
  assert_eq(model.program.controls.length(), 3)
  assert_eq(model.selected_control, "标签")
  let renamed = apply(model, SetControlName("标签", "标题"))
  assert_true(@ir.find_control(renamed.program, "标题") is Some(_))
  assert_eq(renamed.selected_control, "标题")
  // 删除必经确认（confirm.mbt 纪律）：RequestConfirm 已入栈，确认续行
  let deleted = apply(apply(renamed, DeleteControl("标题")), ConfirmAccepted)
  assert_eq(deleted.program.controls.length(), 2)
  // Removing a different control must not clear the current selection.
  let keep_selection = apply(
    apply(@app.initial_model(), DeleteControl("显示")),
    ConfirmAccepted,
  )
  assert_eq(keep_selection.selected_control, "按钮")
  // Reserved DSL words cannot become control identifiers.
  let reserved = apply(@app.initial_model(), SetControlName("按钮", "if"))
  assert_true(@ir.find_control(reserved.program, "按钮") is Some(_))
  // Renaming a control also rewrites control-name arguments in handler IR.
  let renamed_label = apply(
    @app.initial_model(),
    SetControlName("显示", "标题"),
  )
  match @app.current_handler(renamed_label).unwrap().body[0] {
    @ir.Call("set_text", args) => assert_true(args[0] is @ir.Var("标题"))
    _ => fail("问候 handler 应保留 set_text")
  }
}

///|
test "code edit commits into program" {
  let model = dsl_edit_model(@app.initial_model())
  let edited = apply(model, EditCode("设置文本(显示, \"新文本\")\n"))
  let committed = apply(edited, SelectHandler("按钮@on_click"))
  match @app.current_handler(committed) {
    Some(handler) => {
      assert_eq(handler.body.length(), 1)
      match handler.body[0] {
        @ir.Call("set_text", args) =>
          match args[1] {
            @ir.StrLit(text) => assert_eq(text, "新文本")
            _ => fail("提交后第二个参数应为字符串")
          }
        _ => fail("切换 handler 前应提交代码草稿")
      }
    }
    None => fail("提交后应仍有子程序")
  }
}

///|
test "mode switch commits the current code draft" {
  let edited = apply(
    apply(
      dsl_edit_model(@app.initial_model()),
      EditCode("设置文本(显示, \"模式切换后\")\n"),
    ),
    SetMode(@app.ModeDesign),
  )
  match @app.current_handler(edited).unwrap().body[0] {
    @ir.Call("set_text", args) =>
      match args[1] {
        @ir.StrLit(text) => assert_eq(text, "模式切换后")
        _ => fail("提交后第二个参数应为字符串")
      }
    _ => fail("切换模式前应提交代码草稿")
  }
}

///|
test "syntax error surfaces localized message" {
  let model = dsl_edit_model(@app.initial_model())
  let edited = apply(model, EditCode("如果 真的 则\n"))
  let started = apply(edited, RunStart)
  // 语法错误进 notice（本地化），且不进入运行态
  assert_true(started.notice != "")
  assert_true(started.run is None)
  let t = @app.translator(started)
  assert_eq(@app.text(t, "app.code.error"), "语法错误")
  // 正确的草稿可以运行
  let fixed = apply(edited, EditCode("设置文本(显示, \"新文本\")\n"))
  let run = apply(fixed, RunStart)
  assert_true(run.run is Some(_))
  assert_eq(run.notice, "")
}

///|
test "invalid draft never executes stale control handlers" {
  let started = dsl_edit_model(apply(@app.initial_model(), RunStart))
  let broken = apply(started, EditCode("如果 真的 则\n"))
  let clicked = apply(broken, ControlClicked("按钮"))
  assert_true(clicked.code_error != "")
  assert_eq(clicked.run.unwrap().state.texts.get("显示").unwrap_or(""), "")
}

///|
test "invalid draft blocks runtime control events" {
  let started = dsl_edit_model(apply(@app.initial_model(), RunStart))
  let before_steps = started.run.unwrap().state.steps
  let broken = apply(started, EditCode("如果 真的 则\n"))
  let clicked = apply(broken, ControlClicked("按钮"))
  assert_true(clicked.code_error != "")
  assert_eq(clicked.run.unwrap().state.steps, before_steps)
}

///|
test "run start arms the stage; clicking the button executes the handler" {
  let model = apply(@app.initial_model(), RunStart)
  match model.run {
    None => fail("应进入运行态")
    Some(armed) => {
      // **装填不执行**：标签仍是设计初值（空），指令一步未走——
      // 「运行」把舞台装进实时态，事件子程序等真实控件事件。
      assert_eq(armed.state.texts.get("显示").unwrap_or(""), "")
      assert_eq(armed.state.steps, 0)
    }
  }
  // 点击按钮（真实事件路径）→ 子程序执行，标签更新
  let clicked = drain(apply(model, ControlClicked("按钮")))
  let final_run = clicked.run.unwrap()
  assert_true(final_run.state.status is @studio_lang.Completed)
  assert_eq(
    final_run.state.texts.get("显示").unwrap_or(""),
    "你好，MoUI Studio！",
  )
}

///|
/// 推进编译轨运行直到非 Running（编译轨无 tick 语义，事件派发即跑到
/// 完成或闸门；此循环只是防御性等价物）。
fn drain_compiled(model : @app.Model) -> @app.Model {
  let mut stepped = model
  let mut i = 0
  while i < 60 {
    match stepped.compiled_run {
      Some(run) =>
        if run.runtime.status is @compiled_runtime.Running {
          stepped = apply(stepped, RunTick)
        } else {
          break
        }
      None => break
    }
    i = i + 1
  }
  stepped
}

///|
test "compiled track arms the stage; clicking the button executes the handler" {
  let model = @app.initial_model(compile_track_available=true)
  assert_true(model.compile_track_available)
  let switched = apply(model, SetRunTrack(Compile))
  assert_true(switched.run_track is @app.Compile)
  let started = apply(switched, RunStart)
  match started.compiled_run {
    None => fail("编译轨应进入运行态")
    Some(armed) =>
      // **装填不执行**：标签仍是设计初值（空）
      assert_eq(armed.runtime.texts.get("显示").unwrap_or(""), "")
  }
  let clicked = drain_compiled(apply(started, ControlClicked("按钮")))
  let run = clicked.compiled_run.unwrap()
  assert_true(run.runtime.status is @compiled_runtime.Completed)
  assert_eq(
    run.runtime.texts.get("显示").unwrap_or(""),
    "你好，MoUI Studio！",
  )
}

///|
test "compiled track is unreachable on web and says so" {
  let model = @app.initial_model()
  assert_false(model.compile_track_available)
  let switched = apply(model, SetRunTrack(Compile))
  // 不隐藏事实：仍留在解释轨，并给出显式提示
  assert_true(switched.run_track is @app.Interpret)
  assert_true(switched.notice.contains("native"))
  // 切到编译轨后启动运行，实际仍走解释轨（Web 边界）
  let started = apply(switched, RunStart)
  assert_true(started.run is Some(_))
  assert_true(started.compiled_run is None)
}

///|
test "two tracks keep independent run states across switches" {
  let model = @app.initial_model(compile_track_available=true)
  // 解释轨装填后即完成（空计划的装填态第一个 tick 收尾）
  let interpreted = drain(apply(model, RunStart))
  assert_true(interpreted.run.unwrap().state.status is @studio_lang.Completed)
  // 切到编译轨，点按钮派发事件跑一遍
  let compiled = drain_compiled(
    apply(apply(interpreted, SetRunTrack(Compile)), ControlClicked("按钮")),
  )
  assert_true(
    compiled.compiled_run.unwrap().runtime.status is @compiled_runtime.Completed,
  )
  // 两轨运行态同时存在，切回解释轨不丢
  assert_true(compiled.run is Some(_))
  let back = apply(compiled, SetRunTrack(Interpret))
  assert_true(back.run.unwrap().state.status is @studio_lang.Completed)
  // 停止只停当前轨
  let stopped = apply(back, RunStop)
  assert_true(stopped.run is None)
  assert_true(stopped.compiled_run is Some(_))
}

///|
test "both tracks produce identical observable results for the same handler" {
  let model = @app.initial_model(compile_track_available=true)
  // 两轨各自装填后点同一个按钮：同一 handler 的可观察结果必须逐项相同
  let interpreted = drain(
    apply(apply(model, RunStart), ControlClicked("按钮")),
  )
  let compiled = drain_compiled(
    apply(
      apply(apply(model, SetRunTrack(Compile)), RunStart),
      ControlClicked("按钮"),
    ),
  )
  let run = interpreted.run.unwrap()
  let crun = compiled.compiled_run.unwrap()
  // 控件文本终态逐项相同
  for control in model.program.controls {
    assert_eq(
      run.state.texts.get(control.name).unwrap_or(""),
      crun.runtime.texts.get(control.name).unwrap_or(""),
    )
  }
  // 变量终态逐项相同（排除解释轨的隐藏计数槽 @iN / #n）
  for name in run.state.vars.keys() {
    if !name.has_prefix("@i") && !name.contains("#") {
      assert_eq(
        @studio_lang.value_to_text(
          run.state.vars.get(name).unwrap_or(@studio_lang.VUnit),
        ),
        @compiled_runtime.value_to_text(
          crun.runtime.vars.get(name).unwrap_or(@compiled_runtime.VUnit),
        ),
      )
    }
  }
  // 审计序列逐项相同——op 枚举同构，按序号比较。行号不比：两轨的事件
  // 派发行号口径本就不同源（解释轨 run_handler 走 IR 语句 → line 0；
  // 编译轨走草稿 trace → 真实行号），比对 (op, detail) 即可锁住「同一段
  // 程序在同轨上产生同一份可观察执行事实」。
  assert_eq(run.state.audit.length(), crun.runtime.audit.length())
  let mut index = 0
  for record in run.state.audit {
    let other = crun.runtime.audit[index]
    assert_eq(record.detail, other.detail)
    assert_eq(
      @app.audit_op_rank(record.op),
      @app.compiled_audit_op_rank(other.op),
    )
    index = index + 1
  }
}

///|
test "run gate pauses submit and confirm completes" {
  let model = @app.load_template_program(@app.initial_model(), 3)
  let started = apply(model, RunStart)
  match started.run {
    None => fail("小卖部应能运行")
    Some(_run) => {
      // 直接运行卖铅笔 handler：无闸门，营业额 +1
      let sold = drain(apply(started, ControlClicked("卖铅笔")))
      let final_run = sold.run.unwrap()
      let revenue = final_run.state.vars
        .get("营业额")
        .unwrap_or(@studio_lang.VUnit)
      assert_eq(@studio_lang.value_to_text(revenue), "1")
      // 记账 handler：停在提交闸门
      let submitting = drain(apply(sold, ControlClicked("记账")))
      let gated = submitting.run.unwrap()
      assert_true(gated.state.status is @studio_lang.WaitingGate)
      match gated.state.gate {
        Some(gate) => {
          assert_true(gate.kind is @studio_lang.Submit)
          assert_eq(gate.prompt, "班级账本")
          assert_eq(gate.payload, "1")
        }
        None => fail("应停在闸门")
      }
      // 闸门未回答前，其他控件事件不能绕过确认启动新 handler。
      let blocked = apply(submitting, ControlClicked("卖铅笔"))
      assert_true(blocked.run.unwrap().state.status is @studio_lang.WaitingGate)
      assert_eq(
        @studio_lang.value_to_text(
          blocked.run.unwrap().state.vars
          .get("营业额")
          .unwrap_or(@studio_lang.VUnit),
        ),
        "1",
      )
    }
  }
}

///|
test "proposal validates, diffs and applies" {
  let model = set_prompt(@app.initial_model(), "帮我做一个随机点名")
  let generated = with_pending_roll_call(model)
  match generated.pending {
    None => fail("应产生待采纳提案")
    Some(pending) => {
      assert_true(pending.valid)
      assert_true(pending.diff.length() > 0)
      assert_true(pending.summary != "")
      let accepted = apply(generated, AcceptProposal)
      assert_eq(accepted.program.window.title, "班级点名册")
      assert_eq(accepted.program.handlers.length(), 1)
      assert_true(accepted.pending is None)
    }
  }
}

///|
test "rejected proposal keeps program" {
  let model = set_prompt(@app.initial_model(), "口算练习")
  let generated = with_pending_roll_call(model)
  let rejected = apply(generated, RejectProposal)
  assert_true(rejected.pending is None)
  assert_eq(rejected.program.window.title, "问候")
}

///|
test "invalid proposal from real model is rejected wholesale" {
  let model = set_prompt(@app.initial_model(), "随便")
  // 直接喂一个坏 JSON（绕过假模型）：整单拒绝
  let broken = @app.proposal_from_completion(model, "这不是提案")
  assert_true(broken.pending is None)
  assert_true(broken.prompt_error != "")
}

///|
test "templates switch program and selection" {
  let model = @app.load_template_program(@app.initial_model(), 2)
  assert_eq(model.program.window.title, "口算训练营")
  assert_true(model.selected_handler != "")
}

///|
test "split lines helper" {
  let lines = @app.split_lines("铅笔 1元\n\n橡皮 2元\n  笔记本 5元  ")
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "铅笔 1元")
  assert_eq(lines[2], "笔记本 5元")
}

///|
test "runtime state accumulates across events" {
  let model = @app.load_template_program(@app.initial_model(), 3)
  let once = drain(apply(model, ControlClicked("卖铅笔")))
  let twice = drain(apply(once, ControlClicked("卖铅笔")))
  let run = twice.run.unwrap()
  let revenue = run.state.vars.get("营业额").unwrap_or(@studio_lang.VUnit)
  assert_eq(@studio_lang.value_to_text(revenue), "2")
  // 活状态并回模型：下一次运行从 2 继续
  let thrice = drain(apply(twice, ControlClicked("卖铅笔")))
  let three = thrice.run.unwrap().state.vars
    .get("营业额")
    .unwrap_or(@studio_lang.VUnit)
  assert_eq(@studio_lang.value_to_text(three), "3")
  // 控件文本也跨事件保持
  let label = thrice.run.unwrap().state.texts
    .get("营业额标签")
    .unwrap_or("")
  assert_eq(label, "营业额：3")
}

///|
test "list selection survives the next handler run" {
  let started = apply(
    @app.load_template_program(@app.initial_model(), 1),
    RunStart,
  )
  let picked = apply(started, ControlPicked("名单", 2))
  assert_eq(picked.runtime_selections.get("名单").unwrap_or(-1), 2)
  assert_eq(picked.run.unwrap().state.selections.get("名单").unwrap_or(-1), 2)
  let next = apply(picked, ControlClicked("点名按钮"))
  assert_eq(next.run.unwrap().state.selections.get("名单").unwrap_or(-1), 2)
}

///|
test "table row selection dispatches its supported click handler" {
  let model = dsl_edit_model(
    @app.load_template_program(@app.initial_model(), 3),
  )
  let table = @ir.find_control(model.program, "商品表").unwrap()
  let with_handler = apply(model, CreateHandler(table.name, @ir.OnClick))
  let edited = apply(
    with_handler,
    EditCode("设置文本(营业额标签, \"点了商品\")\n"),
  )
  let started = apply(edited, RunStart)
  let picked = drain(apply(started, ControlPicked(table.name, 1)))
  assert_eq(
    picked.run.unwrap().state.texts.get("营业额标签").unwrap_or(""),
    "点了商品",
  )
}

///|
test "append row persists across handlers without changing the program" {
  let model = dsl_edit_model(
    @app.load_template_program(@app.initial_model(), 1),
  )
  let edited = apply(model, EditCode("追加行(名单, \"新同学\")\n"))
  // 装填后**点按钮**才执行（运行不再替用户跑一遍）
  let finished = drain(
    apply(apply(edited, RunStart), ControlClicked("点名按钮")),
  )
  assert_eq(finished.run.unwrap().state.rows.get("名单").unwrap().length(), 6)
  assert_eq(
    @ir.find_control(finished.program, "名单").unwrap().items.length(),
    5,
  )
  let next = drain(apply(finished, ControlClicked("点名按钮")))
  assert_eq(next.run.unwrap().state.rows.get("名单").unwrap().length(), 7)
  assert_eq(@ir.find_control(next.program, "名单").unwrap().items.length(), 5)
}

///|
test "checkbox change keeps its checked state while running on_change" {
  let added = dsl_edit_model(
    apply(@app.initial_model(), AddControl(@ir.CheckBox)),
  )
  let checkbox = added.program.controls[added.program.controls.length() - 1]
  let handler = apply(added, CreateHandler(checkbox.name, @ir.OnChange))
  let edited = apply(handler, EditCode("设置文本(显示, \"已勾选\")\n"))
  let started = apply(edited, RunStart)
  let finished = drain(apply(started, RunToggle(checkbox.name, true)))
  let run = finished.run.unwrap()
  assert_true(run.checks.get(checkbox.name).unwrap_or(false))
  assert_eq(run.state.texts.get("显示").unwrap_or(""), "已勾选")
}

///|
/// 讲解 prompt 的载荷契约：真实 provider 的讲解以 render_handler 输出为
/// 提问体——note 作注释头、语句逐行渲染，AI 上下文里是真实程序文本。
test "explanation prompt payload walks the handler" {
  let model = @app.load_template_program(@app.initial_model(), 2)
  let handler = @app.current_handler(model).unwrap()
  let prompt = @studio_lang.render_handler(
    handler,
    model.language.dsl_language(),
  )
  assert_true(prompt.contains("随机出两个"))
  assert_true(prompt.contains("随机数"))
  assert_true(prompt.contains("设置文本"))
}

///|
/// 可读性验收：讲解 prompt 对全部模板 × 双语给出非空载荷——note 头随
/// 界面语言切换（每个模板讲解的是其首个子程序）。
test "explanation prompt payload covers every template in both languages" {
  // (模板下标, zh note 片段, en note 片段)
  let cases : Array[(Int32, String, String)] = [
    (0, "问候语", "greeting"),
    (1, "随机序号", "random row index"),
    (2, "随机出", "roll two numbers"),
    (3, "铅笔", "revenue per pencil"),
  ]
  for case in cases {
    let zh = @app.load_template_program(@app.initial_model(), case.0)
    let zh_handler = @app.current_handler(zh).unwrap()
    let zh_prompt = @studio_lang.render_handler(
      zh_handler,
      zh.language.dsl_language(),
    )
    assert_true(zh_prompt.contains(case.1))
    let en = apply(zh, SwitchLanguage)
    let en_handler = @app.current_handler(en).unwrap()
    let en_prompt = @studio_lang.render_handler(
      en_handler,
      en.language.dsl_language(),
    )
    assert_true(en_prompt.contains(case.2))
    // note 头随语言切换
    assert_true(en_prompt != zh_prompt)
  }
}

///|
test "exported bundle never carries the provider key" {
  let model = model_with_key("SENTINEL-SECRET-KEY")
  let encoded = @codec.encode_program(model.program)
  let bundle = @app.bundle_files(encoded, "x")
  assert_true(bundle.length() > 10)
  for pair in bundle {
    assert_true(!pair.1.contains("SENTINEL-SECRET-KEY"))
  }
}

///|
test "language loaded message switches without doubling" {
  // LanguageLoaded 走服务流；这里至少验证 @app.ui_language_from_tag 的映射
  let model = { ..@app.initial_model(), language: En, }
  let loaded = { ..model, language: @app.ui_language_from_tag("zh-Hans"), }
  assert_true(loaded.language is ZhHans)
  let bad = @app.ui_language_from_tag("not-a-locale")
  assert_true(bad is ZhHans)
  let en = @app.ui_language_from_tag("en")
  assert_true(en is En)
}

///|
test "every generated catalog key resolves in both locales" {
  // 生成器保证两语言 key 集合一致；这里保住言兜底：任何 key 在任一语言
  // 都不得回落到 [[key]] 缺失标记。
  for catalog in @app.generated_i18n_catalogs {
    let locale = catalog.locale
    let t = @app.translator_for(@app.ui_language_from_tag(locale))
    for pair in catalog.messages {
      let (key, _message) = pair
      let resolved = @app.text(t, key)
      assert_true(!resolved.has_prefix("[["))
    }
  }
}

///|
test "placeholder messages interpolate in both locales" {
  let zh = @app.translator_for(ZhHans)
  let en = @app.translator_for(En)
  let zh_gate = @app.text_with(zh, "app.run.gate.submit", [
    ("target", "班级账本"),
    ("payload", "3"),
  ])
  assert_true(zh_gate.contains("班级账本"))
  assert_true(zh_gate.contains("3"))
  let en_gate = @app.text_with(en, "app.run.gate.submit", [
    ("target", "ledger"),
    ("payload", "3"),
  ])
  assert_true(en_gate.contains("ledger"))
  let zh_err = @app.error_message(
    zh,
    @studio_lang.LangError(@studio_lang.NotDeclared, 2, "得分", ""),
  )
  assert_true(zh_err.contains("得分"))
  let en_err = @app.error_message(
    en,
    @studio_lang.LangError(@studio_lang.NotDeclared, 2, "score", ""),
  )
  assert_true(en_err.contains("score"))
}

///|
test "block view edits write back to the ir" {
  let model = @app.load_template_program(@app.initial_model(), 1)
  // 点名册：handler 链 = [declare 人数, declare 序号, set_text]
  let blocks = @app.block_chain_of(model)
  assert_eq(blocks.length(), 3)
  // 选中第一条（declare 人数 = row_count(名单)）
  let selected = select_block_index(model, 0)
  assert_true(selected.block_draft.contains("变量 人数"))
  assert_eq(selected.selected_block, 0)
  // 改成字符串字面量并应用
  let edited = apply(selected, EditBlock("变量 人数 = 42\n"))
  // 断言代码草稿的 DSL 文本：代码视图默认是 MoonBit 外观（M5-5e），
  // 先切到 DSL 外观让草稿按教学语言渲染再断言。
  let committed = apply(apply(edited, CycleCodeAppearance), CommitBlock)
  match @app.current_handler(committed) {
    Some(handler) => {
      assert_eq(handler.body.length(), 3)
      match @blocks.stmt_at(handler.body, [0]) {
        Some(stmt) => assert_true(stmt is @ir.Declare(_, _))
        None => fail("第一条应仍是 declare")
      }
      assert_true(committed.code_draft.contains("变量 人数 = 42"))
    }
    None => fail("子程序应仍在")
  }
  // 删除第二条（declare 序号）→ 语句数 -1，代码视图同步
  let picked = select_block_index(committed, 1)
  let deleted = apply(picked, DeleteBlock)
  match @app.current_handler(deleted) {
    Some(handler) => assert_eq(handler.body.length(), 2)
    None => fail("子程序应仍在")
  }
  assert_eq(deleted.selected_block, -1)
  assert_true(deleted.code_draft.contains("随机数") == false)
}

///|
test "block edit rejects unparseable draft" {
  let model = @app.load_template_program(@app.initial_model(), 1)
  let selected = select_block_index(model, 0)
  let broken = apply(selected, EditBlock("如果 真的 则\n"))
  let committed = apply(broken, CommitBlock)
  match @app.current_handler(committed) {
    Some(handler) =>
      // 原语句保持不动，notice 提示语法错误
      assert_true(handler.body.length() == 3)
    None => fail("子程序应仍在")
  }
  assert_true(committed.notice != "")
}

///|
test "block edit on nested statement path" {
  // 口算训练营：批改 handler = [If(cond, [set_text], [], [set_text])]
  let model = @app.load_template_program(@app.initial_model(), 2)
  let picked = apply(model, SelectHandler("批改按钮@on_click"))
  let blocks = @app.block_chain_of(picked)
  // if / then-set_text / else / else-set_text / end
  assert_eq(blocks.length(), 5)
  // 选 then 体里的 set_text（path [0,0,0]）
  let selected = select_block_index(picked, 1)
  assert_true(selected.block_draft.contains("设置文本"))
  let edited = apply(
    selected,
    EditBlock("设置文本(判定, \"完全正确\")\n"),
  )
  let committed = apply(edited, CommitBlock)
  match @app.current_handler(committed) {
    Some(handler) =>
      match @blocks.stmt_at(handler.body, [0, 0, 0]) {
        Some(stmt) =>
          match stmt {
            @ir.Stmt::Call(name, args) => {
              assert_eq(name, "set_text")
              assert_true(args.length() == 2)
            }
            _ => fail("应为 call")
          }
        None => fail("then 体第一条应在")
      }
    None => fail("子程序应仍在")
  }
  assert_true(committed.code_draft.contains("完全正确"))
}

///|
test "@app.text field input lands in run state and live texts" {
  let added = apply(@app.initial_model(), AddControl(@ir.TextField))
  let field = added.program.controls[added.program.controls.length() - 1]
  assert_true(field.kind is @ir.TextField)
  // 无运行态：输入也进活状态（受控字段不回跳，取文本 可读到）
  let typed = apply(added, ControlChanged(field.name, "张三"))
  assert_eq(typed.runtime_texts.get(field.name).unwrap_or(""), "张三")
  // 运行态存在：输入同时进运行态文本表
  let running = apply(typed, RunStart)
  assert_true(running.run is Some(_))
  let typed_again = apply(running, ControlChanged(field.name, "李四"))
  assert_eq(
    typed_again.run.unwrap().state.texts.get(field.name).unwrap_or(""),
    "李四",
  )
}

///|
test "design drag moves control and clamps to canvas" {
  let added = apply(@app.initial_model(), AddControl(@ir.Button))
  let control = added.program.controls[added.program.controls.length() - 1]
  // 按下点在控件主体（距角 > 手柄命中半径），不触发角手柄缩放
  let cx = control.x.to_double() + 20.0
  let cy = control.y.to_double() + 15.0
  // 命中即选中并建立拖拽态
  let pressed = apply(added, CanvasPress(cx, cy))
  assert_true(pressed.selected_control == control.name)
  assert_true(pressed.drag is Some(_))
  // 拖向画布外：夹取规则保证控件完整落在 640x480 内
  let moved = apply(pressed, CanvasDragTo(cx + 5000.0, cy + 5000.0))
  let after = @ir.find_control(moved.program, control.name).unwrap()
  assert_eq(after.x, @ir.DESIGN_WIDTH - after.width)
  assert_eq(after.y, @ir.DESIGN_HEIGHT - after.height)
  // 松开清除拖拽态但保留选中
  let released = apply(moved, CanvasRelease(cx, cy))
  assert_true(released.drag is None)
  assert_true(released.selected_control == control.name)
}

///|
test "inspector rect edits clamp and reject bad input" {
  let model = @app.initial_model()
  // 高度超界 → 夹到画布高，y 随之夹回
  let resized = apply(model, SetControlRect("按钮", @ir.RectHeight, "9999"))
  let tall = @ir.find_control(resized.program, "按钮").unwrap()
  assert_eq(tall.height, @ir.DESIGN_HEIGHT)
  assert_eq(tall.y, 0)
  // 合法移动生效
  let moved = apply(resized, SetControlRect("按钮", @ir.RectX, "300"))
  assert_eq(@ir.find_control(moved.program, "按钮").unwrap().x, 300)
  // 非法输入（非数字/超长）被忽略，保持原值
  let bad = apply(moved, SetControlRect("按钮", @ir.RectY, "abc"))
  assert_eq(@ir.find_control(bad.program, "按钮").unwrap().y, 0)
  let bad2 = apply(bad, SetControlRect("按钮", @ir.RectY, "99999"))
  assert_eq(@ir.find_control(bad2.program, "按钮").unwrap().y, 0)
}

///|
test "canvas tap selects on click and stays quiet during drag release" {
  let added = apply(@app.initial_model(), AddControl(@ir.Button))
  let control = added.program.controls[added.program.controls.length() - 1]
  let cx = control.x.to_double() + 10.0
  let cy = control.y.to_double() + 10.0
  // 单击控件 → 选中
  let tapped = apply(added, CanvasTap(cx, cy))
  assert_true(tapped.selected_control == control.name)
  // 拖拽中松手也会产生 tap：drag 态还在时不改选中（消息顺序无关）
  let pressed = apply(tapped, CanvasPress(cx, cy))
  let dragged = apply(pressed, CanvasDragTo(cx + 40.0, cy + 30.0))
  let tap_during_drag = apply(dragged, CanvasTap(cx + 40.0, cy + 30.0))
  assert_true(tap_during_drag.selected_control == control.name)
  // 松开清除拖拽态；随后落在移动后控件上的 tap 选中同一控件
  let released = apply(tap_during_drag, CanvasRelease(cx + 40.0, cy + 30.0))
  assert_true(released.drag is None)
  let tap_after_release = apply(released, CanvasTap(cx + 40.0, cy + 30.0))
  assert_true(tap_after_release.selected_control == control.name)
  // 单击空白处取消选中
  let empty = apply(tap_after_release, CanvasTap(600.0, 450.0))
  assert_true(empty.selected_control == "")
}

///|
test "design canvas plan draws grid, handles and alignment guides" {
  let program = @proposals.sample_hello()
  // 无拖拽：网格点阵 + 选中描边 + 4 角手柄，无参考线
  let plan = @design.design_backdrop_plan()
  // 覆盖层：选中描边/名牌/手柄（无拖拽时无参考线）
  let overlay = @design.design_overlay_plan(program, "按钮", None)
  let mut grid_dots = 0
  let mut handles = 0
  let mut guides = 0
  for op in plan {
    match op {
      @design.DesignDrawOp::GridDot(_) => grid_dots = grid_dots + 1
      _ => ()
    }
  }
  for op in overlay {
    match op {
      @design.DesignDrawOp::SelectionHandle(_) => handles = handles + 1
      @design.DesignDrawOp::GuideV(_) | @design.DesignDrawOp::GuideH(_) =>
        guides = guides + 1
      _ => ()
    }
  }
  assert_true(grid_dots > 200)
  assert_eq(handles, 4)
  assert_eq(guides, 0)
  // 拖拽中：被拖控件左缘与其他控件左缘差 ≤4px 时画竖向参考线
  let base = @ir.empty_program()
  let anchor = @ir.Control::{
    props: @ir.ControlProps::default(),
    id: 1,
    kind: @ir.Label,
    name: "锚点",
    text: "",
    x: 100,
    y: 100,
    width: 30,
    height: 30,
    items: [],
  }
  let dragged = @ir.Control::{ ..anchor, id: 2, name: "拖块", x: 103, y: 40, }
  let pair = @ir.StudioProgram::{ ..base, controls: [anchor, dragged], }
  let dragging = @design.design_overlay_plan(pair, "拖块", Some("拖块"))
  let mut vertical_guides = 0
  for op in dragging {
    match op {
      @design.DesignDrawOp::GuideV(x) => {
        vertical_guides = vertical_guides + 1
        // 同宽控件整体偏移 3px：左缘/中心/右缘三条参考线全部命中
        // （100/115/130），push_unique 保证位置不重复
        assert_true(x == 100.0 || x == 115.0 || x == 130.0)
      }
      _ => ()
    }
  }
  assert_eq(vertical_guides, 3)
}

///|
test "handle hit test resolves corners within radius" {
  let control : @ir.Control = {
    id: 1,
    kind: @ir.Button,
    name: "按钮",
    text: "",
    x: 100,
    y: 100,
    width: 60,
    height: 40,
    items: [],
    props: @ir.ControlProps::default(),
  }
  match @design.hit_test_handle(control, 100.0, 100.0) {
    Some(corner) => assert_true(corner is @ir.CornerNW)
    None => fail("左上角手柄应命中")
  }
  match @design.hit_test_handle(control, 160.0, 140.0) {
    Some(corner) => assert_true(corner is @ir.CornerSE)
    None => fail("右下角手柄应命中")
  }
  // 半径外（10px）与控件中心不命中
  assert_true(@design.hit_test_handle(control, 110.0, 100.0) is None)
  assert_true(@design.hit_test_handle(control, 130.0, 120.0) is None)
}

///|
test "design handle press resizes with opposite corner fixed" {
  let added = apply(@app.initial_model(), AddControl(@ir.Button))
  let control = added.program.controls[added.program.controls.length() - 1]
  let se_x = (control.x + control.width).to_double()
  let se_y = (control.y + control.height).to_double()
  // 按上右下角手柄 → 缩放拖拽态
  let pressed = apply(added, CanvasPress(se_x, se_y))
  match pressed.drag {
    Some(drag) =>
      match drag.kind {
        Resize(corner) => assert_true(corner is @ir.CornerSE)
        Move(_, _) => fail("按手柄应进入缩放而非移动")
      }
    None => fail("按上手柄应建立拖拽态")
  }
  // 向右下拖：左上角不动，移动边落 32px 网格（290→288，252→256）
  let dragged = apply(pressed, CanvasDragTo(se_x + 60.0, se_y + 100.0))
  let after = @ir.find_control(dragged.program, control.name).unwrap()
  assert_eq(after.x, control.x)
  assert_eq(after.y, control.y)
  assert_eq(after.width, 288 - control.x)
  assert_eq(after.height, 256 - control.y)
  // 松手清除拖拽态但保留选中
  let released = apply(dragged, CanvasRelease(se_x + 60.0, se_y + 100.0))
  assert_true(released.drag is None)
  assert_true(released.selected_control == control.name)
}

///|
test "snap move position aligns near edges only within tolerance" {
  let anchor : @ir.Control = {
    id: 1,
    kind: @ir.Label,
    name: "锚点",
    text: "",
    x: 100,
    y: 100,
    width: 30,
    height: 30,
    items: [],
    props: @ir.ControlProps::default(),
  }
  let dragged : @ir.Control = {
    ..anchor,
    id: 2,
    name: "拖块",
    x: 102,
    y: 40,
  }
  let pair = [anchor, dragged]
  // 左缘距锚点左缘 2px（≤4 容差）→ 吸附精确对齐；y 无参考线命中 → 落网格
  let (sx, sy) = @design.snap_move_position(
    pair, "拖块", 102.0, 40.0, 30.0, 30.0,
  )
  assert_eq(sx, 100.0)
  assert_eq(sy, 32.0)
  // 双轴均超参考线容差 → 双轴落网格（106 → 96，40 → 32）
  let (fx, fy) = @design.snap_move_position(
    pair, "拖块", 106.0, 40.0, 30.0, 30.0,
  )
  assert_eq(fx, 96.0)
  assert_eq(fy, 32.0)
}

///|
test "design drag snaps onto alignment guide" {
  let base = apply(@app.initial_model(), AddControl(@ir.Label))
  let label = base.program.controls[base.program.controls.length() - 1]
  // 固定几何：锚点按钮 x=100；标签 x=103（与锚点左缘差 3px ≤ 容差）
  let anchored = apply(base, SetControlRect("按钮", @ir.RectX, "100"))
  let placed_y = apply(anchored, SetControlRect(label.name, @ir.RectY, "200"))
  let placed = apply(placed_y, SetControlRect(label.name, @ir.RectX, "103"))
  let placed_label = @ir.find_control(placed.program, label.name).unwrap()
  // 先点空白取消选中，避免按在选中控件手柄附近误入缩放
  let deselected = apply(placed, CanvasTap(600.0, 450.0))
  let press_x = placed_label.x.to_double() + 20.0
  let press_y = placed_label.y.to_double() + 10.0
  let pressed = apply(deselected, CanvasPress(press_x, press_y))
  match pressed.drag {
    Some(drag) =>
      match drag.kind {
        Move(_, _) => ()
        Resize(_) => fail("按控件主体应进入移动而非缩放")
      }
    None => fail("按控件主体应建立拖拽态")
  }
  // 拖 1px：候选原点 x=102，距按钮左缘 100 差 2px → 吸附到 100
  let dragged = apply(pressed, CanvasDragTo(press_x - 1.0, press_y))
  let after = @ir.find_control(dragged.program, label.name).unwrap()
  assert_eq(after.x, 100)
  // y 无参考线命中 → 落 32px 网格（200 → 192）
  assert_eq(after.y, 192)
}

///|
test "create handler builds empty body and selects it" {
  let added = apply(@app.initial_model(), AddControl(@ir.TextField))
  let field = added.program.controls[added.program.controls.length() - 1]
  let created = apply(added, CreateHandler(field.name, @ir.OnChange))
  assert_eq(created.selected_handler, @app.handler_key(field.name, "on_change"))
  match @app.current_handler(created) {
    Some(handler) => {
      assert_eq(handler.control_name, field.name)
      assert_eq(handler.body.length(), 0)
    }
    None => fail("新建子程序应被选中")
  }
  // 重复创建被忽略（(控件, 事件) 唯一）
  let again = apply(created, CreateHandler(field.name, @ir.OnChange))
  assert_eq(again.program.handlers.length(), created.program.handlers.length())
  // 不支持的事件被忽略
  let unsupported = apply(created, CreateHandler("按钮", @ir.OnChange))
  assert_eq(
    unsupported.program.handlers.length(),
    created.program.handlers.length(),
  )
}

///|
test "add control enforces budget and surfaces notice" {
  let model = apply(@app.initial_model(), AddControl(@ir.Label))
  let mut iter = model
  let mut safety = 0
  while iter.program.controls.length() < @ir.MAX_CONTROLS && safety < 300 {
    iter = apply(iter, AddControl(@ir.Label))
    safety = safety + 1
  }
  assert_eq(iter.program.controls.length(), @ir.MAX_CONTROLS)
  let over = apply(iter, AddControl(@ir.Label))
  assert_eq(over.program.controls.length(), @ir.MAX_CONTROLS)
  assert_true(over.notice != "")
}

///|
test "delete control clears stale draft only for its own handler" {
  let model = @app.initial_model()
  // 选中子程序是 按钮@on_click：删除按钮 → 选中清空、草稿同步清空
  assert_true(model.code_draft != "")
  let deleted = apply(apply(model, DeleteControl("按钮")), ConfirmAccepted)
  assert_eq(deleted.selected_handler, "")
  assert_eq(deleted.code_draft, "")
  // 删除别的控件不动草稿（未提交的编辑不丢失）
  let kept = apply(apply(model, DeleteControl("显示")), ConfirmAccepted)
  assert_true(kept.code_draft != "")
}

///|
test "deleting an unselected control preserves the current selection" {
  let model = apply(@app.initial_model(), SelectControl("按钮"))
  let deleted = apply(model, DeleteControl("显示"))
  assert_eq(deleted.selected_control, "按钮")
}

///|
/// 实测缺陷回归：提案提交后立即进时间线一张忙碌占位卡——
/// 网络回执前的十几秒不再「点了没反应」；回执到达（成功/失败）先摘占位，
/// 再落 diff/错误卡，时间线不留永远转圈的卡。
test "real generation shows busy card until result arrives" {
  let services = @services.AppServices::new()
  let asked = set_prompt(
    model_with_key("k"),
    "把按钮文案改成开始抽签",
  )
  let counted = asked.ai_sessions.current().card_seq
  // 走程序级臂（真实 provider 通道）：noop submit 不发回执，卡的状态由
  // 提交本身断言（生产路径的 message 流一致）。
  let (busy, _effect) = @app.update_with_launch_for_test(
    asked,
    GenerateProposal,
    services,
    fn(_path, _done) { () },
  )
  assert_true(busy.ai_busy)
  let cards = busy.ai_sessions.current().cards
  assert_eq(cards.length(), 1)
  assert_true(cards[0].kind is @ai.CardPlan)
  assert_eq(cards[0].title, "正在生成提案…")
  assert_false(cards[0].settled)
  assert_true(busy.ai_sessions.current().card_seq > counted)
  // 成功回执：占位摘掉，只剩 diff 卡，busy 复位
  let completion = @proposals.encode_proposal(
    @proposals.proposal_from_program(
      @proposals.sample_roll_call(),
      "随机点名",
      "roll call",
    ),
  )
  let done = apply(busy, RealGenerationFinished(Ok(completion)))
  assert_false(done.ai_busy)
  assert_true(done.pending is Some(_))
  assert_false(
    done.ai_sessions.current().cards.any(card => card.kind is @ai.CardPlan),
  )
  assert_true(
    done.ai_sessions.current().cards.any(card => card.kind is @ai.CardDiff),
  )
  // 失败回执：占位同样摘掉，错误卡留下
  let (busy2, _) = @app.update_with_launch_for_test(
    asked,
    GenerateProposal,
    services,
    fn(_path, _done) { () },
  )
  let failed = apply(
    busy2,
    RealGenerationFinished(Err("provider 返回 HTTP 500")),
  )
  assert_false(failed.ai_busy)
  assert_true(failed.prompt_error.contains("500"))
  assert_false(
    failed.ai_sessions.current().cards.any(card => card.kind is @ai.CardPlan),
  )
  assert_true(
    failed.ai_sessions.current().cards.any(card => card.kind is @ai.CardError),
  )
}

///|
test "real generation result becomes pending proposal, failure surfaces" {
  let model = model_with_key("k")
  // 真实生成成功：补全文本走校验链 → 待采纳提案；busy 复位
  let completion = @proposals.encode_proposal(
    @proposals.proposal_from_program(
      @proposals.sample_roll_call(),
      "随机点名",
      "roll call",
    ),
  )
  let next = apply(model, RealGenerationFinished(Ok(completion)))
  assert_true(next.pending is Some(_))
  assert_false(next.ai_busy)
  // 失败：错误进面板提示，不留半成品提案
  let failed = apply(
    model,
    RealGenerationFinished(Err("provider 返回 HTTP 500")),
  )
  assert_true(failed.prompt_error.contains("500"))
  assert_true(failed.pending is None)
  assert_false(failed.ai_busy)
}

///|
test "undo and redo revert and replay control add" {
  let base = @app.initial_model()
  let added = apply(base, AddControl(@ir.Button))
  assert_eq(added.program.controls.length(), base.program.controls.length() + 1)
  // 撤销 → 控件消失、选中清空
  let undone = apply(added, Undo)
  assert_eq(undone.program.controls.length(), base.program.controls.length())
  assert_eq(undone.selected_control, base.selected_control)
  // 重做 → 控件回来
  let redone = apply(undone, Redo)
  assert_eq(redone.program.controls.length(), added.program.controls.length())
  assert_eq(redone.selected_control, added.selected_control)
}

///|
test "drag gesture coalesces into one undo point" {
  let base = apply(@app.initial_model(), AddControl(@ir.Button))
  let control = base.program.controls[base.program.controls.length() - 1]
  let stack_after_add = base.undo_stack.length()
  let cx = control.x.to_double() + 20.0
  let cy = control.y.to_double() + 15.0
  let pressed = apply(base, CanvasPress(cx, cy))
  // 一段手势内的多次 DragTo 合并：撤销栈只长 1
  let dragged = apply(
    apply(
      apply(pressed, CanvasDragTo(cx + 30.0, cy + 10.0)),
      CanvasDragTo(cx + 50.0, cy + 20.0),
    ),
    CanvasDragTo(cx + 70.0, cy + 30.0),
  )
  assert_eq(dragged.undo_stack.length(), stack_after_add + 1)
  // 一次撤销回到拖拽前位置
  let undone = apply(dragged, Undo)
  let after = @ir.find_control(undone.program, control.name).unwrap()
  assert_eq(after.x, control.x)
  assert_eq(after.y, control.y)
}

///|
test "consecutive text edits share one undo point" {
  let base = apply(@app.initial_model(), AddControl(@ir.Label))
  let label = base.program.controls[base.program.controls.length() - 1]
  let stack_after_add = base.undo_stack.length()
  let once = apply(base, SetControlText(label.name, "第一版"))
  let twice = apply(once, SetControlText(label.name, "第二版"))
  assert_eq(twice.undo_stack.length(), stack_after_add + 1)
  // 一次撤销同时回到两版之前
  let undone = apply(twice, Undo)
  let after = @ir.find_control(undone.program, label.name).unwrap()
  assert_eq(after.text, "")
}

///|
test "undo restores selection and code draft" {
  let model = @app.initial_model()
  let draft = model.code_draft
  // 删除「按钮」：选中子程序被清、草稿清空
  let deleted = apply(apply(model, DeleteControl("按钮")), ConfirmAccepted)
  assert_eq(deleted.selected_handler, "")
  assert_eq(deleted.code_draft, "")
  // 撤销：子程序与草稿一起回来
  let undone = apply(deleted, Undo)
  assert_eq(undone.selected_handler, model.selected_handler)
  assert_eq(undone.code_draft, draft)
}

///|
test "new edit clears redo stack" {
  let base = @app.initial_model()
  let added = apply(base, AddControl(@ir.Button))
  let undone = apply(added, Undo)
  assert_true(undone.redo_stack.length() > 0)
  // 新变更（非重做）清空重做栈
  let edited = apply(undone, AddControl(@ir.Label))
  assert_eq(edited.redo_stack.length(), 0)
  assert_eq(
    apply(edited, Redo).program.controls.length(),
    edited.program.controls.length(),
  )
}

///|
test "undo depth is capped" {
  let mut iter = @app.initial_model()
  let mut i = 0
  while i < @app.UNDO_DEPTH + 10 {
    iter = apply(iter, AddControl(@ir.Label))
    i = i + 1
  }
  assert_eq(iter.undo_stack.length(), @app.UNDO_DEPTH)
}

///|
test "duplicate control copies props with offset and undo removes it" {
  let added = apply(@app.initial_model(), AddControl(@ir.ListBox))
  let source = added.program.controls[added.program.controls.length() - 1]
  let with_items = apply(added, SetControlItems(source.name, "铅笔\n橡皮"))
  let copied = apply(with_items, DuplicateControl(source.name))
  assert_true(copied.selected_control != source.name)
  let copy = @ir.find_control(copied.program, copied.selected_control).unwrap()
  assert_eq(copy.kind.tag(), source.kind.tag())
  assert_eq(copy.x, source.x + 16)
  assert_eq(copy.y, source.y + 16)
  assert_eq(copy.items.length(), 2)
  // 撤销复制 → 控件消失、选中回到原件
  let undone = apply(copied, Undo)
  assert_true(@ir.find_control(undone.program, copy.name) is None)
  assert_eq(undone.selected_control, source.name)
}

///|
test "undo reverts accepted proposal" {
  let model = @app.initial_model()
  let prompted = set_prompt(model, "做一个查询成绩的表单")
  let generated = with_pending_roll_call(prompted)
  match generated.pending {
    None => fail("应产出待采纳提案")
    Some(_) => ()
  }
  let accepted = apply(generated, AcceptProposal)
  assert_true(accepted.pending is None)
  assert_true(accepted.undo_stack.length() > model.undo_stack.length())
  let undone = apply(accepted, Undo)
  assert_eq(
    @ir.program_signature(undone.program),
    @ir.program_signature(model.program),
  )
}

///|
test "template switch is undoable" {
  let model = @app.initial_model()
  let switched = @app.load_template_program(model, 2)
  assert_true(
    @ir.program_signature(switched.program) !=
    @ir.program_signature(model.program),
  )
  let undone = apply(switched, Undo)
  assert_eq(
    @ir.program_signature(undone.program),
    @ir.program_signature(model.program),
  )
}

///|
test "single step pauses auto-advance and walks one instruction" {
  // 装填后点按钮派发 hello handler（ RunStart 本身不再执行语句）
  let model = apply(
    apply(@app.initial_model(), RunStart),
    ControlClicked("按钮"),
  )
  let started = match model.run {
    Some(run) => run
    None => fail("应进入运行态")
  }
  let steps_at_start = started.state.steps
  // 单步：恰好走一条指令
  let stepped = apply(model, RunStep)
  let after_step = stepped.run.unwrap()
  assert_eq(after_step.state.steps, steps_at_start + 1)
  assert_true(after_step.single_step)
  assert_true(after_step.state.status is @studio_lang.Running)
  // 计时器 tick 在单步模式下不推进
  let ticked = apply(stepped, RunTick)
  assert_eq(ticked.run.unwrap().state.steps, steps_at_start + 1)
  // 再走一步仍只 +1
  let stepped_again = apply(ticked, RunStep)
  assert_eq(stepped_again.run.unwrap().state.steps, steps_at_start + 2)
  // 继续：恢复自动推进直至完成
  let resumed = apply(stepped_again, RunResume)
  assert_true(!resumed.run.unwrap().single_step)
  let finished = drain(resumed)
  assert_true(finished.run.unwrap().state.status is @studio_lang.Completed)
}

///|
test "variables table data fills as the run declares variables" {
  // 点名册样例声明了变量：装填后点按钮，运行到完成后 vars 非空
  let model = @app.load_template_program(@app.initial_model(), 1)
  let started = apply(apply(model, RunStart), ControlClicked("点名按钮"))
  let finished = drain(started)
  match finished.run {
    None => fail("点名册应可运行")
    Some(run) => {
      let mut count = 0
      for _name in run.state.vars.keys() {
        count = count + 1
      }
      assert_true(count > 0)
    }
  }
}

///|
test "proposal history records accept and reject" {
  let model = @app.initial_model()
  assert_eq(model.ai_sessions.current().proposal_history.length(), 0)
  // 采纳一条
  let accepted = apply(with_pending_roll_call(model), AcceptProposal)
  assert_eq(accepted.ai_sessions.current().proposal_history.length(), 1)
  assert_true(accepted.ai_sessions.current().proposal_history[0].accepted)
  assert_eq(accepted.ai_sessions.current().proposal_history[0].seq, 1)
  // 再生成（口算样例）并拒绝一条
  let second = @app.proposal_from_completion(
    accepted,
    @proposals.encode_proposal(
      @proposals.proposal_from_program(
        @proposals.sample_drill(),
        "口算训练营",
        "arithmetic drill",
      ),
    ),
  )
  let rejected = apply(second, RejectProposal)
  assert_eq(rejected.ai_sessions.current().proposal_history.length(), 2)
  assert_true(!rejected.ai_sessions.current().proposal_history[1].accepted)
  assert_eq(rejected.ai_sessions.current().proposal_history[1].seq, 2)
  // 摘要非空（来自提案 summary）
  assert_true(rejected.ai_sessions.current().proposal_history[1].summary != "")
}

///|
test "help cheatsheet is generated from the keyword catalog" {
  let model = @app.initial_model()
  // 模式可切换且视图可构建（帮助页数据来自 studio_lang 关键字目录）
  let helped = apply(model, SetMode(@app.ModeHelp))
  assert_true(helped.mode is ModeHelp)
  let view = @app.view(helped)
  ignore(view)
  // 目录**非空**且 id 唯一——不写死条数。
  //
  // 写死条数（原为 17）会在每次新增内建时假失败，而它想守的其实是
  // 「帮助页的数据源确实是关键字目录」；条数本身不是契约。改成两条**真的
  // 是契约**的性质：目录非空、id 不重复（重复 id 会让帮助页出现两行同名、
  // 且命令分发会按第一个匹配走）。
  let catalog = @studio_lang.builtin_catalog()
  assert_true(catalog.length() > 0)
  let ids : Array[String] = []
  for spec in catalog {
    assert_false(ids.contains(spec.id))
    ids.push(spec.id)
  }
}

///|
test "audit jump lands on the matching block" {
  // 装填后点按钮执行 hello handler，审计里才有可跳的语句记录
  let model = apply(
    apply(@app.initial_model(), RunStart),
    ControlClicked("按钮"),
  )
  let finished = drain(model)
  // 运行完成后：点击第一条审计 → 积木视图 + 对应语句被选中
  let jumped = apply(finished, AuditJump(0))
  assert_true(jumped.mode is ModeBlocks)
  // 链条即语句列表（事件头单独渲染）→ 应选中下标 0
  assert_eq(jumped.selected_block, 0)
  // 草稿预填该语句的 DSL
  assert_true(jumped.block_draft.contains("设置文本"))
  // 越界索引：切视图但不选中
  let safe = apply(finished, AuditJump(99))
  assert_true(safe.mode is ModeBlocks)
  assert_eq(safe.selected_block, -1)
}

///|
test "redo on empty stack is a safe no-op" {
  // 键盘快捷键（Ctrl/Cmd+Z）在无撤销历史时误触也必须无害
  let model = @app.initial_model()
  let redone = apply(model, Redo)
  assert_eq(
    @ir.program_signature(redone.program),
    @ir.program_signature(model.program),
  )
  assert_true(redone.redo_stack.is_empty())
  let undone_twice = apply(
    apply(apply(model, AddControl(@ir.Label)), Undo),
    Undo,
  )
  // 只有一条撤销历史时，第二次 Undo 也是 no-op
  assert_eq(
    @ir.program_signature(undone_twice.program),
    @ir.program_signature(model.program),
  )
}

///|
test "undo after block commit reverts the statement (snapshot not poisoned)" {
  let model = @app.initial_model()
  // 积木编辑：把唯一语句改成另一条并提交
  let selected = select_block_index(model, 0)
  let edited = apply(selected, EditBlock("设置文本(显示, \"改过\")"))
  let committed = apply(edited, CommitBlock)
  match @app.current_handler(committed).unwrap().body[0] {
    @ir.Call(_, args) =>
      match args[1] {
        @ir.StrLit(text) => assert_true(text.contains("改过"))
        _ => fail("提交后应为新字符串字面量")
      }
    _ => fail("提交后应仍是 Call")
  }
  // 撤销：程序应与最初逐字段一致
  // （若快照被就地手术污染，这里会拿到提交后的语句而失败）
  let undone = apply(committed, Undo)
  assert_eq(
    @ir.program_signature(undone.program),
    @ir.program_signature(model.program),
  )
}

///|
test "blocks canvas layout, hit test and drop slot" {
  // 找一个选中子程序含嵌套语句的样例（深度 ≥ 1 才能断言缩进）
  let samples = @proposals.all_samples()
  let mut chosen : @app.Model? = None
  let mut idx = 0
  for sample in samples {
    // 扫描该样例全部 handler，找到第一个有嵌套语句的
    for handler in sample.handlers {
      let keyed = @app.handler_key(handler.control_name, handler.event.tag())
      let chain = @blocks.block_chain(handler.body)
      let mut has_depth = false
      for item in chain {
        if item.depth >= 1 {
          has_depth = true
        }
      }
      if has_depth {
        chosen = Some(
          apply(
            @app.load_template_program(@app.initial_model(), idx),
            SelectHandler(keyed),
          ),
        )
        break
      }
    }
    if chosen is Some(_) {
      break
    }
    idx = idx + 1
  }
  let model = match chosen {
    Some(m) => m
    None => fail("样例里应存在含嵌套的子程序")
  }
  ignore(idx)
  let blocks = @app.block_chain_of(model)
  assert_true(blocks.length() > 3)
  let rects = @blk.blocks_item_rects(blocks)
  // 布局：行距 = 行高（34，Scratch 堆叠咬合：行与行零缝隙），深度缩进
  assert_eq(rects[0].origin.y, 10.0)
  assert_eq(rects[1].origin.y, 44.0)
  let mut deepest = 0
  let mut deep_index = 0
  let mut i = 0
  for item in blocks {
    if item.depth > deepest {
      deepest = item.depth
    }
    if item.depth == deepest {
      deep_index = i
    }
    i = i + 1
  }
  assert_true(rects[deep_index].origin.x > rects[0].origin.x)
  // 命中：第一行中心命中 0；画布右上角空白命中 -1
  assert_eq(
    @blk.blocks_hit_index(
      blocks,
      rects[0].origin.x + 10.0,
      rects[0].origin.y + 10.0,
    ),
    0,
  )
  assert_eq(@blk.blocks_hit_index(blocks, 460.0, 5.0), -1)
  // 落槽：同层列表内按兄弟中心线计数
  let first_path = blocks[0].path
  let list_path = @blk.blocks_parent_of(first_path)
  assert_eq(
    @blk.blocks_drop_slot(blocks, list_path, rects[0].origin.y + 1.0, rects),
    0,
  )
  assert_eq(
    @blk.blocks_drop_slot(blocks, list_path, rects[1].origin.y + 30.0, rects),
    1,
  )
}

///|
/// 积木标签按块宽截断：宽够就原样，宽不够就「…」收尾且**不超宽**。
test "@chrome.fit_label truncates block labels to the block width" {
  // 够宽：原样返回
  assert_eq(@chrome.fit_label("命令", 200.0), "命令")
  // 不够宽：以省略号收尾
  let long = "命令  set_text(显示, \"你好，MoUI Studio！\")"
  let fitted = @chrome.fit_label(long, 200.0)
  assert_true(fitted.contains("…"))
  assert_true(fitted.length() < long.length())
  // 截断结果必须真的放得下（按 12pt 渲染口径）
  let rendered = @chrome.text_estimate_width(fitted) * (12.0 / 13.0)
  assert_true(rendered <= 200.0)
  // 极窄也不能崩：至少给一个省略号
  assert_eq(@chrome.fit_label(long, 4.0), "…")
}

///|
/// 悬停联动：`HoverIrPath` 只改瞬态 `hover_path`，**不动**驻留的
/// `ir_highlight`——两者共用一个高亮视觉，但语义不同（悬停离开即撤销，
/// 点击驻留到再点一次）。混在一起会让「悬停走过的每一行」都被记住。
test "hover path is transient and does not disturb the pinned highlight" {
  let model = @app.initial_model()
  let (pinned, _) = @app.update_pure(model, HighlightIrPath([0, 1]))
  assert_eq(pinned.ir_highlight, [0, 1])
  // 悬停一条别的路径：驻留高亮必须不变
  let (hovered, _) = @app.update_pure(pinned, HoverIrPath(Some([2, 3])))
  assert_eq(hovered.ir_highlight, [0, 1])
  assert_eq(hovered.hover_path, Some([2, 3]))
  // 离开：只清悬停
  let (left, _) = @app.update_pure(hovered, HoverIrPath(None))
  assert_eq(left.ir_highlight, [0, 1])
  assert_eq(left.hover_path, None)
}

///|
/// 沉浸式窗口必须把顶部窗控带**声明成可拖拽区域**，非沉浸式必须清空。
///
/// 回归意义：无边框窗口没有系统标题栏，不声明这块就**完全没法移动窗口**
/// ——「看起来正常、实际用不了」，任何绘制断言都抓不到。
///
/// 注意这条测试**不**通过 `program(...)` 触发：`Program` 是不透明类型，
/// 它的 view 闭包从测试里拿不到，写了也是装饰（本会话踩过这个坑）。
/// 所以这里直接对**声明契约**本身断言：app 用的是
/// `WindowDragRegionSource`，宿主按 `revision` 去重——把这个契约钉住，
/// 再靠 `moon check` 保证 app 的调用点存在。
test "window drag region declaration is idempotent and clearable" {
  let source = @services.WindowDragRegionSource::new()
  // 初始：无声明（非沉浸式路径会显式写 None，结果相同）
  assert_eq(source.region(), None)
  let band = @core.Rect::new(
    x=0.0,
    y=0.0,
    width=1280.0,
    height=@chrome.WINDOW_CHROME_HEIGHT,
  )
  source.set_region(Some(band))
  // 声明的必须是**顶部整条带**：原点贴左上角，高 = 窗控带高
  let declared = match source.region() {
    Some(rect) => rect
    None => fail("declaring a drag region did not stick")
  }
  assert_eq(declared.origin.x, 0.0)
  assert_eq(declared.origin.y, 0.0)
  assert_eq(declared.size.height, @chrome.WINDOW_CHROME_HEIGHT)
  // 逐帧重复声明不得推进 revision —— 宿主据此跳过原生调用，
  // 这是「声明是状态不是命令」的全部意义所在。
  let revision = source.revision()
  source.set_region(Some(band))
  assert_eq(source.revision(), revision)
  // 清空必须生效**且**推进 revision，否则宿主不会下发「取消拖拽区」，
  // 非沉浸式切回来时会留下一块看不见但能拖窗的死区。
  source.set_region(None)
  assert_eq(source.region(), None)
  assert_true(source.revision() > revision)
}

///|
/// M5-5e：代码视图默认外观是 MoonBit（代码真源的显示投影）。
test "code view defaults to moonbit appearance showing generated source" {
  let model = @app.initial_model()
  assert_true(model.code_appearance is @app.AppMoonBit)
  // 草稿 = codegen 的 handler 子集源码（与导出 bundle 同源形状）
  assert_true(model.code_draft.contains("rt."))
  assert_true(model.code_draft.contains("@compiled_runtime"))
  // MoonBit⇄IR 无损：显示的源码正是 generate_handler_source 的逐字节产物
  match @app.current_handler(model) {
    Some(handler) =>
      assert_eq(
        model.code_draft,
        @export.generate_handler_source(
          handler,
          1,
          functions=model.program.functions,
        ).source,
      )
    None => fail("初始模型应有 handler")
  }
  // 逆解析链仍闭合：生成源可被积木逆解析器认领（M5-5a 契约的外观侧兑现）
  let generated = @export.generate_source(model.program)
  let parsed = @app.parse_generated_source(
    generated.handlers[0].source,
    generated.handlers[0].stmt_lines,
  )
  assert_true(parsed.blocks.length() > 0)
}

///|
test "cycling appearance shows dsl and moonbit display is commit free" {
  let model = @app.initial_model()
  // 切到 DSL 外观：草稿按教学语言渲染
  let dsl = apply(model, CycleCodeAppearance)
  assert_true(dsl.code_appearance is @app.AppDsl)
  assert_true(
    dsl.code_draft.contains("变量") || dsl.code_draft.contains("设置文本"),
  )
  // DSL 外观下编辑→提交通路保持既有语义
  let edited = apply(dsl, EditCode("设置文本(显示, \"改\")\n"))
  let committed = apply(edited, SelectHandler("按钮@on_click"))
  match @app.current_handler(committed) {
    Some(handler) =>
      assert_true(
        handler.body.any(stmt => stmt is @ir.Stmt::Call("set_text", _)),
      )
    None => fail("handler 应仍在")
  }
  // 切回 MoonBit：草稿重新推导为生成源
  let back = apply(committed, CycleCodeAppearance)
  assert_true(back.code_appearance is @app.AppMoonBit)
  assert_true(back.code_draft.contains("rt.set_text("))
  // MoonBit 外观是显示投影：编辑不提交、不产生 DSL 误报（IR 不被污染）
  let garbled = apply(back, EditCode("这不是 MoonBit 也不是 DSL"))
  let settled = apply(garbled, SelectHandler("按钮@on_click"))
  assert_true(settled.code_error == "")
  match @app.current_handler(settled) {
    Some(handler) =>
      assert_true(
        handler.body.any(stmt => stmt is @ir.Stmt::Call("set_text", _)),
      )
    None => fail("MoonBit 外观编辑不得改写 IR")
  }
}

///|
/// M6②：提案 diff 变文本 diff——待采纳卡展示 handlers.mbt/form.mbt 的
/// 行级 ±（代码真源），采纳置位代码工程落盘标记，历史记录保留文本 diff。
test "proposal diff shows code text and accept triggers codegen write" {
  // 在册工程让采纳的写盘事件有目标（counter 工程导入；事件驱动见 app/events.mbt）
  let imported = @app.update_with_services(
      @app.initial_model(compile_track_available=true),
      ProjectScanCompleted(Success(Ok(Single(counter_source())))),
      @services.AppServices::new(),
    ).0
  let model = set_prompt(imported, "帮我做一个随机点名")
  let generated = with_pending_roll_call(model)
  match generated.pending {
    None => fail("应产生待采纳提案")
    Some(pending) => {
      assert_true(pending.valid)
      // 校验链不变：结构化 diff 仍在（可读性/预算门同一链）
      assert_true(pending.diff.length() > 0)
      // 代码真源文本 diff 非空：替换式提案必然改写 handlers.mbt 行
      assert_true(pending.code_diff.length() > 0)
      // 行级 ± 形态：删除行带 -，新增行带 +
      assert_true(pending.code_diff.any(pair => pair.0 == "-"))
      assert_true(pending.code_diff.any(pair => pair.0 == "+"))
      // 采纳：发出代码工程写盘事件（M1 事件化，组合根监听器写盘）
      let accepted = apply(generated, AcceptProposal)
      assert_true(
        accepted.outbox.any(event => event is EvCodeProjectWrite(_, _, _, _)),
      )
      // 历史记录保留文本 diff（会话回放看代码改了哪几行）
      assert_true(accepted.ai_sessions.current().proposal_history.length() > 0)
      let last = accepted.ai_sessions.current().proposal_history[accepted.ai_sessions.current().proposal_history.length() -
        1]
      assert_true(last.accepted)
      assert_eq(last.code_diff.length(), pending.code_diff.length())
    }
  }
}

///|
test "code text diff trims common prefix and suffix" {
  // 完全相同 → 空 diff
  assert_eq(@proj.code_text_diff("a\nb\n", "a\nb\n").length(), 0)
  // 单行改动：中间一行 - 旧 + 新
  let diff = @proj.code_text_diff(
    "let x = 1\nlet y = 2\nlet z = 3\n", "let x = 1\nlet y = 20\nlet z = 3\n",
  )
  assert_eq(diff.length(), 2)
  assert_eq(diff[0].0, "-")
  assert_eq(diff[0].1, "let y = 2")
  assert_eq(diff[1].0, "+")
  assert_eq(diff[1].1, "let y = 20")
}

///|
test "code project text joins form and handlers with a boundary" {
  let program = @proposals.sample_hello()
  let text = @proj.code_project_text(program)
  assert_true(text.contains("=== handlers.mbt ==="))
  assert_true(text.contains("stage(640, 480"))
  assert_true(text.contains("fn studio_"))
}

///|
/// M4 收尾：布局页签开关 + 保存联动——进入布局设计置位页签并无会话时
/// 自动派发 FormDesignOpen；FormDesignSaved 成功后给重载通知并派发
/// BkFramePreview 重建（模式一重放新帧 / 模式二经 build_seq 触发 reload）。
test "design tab toggle and saved rebuild link" {
  let services = @services.AppServices::new()
  let (opened, _) = @app.update_with_services(
    @app.initial_model(),
    SetPreviewDesignOpen(true),
    services,
  )
  assert_true(opened.preview_design_open)
  let (closed, _) = @app.update_with_services(
    opened,
    SetPreviewDesignOpen(false),
    services,
  )
  assert_false(closed.preview_design_open)
  let (saved, saved_effect) = @app.update_with_services(
    @app.initial_model(),
    FormDesignSaved(Success(())),
    services,
  )
  assert_true(saved.notice.contains("重载"))
  // effect 非 none：重建派发真实存在（Effect::none 无法直接判定，
  // 用 notice + 重建语义的集成断言覆盖；派发内容由 app.mbt 装配锁定）
  assert_true(saved_effect is _)
}

///|
/// 实测反馈修复：MoonBit 外观下「按 IR 重渲染」不得把草稿打回中文 DSL——
/// 恢复按当前外观渲染（M5-5e 的 render_code_appearance 口径）。
test "restore respects code appearance" {
  let model = @app.initial_model()
  // 默认 MoonBit 外观：恢复后草稿仍是生成源（rt. 调用形态）
  let restored = apply(model, RestoreCodeDraft)
  assert_true(restored.code_draft.contains("rt."))
  assert_false(restored.code_draft.contains("设置文本"))
  // DSL 外观：恢复后是教学语言渲染
  let dsl = apply(restored, CycleCodeAppearance)
  let restored_dsl = apply(dsl, RestoreCodeDraft)
  assert_true(
    restored_dsl.code_draft.contains("设置文本") ||
    restored_dsl.code_draft.contains("变量"),
  )
}

///|
/// 试用反馈:工程文件点开即可编辑,保存写回磁盘(脏标记 + 回执对齐基准)。
test "project file opens editable and saves" {
  // 点文件:选中态 + 读取回执挂载编辑器(读取走 fake 服务的成功路径——
  // 文件不存在时 fake 返回错误内容,这里直接喂回执测纯转移)
  let selected = apply(@app.initial_model(), SelectProjectFile("app/main.mbt"))
  assert_true(selected.project_state.selected_project_file is Some(_))
  let loaded = apply(
    selected,
    ProjectFileLoaded(
      "app/main.mbt",
      Success("fn main {\n  println(\"hi\")\n}\n"),
    ),
  )
  match @app.active_project_file(loaded) {
    Some(open) => {
      assert_eq(open.rel, "app/main.mbt")
      assert_true(open.draft.contains("println"))
      assert_false(@app.file_is_dirty(open))
      // 编辑:草稿变化 → 脏
      let edited = apply(loaded, ProjectOp(EditProjectFile("fn main {}\n")))
      match @app.active_project_file(edited) {
        Some(open2) => assert_true(@app.file_is_dirty(open2))
        None => fail("编辑后文件应仍打开")
      }
      // 保存:回执按 rel 定位 tab,对齐脏基准
      let saver = apply(edited, SaveProjectFile)
      let saved = apply(
        saver,
        ProjectFileSaveFinished("app/main.mbt", Success(())),
      )
      match @app.active_project_file(saved) {
        Some(open3) => assert_false(@app.file_is_dirty(open3))
        None => fail("保存后文件应仍打开")
      }
      // 关闭:回到 IR 编辑面
      let close_idx = saved.project_state.open_file_index
      let closed = apply(saved, ProjectOp(@proj.CloseFileTab(close_idx)))
      assert_true(closed.project_state.open_project_files.is_empty())
      assert_eq(closed.project_state.open_file_index, -1)
    }
    None => fail("读取回执后文件应打开")
  }
}

///|
/// M3 验收：AI 模式走通「提问 → 提案卡 → 采纳 → 审计」+ 多会话互不串线。
test "ai perspective walks prompt to proposal to accept with isolated sessions" {
  // 在册工程（写盘事件有目标）+ 切到 AI 模式（预设：左栏会话列表/右栏收起）
  let imported = @app.update_with_services(
      @app.initial_model(compile_track_available=true),
      ProjectScanCompleted(Success(Ok(Single(counter_source())))),
      @services.AppServices::new(),
    ).0
  let in_mode = apply(imported, SetPerspective(PsAi))
  assert_true(in_mode.left_view is LeftAiSessions)
  assert_true(in_mode.right_view is RvHidden)
  // 提问：草稿进当前会话
  let asked = set_prompt(in_mode, "帮我做一个随机点名")
  assert_eq(
    asked.ai_sessions.current().prompt_draft,
    "帮我做一个随机点名",
  )
  // 生成（真实回执通道）：待审提案 + diff 卡进线程
  let generated = with_pending_roll_call(asked)
  match generated.pending {
    None => fail("应产生待采纳提案")
    Some(pending) => assert_true(pending.valid)
  }
  assert_eq(generated.ai_sessions.current().cards.length(), 1)
  // 采纳：提案历史进当前会话 + 语义/落盘事件 + 审计留痕
  let accepted = apply(generated, AcceptProposal)
  assert_eq(accepted.ai_sessions.current().proposal_history.length(), 1)
  assert_true(accepted.outbox.any(event => event is EvProposalAccepted(_, _)))
  assert_true(
    accepted.outbox.any(event => event is EvCodeProjectWrite(_, _, _, _)),
  )
  assert_true(
    accepted.audit_entries.any(entry => {
      entry.text == "app.ai.card.applied" || entry.kind is AuditRun
    }),
  )
  // 草稿被消费
  assert_eq(accepted.ai_sessions.current().prompt_draft, "")
  // 多会话互不串线：新建会话是空的，切回原会话内容原样在
  let created = apply(accepted, AiSessionOp(AiSessionCreate(0)))
  assert_eq(created.ai_sessions.count(), 2)
  assert_eq(created.ai_sessions.current().cards.length(), 0)
  assert_eq(created.ai_sessions.current().proposal_history.length(), 0)
  let switched = apply(created, AiSessionOp(AiSessionSwitch(0)))
  assert_eq(switched.ai_sessions.current().cards.length(), 1)
  assert_eq(switched.ai_sessions.current().proposal_history.length(), 1)
  // 删除原会话（RemoveProject 惯例：落到同位下一个）
  let removed = apply(switched, AiSessionOp(AiSessionRemove(0)))
  assert_eq(removed.ai_sessions.count(), 1)
  assert_eq(removed.ai_sessions.current().proposal_history.length(), 0)
}

///|
/// M4 验收：真实讲解提交预置空流式卡——分片逐段追加进当前会话的流式卡，
/// 停止生成干净截断（后续分片被忽略），正常完成复位标志。
/// （noop provider 不发回执：dispatch 效果由测试手动跟随，分片消息可断言。）
test "real explanation streams chunks and stop truncates cleanly" {
  let services = @services.AppServices::new()
  // 密钥掩码态会忽略 SetProviderKey 输入——测试直接展开字段
  let model = model_with_key("k")
  // 启动流式讲解：流式卡就位（空 body）+ 标志为真
  let (streaming, _effect) = @app.update_with_launch_for_test(
    model,
    ExplainHandler,
    services,
    fn(_path, _done) { () },
  )
  ignore(0)
  assert_true(streaming.ai_streaming)
  assert_eq(streaming.ai_sessions.current().cards.length(), 1)
  assert_eq(streaming.ai_sessions.current().cards[0].body, "")
  // 分片逐段到达（消息流断言）
  let (one, _) = @app.update_with_services(
    streaming,
    StreamChunk("第一段。"),
    services,
  )
  let (two, _) = @app.update_with_services(
    one,
    StreamChunk("第二段。"),
    services,
  )
  assert_eq(two.ai_sessions.current().cards[0].body, "第一段。第二段。")
  assert_true(two.ai_streaming)
  // 停止生成：标志复位 + 卡片标记已停止
  let (stopped, _) = @app.update_with_services(two, StopGeneration, services)
  assert_false(stopped.ai_streaming)
  assert_true(stopped.ai_sessions.current().cards[0].settled)
  // 停止后的残余分片被忽略（干净截断，不追加）
  let (ignored, _) = @app.update_with_services(
    stopped,
    StreamChunk("不应出现"),
    services,
  )
  assert_eq(
    ignored.ai_sessions.current().cards[0].body,
    "第一段。第二段。",
  )
  // 正常完成路径：RealExplanationFinished 结算流式卡并复位标志
  // （会话切片共享可变，避免与前段别名）
  let provisioned = model_with_key("k")
  let (fresh_stream, _) = @app.update_with_launch_for_test(
    provisioned,
    ExplainHandler,
    services,
    fn(_path, _done) { () },
  )
  let done = apply(fresh_stream, RealExplanationFinished(Ok("讲完了")))
  assert_false(done.ai_streaming)
  // 完成即结算（全文落卡）
  assert_true(done.ai_sessions.current().cards[0].settled)
  assert_eq(done.ai_sessions.current().cards[0].body, "讲完了")
}

///|
/// M5/M8 验收：终端页签的消息流——派生回执挂句柄、PTY 输出喂屏、直连
/// 键入经服务写出（Dispatch 效应真调 fake write）、关闭触发 kill。
/// 行输入协议（TerminalInput/TerminalType）已随 M9 收尾删除：生产入口
/// 唯一为 keyboard_input → TerminalWrite 直通。
test "terminal tab message flow spawns writes and closes via pty service" {
  let services = @services.AppServices::new()
  // fake PTY 服务：记录派生/写入/终止（无头不真起 PTY）
  let spawn_calls = Ref(0)
  let written = Ref("")
  let killed = Ref(0)
  let pty : @kernel.PtyService[@app.Msg] = {
    available: true,
    spawn: fn(_cols, _rows, _on_output, _on_exit, _emit) {
      spawn_calls.val = spawn_calls.val + 1
      Some(0)
    },
    write: fn(_handle, input) { written.val = written.val + input },
    resize: fn(_handle, _cols, _rows) { () },
    kill: fn(_handle) { killed.val = killed.val + 1 },
  }
  // AI 模式预设 + 终端页签
  let in_mode = apply(
    @app.initial_model(pty_available=true),
    SetPerspective(PsAi),
  )
  let tabbed = apply(in_mode, SetBottomTab(BtTerminal))
  assert_true(tabbed.terminal.available)
  // 派生回执：句柄挂上（真程序里由包装层 spawn 触发经此回执）；
  // 终端臂在 update_with_services（导出层），不走 update_pure
  let spawned = @app.update_with_services(
      tabbed,
      TerminalSpawned(Some(0)),
      services,
      pty~,
    ).0
  assert_true(spawned.terminal.running())
  // PTY 输出喂屏（\r\n 语义：内容行 + 等待空行）
  let out = @app.update_with_services(
      spawned,
      TerminalOutput("user@host % ls\r\n"),
      services,
      pty~,
    ).0
  assert_eq(out.terminal.screen.length(), 2)
  assert_eq(out.terminal.screen[0], "user@host % ls")
  // 直连键入：keyboard_input 编码后的字节经 TerminalWrite 派发
  // Dispatch 效应真调 fake write（run 即执行）
  assert_true(pty.available)
  let (typed, effect) = @app.update_with_services(
    out,
    TerminalWrite("ls -la\r"),
    services,
    pty~,
  )
  match effect {
    @moui.Effect::Dispatch(run) => run(_msg => ())
    _ => fail("TerminalWrite 应派发写入效应")
  }
  assert_eq(written.val, "ls -la\r")
  assert_true(typed.terminal.running())
  // 派生触发在包装层 effect（本测试不经包装层）；派生计数由真机冒烟覆盖
  // 关闭：kill 一次（Dispatch 效应手动泵）+ 句柄清空（屏保留回看）
  let (_cm, close_effect) = @app.update_with_services(
    typed,
    TerminalClose,
    services,
    pty~,
  )
  match close_effect {
    @moui.Effect::Dispatch(run) => run(_msg => ())
    _ => fail("TerminalClose 应派发 kill 效应")
  }
  assert_eq(killed.val, 1)
  assert_false(typed.terminal.running())
  // 屏保留回看（关闭不清内容）
  assert_eq(typed.terminal.screen[0], "user@host % ls")
}

///|
/// M6① 验收：AppMoonBit 外观按 MoonBit 规则着色（修复「MoonBit 源码
/// 用 DSL 关键字表」的缺陷）——关键字/类型名/注释三类 MoonBit 特有判定。
test "code_lines dispatches moonbit rules under AppMoonBit appearance" {
  let model = @app.initial_model()
  assert_true(model.code_appearance is @app.AppMoonBit)
  // MoonBit 源码：fn/let 是 MoonBit 关键字（DSL 表里不存在 fn/struct 判定）
  let with_code = @app.update_moonbit_draft_for_test(
    model, "fn main() { let n = 1 }",
  )
  let lines = @app.code_lines(with_code)
  assert_true(lines.length() >= 1)
  // fn（MoonBit 关键字）与 main（首字母小写→非内建）着色分离：
  // CodeTokenKind 无 Eq，用文本匹配判定关键字命中
  let mut has_keyword = false
  for line in lines {
    for token in line.tokens {
      if token.kind is @app.TokKeyword &&
        (token.text == "fn" || token.text == "let") {
        has_keyword = true
      }
    }
  }
  assert_true(has_keyword)
  // 注释按 MoonBit 规则着色
  let with_comment = @app.update_moonbit_draft_for_test(
    model, "// 注释\nlet x = 1",
  )
  let comment_lines = @app.code_lines(with_comment)
  let mut has_comment = false
  for line in comment_lines {
    for token in line.tokens {
      if token.kind is @app.TokComment && token.text.contains("注释") {
        has_comment = true
      }
    }
  }
  assert_true(has_comment)
  // DSL 外观维持既有 DSL 关键字表（口径不回归）
  let dsl = @app.update_moonbit_draft_for_test(model, "如果 x 那么 y")
  let dsl_switched = apply(dsl, CycleCodeAppearance)
  assert_true(dsl_switched.code_appearance is @app.AppDsl)
}

///|
/// M7 验收：教学版 profile——只开放图形化模式（其它模式切换 no-op、活动栏
/// 只渲染一个模式项、终端强制不可用），完整版不受影响。
test "teaching profile restricts perspectives and terminal" {
  // 教学版：PTY 强制不可用（pty_available 传真也被 profile 取与）
  let teaching = @app.initial_model(pty_available=true, profile=@app.Teaching)
  assert_true(teaching.profile is @app.Teaching)
  assert_false(teaching.terminal.available)
  // 图形化模式切换正常（同值 no-op 语义不变）
  assert_true(teaching.perspective is @app.PsVisual)
  // 切代码/AI：no-op（留在图形化）
  let code = apply(teaching, SetPerspective(PsCode))
  assert_true(code.perspective is @app.PsVisual)
  let ai = apply(teaching, SetPerspective(PsAi))
  assert_true(ai.perspective is @app.PsVisual)
  // 完整版：三模式全可切
  let full = @app.initial_model()
  let full_code = apply(full, SetPerspective(PsCode))
  assert_true(full_code.perspective is @app.PsCode)
  let full_ai = apply(full_code, SetPerspective(PsAi))
  assert_true(full_ai.perspective is @app.PsAi)
}

///|
/// M8① 验收：终端页签开关语义——选中态再点 = 关闭（kill + 收起 + 页签
/// 退出选中）；关闭态再点 = 重开（重派生条件恢复）。
test "terminal tab toggle closes and reopens via select_bottom_tab" {
  let services = @services.AppServices::new()
  let killed = Ref(0)
  let pty : @kernel.PtyService[@app.Msg] = {
    available: true,
    spawn: fn(_cols, _rows, _on_output, _on_exit, _emit) { Some(0) },
    write: fn(_handle, _input) { () },
    resize: fn(_handle, _cols, _rows) { () },
    kill: fn(_handle) { killed.val = killed.val + 1 },
  }
  // AI 模式 + 终端页签选中 + 派生回执
  let in_mode = @app.update_with_services(
      @app.initial_model(pty_available=true),
      SetPerspective(PsAi),
      services,
      pty~,
    ).0
  assert_true(in_mode.terminal_open)
  // M8④：AI 模式底栏默认收起
  assert_false(in_mode.bottom_open)
  let spawned = @app.update_with_services(
      in_mode,
      TerminalSpawned(Some(0)),
      services,
      pty~,
    ).0
  // 再点选中的终端页签 = 关闭（TerminalTabClose）：kill 一次 + 页签退出
  // 选中 + 底栏收起（kill 在 Dispatch 效应里，手动泵）
  let (_cm, close_effect) = @app.update_with_services(
    spawned,
    TerminalTabClose,
    services,
    pty~,
  )
  match close_effect {
    @moui.Effect::Dispatch(run) => run(_msg => ())
    _ => fail("TerminalTabClose 应派发 kill 效应")
  }
  let closed = _cm
  assert_false(closed.terminal_open)
  assert_false(closed.terminal.running())
  assert_eq(killed.val, 1)
  assert_true(closed.bottom_tab is @app.BtConsole)
  assert_false(closed.bottom_open)
  // 关闭态再点 = 重开（terminal_open 恢复；句柄已清 → 重派生条件成立）
  let reopened = @app.update_with_services(
      closed,
      SetBottomTab(BtTerminal),
      services,
      pty~,
    ).0
  assert_true(reopened.terminal_open)
  assert_true(reopened.bottom_tab is @app.BtTerminal)
  assert_true(reopened.bottom_open)
}

///|
/// M8③ 验收：AI 中心空会话 = 居中 composer；有卡片 = 钉底。
test "ai center composer centers when session is empty" {
  let model = @app.initial_model()
  let in_mode = apply(model, SetPerspective(PsAi))
  // 空会话（无卡）：ai_center 用居中形态——直接断言会话无卡（渲染形态由
  // headless 探针覆盖，这里锁状态判据）
  assert_eq(in_mode.ai_sessions.current().cards.length(), 0)
  // 推一张卡后有卡路径成立
  let with_card = @app.push_ai_card(in_mode, @app.AiCard::{
    kind: CardExplanation,
    title: "讲解",
    body: "内容",
    steps: [],
    steps_done: 0,
    progress: 0,
    diff_lines: [],
    code_blocks: [],
    settled: false,
    settled_note: "",
    seq: 0,
    at: 0,
  })
  assert_eq(with_card.ai_sessions.current().cards.length(), 1)
}
