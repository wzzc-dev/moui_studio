///|
/// 新建工程（folder projects）测试：骨架文件集、模块名归一、目录守卫、
/// 应用骨架布局探测、form 支撑面与 render_form 属性集同步。

///|
test "skeleton files form a self-contained moonbit module" {
  let root = "/tmp/folder-projects-smoke"
  let files = new_project_skeleton_files(
    root,
    "my-app",
    @proposals.sample_hello(),
  )
  // 路径前缀与关键文件齐备
  assert_true(files.length() > 10)
  let mut has_mod = false
  let mut has_pkg = false
  let mut has_runner = false
  let mut has_handlers = false
  let mut has_snapshot = false
  let mut has_kernel_runtime = false
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
  }
  assert_true(has_mod)
  assert_true(has_pkg)
  assert_true(has_runner)
  assert_true(has_handlers)
  assert_true(has_snapshot)
  assert_true(has_kernel_runtime)
}

///|
test "folder name folds into a moonbit-friendly module name" {
  assert_eq(new_project_module_name("/tmp/my_app"), "my-app")
  // 非字母数字全折叠为连字符（每个字符一个 -，重复折叠为单 -）
  assert_eq(new_project_module_name("/tmp/点名册"), "-")
  assert_eq(new_project_module_name("/tmp/hello"), "hello")
  // 无分隔符的裸名原样归一
  assert_eq(new_project_module_name("demo"), @export.sanitize_name("demo"))
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

///|
/// 快照恢复：激活工程读回 `<root>/.studio/program.json` → 有快照且无未保存
/// 工作时载入（load_program_state），程序基线对齐、program_root 记账。
test "program snapshot restores the stored program" {
  let model = initial_model()
  let json = @codec.encode_program(@proposals.sample_drill())
  let restored = update_with_services(
      model,
      ProjectProgramLoaded(Success(json)),
      @services.AppServices::new(),
    ).0
  assert_eq(
    @ir.program_signature(restored.program),
    @ir.program_signature(@proposals.sample_drill()),
  )
  // 基线对齐：恢复不产生脏标记
  assert_false(program_has_work(restored))
  // 坏快照：结构化报错，不载入
  let broken = update_with_services(
      model,
      ProjectProgramLoaded(Success("不是 IR")),
      @services.AppServices::new(),
    ).0
  assert_true(broken.notice.contains("快照"))
}
