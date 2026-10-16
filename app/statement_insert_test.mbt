///|
/// 插入位置：选中块之后（同层），不是末尾。这是「插入」与「追加」的分野。
test "insert statement lands right after the selected block" {
  let model = @app.load_template_program(@app.initial_model(), 2)
  let before = @app.block_chain_of(model)
  assert_true(before.length() >= 2)
  let original_second = before[1].text
  let selected = select_block_index(model, 0)
  let inserted = apply(
    selected,
    InsertStatement(
      3,
      @blk.template_index_of(3, "app.stmt.tpl.message").unwrap(),
    ),
  )
  let after = @app.block_chain_of(inserted)
  assert_eq(after.length(), before.length() + 1)
  // 新语句插在下标 1，原第二条被挤到下标 2
  assert_eq(after[2].text, original_second)
  assert_eq(inserted.selected_block, 1)
}

///|
/// 插入可撤销：与 commit/delete 同一口径（写回 IR 才产生还原点）。
test "inserted statement is undoable" {
  let model = @app.load_template_program(@app.initial_model(), 2)
  let count = @app.block_chain_of(model).length()
  let inserted = apply(
    model,
    InsertStatement(
      3,
      @blk.template_index_of(3, "app.stmt.tpl.message").unwrap(),
    ),
  )
  assert_eq(@app.block_chain_of(inserted).length(), count + 1)
  let undone = apply(inserted, Undo)
  assert_eq(@app.block_chain_of(undone).length(), count)
}

///|
/// 没有选中子程序时插入是安全的 no-op（给提示，不改 IR）。
test "insert statement without a handler is a safe no-op" {
  let model = apply(@app.initial_model(), ClearSelection)
  let before = model.program.handlers.length()
  let inserted = apply(
    model,
    InsertStatement(
      3,
      @blk.template_index_of(3, "app.stmt.tpl.message").unwrap(),
    ),
  )
  assert_eq(inserted.program.handlers.length(), before)
  assert_true(@app.block_chain_of(inserted).length() == 0)
}

///|
/// 越界的分类/模板下标是安全的 no-op（命令面板与旧配置都可能送进脏下标）。
test "insert statement ignores out-of-range indices" {
  let model = @app.load_template_program(@app.initial_model(), 2)
  let count = @app.block_chain_of(model).length()
  for bad in [(99, 0), (3, 99), (-1, 0)] {
    let (category, template) = bad
    let inserted = apply(model, InsertStatement(category, template))
    assert_eq(@app.block_chain_of(inserted).length(), count)
  }
}

///|
/// 再点同一个分类 = 收起（与图标栏「再点当前项」同一心智）；
/// 点另一个分类 = 直接切换（不要求先收起）。
test "statement palette toggles on the same category and switches on another" {
  let model = @app.load_template_program(@app.initial_model(), 2)
  let opened = apply(model, BlocksUiOp(@blk.ToggleStatementPalette(3)))
  assert_true(opened.blocks_ui.statement_palette_open)
  let closed = apply(opened, BlocksUiOp(@blk.ToggleStatementPalette(3)))
  assert_true(!closed.blocks_ui.statement_palette_open)
  let switched = apply(opened, BlocksUiOp(@blk.ToggleStatementPalette(2)))
  assert_true(switched.blocks_ui.statement_palette_open)
  assert_eq(switched.blocks_ui.selected_category, 2)
}

///|
/// 每个分类的骨架都必须能被双语解析器接受——骨架表是数据，写错一条
/// 就会在运行时变成「点了没反应」。这条锁定整表。
test "every statement template parses in both languages" {
  for template in @blk.statement_templates() {
    for language in [@studio_lang.ZhHans, @studio_lang.En] {
      let language_name = if language is @studio_lang.ZhHans {
        "zh-Hans"
      } else {
        "en"
      }
      let source = template.skeleton(language)
      match @studio_lang.parse_handler_body(source, language) {
        Ok(body) => assert_true(body.length() > 0)
        Err(_) =>
          fail(
            "template " +
            template.label_key +
            " does not parse as " +
            language_name +
            ": " +
            source,
          )
      }
    }
  }
}

///|
/// 分类下标 ↔ 分类的映射是唯一来源：分类轨与插入面板共用它，
/// 两处各写一份会出现「点第三个分类插入第二个分类的语句」。
test "category index mapping matches the rail order" {
  let expected = [
    @blocks.CatEvent,
    @blocks.CatVariable,
    @blocks.CatFlow,
    @blocks.CatCommand,
    @blocks.CatExpression,
  ]
  let mut index = 0
  for category in expected {
    match @blk.category_at(index) {
      Some(actual) =>
        assert_true(
          @blocks.category_color_key(actual) ==
          @blocks.category_color_key(category),
        )
      None => fail("category_at(" + index.to_string() + ") is None")
    }
    index = index + 1
  }
  assert_true(@blk.category_at(5) is None)
}

///|
/// **自制积木组**：插入一条自定义函数调用。
///
/// 骨架由「函数名 + 占位实参」拼出（`名字(0, 0)`），走与模板插入同一条
/// `parse_handler_body` 校验链——这条用例钉住两件事：
/// ① 函数调用真的落进 IR（不是只在面板里显示）；
/// ② 落点是「选中块的下一行」，与模板插入同一判据。
test "insert custom function call lands after the selected block" {
  let base = @app.load_template_program(@app.initial_model(), 2)
  // 模板没有函数——造一个两形参的
  let program : @ir.StudioProgram = {
    ..base.program,
    functions: [
      @ir.FuncDef::{
        name: "求和",
        params: ["甲", "乙"],
        body: [],
        note_zh: "",
        note_en: "",
      },
    ],
  }
  let model = { ..base, program, }
  let before = @app.block_chain_of(model)
  assert_true(before.length() >= 2)
  let original_second = before[1].text
  let selected = select_block_index(model, 0)
  let inserted = apply(selected, InsertCustomFunction(0))
  let after = @app.block_chain_of(inserted)
  assert_eq(after.length(), before.length() + 1)
  // 新语句插在下标 1，原第二条被挤到下标 2
  assert_eq(after[2].text, original_second)
  assert_true(after[1].text.contains("求和"))
  assert_eq(inserted.selected_block, 1)
  // 越界下标：no-op（不崩、不插）
  let bad = apply(selected, InsertCustomFunction(7))
  assert_eq(@app.block_chain_of(bad).length(), before.length())
}

///|
/// 自制积木组的条目投影：`program.functions` → (名字, 形参个数)，
/// 顺序与 IR 一致（不排序）。
test "custom entries project function name and arity" {
  let base = @app.load_template_program(@app.initial_model(), 2)
  let program : @ir.StudioProgram = {
    ..base.program,
    functions: [
      @ir.FuncDef::{
        name: "甲",
        params: [],
        body: [],
        note_zh: "",
        note_en: "",
      },
      @ir.FuncDef::{
        name: "乙",
        params: ["a", "b"],
        body: [],
        note_zh: "",
        note_en: "",
      },
    ],
  }
  let model = { ..base, program, }
  let entries = @app.custom_entries_of(model)
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].name, "甲")
  assert_eq(entries[0].arity, 0)
  assert_eq(entries[1].name, "乙")
  assert_eq(entries[1].arity, 2)
  // 骨架展示名：占位实参按形参个数生成（0 是任何类型都吃得下的字面量）
  assert_eq(@blk.custom_call_label(entries[0]), "甲()")
  assert_eq(@blk.custom_call_label(entries[1]), "乙(0, 0)")
}
