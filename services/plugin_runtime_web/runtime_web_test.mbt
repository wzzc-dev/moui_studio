///|
/// Web 插件后端测试（wasm-gc）。
///
/// web 后端与 native 后端**共用契约**——这些测试锁住这一点：同一份
/// 贡献描述在两端解码出同样的结构。
///
/// **只测契约面，不调 extern**：web 后端的宿主能力经
/// `extern "wasm"` import 获得，测试运行时没有浏览器 JS 胶水提供这些
/// import（实例化会失败——这是设计使然，不是缺陷）。真实浏览器里的
/// 加载由 `web_wasm/plugin_bridge.js` 承担。

///|
/// 贡献描述错误列表 → 一句话原因。
fn describe_contrib_errors(
  errors : Array[@plugin_contract.PluginContribError],
) -> String {
  let parts : Array[String] = []
  for error in errors {
    parts.push(error.message())
  }
  parts.join("；")
}

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
test "the web backend decodes contributions with the shared contract" {
  // 用契约层的编码器造一份贡献描述——与 native 后端完全同源。
  let contributions : @plugin_contract.PluginContributions = {
    panels: [("main", "主面板")],
    commands: [("do", "执行")],
  }
  let encoded = @plugin_contract.encode_contributions(contributions)
  let decoded = match @plugin_contract.decode_contributions(encoded) {
    Ok(value) => value
    Err(errors) =>
      fail("贡献描述解码失败：\{describe_contrib_errors(errors)}")
  }
  assert_eq(decoded.panels.length(), 1)
  assert_eq(decoded.panels[0].0, "main")
  assert_eq(decoded.commands.length(), 1)
  assert_eq(decoded.commands[0].0, "do")
}

///|
test "the web backend rejects a malformed contributions document" {
  let source = "{\"format\":\"moui.studio.plugin.contrib\",\"format_version\":1,\"panels\":{\"main\":42}}"
  match @plugin_contract.decode_contributions(source) {
    Ok(_) => fail("应当拒绝非字符串贡献项")
    Err(errors) => assert_eq(errors.length(), 1)
  }
}

///|
test "the web view protocol shares the contract with the native backend" {
  // 同一份视图协议 JSON 在两端解释出同样的结构——证明协议共用。
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
  let decoded = match @plugin_contract.decode_view(spec) {
    Ok(value) => value
    Err(errors) =>
      fail("视图协议解码失败：\{describe_view_errors(errors)}")
  }
  assert_eq(decoded.key, "root")
  assert_eq(decoded.width, Some(200.0))
  match decoded.node {
    @plugin_contract.Column(children) => assert_eq(children.length(), 1)
    _ => fail("期望 Column 根节点")
  }
}

///|
test "the web backend keeps the C ABI string convention" {
  // web 端与 native 端共用**同一个插件 ABI**（标准 C 风格：UTF-8 字节 +
  // 显式长度）。这条测试锁住「两端的协议标识一致」——插件作者写一份
  // 插件，两端都能加载。
  //
  // 请求格式由 app 侧构造（`plugin_action_request` / `plugin_view_request`），
  // 插件按 `format` 字段区分请求种类。
  let action = @plugin_contract.plugin_action_request(
    "com.example.a", "increment", "",
  )
  assert_true(action.contains("moui.studio.plugin.action"))
  assert_true(action.contains("increment"))
  let view = @plugin_contract.plugin_view_request("com.example.a", "main", "")
  assert_true(view.contains("moui.studio.plugin.viewreq"))
  assert_true(view.contains("main"))
}

///|
test "the web backend parses the plugin failure list" {
  // 失败插件必须能从 JS 侧回到宿主——否则设置面板会说「没有已加载的
  // WASM 插件」，用户以为插件没装（而不是「插件坏了」）。
  let parsed = @plugin_runtime_web.parse_plugin_failures(
    "{\"com.example.a\":\"链接失败\",\"com.example.b\":\"编译错误\"}",
  )
  assert_eq(parsed.length(), 2)
  assert_eq(parsed[0].0, "com.example.a")
  assert_eq(parsed[0].1, "链接失败")
  assert_eq(parsed[1].0, "com.example.b")
  assert_eq(parsed[1].1, "编译错误")
}

///|
test "the web failure list keeps the whole reason when it contains separators" {
  // 真实原因里含 `=`、`,`、`;`、空格（wasm 的 CompileError 文本）。
  // 用 JSON 编码才不会把一条失败切成两条。
  let parsed = @plugin_runtime_web.parse_plugin_failures(
    "{\"com.example.a\":\"CompileError: expected version 01 00 00 00, found 0d 00; bad\"}",
  )
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].0, "com.example.a")
  assert_eq(
    parsed[0].1,
    "CompileError: expected version 01 00 00 00, found 0d 00; bad",
  )
}

///|
test "the web failure list ignores empty and malformed input" {
  assert_eq(@plugin_runtime_web.parse_plugin_failures("").length(), 0)
  assert_eq(@plugin_runtime_web.parse_plugin_failures("{}").length(), 0)
  assert_eq(@plugin_runtime_web.parse_plugin_failures("not json").length(), 0)
  assert_eq(@plugin_runtime_web.parse_plugin_failures("{\"a\":1}").length(), 1)
}
