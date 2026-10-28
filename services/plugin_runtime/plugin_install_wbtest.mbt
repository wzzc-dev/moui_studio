///|
/// 插件安装/卸载测试（native 后端）。
///
/// 装卸插件是**文件操作**——测的是「装上去能用」「卸干净了」：
/// - 装：清单校验 → 复制 → 目标目录可被扫描器认出（能加载）。
/// - 装：坏清单 / 缺入口 / 重复装 → **明确拒绝**（不装半个）。
/// - 卸：递归删干净（`@x/fs.remove_dir` 非递归，得自己走）。
/// - 卸：非法 id / 未装 → 明确拒绝。

///|
/// 准备一个「待安装」的插件源目录：清单 + 入口 wasm。
fn prepare_source_dir(root : String, plugin_id : String) -> String {
  ensure_dir(root)
  let dir = "\{root}/\{plugin_id}"
  ensure_dir(dir)
  let manifest = "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"\{plugin_id}\",\"name\":\"Fixture\",\"version\":\"1.0.0\",\"description\":\"install fixture\",\"entry\":\"plugin.wasm\",\"capabilities\":[\"CapPanels\"],\"min_api_version\":1}"
  write_file("\{dir}/plugin.json", manifest)
  ignore(copy_file(FIXTURE_WASM, "\{dir}/plugin.wasm"))
  dir
}

///|
test "installing a plugin copies it into the plugin root and it becomes loadable" {
  let root = "_build/test/plugin_install_ok"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  let source = prepare_source_dir("\{root}/source", "com.example.installed")
  // 装
  match install_plugin(plugins_root, source) {
    Installed(plugin_id) => assert_eq(plugin_id, "com.example.installed")
    Rejected(reason) => fail("安装应当成功：\{reason}")
  }
  // 装完目标目录在插件根下，且清单与入口都在
  let installed_dir = "\{plugins_root}/com.example.installed"
  assert_true(@x/fs.path_exists("\{installed_dir}/plugin.json"))
  assert_true(@x/fs.path_exists("\{installed_dir}/plugin.wasm"))
  // 装完**能被扫出来并加载**（这才是「装上了」的真正判据）
  let runtime = PluginRuntime::new(plugins_root~)
  let host = HostBridge::new()
  let outcomes = runtime.load_all(host)
  let mut loaded = false
  for outcome in outcomes {
    match outcome {
      @plugin_contract.Loaded(manifest~, ..) =>
        if manifest.id == "com.example.installed" {
          loaded = true
        }
      _ => ()
    }
  }
  assert_true(loaded)
  runtime.unload_all()
  remove_tree(root)
}

///|
test "installing leaves the source directory untouched" {
  // 安装是**复制**不是移动——用户的源目录不动（可能还要留着）。
  let root = "_build/test/plugin_install_copy"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  let source = prepare_source_dir("\{root}/source", "com.example.copied")
  match install_plugin(plugins_root, source) {
    Installed(_) => ()
    Rejected(reason) => fail("安装应当成功：\{reason}")
  }
  assert_true(@x/fs.path_exists("\{source}/plugin.json"))
  assert_true(@x/fs.path_exists("\{source}/plugin.wasm"))
  remove_tree(root)
}

///|
test "installing rejects a malformed manifest without creating anything" {
  let root = "_build/test/plugin_install_bad_manifest"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  let source = "\{root}/source"
  ensure_dir(source)
  write_file("\{source}/plugin.json", "{ not json")
  match install_plugin(plugins_root, source) {
    Installed(_) => fail("坏清单不该装上")
    Rejected(_) => ()
  }
  // 坏清单不该在插件根下留下任何目录
  let entries = @x/fs.read_dir(plugins_root) catch { _ => [] }
  assert_eq(entries.length(), 0)
  remove_tree(root)
}

///|
test "installing rejects a missing entry file" {
  let root = "_build/test/plugin_install_no_entry"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  let source = "\{root}/source"
  ensure_dir(source)
  // 清单合法，但入口文件不存在
  write_file(
    "\{source}/plugin.json",
    "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"com.example.noentry\",\"name\":\"No Entry\",\"version\":\"1\",\"description\":\"\",\"entry\":\"missing.wasm\",\"capabilities\":[],\"min_api_version\":1}",
  )
  match install_plugin(plugins_root, source) {
    Installed(_) => fail("缺入口文件不该装上")
    Rejected(_) => ()
  }
  remove_tree(root)
}

///|
test "installing refuses to overwrite an already installed plugin" {
  let root = "_build/test/plugin_install_duplicate"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  let source = prepare_source_dir("\{root}/source", "com.example.dup")
  match install_plugin(plugins_root, source) {
    Installed(_) => ()
    Rejected(reason) => fail("首次安装应当成功：\{reason}")
  }
  // 第二次：同一个 id → 拒绝（升级需先卸载）
  match install_plugin(plugins_root, source) {
    Installed(_) => fail("重复安装应当被拒绝")
    Rejected(_) => ()
  }
  remove_tree(root)
}

///|
test "installing rejects a source directory that does not exist" {
  let root = "_build/test/plugin_install_no_source"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  match install_plugin(plugins_root, "\{root}/nope") {
    Installed(_) => fail("源目录不存在不该装上")
    Rejected(_) => ()
  }
  remove_tree(root)
}

///|
test "uninstalling removes the plugin directory recursively" {
  let root = "_build/test/plugin_remove_ok"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  let source = prepare_source_dir("\{root}/source", "com.example.removed")
  ignore(install_plugin(plugins_root, source))
  // 装好了
  assert_true(@x/fs.path_exists("\{plugins_root}/com.example.removed"))
  // 卸
  match remove_plugin(plugins_root, "com.example.removed") {
    Removed(plugin_id) => assert_eq(plugin_id, "com.example.removed")
    Rejected(reason) => fail("卸载应当成功：\{reason}")
  }
  // 目录没了（递归删干净——`@x/fs.remove_dir` 本身非递归）
  assert_false(@x/fs.path_exists("\{plugins_root}/com.example.removed"))
  remove_tree(root)
}

///|
test "uninstalling removes nested directories" {
  // 插件目录里可能有子目录（资源、文档）——必须一并删掉，
  // 否则会留下残骸（下次扫描会把半个插件当插件）。
  let root = "_build/test/plugin_remove_nested"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  let plugin_dir = "\{plugins_root}/com.example.nested"
  ensure_dir("\{plugin_dir}/assets/icons")
  write_file("\{plugin_dir}/plugin.json", "{}")
  write_file("\{plugin_dir}/assets/icons/a.bin", "x")
  match remove_plugin(plugins_root, "com.example.nested") {
    Removed(_) => ()
    Rejected(reason) => fail("卸载应当成功：\{reason}")
  }
  assert_false(@x/fs.path_exists(plugin_dir))
  remove_tree(root)
}

///|
test "uninstalling rejects an illegal plugin id" {
  // id 门卫：防止 `..` 之类的 id 拼出插件根目录之外的路径。
  let root = "_build/test/plugin_remove_bad_id"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  // 造一个「越权」目标：插件根的上一级
  ensure_dir("\{root}/outside")
  write_file("\{root}/outside/keep.txt", "x")
  match remove_plugin(plugins_root, "../outside") {
    Removed(_) => fail("非法 id 不该卸载成功")
    Rejected(_) => ()
  }
  // 越权目标必须还在
  assert_true(@x/fs.path_exists("\{root}/outside/keep.txt"))
  remove_tree(root)
}

///|
test "uninstalling a plugin that is not installed reports it" {
  let root = "_build/test/plugin_remove_missing"
  let plugins_root = "\{root}/plugins"
  remove_tree(root)
  ensure_dir(plugins_root)
  match remove_plugin(plugins_root, "com.example.absent") {
    Removed(_) => fail("没装的插件不该报卸载成功")
    Rejected(_) => ()
  }
  remove_tree(root)
}
