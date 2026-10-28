///|
/// 插件清单扫描：从插件根目录发现插件、读清单、校验。
///
/// 纪律（照 `services/project/walk.mbt` 的扫描口径）：
/// 1. **一个插件坏了不挡住其余插件**——每个插件独立产出 outcome，
///    坏清单只记原因，不 fail-fast、不中断整轮扫描。
/// 2. **清单与入口都必须在插件目录内**——入口路径经
///    `plugin_contract.is_valid_plugin_entry` 门卫（禁绝对路径、禁 `..`），
///    且最终解析路径必须仍在插件目录之下。
/// 3. **扫描有上限**——插件目录数量设上限，防止误指到工程根目录时
///    把整个仓库当插件扫一遍。

///|
/// 扫描发现的插件候选（清单已过门卫，入口文件尚未校验存在）。
pub(all) struct PluginCandidate {
  manifest : @plugin_contract.PluginManifest
  /// 插件目录（绝对或相对，取决于根目录参数）
  dir : String
  /// 入口 wasm 的完整路径
  entry_path : String
}

///|
/// 单个插件的扫描结果。
pub(all) enum PluginScanOutcome {
  /// 清单合法且入口文件存在
  Found(PluginCandidate)
  /// 清单有但非法（记原因，不中断其余插件）
  Invalid(plugin_id~ : String, reason~ : String)
  /// 目录不是插件（没有清单文件）
  NotAPlugin
}

///|
/// 插件清单文件名（放在插件目录根下）。
pub const PLUGIN_MANIFEST_NAME : String = "plugin.json"

///|
/// 扫描上限：单次扫描最多看这么多插件目录。超出即停并如实报告
/// （不静默截断——用户需要知道还有插件没被扫到）。
pub const PLUGIN_SCAN_LIMIT : Int32 = 64

///|
/// 扫描结果：候选列表 + 被跳过的坏插件 + 是否触到上限。
pub(all) struct PluginScanResult {
  candidates : Array[PluginCandidate]
  invalid : Array[(String, String)]
  /// 触到扫描上限 = true（还有插件没被看到）
  truncated : Bool
}

///|
/// 扫描插件根目录下的所有插件。
///
/// 目录结构约定：`<root>/<plugin-id>/plugin.json` + 同目录下的入口 wasm。
pub fn scan_plugins(root : String) -> PluginScanResult {
  let candidates : Array[PluginCandidate] = []
  let invalid : Array[(String, String)] = []
  let mut truncated = false
  let entries = @x/fs.read_dir(root) catch {
    _ => return { candidates, invalid, truncated, }
  }
  let mut visited = 0
  for name in entries {
    if visited >= PLUGIN_SCAN_LIMIT {
      truncated = true
      break
    }
    let dir = "\{root}/\{name}"
    let is_dir = @x/fs.is_dir(dir) catch { _ => false }
    if !is_dir {
      continue
    }
    visited = visited + 1
    let manifest_path = "\{dir}/\{PLUGIN_MANIFEST_NAME}"
    let exists = @x/fs.path_exists(manifest_path)
    if !exists {
      continue
    }
    let source = @x/fs.read_file_to_string(manifest_path) catch {
      _ => {
        invalid.push((name, "清单文件读取失败"))
        continue
      }
    }
    let manifest = match @plugin_contract.decode_manifest(source) {
      Ok(value) => value
      Err(errors) => {
        invalid.push((name, describe_manifest_errors(errors)))
        continue
      }
    }
    // API 版本门卫：插件要求更高的宿主 API → 跳过（不是失败，是不兼容）。
    if !@plugin_contract.is_api_compatible(manifest.min_api_version) {
      invalid.push(
        (
          manifest.id,
          "插件要求宿主 API 版本 \{manifest.min_api_version}，宿主提供 \{@plugin_contract.PLUGIN_API_VERSION}",
        ),
      )
      continue
    }
    let entry_path = "\{dir}/\{manifest.entry}"
    let entry_exists = @x/fs.path_exists(entry_path)
    if !entry_exists {
      invalid.push((manifest.id, "入口文件不存在：\{manifest.entry}"))
      continue
    }
    candidates.push({ manifest, dir, entry_path, })
  }
  { candidates, invalid, truncated, }
}

///|
/// 清单错误列表 → 一句话原因（进 UI 提示）。
pub fn describe_manifest_errors(
  errors : Array[@plugin_contract.PluginManifestError],
) -> String {
  let parts : Array[String] = []
  for error in errors {
    parts.push(error.message())
  }
  parts.join("；")
}

///|
/// 宿主能力白名单：清单声明了某能力，才给对应的宿主函数。
///
/// **能力是请求不是许可**——这里只做「声明→授予」的映射，真正的信任
/// 决策（是否允许写工程文件等）在组合根装配时按 profile 决定。
pub fn capability_granted(
  capabilities : Array[@plugin_contract.PluginCapability],
  capability : @plugin_contract.PluginCapability,
) -> Bool {
  capabilities.contains(capability)
}
