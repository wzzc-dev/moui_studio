///|
/// WASM 插件系统 E2E（native 后端·**组件形态**）：真实加载一个
/// WebAssembly **组件**插件，验证「清单扫描 → 组件校验 → 实例化 →
/// 取贡献描述 → 取视图 → 动作回环」全链路。
///
/// fixture 是 `samples/plugin_fixture_component`（MoonBit `wasm` target
/// 编译 + `wasm-tools component` 组件化）。
///
/// **与核心模块形态 E2E 的差别**：字符串经 **Canonical ABI** 自动
/// 编解码（无 offset/len 手工搬运）；组件形态**不注册任何宿主函数**
/// ——它的 world 只 export 不 import，是更严格的一档沙箱。

///|
/// 组件 fixture 的产物路径（由 `scripts/build_plugin_component.sh` 产出）。
const COMPONENT_FIXTURE_WASM : String = "samples/plugin_fixture_component/dist/plugin_fixture.component.wasm"

///|
/// 准备一个**组件形态**插件目录：清单（`abi: "component"`）+ 入口组件。
fn prepare_component_plugin_dir(root : String, plugin_id : String) -> String {
  ensure_dir(root)
  let dir = "\{root}/\{plugin_id}"
  ensure_dir(dir)
  let manifest = "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"\{plugin_id}\",\"name\":\"Fixture 组件\",\"version\":\"1.0.0\",\"description\":\"E2E 组件 fixture\",\"entry\":\"plugin.component.wasm\",\"capabilities\":[\"CapPanels\",\"CapCommands\"],\"min_api_version\":1,\"abi\":\"component\"}"
  write_file("\{dir}/plugin.json", manifest)
  ignore(copy_file(COMPONENT_FIXTURE_WASM, "\{dir}/plugin.component.wasm"))
  dir
}

///|
test "the component fixture artifact exists (build it with scripts/build_plugin_component.sh)" {
  assert_true(@x/fs.path_exists(COMPONENT_FIXTURE_WASM))
}

///|
test "a real component plugin loads and reports its contributions" {
  let root = "_build/test/plugin_e2e_component_load"
  remove_tree(root)
  let plugin_id = "com.example.fixture.component"
  ignore(prepare_component_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let results = runtime.load_all(HostBridge::new())
  assert_eq(results.length(), 1)
  match results[0] {
    @plugin_contract.Loaded(manifest~, contributions~) => {
      assert_eq(manifest.id, plugin_id)
      assert_eq(manifest.abi, @plugin_contract.AbiComponent)
      assert_eq(contributions.panels.length(), 1)
      assert_eq(contributions.panels[0].0, "main")
    }
    @plugin_contract.Failed(plugin_id~, reason~) =>
      fail("组件插件: \{plugin_id} 加载失败：\{reason}")
    _ => fail("意外的加载结果")
  }
  assert_true(runtime.is_loaded(plugin_id))
}

///|
test "a component plugin answers a view request and an action request" {
  let root = "_build/test/plugin_e2e_component_call"
  remove_tree(root)
  let plugin_id = "com.example.fixture.component"
  ignore(prepare_component_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let results = runtime.load_all(HostBridge::new())
  assert_eq(results.length(), 1)
  // 视图请求：插件回一份视图协议 JSON。
  let view_request = @plugin_contract.plugin_view_request(plugin_id, "main", "")
  let view = match runtime.call(plugin_id, view_request) {
    Ok(text) => text
    Err(reason) => fail("组件视图请求失败：\{reason}")
  }
  let spec = match @plugin_contract.decode_view(view) {
    Ok(value) => value
    Err(errors) =>
      fail("组件视图协议非法：\{describe_view_errors(errors)}")
  }
  match spec.node {
    Column(children) => {
      assert_eq(children.length(), 2)
      match children[1].node {
        Button(label~, action~) => {
          assert_eq(label, "点我")
          assert_eq(action, "increment")
        }
        _ => fail("第二个子节点不是按钮")
      }
    }
    _ => fail("视图根节点不是 Column")
  }
  // 动作请求：插件处理后回**新**视图（计数 +1）。
  let action_request = @plugin_contract.plugin_action_request(
    plugin_id, "increment", "",
  )
  let after = match runtime.call(plugin_id, action_request) {
    Ok(text) => text
    Err(reason) => fail("组件动作请求失败：\{reason}")
  }
  if !after.contains("点击次数：1") {
    fail("组件动作后视图未更新计数")
  }
  runtime.unload_all()
}

///|
test "a core wasm plugin still loads when the manifest declares the core abi" {
  // 回归：既有插件（清单不写 abi）零改动——默认 core 形态。
  let root = "_build/test/plugin_e2e_core_default"
  remove_tree(root)
  let plugin_id = "com.example.fixture.core"
  ignore(prepare_plugin_dir(root, plugin_id))
  let runtime = PluginRuntime::new(plugins_root=root)
  let results = runtime.load_all(HostBridge::new())
  assert_eq(results.length(), 1)
  match results[0] {
    @plugin_contract.Loaded(manifest~, contributions~) => {
      assert_eq(manifest.abi, @plugin_contract.AbiCore)
      assert_eq(contributions.panels.length(), 1)
    }
    @plugin_contract.Failed(plugin_id~, reason~) =>
      fail("核心模块: \{plugin_id} 插件加载失败：\{reason}")
    _ => fail("意外的加载结果")
  }
  runtime.unload_all()
}
