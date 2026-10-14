///|
/// 运行域 UI 状态切片白盒测试（S5i）：编译输出面板开关、预览 Frame/Web
/// 档位切换。全部零副作用；预览导航/构建回执等服务编排住壳。
fn apply_run_ui(state : RunUiState, msg : RunUiMsg) -> RunUiState {
  update_run_ui(state, msg).0
}

///|
test "toggle compile output flips the open flag" {
  let state = RunUiState::new()
  assert_false(state.compile_output_open)
  let opened = apply_run_ui(state, ToggleCompileOutput)
  assert_true(opened.compile_output_open)
  let closed = apply_run_ui(
    apply_run_ui(opened, ToggleCompileOutput),
    ToggleCompileOutput,
  )
  // 连续三次翻转：false → true → false → true
  assert_true(closed.compile_output_open)
}

///|
test "set preview mode selects web or frame" {
  let state = RunUiState::new()
  assert_false(state.web_preview)
  let web = apply_run_ui(state, SetPreviewMode(true))
  assert_true(web.web_preview)
  let frame = apply_run_ui(web, SetPreviewMode(false))
  assert_false(frame.web_preview)
}

///|
test "all run ui arms return no effect" {
  let messages : Array[RunUiMsg] = [
    ToggleCompileOutput,
    SetPreviewMode(true),
    SetPreviewMode(false),
  ]
  for msg in messages {
    match update_run_ui(RunUiState::new(), msg).1 {
      @moui.Effect::NoEffect => ()
      _ => abort("运行域纯 UI 臂必须无副作用")
    }
  }
}
