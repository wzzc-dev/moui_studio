///|
/// 插件管理面板 app 侧测试：
/// - 状态切片：打开/关闭/选中/忙碌/回执
/// - 禁用 ≠ 卸载：禁用只过滤入口（文件留着），卸载删目录
/// - 卸载是**破坏性操作**：必须经确认卡（pending_confirm）
/// - 安装/卸载回执要说话（成功与失败都要有回执）
/// - 本端不支持安装时，UI 显式声明（不假装能装）

///|
/// 造一份清单（名字/版本有值，便于断言界面能拿到真实信息）。
fn manager_sample_manifest(
  plugin_id : String,
) -> @plugin_contract.PluginManifest {
  {
    id: plugin_id,
    name: "样例插件",
    version: "1.2.3",
    description: "测试用插件",
    entry: "plugin.wasm",
    capabilities: [@plugin_contract.CapPanels, @plugin_contract.CapCommands],
    min_api_version: 1,
    abi: @plugin_contract.AbiComponent,
  }
}

///|
fn manager_load_ok(plugin_id : String) -> @plugin_contract.PluginLoadResult {
  @plugin_contract.Loaded(manifest=manager_sample_manifest(plugin_id), contributions={
    panels: [("main", "主面板")],
    commands: [("do", "执行")],
  })
}

///|
test "the plugin manager starts closed and idle" {
  let model = initial_model()
  assert_false(model.plugin_manager.open)
  assert_eq(model.plugin_manager.selected, "")
  assert_false(model.plugin_manager.is_busy())
  assert_eq(model.plugin_manager.notice, "")
}

///|
test "opening and closing the plugin manager keeps the state coherent" {
  let model = initial_model()
  let opened = apply_plugin_manager_open(model)
  assert_true(opened.plugin_manager.open)
  let selected = apply_plugin_manager_select(opened, "com.example.a")
  assert_eq(selected.plugin_manager.selected, "com.example.a")
  // 关闭时清空瞬态（选中与回执）——下次打开是干净的。
  let closed = apply_plugin_manager_close(selected)
  assert_false(closed.plugin_manager.open)
  assert_eq(closed.plugin_manager.selected, "")
}

///|
test "the plugin manager tracks which plugin is busy" {
  let model = initial_model()
  let busy = apply_plugin_manager_busy(model, "com.example.a")
  assert_true(busy.plugin_manager.is_busy())
  assert_true(busy.plugin_manager.is_busy_with("com.example.a"))
  assert_false(busy.plugin_manager.is_busy_with("com.example.b"))
}

///|
test "a successful install reports back and asks for a rescan" {
  let model = initial_model()
  let (next, effect) = apply_plugin_installed(model, Ok("com.example.a"))
  // 成功也要说话——点了没反应会让人以为没生效。
  assert_eq(next.plugin_manager.notice, "已安装插件 com.example.a")
  assert_false(next.plugin_manager.notice_is_error)
  // 装完要重扫：新插件必须立刻出现在列表里。
  assert_true(effect is @moui.Effect::Dispatch(_))
}

///|
test "a failed install reports the reason" {
  let model = initial_model()
  let (next, _effect) = apply_plugin_installed(model, Err("清单非法"))
  assert_true(next.plugin_manager.notice.contains("清单非法"))
  assert_true(next.plugin_manager.notice_is_error)
}

///|
test "a successful uninstall reports back and clears the selection" {
  let model = apply_plugin_manager_select(initial_model(), "com.example.a")
  let (next, effect) = apply_plugin_uninstalled(model, Ok("com.example.a"))
  assert_eq(next.plugin_manager.notice, "已卸载插件 com.example.a")
  assert_false(next.plugin_manager.notice_is_error)
  // 被卸的插件若正被选中 → 取消选中（详情区不能指向不存在的插件）。
  assert_eq(next.plugin_manager.selected, "")
  // 卸完要重扫：被卸的插件要从列表里消失。
  assert_true(effect is @moui.Effect::Dispatch(_))
}

///|
test "a failed uninstall reports the reason" {
  let model = initial_model()
  let (next, _effect) = apply_plugin_uninstalled(model, Err("插件未安装"))
  assert_true(next.plugin_manager.notice.contains("插件未安装"))
  assert_true(next.plugin_manager.notice_is_error)
}

///|
test "uninstalling a plugin asks for confirmation first" {
  // 卸载是**不可逆**的（目录被删）——必须经确认卡，不能一点就删。
  let model = initial_model()
  let (next, effect) = update_with_services(
    model,
    PluginUninstallRequested("com.example.a"),
    @services.AppServices::new(),
  )
  assert_true(next.pending_confirm is Some(CkUninstallPlugin("com.example.a")))
  // 确认前不该有任何副作用。
  assert_true(effect is @moui.Effect::NoEffect)
}

///|
test "the uninstall confirmation copy names the plugin" {
  // 确认卡要说清是**哪个**插件被卸（用户可能同时有多个）。
  let t = translator_for(ZhHans)
  let copy = confirm_copy(CkUninstallPlugin("com.example.a"), t)
  assert_true(copy.contains("com.example.a"))
}

///|
test "disabling a plugin keeps it installed and only hides its entries" {
  // 禁用 ≠ 卸载：禁用只过滤贡献项入口，插件仍在列表里、仍可再启用。
  let model = apply_plugin_scan(
    initial_model(),
    [manager_load_ok("com.example.a")],
    true,
  )
  let disabled = { ..model, plugin_disabled: ["com.example.a"], }
  // 插件还在（没被卸掉）
  assert_eq(disabled.plugin_state.descriptors.length(), 1)
  assert_false(plugin_active(disabled, "com.example.a"))
  // 但它的面板不再出现在工作区
  assert_eq(plugin_panel_visible(disabled), false)
}

///|
test "the plugin state records the install capability of this platform" {
  // 浏览器没有文件系统 → 本端不能装 → UI 不给「安装」按钮。
  let model = initial_model()
  assert_false(model.plugin_state.install_available)
  assert_eq(model.plugin_state.plugins_root, "")
}

///|
test "the plugin manager renders without a plugin runtime" {
  // 能力缺席即降级：没有插件运行时时管理面板是空的（不崩）。
  let model = initial_model()
  let t = translator_for(ZhHans)
  let view = plugin_manager_dialog(model, t, false, "")
  // 视图能构造出来（不抛异常）即通过——`View` 是结构体，无法做类型判断。
  ignore(view)
  assert_false(model.plugin_state.available)
}
