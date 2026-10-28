///|
/// 插件视图解释器：协议 JSON → `@moui.View[Msg]`。
///
/// 位置在 **app 侧**（不在服务层）：服务层不能引用 app 的 `Msg`
/// （依赖方向 app → services）。两个后端（native / web）都只产出协议
/// JSON，由这一个解释器统一转成宿主视图——**一份解释器，两端共用**。
///
/// 白名单纪律：协议只认 `plugin_contract.PluginViewNode` 的节点类型；
/// 未知节点在解码阶段已被拒（`UnknownNode`），解释器只处理合法树。
///
/// 事件：交互不跨界传闭包——按钮/输入框的回调发
/// `Msg::PluginAction(plugin_id, action_id, payload)`，由 update 侧决定
/// 是否回问插件。

///|
/// 解析两位十六进制 → 0..255。
/// 手写而非依赖 strconv：十六进制解析的 API 形态在 MoonBit 各版本间
/// 有差异，自己算反而稳（而且这里只有 8 位，代价可忽略）。
fn hex_pair_to_int(pair : String) -> Int32? {
  if pair.length() != 2 {
    return None
  }
  let mut value = 0
  for index in 0..<2 {
    // Char 不支持算术——取码位（ASCII 十六进制字符 < 128）再算。
    let code = pair.code_unit_at(index).to_int()
    let digit = match code {
      48..<=57 => code - 48
      97..<=102 => code - 97 + 10
      65..<=70 => code - 65 + 10
      _ => return None
    }
    value = value * 16 + digit
  }
  Some(value)
}

///|
/// 解析 `#RRGGBB` / `#AARRGGBB` → `@core.Color`。
/// 非法颜色返回 None（调用方决定回落策略）。
pub fn parse_plugin_color(text : String) -> @core.Color? {
  if !@plugin_contract.is_valid_plugin_color(text) {
    return None
  }
  let digits = text[1:]
  let hex = digits.to_lower()
  let channels : Array[Int32] = []
  let mut index = 0
  while index + 2 <= hex.length() {
    match hex_pair_to_int(hex[index:index + 2].to_owned()) {
      Some(value) => channels.push(value)
      None => return None
    }
    index = index + 2
  }
  if hex.length() == 8 {
    // #AARRGGBB
    let alpha = channels[0].to_double() / 255.0
    Some(
      @core.Color::rgba(
        r=channels[1].to_double() / 255.0,
        g=channels[2].to_double() / 255.0,
        b=channels[3].to_double() / 255.0,
        a=alpha,
      ),
    )
  } else {
    Some(
      @core.Color::rgba(
        r=channels[0].to_double() / 255.0,
        g=channels[1].to_double() / 255.0,
        b=channels[2].to_double() / 255.0,
      ),
    )
  }
}

///|
/// 插件视图的渲染上下文：解释器需要的宿主侧信息。
pub(all) struct PluginViewContext {
  /// 插件 id（事件回传时带上，宿主据此回问哪个插件）
  plugin_id : String
  /// 面板 id（事件回传时带上，宿主据此把新视图归到正确的面板）
  panel_id : String
  /// 动作回调：action id + 载荷 → 宿主消息
  on_action : (String, String) -> Msg
  /// 按钮身份键：随「插件 + 面板 + 动作」变化——按钮的 on_click 是构建时
  /// 求值的值，键不变则运行时复用旧按钮（旧消息）。
  button_key : (String) -> String
}

///|
/// 解释视图树 → `@moui.View[Msg]`。
pub fn interpret_plugin_view(
  spec : @plugin_contract.PluginViewSpec,
  context : PluginViewContext,
) -> @moui.View[Msg] {
  let base = interpret_node(spec.node, context)
  // 修饰逐层叠加：先尺寸与间距，再颜色，最后字体。
  let sized = match spec.width {
    Some(width) => base.frame(width~)
    None => base
  }
  let sized = match spec.height {
    Some(height) => sized.frame(height~)
    None => sized
  }
  let painted = match spec.background {
    Some(text) =>
      match parse_plugin_color(text) {
        Some(color) => sized.background(color)
        None => sized
      }
    None => sized
  }
  let painted = match spec.foreground {
    Some(text) =>
      match parse_plugin_color(text) {
        Some(color) => painted.foreground(color)
        None => painted
      }
    None => painted
  }
  let painted = match spec.font_size {
    Some(size) => painted.font(@core.FontSpec::new(size~))
    None => painted
  }
  let painted = match spec.weight {
    Some(weight) => painted.flexible(weight~)
    None => painted
  }
  // key 决定复用身份（对齐 `View::key`）；空 key 不设（宿主会按位置复用）。
  match spec.key {
    "" => painted
    key => painted.key(key)
  }
}

///|
/// 解释单个节点。
fn interpret_node(
  node : @plugin_contract.PluginViewNode,
  context : PluginViewContext,
) -> @moui.View[Msg] {
  match node {
    Column(children) =>
      @views.column(
        children.map(child => interpret_plugin_view(child, context)),
      )
    Row(children) =>
      @views.row(children.map(child => interpret_plugin_view(child, context)))
    Text(text) => @views.text(text)
    Button(label~, action~) =>
      // on_click 是**构建时求值的值**（`Msg?`）——运行时缓存按钮实例时
      // 会复用它。故视图必须给按钮一个随内容变化的 key，否则重渲后
      // 按钮仍绑着旧消息（旧 action / 旧的插件 id）。
      @views.button(label, on_click=(context.on_action)(action, "")).key(
        (context.button_key)(action),
      )
    TextField(value~, action~) =>
      @views.text_field(value, on_input=fn(next) {
        (context.on_action)(action, next)
      })
    Checkbox(label~, checked~, action~) =>
      @views.checkbox(label, checked~, on_change=fn(next) {
        (context.on_action)(action, if next { "1" } else { "0" })
      })
    Spacer => @views.spacer()
    Divider => @views.divider()
    LabeledBox(label~, child) =>
      @views.container(
        @views.column(
          [
            @views.text(label, width=200.0, height=14.0),
            interpret_plugin_view(child, context),
          ],
          spacing=2.0,
        ),
        padding=4.0,
      )
  }
}

///|
/// 解释协议 JSON → `@moui.View[Msg]`。非法协议返回 None
/// （调用方显示占位而不是崩）。
pub fn interpret_plugin_view_json(
  source : String,
  context : PluginViewContext,
) -> @moui.View[Msg]? {
  let spec = match @plugin_contract.decode_view(source) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(interpret_plugin_view(spec, context))
}
