///|
/// 视图协议解码：JSON 文本 → 视图树。门卫口径同清单：
/// `format` + `version` 双门卫、未知节点显式报错、非法颜色显式报错。

///|
/// 编码侧允许的节点名集合（白名单）。
fn decode_node(
  fields : Map[String, Json],
  errors : Array[PluginViewError],
) -> PluginViewNode {
  let node_name = match view_json_string(fields, "node") {
    Some(text) => text
    None => {
      errors.push(MissingField("node"))
      return Spacer
    }
  }
  match node_name {
    "Column" => Column(decode_children(fields, errors))
    "Row" => Row(decode_children(fields, errors))
    "Text" =>
      match view_json_string(fields, "text") {
        Some(text) => Text(text)
        None => {
          errors.push(MissingField("text"))
          Text("")
        }
      }
    "Button" => {
      let label = match view_json_string(fields, "label") {
        Some(text) => text
        None => {
          errors.push(MissingField("label"))
          ""
        }
      }
      let action = match view_json_string(fields, "action") {
        Some(text) => text
        None => {
          errors.push(MissingField("action"))
          ""
        }
      }
      Button(label~, action~)
    }
    "TextField" => {
      let value = view_json_string(fields, "value").unwrap_or("")
      let action = match view_json_string(fields, "action") {
        Some(text) => text
        None => {
          errors.push(MissingField("action"))
          ""
        }
      }
      TextField(value~, action~)
    }
    "Checkbox" => {
      let label = match view_json_string(fields, "label") {
        Some(text) => text
        None => {
          errors.push(MissingField("label"))
          ""
        }
      }
      let checked = view_json_bool(fields, "checked").unwrap_or(false)
      let action = match view_json_string(fields, "action") {
        Some(text) => text
        None => {
          errors.push(MissingField("action"))
          ""
        }
      }
      Checkbox(label~, checked~, action~)
    }
    "Spacer" => Spacer
    "Divider" => Divider
    "LabeledBox" => {
      let label = match view_json_string(fields, "label") {
        Some(text) => text
        None => {
          errors.push(MissingField("label"))
          ""
        }
      }
      let child = match fields.get("child") {
        Some(Object(child_fields)) => decode_spec(child_fields, errors)
        _ => {
          errors.push(MissingField("child"))
          {
            node: Spacer,
            key: "",
            width: None,
            height: None,
            padding: None,
            spacing: None,
            background: None,
            foreground: None,
            font_size: None,
            weight: None,
          }
        }
      }
      LabeledBox(label~, child)
    }
    other => {
      errors.push(UnknownNode(other))
      Spacer
    }
  }
}

///|
fn decode_children(
  fields : Map[String, Json],
  errors : Array[PluginViewError],
) -> Array[PluginViewSpec] {
  let children : Array[PluginViewSpec] = []
  match fields.get("children") {
    Some(Array(values)) =>
      for value in values {
        match value {
          Object(child_fields) =>
            children.push(decode_spec(child_fields, errors))
          _ => errors.push(UnknownField("children"))
        }
      }
    _ => errors.push(MissingField("children"))
  }
  children
}

///|
fn decode_spec(
  fields : Map[String, Json],
  errors : Array[PluginViewError],
) -> PluginViewSpec {
  let node = decode_node(fields, errors)
  let key = view_json_string(fields, "key").unwrap_or("")
  let background = match view_json_string(fields, "background") {
    Some(text) =>
      if is_valid_plugin_color(text) {
        Some(text)
      } else {
        errors.push(BadColor(text))
        None
      }
    None => None
  }
  let foreground = match view_json_string(fields, "foreground") {
    Some(text) =>
      if is_valid_plugin_color(text) {
        Some(text)
      } else {
        errors.push(BadColor(text))
        None
      }
    None => None
  }
  {
    node,
    key,
    width: view_json_double(fields, "width"),
    height: view_json_double(fields, "height"),
    padding: view_json_double(fields, "padding"),
    spacing: view_json_double(fields, "spacing"),
    background,
    foreground,
    font_size: view_json_double(fields, "font_size"),
    weight: view_json_double(fields, "weight"),
  }
}

///|
/// 解码：视图协议 JSON → 视图树。错误一次性收集。
///
/// 协议版本门卫与清单版本门卫**独立**：清单 v1 的插件可能产出视图
/// 协议 v1；两者各自演进，互不牵连。
pub fn decode_view(
  source : String,
) -> Result[PluginViewSpec, Array[PluginViewError]] {
  let payload = @json.parse(source) catch { _ => return Err([InvalidJson]) }
  let fields = match payload {
    Object(fields) => fields
    _ => return Err([BadFormat])
  }
  match view_json_string(fields, "format") {
    Some(text) => if text != PLUGIN_VIEW_FORMAT { return Err([BadFormat]) }
    None => return Err([BadFormat])
  }
  let version = match fields.get("format_version") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err([UnsupportedVersion(-1)])
  }
  if version != PLUGIN_VIEW_FORMAT_VERSION {
    return Err([UnsupportedVersion(version)])
  }
  let errors : Array[PluginViewError] = []
  let spec = decode_spec(fields, errors)
  if !errors.is_empty() {
    return Err(errors)
  }
  Ok(spec)
}
