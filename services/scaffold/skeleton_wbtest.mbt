///|
/// 骨架生成面测试：落盘文件集、模块名归一、目录守卫、模板下标映射。
/// 状态机侧（草稿→写盘→完成态）的测试留在 `app/new_project_wbtest.mbt`。

///|
test "skeleton files form a self-contained moonbit module" {
  let root = "/tmp/folder-projects-smoke"
  let files = skeleton_files(root, "my-app", @proposals.sample_hello())
  // 路径前缀与关键文件齐备
  assert_true(files.length() > 10)
  let mut has_mod = false
  let mut has_pkg = false
  let mut has_runner = false
  let mut has_handlers = false
  let mut has_snapshot = false
  let mut has_kernel_runtime = false
  let mut has_native_entry = false
  let mut has_web_entry = false
  for pair in files {
    let (path, content) = pair
    if path == "\{root}/moon.mod" {
      has_mod = true
      assert_true(content.contains("name = \"my-app\""))
      assert_true(content.contains("preferred_target = \"native\""))
    }
    if path == "\{root}/app/moon.pkg" {
      has_pkg = true
      // app 包以本地路径导入内核（自包含，不依赖未发布的 moui_studio）
      assert_true(content.contains("my-app/compiled_runtime"))
      assert_true(!content.contains("wzzc-dev/moui_studio"))
    }
    if path == "\{root}/app/runner.mbt" {
      has_runner = true
      assert_true(content.contains("pub fn program()"))
    }
    if path == "\{root}/app/handlers.mbt" {
      has_handlers = true
      assert_true(content.contains("studio_dispatch_handler"))
    }
    if path == "\{root}/.studio/program.json" {
      has_snapshot = true
      assert_true(content.contains("\"format\""))
    }
    if path == "\{root}/compiled_runtime/runtime.mbt" {
      has_kernel_runtime = true
    }
    // 平台入口包：新建的工程要在 Studio 外跑得起来，组合根自己不开窗口
    if path == "\{root}/native_app/main.mbt" {
      has_native_entry = true
      assert_true(content.contains("@app.program()"))
    }
    if path == "\{root}/web_wasm/main.mbt" {
      has_web_entry = true
      assert_true(content.contains("@exported_app.program()"))
    }
  }
  assert_true(has_mod)
  assert_true(has_pkg)
  assert_true(has_runner)
  assert_true(has_handlers)
  assert_true(has_snapshot)
  assert_true(has_kernel_runtime)
  assert_true(has_native_entry)
  assert_true(has_web_entry)
}

///|
test "folder name folds into a moonbit-friendly module name" {
  assert_eq(module_name_from_root("/tmp/my_app"), "my-app")
  // 纯非 ASCII 目录名给可用兜底名：`"-"` 作模块名会让生成的工程
  // 连 `<name>/compiled_runtime` 这类包路径都解析不了
  assert_eq(module_name_from_root("/tmp/点名册"), "moui-app")
  // 数字开头加前缀（MoonBit 模块名不能以数字开头）
  assert_eq(module_name_from_root("/tmp/2024 名单"), "app-2024")
  assert_eq(module_name_from_root("/tmp/hello"), "hello")
  // 无分隔符的裸名原样归一
  assert_eq(module_name_from_root("demo"), @export.sanitize_name("demo"))
}

///|
/// 递归删测试夹具目录（测试专用的最小 rm -rf；路径是本测试写死的 /tmp 前缀）。
fn rm_rf(path : String) -> Unit {
  let entries = @x/fs.read_dir(path) catch { _ => return }
  for name in entries {
    let child = path + "/" + name
    let child_is_dir = @x/fs.is_dir(child) catch { _ => false }
    if child_is_dir {
      rm_rf(child)
    } else {
      let _ = @x/fs.remove_file(child) catch { _ => () }
    }
  }
  let _ = @x/fs.remove_dir(path) catch { _ => () }
}

///|
test "dir guard rejects existing modules and missing dirs" {
  // 不存在的目录拒绝
  match dir_is_writable("/tmp/folder-projects-definitely-missing") {
    Err(_) => ()
    Ok(_) => fail("缺失目录应拒绝")
  }
  // 已有 moon.mod 的目录拒绝（防覆盖用户工程）
  let existing = "/tmp/folder-projects-guard-fixture"
  rm_rf(existing)
  @x/fs.create_dir(existing)
  let _ = @x/fs.write_string_to_file(
    "\{existing}/moon.mod",
    "name = \"taken\"\n",
  ) catch {
    _ => ()
  }
  match dir_is_writable(existing) {
    Err(message) => assert_true(message.contains("moon.mod"))
    Ok(_) => fail("已有模块的目录应拒绝")
  }
  // 空目录放行
  let empty = "/tmp/folder-projects-guard-empty"
  rm_rf(empty)
  @x/fs.create_dir(empty)
  assert_true(dir_is_writable(empty) is Ok(_))
  rm_rf(existing)
  rm_rf(empty)
}

///|
test "template index maps to built-in samples or blank" {
  assert_eq(template_program(-1).controls.length(), 0)
  let samples = @proposals.all_samples()
  assert_eq(template_program(0).window.title, samples[0].window.title)
  assert_eq(template_program(2).window.title, samples[2].window.title)
  // 越界回退空白
  assert_eq(template_program(99).controls.length(), 0)
}
