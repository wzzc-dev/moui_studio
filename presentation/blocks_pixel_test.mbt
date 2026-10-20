// 像素级回归：积木工作台全 chrome（底栏/右栏/状态栏）必须真正**栅格化出像素**。
//
// 为什么 shell_layout 的命令级断言之外还要这一层：本仓踩过的缺陷是「命令
// 流完整、真机像素缺失」——积木画布 draw 闭包 push_transform×2/pop×1 泄漏
// 一个 Transform 作用域，scroll_view 的 PopClip 在渲染器侧类型失配被拒绝
// 恢复，clip 对整帧不再关闭，画布之后绘制的底栏/右栏/状态栏全部被裁进
// 积木画布视口。命令还在（headless 断言全绿），像素没了（真机黑区）。
// 这里把积木台帧离屏栅格化，在「检查器/审计/UTF-8」三块文本的邻域断言
// **存在明暗对比**（文字像素在场）；作用域失配则由渲染器的
// unsupported_command_count 直接判零。
//
// 本文件是黑盒测试：四个依赖全走公共 API，经 moon.pkg.json 的 test-import
// 引入（宿主包没有运行时行为，见 presentation.mbt 的说明）。

///|
test "blocks workbench rasterizes bottom bar, right panel and status bar" {
  let program = @studio_app.program(provider_config={
    endpoint: "",
    model: "",
    api_key: "",
    models: [],
  })
  let runtime = @runtime.new_program_with_dimensions(
    program~,
    width=1280.0,
    height=800.0,
  )
  fn tap_xy(x : Double, y : Double) -> Unit {
    ignore(
      runtime.dispatch_pointer_input(
        @core.PointerEvent::new(position=@core.Point::new(x~, y~), phase=Down),
      ),
    )
    ignore(
      runtime.dispatch_pointer_input(
        @core.PointerEvent::new(position=@core.Point::new(x~, y~), phase=Up),
      ),
    )
  }
  fn text_frame(
    commands : Array[@core.DrawCommand],
    needle : String,
  ) -> @core.Rect? {
    for command in commands {
      match command {
        @core.DrawText(run) =>
          if run.text.contains(needle) {
            return Some(run.frame)
          }
        _ => ()
      }
    }
    None
  }
  // 进积木工作台：活动栏第三个模式钮（壳测试同款定位：x<48、高>10；
  // 钮序 = 图形化/设计/积木｜代码/AI，排序后积木 = 第三小）。
  let commands1 = runtime.draw_commands()
  let button_cys : Array[Double] = []
  for command in commands1 {
    // 活动栏钮底随主题走不同填充变体（纯色/圆角/Brush），全收。
    let rect : @core.Rect? = match command {
      @core.FillRect(rect, _) => Some(rect)
      @core.FillRoundedRect(rounded, _) => Some(rounded.rect)
      @core.FillRoundedRectBrush(rounded, _) => Some(rounded.rect)
      _ => None
    }
    match rect {
      Some(rect) =>
        if rect.origin.x < 48.0 &&
          rect.origin.x + rect.size.width <= 50.0 &&
          rect.origin.y >= 40.0 &&
          rect.origin.y < 700.0 &&
          rect.size.width > 8.0 &&
          rect.size.height > 10.0 {
          button_cys.push(rect.origin.y + rect.size.height / 2.0)
        }
      None => ()
    }
  }
  button_cys.sort()
  assert_true(
    button_cys.length() >= 5,
    msg="expected 5 mode buttons, got \{button_cys.length()}",
  )
  let blocks_cy = button_cys[2]
  tap_xy(24.0, blocks_cy)
  let commands2 = runtime.draw_commands()
  match
    (text_frame(commands2, "IR 映射"), text_frame(commands2, "程序结构")) {
    (Some(_), None) => ()
    _ => fail("blocks workbench not entered")
  }
  // 三块 chrome 的文本锚点（逻辑坐标；scale=1 时即像素坐标）。
  let anchors : Array[(String, String)] = [
    ("right panel head", "检查器"),
    ("bottom bar tab", "审计"),
    ("status bar", "UTF-8"),
  ]
  for anchor in anchors {
    match text_frame(commands2, anchor.1) {
      Some(frame) => {
        // 文本邻域外扩 2pt，扫描该矩形内的明暗极差——文字像素在场时
        // 极差远超底色抖动；被裁剪成均匀底色时极差 ≈ 0。
        let x0 = (frame.origin.x - 2.0).floor().max(0.0).to_int()
        let y0 = (frame.origin.y - 2.0).floor().max(0.0).to_int()
        let x1 = (frame.origin.x + frame.size.width + 2.0)
          .ceil()
          .min(1279.0)
          .to_int()
        let y1 = (frame.origin.y + frame.size.height + 2.0)
          .ceil()
          .min(799.0)
          .to_int()
        contrast_gate(runtime, x0, y0, x1, y1, anchor.0)
      }
      None => fail("anchor text missing: \{anchor.1}")
    }
  }
}

///|
/// 把当前帧离屏栅格化，断言 [x0,x1)×[y0,y1) 内明暗极差超过阈值。
fn contrast_gate(
  runtime : @runtime.AppRuntime,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
  label : String,
) -> Unit raise {
  let captured : Ref[@render_skia.SkiaPixelFrame?] = Ref(None)
  let target = @render_skia.SkiaPresentTarget::new(
    description="blocks-workbench-pixel-gate",
    present=fn(frame) {
      captured.val = Some(frame)
      true
    },
  )
  let renderer = @render_skia.create_with_present_target(
    @core.SurfaceMetrics::from_logical(
      size=@core.Size::new(width=1280.0, height=800.0),
      scale_factor=1.0,
    ),
    target,
  )
  let result = renderer.render_frame(runtime.draw_frame())
  assert_true(result.presented, msg="\{label}: frame not presented")
  assert_true(
    renderer.unsupported_command_count() == 0,
    msg="\{label}: \{renderer.unsupported_command_count()} unsupported draw commands (scope push/pop imbalance)",
  )
  let frame = match captured.val {
    Some(frame) => frame
    None => fail("\{label}: no pixel frame captured")
  }
  let pixels = frame.pixels()
  let row = frame.row_bytes()
  let mut min_b : Double = 2.0
  let mut max_b : Double = 0.0
  for y in y0..<y1 {
    let base = y * row
    for x in x0..<x1 {
      let offset = base + x * 4
      // 像素字节序（BGRA/RGBA）不影响「前三个字节取均值」的极差判据。
      let brightness = (
          pixels[offset].to_double() +
          pixels[offset + 1].to_double() +
          pixels[offset + 2].to_double()
        ) /
        3.0 /
        255.0
      if brightness < min_b {
        min_b = brightness
      }
      if brightness > max_b {
        max_b = brightness
      }
    }
  }
  assert_true(
    max_b - min_b > 0.25,
    msg="\{label}: region (\{x0},\{y0})..(\{x1},\{y1}) is uniform (contrast \{max_b - min_b}) — chrome pixels missing",
  )
}
