///|
/// 词法/语法边界：全角归一化、比较符兼容、混合标识符、错误定位、深嵌套。

///|
fn parse_body(source : String) -> Array[@ir.Stmt] raise @studio_lang.LangError {
  @studio_lang.parse_handler_body(source, @studio_lang.ZhHans).map(t => t.stmt)
}

///|
test "full-width punctuation and digits normalize" {
  // 全角括号/逗号/等号/数字/加号直接解析（中文 IME 输入友好）
  let body = parse_body(
    "信息框（\"你好\"）\n变量 x ＝ １２ ＋ ３\n",
  ) catch {
    error =>
      fail("全角应可解析: line \{@studio_lang.LangError::line(error)}")
  }
  assert_eq(body.length(), 2)
  assert_true(body[0] is @ir.Call(_, _))
  assert_true(body[1] is @ir.Declare("x", _))
}

///|
test "compat comparison symbols ne/le/ge" {
  let source = "如果 1 ≠ 2 则\nx = 1\n结束\n如果 1 ≤ 2 则\nx = 2\n结束\n如果 1 ≥ 0 则\nx = 3\n结束\n"
  let body = parse_body(source) catch {
    error =>
      fail(
        "≠ ≤ ≥ 应可解析: line \{@studio_lang.LangError::line(error)}",
      )
  }
  assert_eq(body.length(), 3)
}

///|
test "mixed cjk/ascii identifiers with digits" {
  let body = parse_body("变量 姓名2 = \"张三\"\n姓名2 = \"李四\"\n") catch {
    error =>
      fail(
        "混合标识符应可解析: line \{@studio_lang.LangError::line(error)}",
      )
  }
  assert_true(body[0] is @ir.Declare("姓名2", _))
  assert_true(body[1] is @ir.Assign("姓名2", _))
}

///|
test "parse errors carry the line number" {
  try parse_body("变量 x = 1\n变量 y = \n") catch {
    error => assert_eq(@studio_lang.LangError::line(error), 2)
  } noraise {
    _ => fail("残缺语句应报错")
  }
}

///|
test "deep loop nesting parses (within budget)" {
  let depth = 15
  let buf = StringBuilder()
  let mut i = 0
  while i < depth {
    buf.write_string("计次循环 2 次\n")
    i = i + 1
  }
  buf.write_string("x = 1\n")
  i = 0
  while i < depth {
    buf.write_string("结束\n")
    i = i + 1
  }
  let body = parse_body(buf.to_string()) catch {
    error =>
      fail(
        "15 层嵌套应可解析: line \{@studio_lang.LangError::line(error)}",
      )
  }
  assert_eq(@ir.stmt_loop_depth(body), depth)
}

///|
test "program validation rejects reserved names and undeclared assignments" {
  let program : @ir.StudioProgram = {
    version: 1,
    window: @ir.default_window(),
    controls: [
      @ir.Control::{
        props: @ir.ControlProps::default(),
        id: 1,
        kind: @ir.Button,
        name: "按钮",
        text: "",
        x: 0,
        y: 0,
        width: 80,
        height: 28,
        items: [],
      },
    ],
    variables: [],
    handlers: [
      @ir.Handler::{
        control_name: "按钮",
        event: @ir.OnClick,
        note_zh: "",
        note_en: "",
        body: [
          @ir.Declare("if", @ir.IntLit(1)),
          @ir.Declare("value", @ir.Var("unknown")),
          @ir.Declare("label_text", @ir.Call("get_text", [@ir.Var("按钮")])),
          @ir.Assign("missing", @ir.IntLit(2)),
        ],
      },
    ],
    functions: [],
    structs: [],
    enums: [],
  }
  let errors = @studio_lang.validate_program_language(program)
  assert_true(errors.any(e => e.kind() is @studio_lang.ReservedWord))
  assert_true(errors.any(e => e.kind() is @studio_lang.NotDeclared))
  assert_true(
    errors.any(e => e.kind() is @studio_lang.NotDeclared && e.a() == "unknown"),
  )
  assert_true(
    !errors.any(e => e.kind() is @studio_lang.NotDeclared && e.a() == "按钮"),
  )
}
