///|
/// 设计器画布拖拽链的单元锚点(M4-3 收尾):
/// - 纯函数层:命中/手柄判定/拖拽提交消息(表单设计器特有语义)
/// - 会话层:span 补丁 → 源码 → 重解析的往返(activate 已写好的 update 链)
///
/// wbtest 与 app 同包:直接调私有命中/提交助手,不经渲染。
/// 渲染级坐标换算由 `canvas.mbt` 的共享命中栈保证(视图 1:1)。

///|
fn fd_rects_of(model : @form_designer.FormModel) -> Array[@geometry.Rect] {
  let rects : Array[@geometry.Rect] = []
  for control in model.controls {
    rects.push(
      @geometry.Rect::new(
        x=control.x,
        y=control.y,
        width=control.width,
        height=control.height,
      ),
    )
  }
  rects
}

///|
fn fd_two_controls() -> @form_designer.FormModel {
  {
    stage_width: 640.0,
    stage_height: 480.0,
    controls: [
      {
        kind: @form_designer.FkButton,
        text: "ok",
        handler: None,
        x: 10.0,
        y: 20.0,
        width: 80.0,
        height: 30.0,
        props: @ir.ControlProps::default(),
      },
      {
        kind: @form_designer.FkText,
        text: "hi",
        handler: None,
        x: 200.0,
        y: 100.0,
        width: 120.0,
        height: 24.0,
        props: @ir.ControlProps::default(),
      },
    ],
  }
}

///|
test "命中:控件体内命中下标,空白 -1,重叠取最上层" {
  let rects = fd_rects_of(fd_two_controls())
  assert_eq(form_design_hit_index(rects, 50.0, 30.0), 0)
  assert_eq(form_design_hit_index(rects, 250.0, 110.0), 1)
  assert_eq(form_design_hit_index(rects, 500.0, 400.0), -1)
  // 重叠区域:后画的在上(数组最后一个匹配)
  let overlap : Array[@geometry.Rect] = [
    @geometry.Rect::new(x=0.0, y=0.0, width=100.0, height=100.0),
    @geometry.Rect::new(x=50.0, y=50.0, width=100.0, height=100.0),
  ]
  assert_eq(form_design_hit_index(overlap, 60.0, 60.0), 1)
}

///|
test "手柄:仅选中控件右下角 6px 半径内命中" {
  let rects = fd_rects_of(fd_two_controls())
  // 0 号右下角 = (90, 50)
  assert_true(form_design_handle_hit(rects, 0, 90.0, 50.0))
  assert_true(form_design_handle_hit(rects, 0, 94.0, 52.0))
  // 体内但离角远 → 不是手柄
  assert_false(form_design_handle_hit(rects, 0, 15.0, 25.0))
  // 1 号手柄不该被 0 号命中
  assert_false(form_design_handle_hit(rects, 0, 320.0, 124.0))
  // 越界下标安全
  assert_false(form_design_handle_hit(rects, 9, 320.0, 124.0))
  assert_false(form_design_handle_hit(rects, -1, 90.0, 50.0))
}

///|
test "提交:体内起手拖 → FormDesignDragEnd(起手下标)" {
  let rects = fd_rects_of(fd_two_controls())
  match form_design_drag_commit(rects, None, 250.0, 110.0, 12.0, -4.0) {
    Msg::FormDesignDragEnd(index, dx, dy) => {
      assert_eq(index, 1)
      assert_eq(dx, 12.0)
      assert_eq(dy, -4.0)
    }
    _ => fail("体内起手应派发 DragEnd")
  }
}

///|
test "提交:选中控件的 SE 手柄起手 → FormDesignResizeEnd" {
  let rects = fd_rects_of(fd_two_controls())
  match form_design_drag_commit(rects, Some(0), 90.0, 50.0, 20.0, 10.0) {
    Msg::FormDesignResizeEnd(index, dw, dh) => {
      assert_eq(index, 0)
      assert_eq(dw, 20.0)
      assert_eq(dh, 10.0)
    }
    _ => fail("手柄起手应派发 ResizeEnd")
  }
  // 未选中时点手柄区域 = 普通移动(无手柄可拖)
  match form_design_drag_commit(rects, None, 90.0, 50.0, 20.0, 10.0) {
    Msg::FormDesignDragEnd(index, _, _) => assert_eq(index, 0)
    _ => fail("未选中时手柄区域应按控件体移动")
  }
}

///|
test "提交:空白起手或微动 → Noop" {
  let rects = fd_rects_of(fd_two_controls())
  match form_design_drag_commit(rects, None, 500.0, 400.0, 40.0, 40.0) {
    Msg::Noop => ()
    _ => fail("空白起手应 Noop")
  }
  match form_design_drag_commit(rects, Some(0), 50.0, 30.0, 0.2, -0.3) {
    Msg::Noop => ()
    _ => fail("微动应 Noop(防御性兜底)")
  }
}

///|
/// 会话层往返:move 补丁只动 x/y,重解析后模型与 span 都刷新。
test "移动补丁:写源码 + 重解析 + 其余字段不动" {
  let original = "/// form\npub fn layout() -> @moui.View[Msg] {\n  stage(640, 480, [\n    place(@views.button(\"go\"), x=10, y=20, width=80, height=30),\n  ])\n}\n"
  match @form_designer.parse_form(original) {
    Err(message) => fail("原始 form 应可解析: \{message}")
    Ok(parsed) => {
      let session : FormDesignerSession = {
        root: "/tmp/proj",
        form_rel: "app/form.mbt",
        source: original,
        parsed,
      }
      let (moved, changed) = form_design_apply_move(session, 0, 15.0, -5.0)
      assert_true(changed)
      let control = moved.parsed.model.controls[0]

      assert_eq(control.x, 25.0)
      assert_eq(control.y, 15.0)
      assert_eq(control.width, 80.0)
      assert_eq(control.height, 30.0)
      assert_eq(control.text, "go")
      // 补丁后必须仍可解析(span 刷新是后续补丁的前提)
      assert_true(@form_designer.parse_form(moved.source) is Ok(_))
      // 越界下标:会话原样返回
      let (same, ok) = form_design_apply_move(session, 9, 1.0, 1.0)
      assert_false(ok)
      assert_eq(same.source, session.source)
    }
    Err(_) => ()
  }
}

///|
test "缩放补丁:写源码 + 重解析 + 坐标不动" {
  let original = "/// form\npub fn layout() -> @moui.View[Msg] {\n  stage(640, 480, [\n    place(@views.button(\"go\"), x=10, y=20, width=80, height=30),\n  ])\n}\n"
  match @form_designer.parse_form(original) {
    Err(message) => fail("原始 form 应可解析: \{message}")
    Ok(parsed) => {
      let session : FormDesignerSession = {
        root: "/tmp/proj",
        form_rel: "app/form.mbt",
        source: original,
        parsed,
      }
      let (resized, changed) = form_design_apply_resize(session, 0, 24.0, 6.0)
      assert_true(changed)
      let control = resized.parsed.model.controls[0]
      assert_eq(control.width, 104.0)
      assert_eq(control.height, 36.0)
      assert_eq(control.x, 10.0)
      assert_eq(control.y, 20.0)
      let (_, bad) = form_design_apply_resize(session, -1, 1.0, 1.0)
      assert_false(bad)
    }
    Err(_) => ()
  }
}
