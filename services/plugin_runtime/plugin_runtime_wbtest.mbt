///|
/// 插件运行时测试：清单扫描（坏插件不阻断好插件）、能力门控、配额、
/// 内存读写边界。
///
/// 不测「真实加载一个 wasm 插件」——那需要 wasm fixture（M5 的 E2E）。
/// 这里测的是**宿主侧**的行为：扫描、门控、配额构造、内存边界。

///|
/// 递归建目录（`@x/fs.create_dir` 不建父目录——测试要建
/// `_build/test/xxx` 这类嵌套路径，必须自己上溯建父级）。
fn ensure_dir(path : String) -> Unit {
  let parts = path.split("/")
  let mut current = ""
  for part in parts {
    let piece = part.to_owned()
    if piece == "" {
      continue
    }
    current = if current == "" { piece } else { "\{current}/\{piece}" }
    let exists = @x/fs.path_exists(current)
    if !exists {
      @x/fs.create_dir(current) catch {
        _ => ()
      }
    }
  }
}

///|
fn write_file(path : String, content : String) -> Unit {
  @x/fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}

///|
fn write_bytes(path : String, content : Bytes) -> Unit {
  @x/fs.write_bytes_to_file(path, content) catch {
    _ => ()
  }
}

///|
fn remove_tree(path : String) -> Unit {
  let entries = @x/fs.read_dir(path) catch { _ => return }
  for name in entries {
    let child = "\{path}/\{name}"
    let is_directory = @x/fs.is_dir(child) catch { _ => false }
    if is_directory {
      remove_tree(child)
    } else {
      @x/fs.remove_file(child) catch {
        _ => ()
      }
    }
  }
  @x/fs.remove_dir(path) catch {
    _ => ()
  }
}

///|
fn valid_manifest_json(id : String, entry : String) -> String {
  "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"\{id}\",\"name\":\"Test\",\"version\":\"1.0.0\",\"description\":\"\",\"entry\":\"\{entry}\",\"capabilities\":[\"CapPanels\"],\"min_api_version\":1}"
}

///|
test "scan finds a valid plugin and reports a broken one without blocking" {
  let root = "_build/test/plugin_scan_ok"
  remove_tree(root)
  @x/fs.create_dir(root) catch {
    _ => ()
  }
  // 好插件：清单合法 + 入口存在。
  ensure_dir("\{root}/good")
  write_file(
    "\{root}/good/plugin.json",
    valid_manifest_json("com.example.good", "good.wasm"),
  )
  write_bytes("\{root}/good/good.wasm", b"\x00asm")
  // 坏插件：清单格式错。
  ensure_dir("\{root}/bad")
  write_file("\{root}/bad/plugin.json", "{\"format\":\"wrong\"}")
  let result = scan_plugins(root)
  assert_eq(result.candidates.length(), 1)
  assert_eq(result.candidates[0].manifest.id, "com.example.good")
  assert_eq(result.candidates[0].manifest.entry, "good.wasm")
  // 坏插件被报告，但没挡住好插件。
  assert_eq(result.invalid.length(), 1)
  assert_eq(result.invalid[0].0, "bad")
  assert_false(result.truncated)
  remove_tree(root)
}

///|
test "scan reports a missing entry file as invalid" {
  let root = "_build/test/plugin_scan_missing"
  remove_tree(root)
  @x/fs.create_dir(root) catch {
    _ => ()
  }
  ensure_dir("\{root}/p")
  write_file(
    "\{root}/p/plugin.json",
    valid_manifest_json("com.example.p", "absent.wasm"),
  )
  let result = scan_plugins(root)
  assert_eq(result.candidates.length(), 0)
  assert_eq(result.invalid.length(), 1)
  assert_eq(result.invalid[0].0, "com.example.p")
  remove_tree(root)
}

///|
test "scan on a missing root yields nothing rather than failing" {
  let result = scan_plugins("_build/test/definitely_not_there")
  assert_eq(result.candidates.length(), 0)
  assert_eq(result.invalid.length(), 0)
}

///|
test "scan ignores directories without a manifest" {
  let root = "_build/test/plugin_scan_none"
  remove_tree(root)
  @x/fs.create_dir(root) catch {
    _ => ()
  }
  ensure_dir("\{root}/notaplugin")
  let result = scan_plugins(root)
  assert_eq(result.candidates.length(), 0)
  assert_eq(result.invalid.length(), 0)
  remove_tree(root)
}

///|
test "host bridge grants only what both sides allow" {
  let capabilities = [
    @plugin_contract.CapPanels,
    @plugin_contract.CapWorkspaceRead,
  ]
  // 宿主默认不给工程读 → 清单声明了也不给。
  let default_bridge = HostBridge::new()
  assert_false(
    default_bridge.grants(capabilities, @plugin_contract.CapWorkspaceRead),
  )
  // 宿主允许 + 清单声明 → 给。
  let trusted_bridge = HostBridge::new(capabilities=HostCapabilities::trusted())
  assert_true(
    trusted_bridge.grants(capabilities, @plugin_contract.CapWorkspaceRead),
  )
  // 宿主允许 + 清单没声明 → 不给。
  assert_false(
    trusted_bridge.grants(capabilities, @plugin_contract.CapWorkspaceWrite),
  )
}

///|
test "host bridge grants basic capabilities regardless of declaration" {
  let bridge = HostBridge::new()
  // 面板能力：宿主默认允许（面板渲染是插件系统的核心能力面）。
  assert_true(
    bridge.grants([@plugin_contract.CapPanels], @plugin_contract.CapPanels),
  )
}

///|
test "a store can be created under the default quota" {
  let limits = PluginLimits::default()
  let store = limits.make_store()
  assert_true(store is Some(_))
  match store {
    Some(value) => value.close()
    None => fail("expected a store")
  }
}

///|
test "call to an unloaded plugin reports a clear error" {
  let runtime = PluginRuntime::new(plugins_root="_build/test/none")
  match runtime.call("com.example.absent", "{}") {
    Ok(_) => fail("expected an error for an unloaded plugin")
    Err(reason) => assert_true(reason.contains("未加载"))
  }
}

///|
test "unloading an unknown plugin is a no-op" {
  let runtime = PluginRuntime::new(plugins_root="_build/test/none")
  runtime.unload("com.example.absent")
  assert_false(runtime.is_loaded("com.example.absent"))
}

///|
test "invalid wasm bytes are rejected with a reason" {
  match validate_plugin_module(b"not a wasm module at all") {
    Ok(_) => fail("expected parse failure")
    Err(reason) => assert_true(reason.contains("解析失败"))
  }
}

///|
test "describing manifest errors yields a readable reason" {
  let reason = describe_manifest_errors([
    @plugin_contract.BadFormat,
    @plugin_contract.MissingField("entry"),
  ])
  assert_true(reason.contains("格式"))
  assert_true(reason.contains("entry"))
}

///|
/// native 端的 ABI 常量**必须**等于契约层的（唯一真源）。
///
/// native 端的常量是契约层的**引用**（不是副本），故这条断言恒成立——
/// 它锁的是「引用关系」这个事实：若有人把常量改回本地副本且值漂移，
/// 这条断言会失败。
test "the native abi constants come from the contract layer" {
  assert_eq(
    PLUGIN_ABI_REQUEST_OFFSET,
    @plugin_contract.PLUGIN_ABI_REQUEST_OFFSET,
  )
  assert_eq(
    PLUGIN_ABI_RESPONSE_OFFSET,
    @plugin_contract.PLUGIN_ABI_RESPONSE_OFFSET,
  )
  assert_eq(PLUGIN_ABI_CALL_EXPORT, @plugin_contract.PLUGIN_ABI_CALL_EXPORT)
  assert_eq(
    PLUGIN_ABI_DESCRIBE_EXPORT,
    @plugin_contract.PLUGIN_ABI_DESCRIBE_EXPORT,
  )
  assert_eq(
    PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT,
    @plugin_contract.PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT,
  )
  assert_eq(PLUGIN_ABI_LENGTH_EXPORT, @plugin_contract.PLUGIN_ABI_LENGTH_EXPORT)
}
