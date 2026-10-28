///|
/// 插件契约·视图协议：插件贡献 UI 的**声明式描述**。
///
/// 为什么是协议而不是直接传视图：`@moui.View[Msg]` 带闭包，闭包无法
/// 跨 WASM 边界搬运；`@moui/core.ViewNode` 是 open trait，但 trait 实现
/// 同样不能安全跨界（要在 guest 侧实现 MoonBit trait 再在宿主侧解释，
/// 等于把整条渲染管线复制一份）。所以插件产出**纯数据的视图树**，
/// 宿主解释为 `@moui.View[Msg]`——与 `plugins/blocks` 的「纯数据 op 序列
/// → 壳侧翻译成 paint 命令」同构。
///
/// 沙箱的关键在**白名单节点集**：协议只认下面这几个节点，插件无法注入
/// 任意闭包、无法画任意路径、无法触碰宿主内存。
///
/// 交互不跨界传闭包，只传 **action id 字符串**：宿主把它转成消息，
/// 由 update 侧决定是否回问插件（`handle_action` 导出）。

///|
/// 视图节点。白名单——新增节点类型是**协议版本**变更。
pub(all) enum PluginViewNode {
  Column(Array[PluginViewSpec])
  Row(Array[PluginViewSpec])
  Text(String)
  Button(label~ : String, action~ : String)
  TextField(value~ : String, action~ : String)
  Checkbox(label~ : String, checked~ : Bool, action~ : String)
  Spacer
  Divider
  LabeledBox(label~ : String, PluginViewSpec)
} derive(Eq, Debug)

///|
/// 视图修饰（对应 `@moui.View` 的 builder 方法）。
pub(all) struct PluginViewSpec {
  node : PluginViewNode
  /// 复用身份键（对齐 `View::key`）。同一 key 的节点在重渲中复用，
  /// key 变化则重挂载——插件的交互态（输入框焦点等）依赖它稳定。
  key : String
  width : Double?
  height : Double?
  padding : Double?
  spacing : Double?
  /// 背景色（`#RRGGBB` 或 `#AARRGGBB`）。非法颜色值由宿主忽略。
  background : String?
  /// 前景色。
  foreground : String?
  font_size : Double?
  /// 弹性权重（对应 `View::flexible`）。
  weight : Double?
} derive(Eq, Debug)

///|
/// 视图协议格式标识（协议自带门卫——与清单格式是**两套独立版本**：
/// 清单管「插件是谁」，协议管「视图长什么样」）。
pub const PLUGIN_VIEW_FORMAT : String = "moui.studio.plugin.view"

///|
/// 视图协议版本。
pub const PLUGIN_VIEW_FORMAT_VERSION : Int32 = 1

///|
/// 视图协议错误分类。
pub(all) enum PluginViewError {
  InvalidJson
  BadFormat
  UnsupportedVersion(Int32)
  MissingField(String)
  UnknownNode(String)
  UnknownField(String)
  BadColor(String)
} derive(Eq, Debug)

///|
fn view_json_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn view_json_double(fields : Map[String, Json], key : String) -> Double? {
  match fields.get(key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
fn view_json_bool(fields : Map[String, Json], key : String) -> Bool? {
  match fields.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// 颜色字符串校验：`#RRGGBB` 或 `#AARRGGBB`（`#` 开头 + 6 或 8 位十六进制）。
/// 非法颜色**报错**而不是静默忽略——插件作者需要知道自己写错了。
pub fn is_valid_plugin_color(text : String) -> Bool {
  if !text.has_prefix("#") {
    return false
  }
  let digits = text[1:]
  if digits.length() != 6 && digits.length() != 8 {
    return false
  }
  for ch in digits {
    let is_hex = (ch >= '0' && ch <= '9') ||
      (ch >= 'a' && ch <= 'f') ||
      (ch >= 'A' && ch <= 'F')
    if !is_hex {
      return false
    }
  }
  true
}

///|
/// 编码：视图树 → JSON 文本。
pub fn encode_view(spec : PluginViewSpec) -> String {
  let fields : Map[String, Json] = Map([], capacity=10)
  fields["format"] = Json::string(PLUGIN_VIEW_FORMAT)
  fields["format_version"] = Json::number(
    PLUGIN_VIEW_FORMAT_VERSION.to_double(),
  )
  fields["key"] = Json::string(spec.key)
  encode_node(spec.node, fields)
  encode_view_modifiers(spec, fields)
  Json::object(fields).stringify()
}

///|
/// 节点 → JSON 字段。子节点**直接构造 Json 对象**（不经 parse）——
/// parse 会 raise，且多一次字符串往返没有意义。
fn encode_node(node : PluginViewNode, fields : Map[String, Json]) -> Unit {
  match node {
    Column(children) => {
      fields["node"] = Json::string("Column")
      fields["children"] = Json::array(
        children.map(child => encode_view_json(child)),
      )
    }
    Row(children) => {
      fields["node"] = Json::string("Row")
      fields["children"] = Json::array(
        children.map(child => encode_view_json(child)),
      )
    }
    Text(text) => {
      fields["node"] = Json::string("Text")
      fields["text"] = Json::string(text)
    }
    Button(label~, action~) => {
      fields["node"] = Json::string("Button")
      fields["label"] = Json::string(label)
      fields["action"] = Json::string(action)
    }
    TextField(value~, action~) => {
      fields["node"] = Json::string("TextField")
      fields["value"] = Json::string(value)
      fields["action"] = Json::string(action)
    }
    Checkbox(label~, checked~, action~) => {
      fields["node"] = Json::string("Checkbox")
      fields["label"] = Json::string(label)
      fields["checked"] = Json::boolean(checked)
      fields["action"] = Json::string(action)
    }
    Spacer => fields["node"] = Json::string("Spacer")
    Divider => fields["node"] = Json::string("Divider")
    LabeledBox(label~, child) => {
      fields["node"] = Json::string("LabeledBox")
      fields["label"] = Json::string(label)
      fields["child"] = encode_view_json(child)
    }
  }
}

///|
/// 视图 → Json（不套 format/version 门卫——子节点用父节点的）。
fn encode_view_json(spec : PluginViewSpec) -> Json {
  let fields : Map[String, Json] = Map([], capacity=10)
  fields["key"] = Json::string(spec.key)
  encode_node(spec.node, fields)
  encode_view_modifiers(spec, fields)
  Json::object(fields)
}

///|
fn encode_view_modifiers(
  spec : PluginViewSpec,
  fields : Map[String, Json],
) -> Unit {
  match spec.width {
    Some(value) => fields["width"] = Json::number(value)
    None => ()
  }
  match spec.height {
    Some(value) => fields["height"] = Json::number(value)
    None => ()
  }
  match spec.padding {
    Some(value) => fields["padding"] = Json::number(value)
    None => ()
  }
  match spec.spacing {
    Some(value) => fields["spacing"] = Json::number(value)
    None => ()
  }
  match spec.background {
    Some(value) => fields["background"] = Json::string(value)
    None => ()
  }
  match spec.foreground {
    Some(value) => fields["foreground"] = Json::string(value)
    None => ()
  }
  match spec.font_size {
    Some(value) => fields["font_size"] = Json::number(value)
    None => ()
  }
  match spec.weight {
    Some(value) => fields["weight"] = Json::number(value)
    None => ()
  }
}

///|
pub extend PluginViewNode with Eq::{not_equal, equal}

///|
pub extend PluginViewNode with @debug.Debug::{to_repr}

///|
pub extend PluginViewSpec with Eq::{not_equal, equal}

///|
pub extend PluginViewSpec with @debug.Debug::{to_repr}

///|
pub extend PluginViewError with Eq::{not_equal, equal}

///|
pub extend PluginViewError with @debug.Debug::{to_repr}

///|
/// 错误可读文本（进 UI 提示）。
pub fn PluginViewError::message(self : PluginViewError) -> String {
  match self {
    InvalidJson => "视图协议不是合法 JSON"
    BadFormat => "视图协议格式标识不匹配"
    UnsupportedVersion(version) =>
      "视图协议版本 \{version} 不受支持（宿主支持 \{PLUGIN_VIEW_FORMAT_VERSION}）"
    MissingField(field) => "视图协议缺少字段 \{field}"
    UnknownNode(name) => "未知节点类型 \{name}"
    UnknownField(field) => "未知字段 \{field}"
    BadColor(color) => "非法颜色值 \{color}"
  }
}

///|
pub impl Show for PluginViewError with fn to_string(self : PluginViewError) -> String {
  self.message()
}

///|
pub extend PluginViewError with Show::{to_string, output}
