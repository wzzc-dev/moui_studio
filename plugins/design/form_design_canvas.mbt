///|
/// 布局设计器画布视图（M4-3）：Stage 原语渲染 FormModel 控件 + 拖拽手势。
///
/// 这是**布局设计器**（form.mbt 坐标布局），不是 IR 表单画布——拖拽不写 IR，
/// 写的是 form.mbt 字面量。几何 / 手势命中 / 视图已出壳 plugins/design，
/// 会话加载、span 补丁与写回（FileServices）留在壳（form_design_session）。
///
/// 手柄范围（诚实）：v1 拖拽协议只携带位移增量，所以只画/只接 **SE** 手柄；
/// NW/NE/SW 的保角缩放需要协议先升成"绝对角点坐标 + 角标"，不在本文件补。
/// 与设计画布的分工：见壳内 form_design_session.mbt 接线说明。

///|
/// 命中测试（设计坐标）：点在哪个控件里（取最后一个匹配 = 最上层）。
/// 点选与拖拽共用（纯函数，便于测试）。
pub fn form_design_hit_index(
  rects : Array[@geometry.Rect],
  x : Double,
  y : Double,
) -> Int {
  let mut hit = -1
  let mut i = 0
  for rect in rects {
    if x >= rect.origin.x &&
      x <= rect.origin.x + rect.size.width &&
      y >= rect.origin.y &&
      y <= rect.origin.y + rect.size.height {
      hit = i
    }
    i = i + 1
  }
  hit
}

///|
/// SE 缩放手柄命中（设计坐标，与绘制同一组矩形）：以控件右下角为心，
/// 命中半径与设计画布四角手柄同口径（@design.handle_hit_radius）。
pub fn form_design_handle_hit(
  rects : Array[@geometry.Rect],
  index : Int,
  x : Double,
  y : Double,
) -> Bool {
  if index < 0 || index >= rects.length() {
    return false
  }
  let rect = rects[index]
  let cx = rect.origin.x + rect.size.width
  let cy = rect.origin.y + rect.size.height
  (x - cx).abs() <= handle_hit_radius && (y - cy).abs() <= handle_hit_radius
}

///|
/// 拖拽结束 → 提交消息（纯函数）：
/// - 起手点在选中控件的 SE 手柄上 → 缩放（增量 = 总位移）
/// - 起手点落在控件体上 → 移动到该控件（位移 = 总位移）
/// - 空白起手 / 微动（平移 < 0.5px，防御性兜底）→ noop
///
/// 命中全部按**起手点**（event.start）而非当前点——拖动一像素就换目标
/// 会让"按住 A 拖走"在中途变成"抓住 B"。
pub fn[Msg] form_design_drag_commit(
  rects : Array[@geometry.Rect],
  selected : Int?,
  start_x : Double,
  start_y : Double,
  tx : Double,
  ty : Double,
  noop~ : Msg,
  on_resize~ : (Int, Double, Double) -> Msg,
  on_drag~ : (Int, Double, Double) -> Msg,
) -> Msg {
  if tx.abs() < 0.5 && ty.abs() < 0.5 {
    return noop
  }
  match selected {
    Some(index) =>
      if form_design_handle_hit(rects, index, start_x, start_y) {
        return on_resize(index, tx, ty)
      }
    None => ()
  }
  let hit = form_design_hit_index(rects, start_x, start_y)
  if hit >= 0 {
    on_drag(hit, tx, ty)
  } else {
    noop
  }
}

///|
/// 设计器画布（布局页签主体）。scale 1:1：view-local == 设计坐标。
/// 纯视图：会话/补丁/写回由壳处理，手势经回调上交 typed Msg。
pub fn[Msg] form_design_canvas(
  form_model : @form_designer.FormModel,
  selected : Int?,
  width : Double,
  height : Double,
  noop~ : Msg,
  on_select~ : (Int) -> Msg,
  on_drag~ : (Int, Double, Double) -> Msg,
  on_resize~ : (Int, Double, Double) -> Msg,
) -> @moui.View[Msg] {
  let controls = @form_designer.form_controls_to_ir(form_model)
  let rects : Array[@geometry.Rect] = []
  for control in controls {
    rects.push(
      @geometry.Rect::new(
        x=control.x.to_double(),
        y=control.y.to_double(),
        width=control.width.to_double(),
        height=control.height.to_double(),
      ),
    )
  }
  // 选中高亮矩形
  let highlight = match selected {
    Some(index) =>
      if index >= 0 && index < rects.length() {
        Some(rects[index])
      } else {
        None
      }
    None => None
  }
  @views.container(
    @views.measured_canvas(
      measure=fn(_constraints, _text_system) {
        @geometry.Size::new(
          width=form_model.stage_width.max(1.0),
          height=form_model.stage_height.max(1.0),
        )
      },
      draw=fn(ctx, _frame) {
        // 舞台底色
        ctx.commands.push(
          @core.FillRect(
            @core.Rect::new(
              x=0.0,
              y=0.0,
              width=form_model.stage_width,
              height=form_model.stage_height,
            ),
            @core.Color::{ r: 1.0, g: 1.0, b: 1.0, a: 1.0, },
          ),
        )
        // 选中高亮：强调色描边 + 右下角缩放手柄
        match highlight {
          Some(rect) => {
            ctx.commands.push(
              @core.StrokeRect(
                @core.Rect::new(
                  x=rect.origin.x - 2.0,
                  y=rect.origin.y - 2.0,
                  width=rect.size.width + 4.0,
                  height=rect.size.height + 4.0,
                ),
                @chrome.ide_accent(),
                2.0,
              ),
            )
            ctx.commands.push(
              @core.FillRect(
                @core.Rect::new(
                  x=rect.origin.x + rect.size.width - 4.0,
                  y=rect.origin.y + rect.size.height - 4.0,
                  width=8.0,
                  height=8.0,
                ),
                @chrome.ide_accent(),
              ),
            )
          }
          None => ()
        }
      },
      semantics_label="form-design-canvas",
    )
    // 单选：纯点击派发 on_select（拖拽识别后 runtime 会向 tap 发合成
    // Cancel，两者在同一视图上共存，不需要额外状态机）。
    .on_tap_with_frame(fn(position, tap_frame) {
      let x : Double = position.x - tap_frame.origin.x
      let y : Double = position.y - tap_frame.origin.y
      on_select(form_design_hit_index(rects, x, y))
    })
    // 拖拽：Started 用**起手点**锁定目标（手柄 → 保持选中；控件体 → 选中
    // 该控件；空白 → 取消选中），Changed 不发消息，Ended 才提交补丁。
    .on_drag_with_frame(fn(event, drag_frame) {
      let lx = event.start.x - drag_frame.origin.x
      let ly = event.start.y - drag_frame.origin.y
      match event.phase {
        @views.DragGesturePhase::Started =>
          match selected {
            Some(index) if form_design_handle_hit(rects, index, lx, ly) => noop
            _ => on_select(form_design_hit_index(rects, lx, ly))
          }
        @views.DragGesturePhase::Ended =>
          form_design_drag_commit(
            rects,
            selected,
            lx,
            ly,
            event.translation.x,
            event.translation.y,
            noop~,
            on_resize~,
            on_drag~,
          )
        _ => noop
      }
    }),
    background=@chrome.ide_panel(),
    width=canvas_width_of(form_model, width),
    height=canvas_height_of(form_model, height),
    padding=0.0,
  )
}

///|
/// 画布尺寸：舞台尺寸与窗格取小者（1:1；缩放跟随后续里程碑）。
pub fn canvas_width_of(
  model : @form_designer.FormModel,
  pane_width : Double,
) -> Double {
  model.stage_width.max(1.0).min((pane_width - 2.0).max(1.0))
}

///|
pub fn canvas_height_of(
  model : @form_designer.FormModel,
  pane_height : Double,
) -> Double {
  model.stage_height.max(1.0).min((pane_height - 2.0).max(1.0))
}
