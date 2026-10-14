///|
/// 一个最小但完整的合法 `.studio.json`（ASCII，便于测试里逐字符抽取内嵌 JSON）。
const SAMPLE_PROJECT : String = "{\"format\":\"moui.studio.project\",\"version\":1,\"window\":{\"title\":\"demo\",\"width\":640,\"height\":480},\"controls\":[{\"id\":1,\"kind\":\"button\",\"name\":\"btn\",\"text\":\"go\",\"x\":20,\"y\":20,\"width\":100,\"height\":32,\"items\":[]},{\"id\":2,\"kind\":\"label\",\"name\":\"lbl\",\"text\":\"\",\"x\":20,\"y\":80,\"width\":200,\"height\":32,\"items\":[]}],\"variables\":[],\"handlers\":[{\"control\":\"btn\",\"event\":\"on_click\",\"note\":{\"zh\":\"\",\"en\":\"\"},\"body\":[{\"op\":\"call\",\"name\":\"set_text\",\"args\":[{\"t\":\"var\",\"v\":\"lbl\"},{\"t\":\"str\",\"v\":\"hi\"}]}]}]}"

///|
test "导出的包包含全部必需文件" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let paths = files.map(fn(pair) { pair.0 })
  assert_true(paths.any(fn(path) { path.has_suffix("/moon.mod") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/app/moon.pkg") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/app/project_data.mbt") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/app/runner.mbt") }))
  assert_true(
    paths.any(fn(path) { path.has_suffix("/app/generated_handlers.mbt") }),
  )
  assert_true(
    paths.any(fn(path) { path.has_suffix("/compiled_runtime/moon.pkg") }),
  )
  assert_true(paths.any(fn(path) { path.has_suffix("/domain/ir/moon.pkg") }))
  assert_true(
    paths.any(fn(path) { path.has_suffix("/domain/studio_lang/moon.pkg") }),
  )
  assert_true(paths.any(fn(path) { path.has_suffix("/domain/codec/moon.pkg") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/web_wasm/moon.pkg") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/web_wasm/main.mbt") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/web_wasm/index.html") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/README.md") }))
  assert_true(paths.any(fn(path) { path.has_suffix("/deps.txt") }))
}

///|
test "模块名安全化" {
  assert_eq(@export.sanitize_name("My App"), "My-App")
  // 退化输入给可用兜底名：中文名整体折叠会成 "-"，而 "-" 作模块名会让
  // 生成的工程连包路径都解析不了
  assert_eq(@export.sanitize_name("点名册 小工具"), "moui-app")
  assert_eq(@export.sanitize_name(""), "moui-app")
  // 数字开头非法：加前缀而不是原样交给 moon.mod
  assert_eq(@export.sanitize_name("3D viewer"), "app-3D-viewer")
  // 首尾分隔符不进结果
  assert_eq(@export.sanitize_name("  hello__  "), "hello")
}

///|
/// 导出 moon.mod 的版本**从 Studio 自己的 moon.mod 派生**：唯一事实源是
/// `bundle_dependency_versions()`（`tools/sync_versions` 生成），漂开由
/// `moon run moui_studio/tools/sync_versions --target native -- --check` 挡。
///
/// 为什么改这条断言：旧版钉的是 export.mbt 里一组**硬编码字面量**，于是
/// Studio bump 到 0.2.3 之后生成工程仍 pin 0.2.0，测试照样绿——它守的是
/// 「常量等于自己」而不是「与 Studio 同源」，正是它注释里声称要防的事故。
/// 回归意义不变：bundle 的代码全部从 Studio workspace 拷出、只有依赖去注册表
/// 拉，版本一错开就是「Studio 编得过、导出项目编不过」（实测旧线 `moui@0.1.12`
/// 的源码在新工具链下过不了类型检查，整条 native GUI 构建失败）。
test "moon.mod 版本从 Studio moon.mod 派生（导出可构建的前提）" {
  let table = @export.bundle_dependency_versions()
  // 表必须覆盖 IDE 与产物共同依赖的六项（缺项 = 生成器白名单漏了）
  assert_true(table.length() >= 6)
  let mut expected_imports = ""
  for pair in table {
    let (path, version) = pair
    // 旧线不得回归：0.1.x 自己的源码在新工具链下过不了检查
    assert_false(version.has_prefix("0.1."))
    expected_imports = expected_imports + "  \"\{path}@\{version}\",\n"
  }
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let manifest = bundle_file(files, "/moon.mod")
  assert_true(manifest.contains(expected_imports))
  // deps.txt 与 moon.mod 同一组事实：逐行都必须命中表，不能一处新一处旧
  let deps = bundle_file(files, "/deps.txt")
  for view in deps.split("\n") {
    let line = view.trim(chars=" \t\r").to_owned()
    if line == "" {
      continue
    }
    let mut matched = false
    for pair in table {
      let (path, version) = pair
      if line == "\{path}@\{version}" {
        matched = true
      }
    }
    assert_true(matched)
  }
  assert_true(deps.contains("wzzc-dev/moui_web_renderer@"))
  assert_true(deps.contains("wzzc-dev/moui_skia_renderer@"))
}

///|
/// 导出 bundle 必须带 **native GUI 入口**（`native_app/`）。
///
/// 回归意义：旧 bundle 只有 `native_smoke`（无头存活探针：打印标记就退出），
/// 编译轨把它当 native 产物交出去，用户运行后**看不到任何窗口**。GUI 入口
/// 是「编译出来的东西能当应用跑」的唯一凭据。
test "bundle ships a native GUI entrypoint, not just a headless probe" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let pkg = bundle_file(files, "/native_app/moon.pkg")
  let main = bundle_file(files, "/native_app/main.mbt")
  // GUI 组合根必须接真实窗口后端 + 渲染器 + 运行时
  assert_true(pkg.contains("wzzc-dev/moui/backend/macos"))
  assert_true(pkg.contains("wzzc-dev/moui_skia_renderer"))
  assert_true(pkg.contains("wzzc-dev/moui/runtime"))
  assert_true(pkg.contains("pkgtype(kind: \"executable\")"))
  // main 用 run_app 开窗（不是打印标记退出）
  assert_true(main.contains("@runtime.run_app"))
  assert_true(main.contains("@macos.entry()"))
  assert_true(main.contains("@render_skia.from_env"))
  assert_false(main.contains("@sys.exit"))
  // 标题与尺寸取自项目，而不是写死
  assert_true(main.contains("@app.window_title()"))
  assert_true(main.contains("@app.window_size()"))
  // 无头探针仍在（它是启动自检的证据），但它是**另一个**包
  assert_true(
    bundle_file(files, "/native_smoke/main.mbt").contains("@sys.exit"),
  )
}

///|
test "README 含构建命令，project_data 内嵌可解析回原 JSON" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let readme = bundle_file(files, "/README.md")
  assert_true(readme.contains("moon build"))
  assert_true(readme.contains("--target wasm-gc"))
  // project_data.mbt 的 #| 字面量逐字节嵌入紧凑 JSON，且可被 json.parse 还原
  let data = bundle_file(files, "/app/project_data.mbt")
  let compact = parse_or_fail(SAMPLE_PROJECT).stringify()
  assert_true(data.contains(compact))
  let reparsed = parse_or_fail(compact)
  assert_eq(reparsed.stringify(), compact)
  // #| 原样输出：反斜杠/引号不被转义（紧凑 JSON 里没有转义换行序列）
  assert_false(data.contains("\\n"))
  assert_true(data.contains("#|"))
}

///|
test "转义覆盖换行与控制字符" {
  let messy = "a\"b\\c\nd\te\rf"
  let escaped = @export.escape_mbt(messy)
  assert_true(escaped.contains("\\n"))
  assert_true(escaped.contains("\\t"))
  assert_true(escaped.contains("\\r"))
}

///|
test "导出包含 Web 宿主页且引用相对 wasm 路径" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let html = bundle_file(files, "/web_wasm/index.html")
  assert_true(html.length() > 0)
  assert_true(html.contains("canvas-host"))
  assert_true(html.contains("<!doctype html>"))
  assert_true(
    html.contains("../.mooncakes/wzzc-dev/moui_web_renderer/runtime.js"),
  )
  assert_false(html.contains("importModule"))
}

///|
test "导出可执行包含 ABI 垫片（Moon 只导出可执行包自身定义的函数）" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let abi = bundle_file(files, "/web_wasm/abi.mbt")
  let pkg = bundle_file(files, "/web_wasm/moon.pkg")
  for
    name in [
      "web_dispatch_event", "web_dispatch_pointer_input", "web_dispatch_semantics_action",
      "web_dispatch_route", "web_complete_async_clipboard_read", "web_complete_async_file_dialog",
    ] {
    assert_true(pkg.contains("\"" + name + "\""))
    assert_true(abi.contains("pub fn " + name + "("))
    assert_true(abi.contains("@web." + name + "("))
  }
}

///|
test "导出应用是可执行的（含领域内核 + runner 驱动）" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  // 领域内核 11 个 .mbt（ir 3 + studio_lang 8）+ 编译轨运行时 + runner + project_data
  for
    rel in [
      "domain/ir/ir.mbt", "domain/ir/invariants.mbt", "domain/ir/signature.mbt",
      "domain/studio_lang/aliases.mbt", "domain/studio_lang/errors.mbt", "domain/studio_lang/keywords.mbt",
      "domain/studio_lang/lexer.mbt", "domain/studio_lang/parser.mbt", "domain/studio_lang/printer.mbt",
      "domain/studio_lang/interp.mbt", "domain/studio_lang/semantics.mbt", "domain/codec/codec.mbt",
      "compiled_runtime/runtime.mbt",
    ] {
    let source = bundle_file(files, "/\{rel}")
    assert_true(source.length() > 100)
  }
  let runner = bundle_file(files, "/app/runner.mbt")
  let pkg = bundle_file(files, "/app/moon.pkg")
  let generated = bundle_file(files, "/app/generated_handlers.mbt")
  // runner 走编译轨：分派到生成源码 + compiled_runtime 执行面，
  // 不再有指令流解释器入口。
  assert_true(runner.contains("decode_program("))
  assert_true(runner.contains("studio_dispatch_handler("))
  assert_true(runner.contains("@compiled_runtime.run_handler("))
  assert_true(runner.contains("@compiled_runtime.answer_gate("))
  assert_true(runner.contains("runtime_for_program("))
  assert_false(runner.contains("start_run_stmts("))
  assert_false(runner.contains("run_to_end("))
  // 生成源码是本 bundle 真正编译的一份源码（预览同源）
  assert_true(generated.contains("studio_dispatch_handler"))
  assert_true(generated.contains("@compiled_runtime.Handler("))
  assert_false(generated.contains("start_run_stmts"))
  // TEA 组合根与依赖导入
  assert_true(runner.contains("pub fn program("))
  assert_true(pkg.contains("domain/ir"))
  assert_true(pkg.contains("domain/codec"))
  assert_true(pkg.contains("compiled_runtime"))
  assert_true(pkg.contains("wzzc-dev/moui/views"))
}

///|
/// 属性 v2 P3（G7.2）：导出的 runner 必须消费 `control.props`——与 Studio
/// 的 form_widget 同口径（字号/颜色/对齐/可见/禁用）。
///
/// 回归意义：P3 的「导出应用渲染一致（kernel 同步再生）」此前只落了
/// Studio 侧 form_widget；runner 模板没消费 props，导出应用里调好字号/颜色
/// 的控件会静默回退默认外观。本测试钉住 runner 模板的消费点（同步内核
/// 逐字节携带），真正编译验证由 emit_bundle 冒烟 + `moon check` 承担。
test "导出的 runner 消费控件属性 v2（字号/颜色/可见/禁用）" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let runner = bundle_file(files, "/app/runner.mbt")
  assert_true(runner.contains("control.props.visible"))
  assert_true(runner.contains("runner_prop_theme("))
  assert_true(runner.contains("runner_prop_color("))
  assert_true(runner.contains("runner_prop_align("))
  assert_true(runner.contains("with_typography"))
  assert_true(runner.contains("runner_finish_prop_view("))
  // 禁用 Button 不得挂 on_click（与 Studio form_widget 同纪律）
  assert_true(runner.contains("props.disabled"))
  // TextField 占位符透传
  assert_true(runner.contains("placeholder=props.placeholder"))
}

///|
/// 按路径后缀取 bundle 文件内容（避免依赖 files 数组顺序）。
fn bundle_file(files : Array[(String, String)], suffix : String) -> String {
  let matches = files.filter(fn(pair) { pair.0.has_suffix(suffix) })
  if matches.is_empty() {
    ""
  } else {
    matches[0].1
  }
}

///|
fn parse_or_fail(source : String) -> Json raise {
  @json.parse(source) catch {
    _ => fail("fixture JSON 应可解析")
  }
}

///|
/// 导出应用的 runner 必须**视口自适应**，不得写死大于项目窗口的尺寸。
///
/// 回归意义（用户现象：「运行的产物 UI 窗口显示不全」）：旧 runner 把整棵树
/// 塞进一张写死 **960×600** 的卡片，而窗口只有项目声明的 640×480——实测内容
/// 包围盒 1090×634，右溢出 450pt、下溢出 154pt（名单右半边、审计标题都在
/// 窗口外）。修法是三件事，本用例逐条钉住：
///
/// 1. 组合根用 `new_with_environment` 拿真实视口（用 `new` 只能猜尺寸）；
/// 2. 视图走 `view_with_viewport`，根节点按视口定尺；
/// 3. 舞台在 `StageLayout` 里等比缩放（`fit_scale` + `child_frames_tight`），
///    所以窗口比设计小也不裁内容。
///
/// 只要有人把硬编码尺寸改回来，这几条断言立刻失败。
test "导出的 runner 视口自适应，不写死大尺寸" {
  let files = @export.export_bundle(SAMPLE_PROJECT, "demo")
  let runner = bundle_file(files, "/app/runner.mbt")
  // 1) 组合根拿真实视口
  assert_true(runner.contains("@moui.Program::new_with_environment"))
  assert_true(runner.contains("env.viewport_size()"))
  // 2) 视口入口存在且被 view 委托
  assert_true(runner.contains("pub fn view_with_viewport"))
  assert_true(runner.contains("pub fn default_viewport_size"))
  // 3) 舞台等比缩放
  assert_true(runner.contains("pub fn fit_scale"))
  assert_true(runner.contains("child_frames_tight=true"))
  // 不得残留「比项目窗口大」的写死尺寸（960/600/920/560 都是旧卡的尺寸）
  assert_false(runner.contains("width=960.0"))
  assert_false(runner.contains("height=600.0"))
  assert_false(runner.contains("width=920.0"))
  assert_false(runner.contains("height=560.0"))
}
