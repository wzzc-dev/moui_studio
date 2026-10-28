///|
/// WASM 插件系统 E2E（native 后端）：真实加载一个 .wasm 插件，验证
/// 「清单扫描 → 校验 → 实例化 → 取贡献描述 → 取视图 → 动作回环」全链路。
///
/// fixture 是 `samples/plugin_fixture`（`wasm` target 编译的最小插件）。
/// 测试自己准备插件目录：把 fixture 的 wasm 产物复制进临时插件目录，
/// 配一份清单——这样测试不依赖仓库外的构建产物路径。
///
/// 目录辅助（`ensure_dir` / `remove_tree` / `write_file`）复用同包的
/// `plugin_runtime_wbtest.mbt` 定义。

///|
/// 视图协议错误列表 → 一句话原因。
fn describe_view_errors(
  errors : Array[@plugin_contract.PluginViewError],
) -> String {
  let parts : Array[String] = []
  for error in errors {
    parts.push(error.message())
  }
  parts.join("；")
}

///|
fn copy_file(from : String, to : String) -> Bool {
  let bytes = @x/fs.read_file_to_bytes(from) catch { _ => return false }
  @x/fs.write_bytes_to_file(to, bytes) catch {
    _ => return false
  }
  true
}

///|
/// fixture 的 wasm 产物路径（由 `scripts/build_plugin.sh` 产出）。
const FIXTURE_WASM : String = "samples/plugin_fixture/dist/plugin_fixture.wasm"

///|
/// 准备一个插件目录：清单 + 入口 wasm。返回插件目录路径。
fn prepare_plugin_dir(root : String, plugin_id : String) -> String {
  ensure_dir(root)
  let dir = "\{root}/\{plugin_id}"
  ensure_dir(dir)
  let manifest = "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"\{plugin_id}\",\"name\":\"Fixture\",\"version\":\"1.0.0\",\"description\":\"E2E fixture\",\"entry\":\"plugin.wasm\",\"capabilities\":[\"CapPanels\",\"CapCommands\"],\"min_api_version\":1}"
  write_file("\{dir}/plugin.json", manifest)
  ignore(copy_file(FIXTURE_WASM, "\{dir}/plugin.wasm"))
  dir
}

///|
test "the fixture artifact exists (build it with scripts/build_plugin.sh)" {
  assert_true(@x/fs.path_exists(FIXTURE_WASM))
}

///|
test "a real wasm plugin loads and reports its contributions" {
  let root = "_build/test/plugin_e2e_load"
  remove_tree(root)
  let plugin_id = "com.example.fixture"
  ignore(prepare_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let host = HostBridge::new()
  let outcomes = runtime.load_all(host)
  // 加载结果里应有这个插件，且状态是 Loaded。
  let mut loaded = false
  let expected_plugin_id = plugin_id
  for outcome in outcomes {
    match outcome {
      @plugin_contract.Loaded(manifest~, contributions~) =>
        if manifest.id == expected_plugin_id {
          loaded = true
          // 贡献描述：一个面板 + 一条命令。
          assert_eq(contributions.panels.length(), 1)
          assert_eq(contributions.panels[0].0, "main")
          assert_eq(contributions.commands.length(), 1)
          assert_eq(contributions.commands[0].0, "reset")
          // 清单信息随结果一起上来（插件管理界面要用真实名字/版本）。
          assert_eq(manifest.name, "Fixture")
          assert_eq(manifest.version, "1.0.0")
        }
      _ => ()
    }
  }
  assert_true(loaded)
  assert_true(runtime.is_loaded(plugin_id))
  runtime.unload_all()
  remove_tree(root)
}

///|
test "a real wasm plugin answers a call with a view protocol document" {
  let root = "_build/test/plugin_e2e_call"
  remove_tree(root)
  let plugin_id = "com.example.fixture"
  ignore(prepare_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let host = HostBridge::new()
  let outcomes = runtime.load_all(host)
  assert_eq(outcomes.length(), 1)
  // 请求一个视图：插件回一份视图协议 JSON。
  let request = "{\"format\":\"moui.studio.plugin.action\",\"format_version\":1,\"plugin_id\":\"com.example.fixture\",\"action_id\":\"increment\",\"payload\":\"\"}"
  let response = match runtime.call(plugin_id, request) {
    Ok(text) => text
    Err(reason) => {
      runtime.unload_all()
      remove_tree(root)
      fail("插件调用失败：\{reason}")
    }
  }
  // 响应能被视图协议解码（说明 ABI 的字符串往返无损）。
  let spec = match @plugin_contract.decode_view(response) {
    Ok(value) => value
    Err(errors) => {
      runtime.unload_all()
      remove_tree(root)
      fail(
        "插件响应不是合法视图协议：\{describe_view_errors(errors)}",
      )
    }
  }
  assert_eq(spec.key, "fixture-root")
  runtime.unload_all()
  remove_tree(root)
}

///|
test "a broken plugin does not block a good one" {
  let root = "_build/test/plugin_e2e_mixed"
  remove_tree(root)
  // 好插件
  ignore(prepare_plugin_dir(root, "com.example.good"))
  // 坏插件：入口不是合法 wasm
  let bad_dir = "\{root}/com.example.bad"
  ensure_dir(bad_dir)
  write_file(
    "\{bad_dir}/plugin.json",
    "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"com.example.bad\",\"name\":\"Bad\",\"version\":\"1\",\"description\":\"\",\"entry\":\"bad.wasm\",\"capabilities\":[],\"min_api_version\":1}",
  )
  write_file("\{bad_dir}/bad.wasm", "definitely not a wasm module")
  let runtime = PluginRuntime::new(plugins_root=root)
  let host = HostBridge::new()
  let outcomes = runtime.load_all(host)
  // 好插件照常加载，坏插件单独失败。
  let mut good = false
  let mut bad = false
  for outcome in outcomes {
    match outcome {
      @plugin_contract.Loaded(manifest~, ..) =>
        if manifest.id == "com.example.good" {
          good = true
        }
      @plugin_contract.Failed(plugin_id~, ..) =>
        if plugin_id == "com.example.bad" {
          bad = true
        }
      _ => ()
    }
  }
  assert_true(good)
  assert_true(bad)
  runtime.unload_all()
  remove_tree(root)
}

///|
test "calling an unloaded plugin reports a clear error" {
  let root = "_build/test/plugin_e2e_unloaded"
  remove_tree(root)
  let runtime = PluginRuntime::new(plugins_root=root)
  match runtime.call("com.example.never", "{}") {
    Ok(_) => fail("expected an error")
    Err(reason) => assert_true(reason.contains("未加载"))
  }
  remove_tree(root)
}

///|
test "a loaded plugin answers a view request with a view protocol document" {
  let root = "_build/test/plugin_e2e_view"
  remove_tree(root)
  let plugin_id = "com.example.fixture"
  ignore(prepare_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let host = HostBridge::new()
  ignore(runtime.load_all(host))
  assert_true(runtime.is_loaded(plugin_id))
  // 视图请求：宿主问插件要某个面板的视图。
  let request = "{\"format\":\"moui.studio.plugin.viewreq\",\"format_version\":1,\"plugin_id\":\"com.example.fixture\",\"panel_id\":\"main\",\"payload\":\"\"}"
  let response = match runtime.call(plugin_id, request) {
    Ok(text) => text
    Err(reason) => {
      runtime.unload_all()
      remove_tree(root)
      fail("视图请求失败：\{reason}")
    }
  }
  // 响应是合法的视图协议（宿主侧就能解释成 @moui.View）。
  let spec = match @plugin_contract.decode_view(response) {
    Ok(value) => value
    Err(errors) => {
      runtime.unload_all()
      remove_tree(root)
      fail(
        "视图响应不是合法视图协议：\{describe_view_errors(errors)}",
      )
    }
  }
  assert_eq(spec.key, "fixture-root")
  runtime.unload_all()
  remove_tree(root)
}

///|
test "a plugin action updates the panel view" {
  let root = "_build/test/plugin_e2e_action"
  remove_tree(root)
  let plugin_id = "com.example.fixture"
  ignore(prepare_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let host = HostBridge::new()
  ignore(runtime.load_all(host))
  // 动作请求：插件处理后回一份**新**视图。
  let request = "{\"format\":\"moui.studio.plugin.action\",\"format_version\":1,\"plugin_id\":\"com.example.fixture\",\"action_id\":\"increment\",\"payload\":\"\"}"
  let response = match runtime.call(plugin_id, request) {
    Ok(text) => text
    Err(reason) => {
      runtime.unload_all()
      remove_tree(root)
      fail("动作请求失败：\{reason}")
    }
  }
  // 新视图仍然合法（宿主据此更新缓存 → 界面重绘）。
  let spec = match @plugin_contract.decode_view(response) {
    Ok(value) => value
    Err(errors) => {
      runtime.unload_all()
      remove_tree(root)
      fail(
        "动作响应不是合法视图协议：\{describe_view_errors(errors)}",
      )
    }
  }
  assert_eq(spec.key, "fixture-root")
  runtime.unload_all()
  remove_tree(root)
}

///|
test "a plugin action changes the returned view" {
  let root = "_build/test/plugin_e2e_action_effect"
  remove_tree(root)
  let plugin_id = "com.example.fixture"
  ignore(prepare_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let host = HostBridge::new()
  ignore(runtime.load_all(host))
  // 先做一次 increment，再取视图——看状态是否在调用间保持。
  let action_first = "{\"format\":\"moui.studio.plugin.action\",\"format_version\":1,\"plugin_id\":\"com.example.fixture\",\"action_id\":\"increment\",\"payload\":\"\"}"
  ignore(runtime.call(plugin_id, action_first))
  // 第一次取视图：计数应为 1（若状态保持）。
  let view_request = "{\"format\":\"moui.studio.plugin.viewreq\",\"format_version\":1,\"plugin_id\":\"com.example.fixture\",\"panel_id\":\"main\",\"payload\":\"\"}"
  let before = match runtime.call(plugin_id, view_request) {
    Ok(text) => text
    Err(reason) => {
      runtime.unload_all()
      remove_tree(root)
      fail("视图请求失败：\{reason}")
    }
  }
  // 动作：increment。
  let action_request = "{\"format\":\"moui.studio.plugin.action\",\"format_version\":1,\"plugin_id\":\"com.example.fixture\",\"action_id\":\"increment\",\"payload\":\"\"}"
  let after = match runtime.call(plugin_id, action_request) {
    Ok(text) => text
    Err(reason) => {
      runtime.unload_all()
      remove_tree(root)
      fail("动作请求失败：\{reason}")
    }
  }
  // 动作后视图内容**变了**——这正是「点击后界面应更新」的根据。
  assert_false(before == after)
  // 新视图里的计数应当 +1（插件状态在调用间保持）。
  // 插件状态在调用间保持：动作后计数 +1，且动作被识别。
  assert_true(before.contains("点击次数：1"))
  assert_true(after.contains("点击次数：2"))
  assert_true(after.contains("last=increment"))
  // 新视图仍是合法的视图协议。
  let spec = match @plugin_contract.decode_view(after) {
    Ok(value) => value
    Err(errors) => {
      runtime.unload_all()
      remove_tree(root)
      fail(
        "动作响应不是合法视图协议：\{describe_view_errors(errors)}",
      )
    }
  }
  assert_eq(spec.key, "fixture-root")
  runtime.unload_all()
  remove_tree(root)
}
