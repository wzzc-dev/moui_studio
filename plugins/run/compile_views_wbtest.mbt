///|
/// 编译轨纯逻辑的白盒契约（S7d 随视图迁插件）：进度归并（开始/进行中/
/// 完成/未开始 + 同步覆盖语义）与产物路径中间省略的宽度保真。
/// 这些都是无窗口、纯函数判据。

///|
/// 进度归并：步开始 → 进行中；步结束 → 已完成；未出现的步 → 未开始。
test "compile progress merges step start and finish" {
  let progress : Array[@export.CompileProgress] = [
    @export.CompileProgress::{ phase: @export.CompilePrepare, started: true, },
    @export.CompileProgress::{ phase: @export.CompilePrepare, started: false, },
    @export.CompileProgress::{ phase: @export.CompileUpdate, started: true, },
  ]
  assert_true(
    compile_step_state(progress, @export.CompilePrepare) is Some(false),
  )
  assert_true(compile_step_state(progress, @export.CompileUpdate) is Some(true))
  assert_true(compile_step_state(progress, @export.CompileCheck) is None)
  let (done, total) = compile_progress_counts(progress)
  assert_eq(done, 1)
  assert_eq(total, @export.compile_phases().length())
  match compile_active_phase(progress) {
    Some(phase) => assert_eq(phase.tag(), "update")
    None => fail("应能读到最后一条进行中的步")
  }
}

///|
/// 进度归并的覆盖语义：同一步的 finished 必须压过先到的 started。
test "later progress for the same step overrides the earlier one" {
  let progress : Array[@export.CompileProgress] = [
    @export.CompileProgress::{ phase: @export.CompileCheck, started: true, },
    @export.CompileProgress::{ phase: @export.CompileCheck, started: false, },
  ]
  assert_true(compile_step_state(progress, @export.CompileCheck) is Some(false))
  let (done, _) = compile_progress_counts(progress)
  assert_eq(done, 1)
  assert_true(compile_active_phase(progress) is None)
}

///|
/// 全部七步走完后：完成数 = 总数，且没有活跃步。
test "compile progress completes all phases" {
  let progress : Array[@export.CompileProgress] = []
  for phase in @export.compile_phases() {
    progress.push(@export.CompileProgress::{ phase, started: true, })
    progress.push(@export.CompileProgress::{ phase, started: false, })
  }
  let (done, total) = compile_progress_counts(progress)
  assert_eq(done, total)
  assert_true(compile_active_phase(progress) is None)
}

///|
/// 中间省略：短路径原样返回；长路径保头保尾且宽度真的进预算。
test "long artifact paths keep head and tail inside the budget" {
  let short = "/tmp/app.exe"
  assert_eq(middle_ellipsis(short, 400.0), short)
  let long = "/var/folders/66/8ky25j191cj8f7zw_xhq4mrm0000gn/T/moui_studio-compile/studio-app/_build/native/debug/build/native_smoke/native_smoke.exe"
  let budget = 300.0
  let fitted = middle_ellipsis(long, budget)
  assert_true(@chrome.text_estimate_width(fitted) <= budget)
  assert_true(fitted.contains("…"))
  assert_true(fitted.has_prefix("/var/folders"))
  assert_true(fitted.has_suffix("native_smoke.exe"))
  assert_false(fitted.has_suffix("native_smoke/"))
}

///|
/// 中间省略在极窄预算下不崩、不产出超宽串。
test "middle ellipsis stays within budget at extreme widths" {
  let long = "/Users/someone/Documents/projects/demo-app/_build/wasm-gc/debug/build/web_wasm/web_wasm.wasm"
  for budget in [40.0, 80.0, 120.0, 200.0] {
    let fitted = middle_ellipsis(long, budget)
    assert_true(@chrome.text_estimate_width(fitted) <= budget)
    assert_true(fitted.contains("…"))
  }
  let roomy = middle_ellipsis(long, 200.0)
  assert_true(roomy.has_prefix("/Users"))
  assert_true(roomy.has_suffix("b_wasm.wasm"))
  assert_true(roomy.has_suffix("_wasm.wasm"))
  assert_false(roomy.has_suffix("msaw_"))
  assert_eq(middle_ellipsis(long, 2.0), "")
}
