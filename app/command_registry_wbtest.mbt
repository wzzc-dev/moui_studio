///|
/// 命令贡献表回归（M5）：43 个 id 全覆盖、面板 40 条顺序/文案不变、
/// 隐藏命令不进面板但可派发、代表命令状态转移与旧 switch 一致。

///|
test "command registry covers all 43 ids without duplicates" {
  let registry = studio_command_registry()
  assert_eq(registry.length(), 43)
  for index, contribution in registry {
    for probe_index, probe in registry {
      if probe_index != index && probe.id == contribution.id {
        fail("duplicate command id: " + contribution.id)
      }
    }
    // 每条命令都必须绑定动作（表里不允许占位空壳）
    let ctx : StudioCtx = { model: initial_model(), t: translator_for(ZhHans), }
    match (contribution.run)(ctx) {
      @wb.Apply(_) | @wb.Dispatch(_) => ()
      @wb.Unavailable =>
        fail("command must be dispatchable: " + contribution.id)
    }
  }
  // 面板可见 40 条严格按旧命令表顺序
  let visible : Array[String] = []
  for contribution in registry {
    if contribution.label_key != "" {
      visible.push(contribution.id)
    }
  }
  assert_eq(visible.length(), 40)
  let expected : Array[String] = [
    "studio.mode.visual", "studio.mode.code", "studio.mode.ai", "studio.workspace.preview",
    "studio.workspace.design", "studio.workspace.blocks", "studio.left.toggle", "studio.pane.live",
    "studio.pane.blocks", "studio.pane.split", "studio.left.tree", "studio.left.data",
    "studio.right.toggle", "studio.right.ai", "studio.ctx.runtime", "studio.code.complete",
    "studio.code.jump", "studio.bottom.toggle", "studio.bottom.audit", "studio.bottom.console",
    "studio.bottom.problems", "studio.audit.settle_all", "studio.ai.new_session",
    "studio.ai.search", "studio.ai.history", "studio.run.start", "studio.run.stop",
    "studio.compile.run", "studio.template.hello", "studio.template.roll_call", "studio.template.drill",
    "studio.template.store", "studio.file.new", "studio.file.save", "studio.file.open",
    "studio.file.export", "studio.preview", "studio.help", "studio.settings", "studio.lang.switch",
  ]
  for index, id in expected {
    assert_eq(visible[index], id, msg="palette order drifted at " + id)
  }
}

///|
test "command palette derives legacy descriptors in order" {
  let t = translator_for(ZhHans)
  let commands = studio_commands(t)
  assert_eq(commands.length(), 40)
  for command in commands {
    // 隐藏 3 条不进面板
    assert_false(
      command.id == "studio.workspace.visual" ||
      command.id == "studio.workspace.code" ||
      command.id == "studio.right.context",
    )
  }
  // 分组锚点：本地化键没有漂移
  assert_eq(commands[0].id, "studio.mode.visual")
  assert_eq(commands[0].label, text(t, "app.command.perspective.visual"))
  assert_eq(commands[0].group, "工作区")
  assert_eq(commands[21].id, "studio.audit.settle_all")
  assert_eq(commands[21].group, "面板")
  assert_eq(commands[22].id, "studio.ai.new_session")
  assert_eq(commands[22].group, "AI 层")
  assert_eq(commands[25].id, "studio.run.start")
  assert_eq(commands[25].group, "运行")
  assert_eq(commands[28].id, "studio.template.hello")
  assert_eq(commands[28].group, "模板")
  assert_eq(commands[32].id, "studio.file.new")
  assert_eq(commands[32].group, "文件")
  assert_eq(commands[36].id, "studio.preview")
  assert_eq(commands[36].group, "视图")
  assert_eq(commands[39].id, "studio.lang.switch")
  assert_eq(commands[39].label, text(t, "app.command.lang.switch"))
  assert_eq(commands[39].group, "文件")
}

///|
test "registry dispatch preserves representative state transitions" {
  let model = initial_model()
  // 模式命令
  let ai_mode = apply_shell(model, StudioCommandRun("studio.mode.ai"))
  assert_true(ai_mode.perspective is PsAi)
  // 窗格命令：live pane 开关（初态开 → 关）
  let pane = apply_shell(model, StudioCommandRun("studio.pane.live"))
  assert_eq(pane.workbench.layout.pane_live, false)
  // 底栏页签命令：先收起底栏再点页签 → 选中并展开
  let collapsed = apply_shell(model, ToggleBottom)
  assert_false(collapsed.bottom_open)
  let audit = apply_shell(collapsed, StudioCommandRun("studio.bottom.audit"))
  assert_true(audit.bottom_tab is BtAudit)
  assert_true(audit.bottom_open)
  // 未知命令 no-op
  let unknown = apply_shell(model, StudioCommandRun("studio.nope"))
  assert_true(unknown.perspective is PsVisual)
  assert_true(
    @wb.find_command(studio_command_registry(), "studio.nope") is None,
  )
}

///|
test "stateful toggle commands read the current model" {
  let model = initial_model()
  // 左栏开关：LeftTree ↔ LeftHidden
  let hidden = apply_shell(model, StudioCommandRun("studio.left.toggle"))
  assert_true(hidden.left_view is LeftHidden)
  let shown = apply_shell(hidden, StudioCommandRun("studio.left.toggle"))
  assert_true(shown.left_view is LeftTree)
  // 右栏开关（非 AI 模式）：RvContext ↔ RvHidden
  let right_hidden = apply_shell(model, StudioCommandRun("studio.right.toggle"))
  assert_true(right_hidden.right_view is RvHidden)
  let right_shown = apply_shell(
    right_hidden,
    StudioCommandRun("studio.right.toggle"),
  )
  assert_true(right_shown.right_view is RvContext)
  // AI 模式预设收起右栏；展开 = 工作区面板（VS Code 智能体模式口径）
  let ai_model = apply_shell(model, SetPerspective(PsAi))
  assert_true(ai_model.right_view is RvHidden)
  let ai_shown = apply_shell(ai_model, StudioCommandRun("studio.right.toggle"))
  assert_true(ai_shown.right_view is RvWorkspace)
  let ai_hidden = apply_shell(ai_shown, StudioCommandRun("studio.right.toggle"))
  assert_true(ai_hidden.right_view is RvHidden)
}

///|
test "hidden commands stay dispatchable but absent from palette" {
  let model = initial_model()
  let designed = apply_shell(model, SetPerspective(PsDesign))
  let visual = apply_shell(
    designed,
    StudioCommandRun("studio.workspace.visual"),
  )
  assert_true(visual.perspective is PsVisual)
  let coded = apply_shell(designed, StudioCommandRun("studio.workspace.code"))
  assert_true(coded.perspective is PsCode)
  let ai_docked = apply_shell(model, SetRightView(RvAi))
  let inspector = apply_shell(
    ai_docked,
    StudioCommandRun("studio.right.context"),
  )
  assert_true(inspector.right_view is RvContext)
}

///|
test "action channels: apply vs dispatch match the legacy switch" {
  let ctx : StudioCtx = { model: initial_model(), t: translator_for(ZhHans), }
  let registry = studio_command_registry()
  // 保存走纯更新通道（服务臂在 update_with_services 接住）
  match (@wb.find_command(registry, "studio.file.save").unwrap().run)(ctx) {
    @wb.Apply(SaveRequested) => ()
    _ => fail("studio.file.save must apply SaveRequested")
  }
  // 新建工程 / 模板走效果派发回程序环（服务流）
  match (@wb.find_command(registry, "studio.file.new").unwrap().run)(ctx) {
    @wb.Dispatch(NewProjectRequested(-1)) => ()
    _ => fail("studio.file.new must dispatch NewProjectRequested(-1)")
  }
  match
    (@wb.find_command(registry, "studio.template.hello").unwrap().run)(ctx) {
    @wb.Dispatch(NewProjectRequested(0)) => ()
    _ => fail("studio.template.hello must dispatch NewProjectRequested(0)")
  }
  match
    (@wb.find_command(registry, "studio.template.store").unwrap().run)(ctx) {
    @wb.Dispatch(NewProjectRequested(3)) => ()
    _ => fail("studio.template.store must dispatch NewProjectRequested(3)")
  }
  // AI 新会话带时钟时间戳（状态依赖消息）
  match
    (@wb.find_command(registry, "studio.ai.new_session").unwrap().run)(ctx) {
    @wb.Apply(AiSessionOp(AiSessionCreate(_))) => ()
    _ => fail("studio.ai.new_session must apply AiSessionCreate")
  }
}
