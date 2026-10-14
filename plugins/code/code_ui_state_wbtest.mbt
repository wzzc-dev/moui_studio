///|
/// S5g 代码编辑器 UI 状态切片白盒测试：光标/选区回传、受控滚动、补全弹层
/// 关闭与候选回写。全部零副作用（Effect::none）；触发/应用补全/跳转声明
/// 需读 code_draft/program，仍住壳。
fn apply_code_ui(state : CodeUiState, msg : CodeUiMsg) -> CodeUiState {
  update_code_ui(state, msg).0
}

///|
test "caret moved records caret and selection" {
  let moved = apply_code_ui(
    CodeUiState::new(),
    CaretMoved(12, Some(@core.TextRange::new(start=8, end=12))),
  )
  assert_eq(moved.caret, 12)
  assert_eq(moved.selection, Some(@core.TextRange::new(start=8, end=12)))
  // 空选区显式回 None
  let cleared = apply_code_ui(moved, CaretMoved(3, None))
  assert_eq(cleared.caret, 3)
  assert_eq(cleared.selection, None)
}

///|
test "scrolled records only the y offset" {
  let scrolled = apply_code_ui(CodeUiState::new(), Scrolled(120.0))
  assert_eq(scrolled.scroll.y, 120.0)
  assert_eq(scrolled.scroll.x, 0.0)
}

///|
test "set completions opens the popup" {
  let opened = apply_code_ui(
    CodeUiState::new(),
    SetCompletions(["如果", "循环"]),
  )
  assert_eq(opened.completions, ["如果", "循环"])
  assert_true(opened.completion_open)
  // 关闭弹层只清开关，候选词保留（下一次触发会整体覆盖）。
  let dismissed = apply_code_ui(opened, DismissCompletion)
  assert_false(dismissed.completion_open)
  assert_eq(dismissed.completions.length(), 2)
}

///|
test "apply completion advances caret clears selection and closes popup" {
  let opened = apply_code_ui(CodeUiState::new(), SetCompletions(["循环"]))
  let applied = apply_code_ui(opened, ApplyCompletion(18))
  assert_eq(applied.caret, 18)
  assert_eq(applied.selection, None)
  assert_false(applied.completion_open)
}

///|
test "go to line pins caret clears selection and scrolls" {
  let jumped = apply_code_ui(
    {
      ..CodeUiState::new(),
      selection: Some(@core.TextRange::new(start=1, end=3)),
    },
    GoToLine(40, 80.0),
  )
  assert_eq(jumped.caret, 40)
  assert_eq(jumped.selection, None)
  assert_eq(jumped.scroll.y, 80.0)
  assert_eq(jumped.scroll.x, 0.0)
}

///|
test "all code ui arms return no effect" {
  let messages : Array[CodeUiMsg] = [
    CaretMoved(0, None),
    Scrolled(4.0),
    DismissCompletion,
    SetCompletions(["x"]),
    ApplyCompletion(1),
    GoToLine(1, 0.0),
  ]
  for msg in messages {
    match update_code_ui(CodeUiState::new(), msg).1 {
      @moui.Effect::NoEffect => ()
      _ => abort("代码编辑器纯 UI 臂必须无副作用")
    }
  }
}
