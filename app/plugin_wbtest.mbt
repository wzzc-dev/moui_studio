///|
/// WASM 插件系统(M8)app 侧测试：
/// - 状态切片：加载回执写入、坏插件不阻断好插件、启停口径
/// - 贡献点桥接：插件面板在 studio_panels 出现/缺席、插件命令不进全局表
/// - 视图解释器：协议 JSON → 宿主视图、颜色解析
/// - 跨平台降级：无插件运行时时页签不出现

///|
fn plugin_load_ok(plugin_id : String) -> @plugin_contract.PluginLoadResult {
  @plugin_contract.Loaded(manifest=sample_manifest(plugin_id), contributions={
    panels: [("main", "主面板")],
    commands: [("do", "执行")],
  })
}

///|
/// 造一份清单（名字/版本有值，便于断言界面能拿到真实信息）。
fn sample_manifest(plugin_id : String) -> @plugin_contract.PluginManifest {
  {
    id: plugin_id,
    name: "样例插件",
    version: "1.2.3",
    description: "测试用插件",
    entry: "plugin.wasm",
    capabilities: [@plugin_contract.CapPanels],
    min_api_version: 1,
    abi: @plugin_contract.AbiCore,
  }
}

///|
test "plugin scan results register the plugin and its contributions" {
  let model = initial_model()
  let next = apply_plugin_scan(model, [plugin_load_ok("com.example.a")], true)
  assert_eq(next.plugin_state.descriptors.length(), 1)
  assert_eq(next.plugin_state.descriptors[0].manifest.id, "com.example.a")
  assert_eq(next.plugin_state.plugin_panels("com.example.a").length(), 1)
  assert_eq(
    next.plugin_state.plugin_panels("com.example.a")[0],
    ("main", "主面板"),
  )
  assert_eq(next.plugin_state.plugin_commands("com.example.a").length(), 1)
}

///|
test "a failed plugin is reported without blocking the good one" {
  let model = initial_model()
  let next = apply_plugin_scan(
    model,
    [
      plugin_load_ok("com.example.good"),
      @plugin_contract.Failed(
        plugin_id="com.example.bad",
        reason="wasm 校验失败",
      ),
    ],
    true,
  )
  // 好插件照常注册。
  assert_eq(next.plugin_state.descriptors.length(), 1)
  assert_eq(next.plugin_state.descriptors[0].manifest.id, "com.example.good")
  // 坏插件进错误表——**必须说话**，不能静默消失。
  assert_true(next.plugin_state.errors.contains("com.example.bad"))
}

///|
test "plugin availability follows the runtime presence" {
  let model = initial_model()
  assert_false(model.plugin_state.available)
  let next = apply_plugin_scan(model, [], true)
  assert_true(next.plugin_state.available)
}

///|
test "the plugin panel appears only when a loaded plugin is enabled" {
  let model = initial_model()
  // 没有插件运行时 → 不显示。
  assert_false(plugin_panel_visible(model))
  // 有运行时但没插件 → 不显示（不留空页）。
  let with_runtime = apply_plugin_scan(model, [], true)
  assert_false(plugin_panel_visible(with_runtime))
  // 有运行时且有已加载插件 → 显示。
  let with_plugin = apply_plugin_scan(
    with_runtime,
    [plugin_load_ok("com.example.a")],
    true,
  )
  assert_true(plugin_panel_visible(with_plugin))
  // 插件被禁用 → 页签消失。
  let disabled = { ..with_plugin, plugin_disabled: ["com.example.a"], }
  assert_false(plugin_panel_visible(disabled))
}

///|
test "the plugin panel is registered in the bottom panel table" {
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.a")],
    true,
  )
  let panels = studio_panels(model)
  let mut found = false
  for panel in panels {
    if panel.id == "bottom.plugins" {
      found = true
    }
  }
  assert_true(found)
}

///|
test "no plugin panel is registered when the runtime is absent" {
  let panels = studio_panels(initial_model())
  for panel in panels {
    assert_false(panel.id == "bottom.plugins")
  }
}

///|
test "plugin commands do not enter the global command registry" {
  // 既有回归硬编码 43 条命令 / 40 条可见——插件命令**不进**那张表
  // （插件命令在自己的面板里成区展示）。
  let registry = studio_command_registry()
  for contribution in registry {
    assert_false(contribution.id.has_prefix("plugin."))
  }
}

///|
test "plugin color parsing accepts the documented shapes" {
  let color = parse_plugin_color("#112233")
  assert_true(color is Some(_))
  let with_alpha = parse_plugin_color("#80112233")
  assert_true(with_alpha is Some(_))
  assert_true(parse_plugin_color("nope") is None)
  assert_true(parse_plugin_color("#GGGGGG") is None)
}

///|
test "a plugin view protocol renders through the interpreter" {
  let spec = @plugin_contract.encode_view({
    node: @plugin_contract.Column([
      {
        node: @plugin_contract.Text("你好"),
        key: "greeting",
        width: None,
        height: None,
        padding: None,
        spacing: None,
        background: None,
        foreground: None,
        font_size: None,
        weight: None,
      },
    ]),
    key: "root",
    width: Some(200.0),
    height: None,
    padding: None,
    spacing: None,
    background: None,
    foreground: None,
    font_size: None,
    weight: None,
  })
  let view = interpret_plugin_view_json(spec, {
    plugin_id: "com.example.a",
    panel_id: "main",
    button_key: fn(action_id) { "com.example.a/main/" + action_id },
    on_action: fn(action_id, payload) {
      PluginAction("com.example.a", "main", action_id, payload)
    },
  })
  assert_true(view is Some(_))
}

///|
test "an invalid plugin view protocol yields no view rather than a crash" {
  let view = interpret_plugin_view_json("not json", {
    plugin_id: "com.example.a",
    panel_id: "main",
    button_key: fn(action_id) { "com.example.a/main/" + action_id },
    on_action: fn(action_id, payload) {
      PluginAction("com.example.a", "main", action_id, payload)
    },
  })
  assert_true(view is None)
}

///|
test "plugin action requests carry the plugin and action identity" {
  let request = plugin_action_request("com.example.a", "on_click", "payload")
  assert_true(request.contains("com.example.a"))
  assert_true(request.contains("on_click"))
}

///|
test "plugin view requests carry the plugin and panel identity" {
  let request = plugin_view_request("com.example.a", "main", "")
  assert_true(request.contains("com.example.a"))
  assert_true(request.contains("main"))
}

///|
test "plugin panel specs are cached and retrievable" {
  let model = initial_model()
  let next = apply_plugin_panel_spec(model, "com.example.a", "main", "{}")
  assert_eq(next.plugin_state.panel_spec("com.example.a", "main"), Some("{}"))
  assert_eq(next.plugin_state.panel_spec("com.example.a", "absent"), None)
}

///|
test "the unavailable bridge reports no runtime and no plugins" {
  let bridge = @plugin_contract.PluginBridge::unavailable()
  assert_false(bridge.is_available())
  let mut loaded_count = 0
  (bridge.load)(fn(items) { loaded_count = items.length() })
  assert_eq(loaded_count, 0)
  assert_false((bridge.is_loaded)("com.example.a"))
}

///|
test "plugin descriptors carry the real manifest info for the settings UI" {
  let model = initial_model()
  let next = apply_plugin_scan(model, [plugin_load_ok("com.example.a")], true)
  let descriptor = next.plugin_state.descriptors[0]
  // 插件管理界面显示的是**作者写的**名字/版本/职责，不是把 id 当名字。
  assert_eq(descriptor.manifest.name, "样例插件")
  assert_eq(descriptor.manifest.version, "1.2.3")
  assert_eq(descriptor.manifest.description, "测试用插件")
}

///|
test "a failed plugin is visible with its reason" {
  let model = initial_model()
  let next = apply_plugin_scan(
    model,
    [
      @plugin_contract.Failed(
        plugin_id="com.example.bad",
        reason="wasm 校验失败",
      ),
    ],
    true,
  )
  // 失败原因必须能查到——**坏插件要说话**，不能静默消失。
  let failures = next.plugin_state.failures()
  assert_eq(failures.length(), 1)
  assert_eq(failures[0].0, "com.example.bad")
  assert_eq(failures[0].1, "wasm 校验失败")
  assert_eq(
    next.plugin_state.failure_reason("com.example.bad"),
    Some("wasm 校验失败"),
  )
}

///|
test "the wasm plugin section appears when a runtime is present" {
  let model = initial_model()
  // 没有运行时 → 整组不出现（能力缺席就不留空页）。
  assert_false(model.plugin_state.available)
  // 有运行时 + 已加载插件 → 出现。
  let loaded = apply_plugin_scan(model, [plugin_load_ok("com.example.a")], true)
  assert_true(loaded.plugin_state.available)
  assert_eq(loaded.plugin_state.loaded_ids().length(), 1)
  assert_eq(loaded.plugin_state.loaded_ids()[0], "com.example.a")
}

///|
test "disabling a wasm plugin uses the shared disable list" {
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.a")],
    true,
  )
  // 启停走既有 `plugin_disabled`——与内置插件同一个开关语义。
  assert_true(plugin_active(model, "com.example.a"))
  let disabled = { ..model, plugin_disabled: ["com.example.a"], }
  assert_false(plugin_active(disabled, "com.example.a"))
  // 禁用后插件页签不再出现。
  assert_false(plugin_panel_visible(disabled))
}

///|
test "panels without a cached view are requested once" {
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.a")],
    true,
  )
  // 插件有一个面板（main），还没拿到视图 → 需要请求。
  let pending = panels_needing_view(model)
  assert_eq(pending.length(), 1)
  assert_eq(pending[0].0, "com.example.a")
  assert_eq(pending[0].1, "main")
  // 标记已请求后不再重复请求（否则每次重渲都发一次，队列会打满）。
  let marked = mark_panels_requested(model, pending)
  assert_eq(panels_needing_view(marked).length(), 0)
}

///|
test "a cached panel view is not requested again" {
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.a")],
    true,
  )
  // 视图已到达 → 不再请求。
  let cached = apply_plugin_panel_spec(model, "com.example.a", "main", "{}")
  assert_true(cached.plugin_state.has_panel_spec("com.example.a", "main"))
  assert_eq(panels_needing_view(cached).length(), 0)
}

///|
test "a disabled plugin's panels are not requested" {
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.a")],
    true,
  )
  let disabled = { ..model, plugin_disabled: ["com.example.a"], }
  // 禁用的插件不请求视图——不给它白干活的机会。
  assert_eq(panels_needing_view(disabled).length(), 0)
}

///|
test "the plugin view request carries the panel identity" {
  let request = plugin_view_request("com.example.a", "main", "")
  // 插件靠它知道要渲染哪个面板。
  assert_true(request.contains("com.example.a"))
  assert_true(request.contains("main"))
  assert_true(request.contains("moui.studio.plugin.viewreq"))
}

///|
test "a plugin action carries the panel identity so the new view lands right" {
  let request = plugin_action_request("com.example.a", "increment", "")
  assert_true(request.contains("increment"))
  // 动作请求本身不带面板 id（插件按 action 处理），但回执会带——
  // 宿主要靠它把新视图归到正确的面板。
  assert_false(request.contains("panel_id"))
}

///|
test "a web plugin is rendered once even when it also reaches the model" {
  // web 端插件的贡献进两个地方：进程级槽位（JS 侧推入）**和** model 的
  // descriptors（`PluginsScanned` 回执）。曾经两条路径各渲染一遍 → 同一
  // 个插件的面出现两份。现已统一为单一路径（视图一律走 model 缓存），
  // 故只出现一次。
  let contributions = @plugin_contract.encode_contributions({
    panels: [("main", "主面板")],
    commands: [("do", "执行")],
  })
  install_web_plugin_provider(fn() {
    let map : Map[String, String] = Map([], capacity=4)
    map.set("com.example.web", contributions)
    map
  })
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.web")],
    true,
  )
  // 只出现一次。
  let ids = plugin_panel_plugin_ids(model)
  assert_eq(ids.length(), 1)
  assert_eq(ids[0], "com.example.web")
  // 清理：进程级槽位是全局的，别污染后续用例。
  install_web_plugin_provider(fn() { Map([], capacity=4) })
}

///|
test "native and web plugins are both rendered but never twice" {
  // native 插件（只有 model 描述）+ web 插件（槽位 + model 描述）。
  let contributions = @plugin_contract.encode_contributions({
    panels: [("main", "主面板")],
    commands: [],
  })
  install_web_plugin_provider(fn() {
    let map : Map[String, String] = Map([], capacity=4)
    map.set("com.example.web", contributions)
    map
  })
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.native"), plugin_load_ok("com.example.web")],
    true,
  )
  let ids = plugin_panel_plugin_ids(model)
  assert_eq(ids.length(), 2)
  assert_true(ids.contains("com.example.native"))
  assert_true(ids.contains("com.example.web"))
  install_web_plugin_provider(fn() { Map([], capacity=4) })
}

///|
test "a disabled web plugin is not rendered" {
  let contributions = @plugin_contract.encode_contributions({
    panels: [("main", "主面板")],
    commands: [],
  })
  install_web_plugin_provider(fn() {
    let map : Map[String, String] = Map([], capacity=4)
    map.set("com.example.web", contributions)
    map
  })
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.web")],
    true,
  )
  // 启停语义与 native 同份（`plugin_disabled`）——禁用的插件不出现。
  let disabled = { ..model, plugin_disabled: ["com.example.web"], }
  assert_eq(plugin_panel_plugin_ids(disabled).length(), 0)
  install_web_plugin_provider(fn() { Map([], capacity=4) })
}

///|
test "a plugin without panel contributions is not rendered" { // 插件加载成功但没贡献面板 → 不占位（页签里不出现空区块）。
  let model = apply_plugin_scan(
    initial_model(),
    [
      @plugin_contract.Loaded(manifest=sample_manifest("com.example.empty"), contributions={
        panels: [],
        commands: [],
      }),
    ],
    true,
  )
  assert_eq(plugin_panel_plugin_ids(model).length(), 0)
}

///|
test "reloading the same plugin does not duplicate it" {
  // 加载回执必须**幂等**：web 端轮询 / native 端重扫会多次加载同一个
  // 插件，追加语义会让插件的面渲染多份（同一个插件出现 N 次）。
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.a")],
    true,
  )
  assert_eq(model.plugin_state.descriptors.length(), 1)
  // 再加载一次 → 仍然只有一个。
  let reloaded = apply_plugin_scan(
    model,
    [plugin_load_ok("com.example.a")],
    true,
  )
  assert_eq(reloaded.plugin_state.descriptors.length(), 1)
  assert_eq(reloaded.plugin_state.loaded_ids().length(), 1)
  assert_eq(reloaded.plugin_state.loaded_ids()[0], "com.example.a")
  // 面板列表也不重复。
  assert_eq(plugin_panel_plugin_ids(reloaded).length(), 1)
}

///|
test "reloading keeps the other plugins" {
  // 幂等替换**不能**误删别的插件。
  let model = apply_plugin_scan(
    initial_model(),
    [plugin_load_ok("com.example.a"), plugin_load_ok("com.example.b")],
    true,
  )
  let reloaded = apply_plugin_scan(
    model,
    [plugin_load_ok("com.example.a")],
    true,
  )
  assert_eq(reloaded.plugin_state.loaded_ids().length(), 2)
  assert_true(reloaded.plugin_state.loaded_ids().contains("com.example.a"))
  assert_true(reloaded.plugin_state.loaded_ids().contains("com.example.b"))
}
