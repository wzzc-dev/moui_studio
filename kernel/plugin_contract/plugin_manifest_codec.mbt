///|
/// 插件清单的 JSON 编解码。门卫口径与 `domain/codec` 同款：
/// `format` + `version` 双门卫、必填字段严格检查、未知能力显式报错。
///
/// 错误**一次性收集**（`Array[PluginManifestError]`）而不是遇错即返回：
/// 清单坏在多个字段时，用户应该一次看到全部问题，而不是改一个试一次。

///|
fn json_string_field(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn json_int_field(fields : Map[String, Json], key : String) -> Int32? {
  match fields.get(key) {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
/// 编码：清单 → JSON 文本。字段顺序固定（map 插入序），保证
/// 「同一份清单两次编码结果一致」——插件作者据此把清单纳入版本控制。
///
/// **两个版本字段不撞名**：清单格式版本是 `format_version`，插件自己的
/// 版本号是 `version`。曾经把格式版本也写成 `version`——解码时读到的
/// 是插件版本号（"1.0.0" 不是整数 → 版本门卫直接报 UnsupportedVersion），
/// 整份清单永远解不开。故格式版本另起键名。
pub fn encode_manifest(manifest : PluginManifest) -> String {
  let fields : Map[String, Json] = Map([], capacity=10)
  fields["format"] = Json::string(PLUGIN_FORMAT)
  fields["format_version"] = Json::number(PLUGIN_FORMAT_VERSION.to_double())
  fields["id"] = Json::string(manifest.id)
  fields["name"] = Json::string(manifest.name)
  fields["version"] = Json::string(manifest.version)
  fields["description"] = Json::string(manifest.description)
  fields["entry"] = Json::string(manifest.entry)
  fields["capabilities"] = Json::array(
    manifest.capabilities.map(capability => Json::string(capability.token())),
  )
  fields["min_api_version"] = Json::number(manifest.min_api_version.to_double())
  fields["abi"] = Json::string(manifest.abi.token())
  Json::object(fields).stringify()
}

///|
/// 解码：清单文本 → 清单。错误一次性收集。
pub fn decode_manifest(
  source : String,
) -> Result[PluginManifest, Array[PluginManifestError]] {
  let payload = @json.parse(source) catch { _ => return Err([InvalidJson]) }
  let fields = match payload {
    Object(fields) => fields
    _ => return Err([BadFormat])
  }
  // 门卫一：格式标识。
  match json_string_field(fields, "format") {
    Some(text) => if text != PLUGIN_FORMAT { return Err([BadFormat]) }
    None => return Err([BadFormat])
  }
  // 门卫二：格式版本（键名 format_version，与插件自身版本号 version 区分）。
  let version = match json_int_field(fields, "format_version") {
    Some(value) => value
    None => return Err([UnsupportedVersion(-1)])
  }
  if version != PLUGIN_FORMAT_VERSION {
    return Err([UnsupportedVersion(version)])
  }
  let errors : Array[PluginManifestError] = []
  // 必填字段：缺失即报错（不填默认值——清单是插件自述，缺就是缺）。
  let id = match json_string_field(fields, "id") {
    Some(value) => {
      if !is_valid_plugin_id(value) {
        errors.push(BadPluginId(value))
      }
      value
    }
    None => {
      errors.push(MissingField("id"))
      ""
    }
  }
  let name = match json_string_field(fields, "name") {
    Some(value) => value
    None => {
      errors.push(MissingField("name"))
      ""
    }
  }
  let plugin_version = match json_string_field(fields, "version") {
    Some(value) => value
    None => {
      errors.push(MissingField("version"))
      ""
    }
  }
  let description = json_string_field(fields, "description").unwrap_or("")
  let entry = match json_string_field(fields, "entry") {
    Some(value) => {
      if !is_valid_plugin_entry(value) {
        errors.push(BadEntry(value))
      }
      value
    }
    None => {
      errors.push(MissingField("entry"))
      ""
    }
  }
  let min_api_version = match json_int_field(fields, "min_api_version") {
    Some(value) => value
    None => {
      errors.push(MissingField("min_api_version"))
      0
    }
  }
  // 能力列表：未知 token 显式报错（静默忽略会让插件以为能力已授予）。
  let capabilities : Array[PluginCapability] = []
  match fields.get("capabilities") {
    Some(Array(values)) =>
      for value in values {
        match value {
          String(token) =>
            match plugin_capability_of_token(token) {
              Some(capability) => capabilities.push(capability)
              None => errors.push(BadCapability(token))
            }
          _ => errors.push(BadCapability("<non-string>"))
        }
      }
    Some(_) => errors.push(MissingField("capabilities"))
    None => errors.push(MissingField("capabilities"))
  }
  // ABI 形态：**可选**——缺省 `core`（既有清单零改动）。未知 token
  // 显式报错（静默回落 core 会让组件插件被当核心模块加载 → 报 ABI
  // 不兼容，用户看到的错误与真实原因不符）。
  let abi = match fields.get("abi") {
    None => AbiCore
    Some(String(token)) =>
      match plugin_abi_of_token(token) {
        Some(value) => value
        None => {
          errors.push(BadAbi(token))
          AbiCore
        }
      }
    Some(_) => {
      errors.push(BadAbi("<non-string>"))
      AbiCore
    }
  }
  if !errors.is_empty() {
    return Err(errors)
  }
  Ok({
    id,
    name,
    version: plugin_version,
    description,
    entry,
    capabilities,
    min_api_version,
    abi,
  })
}
