///|
/// 插件契约·运行时描述：插件在 Studio 里的**状态事实**。
///
/// 清单（`PluginManifest`）是插件自述；描述符（`PluginDescriptor`）是
/// 宿主观察到的结果——含加载状态与失败原因。两者分开，是因为「插件说
/// 自己是谁」与「宿主发现它其实是坏的」必须能同时呈现给用户。

///|
/// 插件加载状态。
pub(all) enum PluginStatus {
  /// 已加载并可用
  Loaded
  /// 已发现但被用户禁用
  Disabled
  /// 加载中
  Loading
  /// 加载失败（带原因；原因进 UI 提示，不吞掉）
  Failed(String)
} derive(Eq, Debug)

///|
/// 插件在宿主里的运行时描述。
pub(all) struct PluginDescriptor {
  manifest : PluginManifest
  status : PluginStatus
} derive(Eq, Debug)

///|
/// 描述符是否可用（已加载且未被禁用）。
pub fn PluginDescriptor::is_active(self : PluginDescriptor) -> Bool {
  self.status is Loaded
}

///|
/// 插件贡献的面描述——插件在 `describe` 导出里返回的 JSON。
///
/// 贡献用**纯数据**描述（不是闭包）：面板给出 id 与标题，命令给出
/// id 与标题，宿主按这些描述去注册既有贡献点。
pub(all) struct PluginContributions {
  /// 面板贡献：id → 标题（本地化键或纯文本，由宿主决定怎么显示）。
  panels : Array[(String, String)]
  /// 命令贡献：id → 标题。
  commands : Array[(String, String)]
} derive(Eq, Debug)

///|
/// 贡献描述的 JSON 编解码（插件 `describe` 导出的载荷格式）。
pub const PLUGIN_CONTRIB_FORMAT : String = "moui.studio.plugin.contrib"

///|
/// 贡献描述格式版本。
pub const PLUGIN_CONTRIB_FORMAT_VERSION : Int32 = 1

///|
/// 贡献描述解码错误。
pub(all) enum PluginContribError {
  InvalidJson
  BadFormat
  UnsupportedVersion(Int32)
  BadEntry(String)
} derive(Eq, Debug)

///|
fn contrib_string_field(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn decode_contrib_pairs(
  fields : Map[String, Json],
  key : String,
  errors : Array[PluginContribError],
) -> Array[(String, String)] {
  let pairs : Array[(String, String)] = []
  match fields.get(key) {
    Some(Object(entries)) =>
      for (id, value) in entries {
        match value {
          String(title) => pairs.push((id, title))
          _ => errors.push(BadEntry(id))
        }
      }
    Some(_) => errors.push(BadEntry(key))
    None => () // 缺该键 = 该面无贡献（合法：插件可能只贡献面板）
  }
  pairs
}

///|
/// 解码插件贡献描述。
pub fn decode_contributions(
  source : String,
) -> Result[PluginContributions, Array[PluginContribError]] {
  let payload = @json.parse(source) catch { _ => return Err([InvalidJson]) }
  let fields = match payload {
    Object(fields) => fields
    _ => return Err([BadFormat])
  }
  match contrib_string_field(fields, "format") {
    Some(text) => if text != PLUGIN_CONTRIB_FORMAT { return Err([BadFormat]) }
    None => return Err([BadFormat])
  }
  let version = match fields.get("format_version") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err([UnsupportedVersion(-1)])
  }
  if version != PLUGIN_CONTRIB_FORMAT_VERSION {
    return Err([UnsupportedVersion(version)])
  }
  let errors : Array[PluginContribError] = []
  let panels = decode_contrib_pairs(fields, "panels", errors)
  let commands = decode_contrib_pairs(fields, "commands", errors)
  if !errors.is_empty() {
    return Err(errors)
  }
  Ok({ panels, commands, })
}

///|
/// 编码插件贡献描述（测试与文档示例用）。
pub fn encode_contributions(contrib : PluginContributions) -> String {
  let fields : Map[String, Json] = Map([], capacity=4)
  fields["format"] = Json::string(PLUGIN_CONTRIB_FORMAT)
  fields["format_version"] = Json::number(
    PLUGIN_CONTRIB_FORMAT_VERSION.to_double(),
  )
  let panels : Map[String, Json] = Map([], capacity=4)
  for (id, title) in contrib.panels {
    panels[id] = Json::string(title)
  }
  fields["panels"] = Json::object(panels)
  let commands : Map[String, Json] = Map([], capacity=4)
  for (id, title) in contrib.commands {
    commands[id] = Json::string(title)
  }
  fields["commands"] = Json::object(commands)
  Json::object(fields).stringify()
}

///|
pub extend PluginStatus with Eq::{not_equal, equal}

///|
pub extend PluginStatus with @debug.Debug::{to_repr}

///|
pub extend PluginDescriptor with Eq::{not_equal, equal}

///|
pub extend PluginDescriptor with @debug.Debug::{to_repr}

///|
pub extend PluginContribError with Eq::{not_equal, equal}

///|
pub extend PluginContribError with @debug.Debug::{to_repr}

///|
/// 错误可读文本（进 UI 提示）。
pub fn PluginContribError::message(self : PluginContribError) -> String {
  match self {
    InvalidJson => "贡献描述不是合法 JSON"
    BadFormat => "贡献描述格式标识不匹配"
    UnsupportedVersion(version) =>
      "贡献描述版本 \{version} 不受支持（宿主支持 \{PLUGIN_CONTRIB_FORMAT_VERSION}）"
    BadEntry(entry) => "非法贡献项 \{entry}"
  }
}

///|
pub impl Show for PluginContribError with fn to_string(
  self : PluginContribError,
) -> String {
  self.message()
}

///|
pub extend PluginContribError with Show::{to_string, output}

///|
pub extend PluginContributions with Eq::{not_equal, equal}

///|
pub extend PluginContributions with @debug.Debug::{to_repr}
