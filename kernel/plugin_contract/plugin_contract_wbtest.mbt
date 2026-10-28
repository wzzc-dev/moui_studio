///|
/// 插件契约测试：清单往返、门卫、视图协议往返、贡献描述。
/// 纪律照 `domain/codec/codec_test.mbt`：往返保真 + 错误分类 + 稳定编码。

///|
fn sample_manifest() -> PluginManifest {
  {
    id: "com.example.hello",
    name: "Hello Plugin",
    version: "1.0.0",
    description: "示例插件",
    entry: "hello.wasm",
    capabilities: [CapCommands, CapPanels, CapWorkspaceRead],
    min_api_version: 1,
    abi: AbiCore,
  }
}

///|
fn sample_spec() -> PluginViewSpec {
  {
    node: Column([
      {
        node: Text("你好"),
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
      {
        node: Button(label="点我", action="on_click"),
        key: "btn",
        width: Some(120.0),
        height: Some(30.0),
        padding: None,
        spacing: None,
        background: Some("#112233"),
        foreground: Some("#AABBCC"),
        font_size: Some(14.0),
        weight: None,
      },
    ]),
    key: "root",
    width: Some(320.0),
    height: None,
    padding: Some(8.0),
    spacing: Some(4.0),
    background: None,
    foreground: None,
    font_size: None,
    weight: None,
  }
}

///|
test "manifest round-trips through JSON" {
  let manifest = sample_manifest()
  let encoded = encode_manifest(manifest)
  let decoded = match decode_manifest(encoded) {
    Ok(value) => value
    Err(errors) => fail("decode failed: \{debug_inspect(errors)}")
  }
  assert_eq(decoded.id, manifest.id)
  assert_eq(decoded.name, manifest.name)
  assert_eq(decoded.version, manifest.version)
  assert_eq(decoded.description, manifest.description)
  assert_eq(decoded.entry, manifest.entry)
  assert_eq(decoded.capabilities.length(), manifest.capabilities.length())
  assert_eq(decoded.capabilities, manifest.capabilities)
  assert_eq(decoded.min_api_version, manifest.min_api_version)
}

///|
test "manifest encoding is stable across repeated calls" {
  let manifest = sample_manifest()
  assert_eq(encode_manifest(manifest), encode_manifest(manifest))
}

///|
test "manifest rejects a wrong format tag" {
  let source = "{\"format\":\"something.else\",\"version\":1}"
  match decode_manifest(source) {
    Ok(_) => fail("expected BadFormat")
    Err(errors) => assert_eq(errors, [BadFormat])
  }
}

///|
test "manifest rejects an unsupported version" {
  let source = "{\"format\":\"moui.studio.plugin\",\"format_version\":99}"
  match decode_manifest(source) {
    Ok(_) => fail("expected UnsupportedVersion")
    Err(errors) => assert_eq(errors, [UnsupportedVersion(99)])
  }
}

///|
test "manifest reports every missing field at once" {
  let source = "{\"format\":\"moui.studio.plugin\",\"format_version\":1}"
  match decode_manifest(source) {
    Ok(_) => fail("expected missing field errors")
    Err(errors) => {
      // 缺 id/name/version/entry/capabilities/min_api_version → 6 条
      assert_eq(errors.length(), 6)
      assert_true(errors.contains(MissingField("id")))
      assert_true(errors.contains(MissingField("entry")))
      assert_true(errors.contains(MissingField("capabilities")))
    }
  }
}

///|
test "manifest rejects an unknown capability token" {
  let source = "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"a\",\"name\":\"A\",\"version\":\"1\",\"entry\":\"a.wasm\",\"capabilities\":[\"CapNope\"],\"min_api_version\":1}"
  match decode_manifest(source) {
    Ok(_) => fail("expected BadCapability")
    Err(errors) => assert_eq(errors, [BadCapability("CapNope")])
  }
}

///|
test "manifest rejects an invalid plugin id" {
  let source = "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"bad id!\",\"name\":\"A\",\"version\":\"1\",\"entry\":\"a.wasm\",\"capabilities\":[],\"min_api_version\":1}"
  match decode_manifest(source) {
    Ok(_) => fail("expected BadPluginId")
    Err(errors) => assert_eq(errors, [BadPluginId("bad id!")])
  }
}

///|
test "manifest rejects an escaping entry path" {
  let source = "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"a\",\"name\":\"A\",\"version\":\"1\",\"entry\":\"../evil.wasm\",\"capabilities\":[],\"min_api_version\":1}"
  match decode_manifest(source) {
    Ok(_) => fail("expected BadEntry")
    Err(errors) => assert_eq(errors, [BadEntry("../evil.wasm")])
  }
}

///|
test "manifest rejects an absolute entry path" {
  let source = "{\"format\":\"moui.studio.plugin\",\"format_version\":1,\"id\":\"a\",\"name\":\"A\",\"version\":\"1\",\"entry\":\"/etc/passwd\",\"capabilities\":[],\"min_api_version\":1}"
  match decode_manifest(source) {
    Ok(_) => fail("expected BadEntry")
    Err(errors) => assert_eq(errors, [BadEntry("/etc/passwd")])
  }
}

///|
test "api version gate rejects a plugin that needs a newer host" {
  assert_true(is_api_compatible(1))
  assert_true(is_api_compatible(0))
  assert_false(is_api_compatible(PLUGIN_API_VERSION + 1))
}

///|
test "view spec round-trips through JSON" {
  let spec = sample_spec()
  let decoded = match decode_view(encode_view(spec)) {
    Ok(value) => value
    Err(errors) => fail("decode failed: \{debug_inspect(errors)}")
  }
  assert_eq(decoded.key, spec.key)
  assert_eq(decoded.width, spec.width)
  assert_eq(decoded.height, spec.height)
  assert_eq(decoded.padding, spec.padding)
  assert_eq(decoded.spacing, spec.spacing)
  match decoded.node {
    Column(children) => {
      assert_eq(children.length(), 2)
      match children[0].node {
        Text(text) => assert_eq(text, "你好")
        _ => fail("expected Text child")
      }
      match children[1].node {
        Button(label~, action~) => {
          assert_eq(label, "点我")
          assert_eq(action, "on_click")
        }
        _ => fail("expected Button child")
      }
      assert_eq(children[1].background, Some("#112233"))
      assert_eq(children[1].foreground, Some("#AABBCC"))
    }
    _ => fail("expected Column root")
  }
}

///|
test "view rejects an unknown node type" {
  let source = "{\"format\":\"moui.studio.plugin.view\",\"format_version\":1,\"key\":\"k\",\"node\":\"Teleport\"}"
  match decode_view(source) {
    Ok(_) => fail("expected UnknownNode")
    Err(errors) => assert_eq(errors, [UnknownNode("Teleport")])
  }
}

///|
test "view rejects an invalid color" {
  let source = "{\"format\":\"moui.studio.plugin.view\",\"format_version\":1,\"key\":\"k\",\"node\":\"Text\",\"text\":\"x\",\"background\":\"not-a-color\"}"
  match decode_view(source) {
    Ok(_) => fail("expected BadColor")
    Err(errors) => assert_eq(errors, [BadColor("not-a-color")])
  }
}

///|
test "view rejects a wrong format tag" {
  let source = "{\"format\":\"nope\",\"version\":1,\"node\":\"Spacer\"}"
  match decode_view(source) {
    Ok(_) => fail("expected BadFormat")
    Err(errors) => assert_eq(errors, [BadFormat])
  }
}

///|
test "view rejects an unsupported version" {
  let source = "{\"format\":\"moui.studio.plugin.view\",\"format_version\":42,\"node\":\"Spacer\"}"
  match decode_view(source) {
    Ok(_) => fail("expected UnsupportedVersion")
    Err(errors) => assert_eq(errors, [UnsupportedVersion(42)])
  }
}

///|
test "color validator accepts the documented shapes" {
  assert_true(is_valid_plugin_color("#000000"))
  assert_true(is_valid_plugin_color("#FFFFFF"))
  assert_true(is_valid_plugin_color("#12345678"))
  assert_false(is_valid_plugin_color("#12345"))
  assert_false(is_valid_plugin_color("000000"))
  assert_false(is_valid_plugin_color("#GGGGGG"))
}

///|
test "contributions round-trip through JSON" {
  let contrib : PluginContributions = {
    panels: [("main", "主面板")],
    commands: [("do", "执行")],
  }
  let decoded = match decode_contributions(encode_contributions(contrib)) {
    Ok(value) => value
    Err(errors) => fail("decode failed: \{debug_inspect(errors)}")
  }
  assert_eq(decoded.panels.length(), 1)
  assert_eq(decoded.panels[0], ("main", "主面板"))
  assert_eq(decoded.commands[0], ("do", "执行"))
}

///|
test "contributions tolerate a missing panel section" {
  let source = "{\"format\":\"moui.studio.plugin.contrib\",\"format_version\":1,\"commands\":{\"do\":\"执行\"}}"
  let decoded = match decode_contributions(source) {
    Ok(value) => value
    Err(errors) => fail("decode failed: \{debug_inspect(errors)}")
  }
  assert_eq(decoded.panels.length(), 0)
  assert_eq(decoded.commands.length(), 1)
}

///|
test "contributions reject a non-string entry" {
  let source = "{\"format\":\"moui.studio.plugin.contrib\",\"format_version\":1,\"panels\":{\"main\":123}}"
  match decode_contributions(source) {
    Ok(_) => fail("expected BadEntry")
    Err(errors) => assert_eq(errors, [BadEntry("main")])
  }
}

///|
test "descriptor reports active state only when loaded" {
  let manifest = sample_manifest()
  let loaded : PluginDescriptor = { manifest, status: Loaded, }
  let failed : PluginDescriptor = { manifest, status: Failed("boom"), }
  assert_true(loaded.is_active())
  assert_false(failed.is_active())
}

///|
/// ABI 描述：契约层是**唯一真源**——native 与 web 都读它。
///
/// 这个测试锁住描述的**内容**（不是「有没有」）：改了常量而忘了改
/// 描述，web 侧就会用旧值 → 「web 能加载、native 报 ABI 不兼容」。
test "the abi descriptor carries the canonical constants" {
  let descriptor = plugin_abi_descriptor()
  let payload = @json.parse(descriptor) catch {
    _ => fail("描述不是合法 JSON")
  }
  let fields = match payload {
    Object(value) => value
    _ => fail("描述不是 JSON 对象")
  }
  let request_offset = match fields.get("request_offset") {
    Some(Number(n, ..)) => n.to_int()
    _ => fail("描述缺 request_offset")
  }
  let response_offset = match fields.get("response_offset") {
    Some(Number(n, ..)) => n.to_int()
    _ => fail("描述缺 response_offset")
  }
  let call_export = match fields.get("call_export") {
    Some(String(value)) => value
    _ => fail("描述缺 call_export")
  }
  let describe_export = match fields.get("describe_export") {
    Some(String(value)) => value
    _ => fail("描述缺 describe_export")
  }
  let set_response_ptr_export = match fields.get("set_response_ptr_export") {
    Some(String(value)) => value
    _ => fail("描述缺 set_response_ptr_export")
  }
  let length_export = match fields.get("length_export") {
    Some(String(value)) => value
    _ => fail("描述缺 length_export")
  }
  assert_eq(request_offset, PLUGIN_ABI_REQUEST_OFFSET)
  assert_eq(response_offset, PLUGIN_ABI_RESPONSE_OFFSET)
  assert_eq(call_export, PLUGIN_ABI_CALL_EXPORT)
  assert_eq(describe_export, PLUGIN_ABI_DESCRIBE_EXPORT)
  assert_eq(set_response_ptr_export, PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT)
  assert_eq(length_export, PLUGIN_ABI_LENGTH_EXPORT)
}

///|
/// ABI 常量的**取值**是契约的一部分（插件按它写），故钉死。
///
/// 改了这些值 = 破坏 ABI → 老插件全部失效。故此处是「刻意的硬编码」。
test "the abi constants keep their contract values" {
  assert_eq(PLUGIN_ABI_REQUEST_OFFSET, 1024)
  assert_eq(PLUGIN_ABI_RESPONSE_OFFSET, 0)
  assert_eq(PLUGIN_ABI_CALL_EXPORT, "studio_call")
  assert_eq(PLUGIN_ABI_DESCRIBE_EXPORT, "studio_describe")
  assert_eq(PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT, "studio_set_response_ptr")
  assert_eq(PLUGIN_ABI_LENGTH_EXPORT, "studio_last_result_len")
}
