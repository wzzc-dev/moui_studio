///|
using @views {canvas, draw_text, fill_rounded_rect, stroke_rounded_rect, stack}

///|
/// 设计舞台：三层结构，治本「设计≠运行」的双渲染器问题。
/// 1) 背景画布：**铺满整个窗格**——点阵晶格从舞台内容区向四周延续
///    （Figma 式画布），白色拟真 App 窗口浮在画布中央；信箱式的留白
///    由晶格接管，不再是死黑；
/// 2) 控件层：真实控件（与运行舞台共用 form_widget 构造），StageLayout
///    按 IR 矩形分配帧——设计态外观与运行态由构造保证一致；
/// 3) 手势覆盖层：透明画布拦截全部指针事件（控件收不到输入），绘制
///    选中描边/名牌/参考线，并把指针转成设计坐标的 typed Msg。
/// 三层与指针换算共用 stage_mapping 的同一映射（缩放 + 居中原点），
/// 缩放钳在 [0.5, 1]：不放大（像素发虚），不缩到看不清。
pub fn[Msg] design_stage(
  program : @ir.StudioProgram,
  selection : String,
  drag_control : String?,
  stage_widgets : Array[@moui.View[Msg]],
  stage_rects : Array[@geometry.Rect],
  semantics_label : String,
  empty_hint : String,
  window_back_color : @core.Color?,
  on_tap~ : (Double, Double) -> Msg,
  on_drag~ : (@views.DragGesturePhase, Double, Double) -> Msg,
  multi_selected~ : Array[String] = [],
) -> @moui.View[Msg] {
  let backdrop = canvas(
    measure=pane_fill_measure,
    draw=fn(ctx, frame) {
      let (scale, ox, oy) = stage_mapping(frame)
      // 1) 满幅点阵晶格：与舞台内容区同一 32px 设计网格，向四周延续。
      //    先铺满幅点，舞台白底随后盖住自己内部的点，plan 再画内容区点。
      let spacing = grid_step * scale
      let dot = (2.0 * scale).max(1.0)
      let right = frame.origin.x + frame.size.width
      let bottom = frame.origin.y + frame.size.height
      let mut mx = ((frame.origin.x - ox) / spacing).floor()
      while ox + mx * spacing < right {
        let mut ny = ((frame.origin.y - oy - title_bar_height * scale) / spacing).floor()
        while oy + title_bar_height * scale + ny * spacing < bottom {
          fill_rounded_rect(
            ctx,
            @graphics.RoundedRect::new(
              rect=@geometry.Rect::new(
                x=ox + mx * spacing,
                y=oy + title_bar_height * scale + ny * spacing,
                width=dot,
                height=dot,
              ),
              radius=dot / 2.0,
            ),
            @graphics.Brush::solid(@chrome.studio_stage_outline()),
          )
          ny = ny + 1.0
        }
        mx = mx + 1.0
      }
      // 2) 拟真窗口：白底 + 小圆角 + 发丝框线（浮在画布中央）
      fn place(rect : @geometry.Rect) -> @geometry.Rect {
        @geometry.Rect::new(
          x=ox + rect.origin.x * scale,
          y=oy + rect.origin.y * scale,
          width=rect.size.width * scale,
          height=rect.size.height * scale,
        )
      }
      for op in design_backdrop_plan() {
        match op {
          WindowFrame(rect) =>
            fill_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=6.0 * scale),
              @graphics.Brush::solid(
                match window_back_color {
                  Some(color) => color
                  None => @chrome.studio_stage_background()
                },
              ),
            )
          GridDot(rect) =>
            fill_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=1.0 * scale),
              @graphics.Brush::solid(@chrome.studio_grid_line()),
            )
          WindowTitleBar(rect) =>
            fill_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=6.0 * scale),
              @graphics.Brush::solid(@chrome.studio_stage_title_bar()),
            )
          TrafficLight(rect, index) =>
            fill_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=4.0 * scale),
              @graphics.Brush::solid(
                match index {
                  0 => @core.Color::rgba(r=0.976, g=0.490, b=0.361)
                  1 => @core.Color::rgba(r=1.0, g=0.824, b=0.243)
                  _ => @core.Color::rgba(r=0.412, g=0.831, b=0.494)
                },
              ),
            )
          _ => ()
        }
      }
      // 窗体框线画在最上（fill 之上才能看清边界）
      for op in design_backdrop_plan() {
        match op {
          WindowFrame(rect) =>
            stroke_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=6.0 * scale),
              @graphics.Brush::solid(@chrome.studio_stage_outline()),
              1.0,
            )
          _ => ()
        }
      }
      // 3) 空画布引导：没有控件时在舞台中央给一句从哪开始的提示
      if program.controls.length() == 0 {
        let cx = ox + design_width * scale / 2.0
        let cy = oy + (title_bar_height + design_height * scale / 2.0)
        draw_text(
          ctx,
          @text.TextRun::new(
            text=empty_hint,
            frame=@geometry.Rect::new(
              x=cx - 200.0,
              y=cy - 10.0,
              width=400.0,
              height=20.0,
            ),
            font=@text.FontSpec::new(size=15.0),
            color=@core.Color::rgba(r=0.553, g=0.580, b=0.620),
            align=TextCenter,
          ),
        )
      }
    },
    semantics_label~,
  )
  let widget_layer = stage_layout(stage_widgets, stage_rects)
  let overlay = canvas(measure=pane_fill_measure, draw=fn(ctx, frame) {
      let (scale, ox, oy) = stage_mapping(frame)
      // 覆盖层与控件层共用同一映射：控件区在标题条之下，覆盖层不跟着
      // 平移就会出现「框选到了、描边却没跟上」的错位。
      fn place(rect : @geometry.Rect) -> @geometry.Rect {
        @geometry.Rect::new(
          x=ox + rect.origin.x * scale,
          y=oy + (title_bar_height + rect.origin.y) * scale,
          width=rect.size.width * scale,
          height=rect.size.height * scale,
        )
      }
      // 参考线只画在舞台范围内（满幅画布里贯穿窗格的参考线会读成界面装饰）
      let stage_left = ox
      let stage_right = ox + design_width * scale
      let stage_top = oy
      let stage_bottom = oy + design_total_height * scale
      for
        op in design_overlay_plan(
          program,
          selection,
          drag_control,
          multi_selected~,
        ) {
        match op {
          BoundsOutline(rect) =>
            stroke_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=4.0 * scale),
              @graphics.Brush::solid(
                @graphics.Color::rgba(r=0.80, g=0.81, b=0.85),
              ),
              1.0 * scale,
            )
          GhostName(rect, name) => {
            fill_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=4.0 * scale),
              @graphics.Brush::solid(
                @graphics.Color::rgba(r=1.0, g=1.0, b=1.0, a=0.55),
              ),
            )
            draw_text(
              ctx,
              @text.TextRun::new(
                text=name,
                frame=place(
                  @geometry.Rect::new(
                    x=rect.origin.x,
                    y=rect.origin.y + (rect.size.height - 15.0) / 2.0,
                    width=rect.size.width,
                    height=15.0,
                  ),
                ),
                font=@text.FontSpec::new(size=12.0 * scale),
                color=@graphics.Color::rgba(r=0.553, g=0.580, b=0.620),
                align=TextCenter,
              ),
            )
          }
          SelectionStroke(rect) => {
            let inflate = 3.0
            stroke_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(
                rect=place(
                  @geometry.Rect::new(
                    x=rect.origin.x - inflate,
                    y=rect.origin.y - inflate,
                    width=rect.size.width + inflate * 2.0,
                    height=rect.size.height + inflate * 2.0,
                  ),
                ),
                radius=8.0 * scale,
              ),
              @graphics.Brush::solid(@chrome.ide_accent()),
              2.5,
            )
          }
          SelectedNamePill(rect, name) => {
            fill_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=4.0 * scale),
              @graphics.Brush::solid(@chrome.ide_accent()),
            )
            draw_text(
              ctx,
              @text.TextRun::new(
                text=name,
                frame=place(
                  @geometry.Rect::new(
                    x=rect.origin.x,
                    y=rect.origin.y + (rect.size.height - 12.5) / 2.0,
                    width=rect.size.width,
                    height=12.5,
                  ),
                ),
                font=@text.FontSpec::new(size=10.0 * scale),
                color=@graphics.Color::rgba(r=1.0, g=1.0, b=1.0),
                align=TextCenter,
              ),
            )
          }
          SelectionHandle(rect) =>
            fill_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(rect=place(rect), radius=2.0 * scale),
              @graphics.Brush::solid(@chrome.ide_accent()),
            )
          GuideV(x) =>
            stroke_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(
                rect=@geometry.Rect::new(
                  x=ox + x * scale - 0.75,
                  y=stage_top,
                  width=1.5,
                  height=stage_bottom - stage_top,
                ),
                radius=0.0,
              ),
              @graphics.Brush::solid(guide_color()),
              1.5,
            )
          GuideH(y) =>
            stroke_rounded_rect(
              ctx,
              @graphics.RoundedRect::new(
                rect=@geometry.Rect::new(
                  x=stage_left,
                  y=oy + (title_bar_height + y) * scale - 0.75,
                  width=stage_right - stage_left,
                  height=1.5,
                ),
                radius=0.0,
              ),
              @graphics.Brush::solid(guide_color()),
              1.5,
            )
          _ => ()
        }
      }
    })
    // 覆盖层在最上：拦截全部指针事件（点选/拖拽在此转 typed Msg），
    // 下层真实控件收不到输入，设计态不会误触运行行为。
    .on_tap_with_frame(fn(position, frame) {
      let (lx, ly) = stage_point(position, frame)
      on_tap(lx, ly)
    })
    .on_drag_with_frame(fn(event, frame) {
      let (lx, ly) = stage_point(event.position, frame)
      on_drag(event.phase, lx, ly)
    })
  stack([backdrop, widget_layer, overlay])
}
