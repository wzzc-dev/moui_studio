///|
/// 插件契约·清单：插件自述的**声明式事实**（谁、什么版本、要什么能力、
/// 入口在哪）。清单是纯数据——它不 import 任何运行时，因此 native 与
/// web 两个后端读同一份清单、同一套守卫、同一份错误语义。
///
/// 纪律（照 `domain/codec` 的门卫口径）：
/// 1. `format` + `version` 双门卫——不匹配整单拒绝，不猜、不迁移。
/// 2. 严格字段检查：必填字段缺失即报错；未知字段**不**静默忽略
///    （未知能力会被当成「没声明」，那会让宿主少给能力——但仍要报出来）。
/// 3. 能力是**请求**不是许可：清单声明 `CapWorkspaceWrite` 只说明插件
///    想要写权限，真正给不给由宿主按信任口径决定（见 `host_api`）。

///|
/// 清单格式标识：不匹配整单拒绝。
pub const PLUGIN_FORMAT : String = "moui.studio.plugin"

///|
/// 清单格式版本。宿主 API 版本见 `PLUGIN_API_VERSION`——两者独立演进：
/// 清单格式变 = 文件布局变；API 版本变 = 宿主能力面变。
pub const PLUGIN_FORMAT_VERSION : Int32 = 1

///|
/// 宿主插件 API 版本。插件在清单里声明 `min_api_version`；高于此值
/// 的插件**不加载**（Skipped），而不是加载后运行期炸。
pub const PLUGIN_API_VERSION : Int32 = 1

///|
/// 插件能力声明。宿主按此决定**暴露哪些宿主函数**——没有声明的能力
/// 一律不暴露（导入缺失 → 实例化失败 → 该插件 Failed，绝不静默放行）。
pub(all) enum PluginCapability {
  /// 贡献命令（在插件面板的命令区里，不进全局命令面板）
  CapCommands
  /// 贡献面板（宿主解释插件的视图协议 JSON）
  CapPanels
  /// 认领某类文档的编辑面
  CapEditor
  /// 读工程文件与 Studio 状态投影
  CapWorkspaceRead
  /// 写工程文件
  CapWorkspaceWrite
  /// 向 Studio 事件总线发事件
  CapEvents
} derive(Eq, Debug)

///|
/// 能力 token（清单里的稳定字符串）。**token 是契约的一部分**——
/// 改名字会让旧清单静默少声明能力，故与枚举一一对应且不轻易改。
pub fn PluginCapability::token(self : PluginCapability) -> String {
  match self {
    CapCommands => "CapCommands"
    CapPanels => "CapPanels"
    CapEditor => "CapEditor"
    CapWorkspaceRead => "CapWorkspaceRead"
    CapWorkspaceWrite => "CapWorkspaceWrite"
    CapEvents => "CapEvents"
  }
}

///|
/// token → 能力。未知 token 返回 None（**不**静默忽略——调用方据此报错）。
pub fn plugin_capability_of_token(token : String) -> PluginCapability? {
  match token {
    "CapCommands" => Some(CapCommands)
    "CapPanels" => Some(CapPanels)
    "CapEditor" => Some(CapEditor)
    "CapWorkspaceRead" => Some(CapWorkspaceRead)
    "CapWorkspaceWrite" => Some(CapWorkspaceWrite)
    "CapEvents" => Some(CapEvents)
    _ => None
  }
}

///|
/// 插件的 **ABI 形态**（入口 wasm 的形态）。
///
/// 两种形态**并存**，宿主都认：
///
/// | 形态 | 入口是什么 | 调用方式 |
/// | --- | --- | --- |
/// | `AbiCore` | 核心 wasm 模块 | 手写 C 风格 ABI（字节 + 偏移） |
/// | `AbiComponent` | WebAssembly **组件** | Canonical ABI（类型化 string） |
///
/// **`AbiCore` 是默认**（清单不写 `abi` 字段时）——既有插件零改动。
/// `AbiComponent` 是更现代的形态：字符串直接传（无需 offset/len 手工
/// 搬运）、类型由 WIT 声明、跨语言（Rust/TS 用官方 `wit-bindgen`）。
///
/// 选哪种：组件形态更适合新插件（ABI 稳定、跨语言、样板代码少）；
/// 核心模块形态适合无法产出组件的工具链。
pub(all) enum PluginAbi {
  /// 核心 wasm 模块（默认）——手写 C 风格 ABI。
  AbiCore
  /// WebAssembly 组件——Canonical ABI。
  AbiComponent
} derive(Eq, Debug)

///|
/// ABI 形态的 token（清单里的稳定字符串）。
pub fn PluginAbi::token(self : PluginAbi) -> String {
  match self {
    AbiCore => "core"
    AbiComponent => "component"
  }
}

///|
/// token → ABI 形态。未知 token 返回 None（**不**静默忽略）。
pub fn plugin_abi_of_token(token : String) -> PluginAbi? {
  match token {
    "core" => Some(AbiCore)
    "component" => Some(AbiComponent)
    _ => None
  }
}

///|
/// 插件清单（清单文件解码后的产物）。
pub(all) struct PluginManifest {
  id : String
  name : String
  version : String
  description : String
  /// 入口 wasm 的**相对路径**（相对插件目录）。绝对路径与 `..` 都会被
  /// 宿主拒绝（见 `services/plugin_runtime` 的路径校验）。
  entry : String
  capabilities : Array[PluginCapability]
  /// 插件要求的最低宿主 API 版本。
  min_api_version : Int32
  /// 入口的 ABI 形态（默认 `AbiCore`）。
  abi : PluginAbi
} derive(Eq, Debug)

///|
/// 清单错误分类。照 `domain/codec.CodecError` 的口径：区分「格式不对」
/// 「版本不对」「字段缺失」「值不合法」——不同错的处置不同
/// （版本不匹配 → Skipped；字段缺失 → Failed）。
pub(all) enum PluginManifestError {
  InvalidJson
  BadFormat
  UnsupportedVersion(Int32)
  MissingField(String)
  BadCapability(String)
  BadAbi(String)
  BadPluginId(String)
  BadEntry(String)
} derive(Eq, Debug)

///|
/// 插件 id 的合法性：非空 + 只允许 `[A-Za-z0-9._-]`。
/// id 会进设置持久化键与面板标识，非法字符会造成跨层歧义，故在
/// 解码门卫处就拒绝（而不是等到用的时候才炸）。
pub fn is_valid_plugin_id(id : String) -> Bool {
  if id == "" {
    return false
  }
  for ch in id {
    let ok = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '.' ||
      ch == '_' ||
      ch == '-'
    if !ok {
      return false
    }
  }
  true
}

///|
/// 入口路径的合法性：必须是**相对**路径、不含 `..`、非空。
/// 绝对路径与上溯会让插件读到宿主目录之外的文件——沙箱的第一道门。
pub fn is_valid_plugin_entry(entry : String) -> Bool {
  if entry == "" {
    return false
  }
  if entry.has_prefix("/") {
    return false
  }
  // Windows 绝对路径（盘符）同样拒绝。
  if entry.length() >= 2 && entry[1] == ':' {
    return false
  }
  for segment in entry.split("/") {
    if segment == ".." {
      return false
    }
  }
  true
}

///|
/// 宿主 API 版本兼容性：插件要求的 `min_api_version` 不得超过宿主版本。
/// 插件要求**更高**的版本 → 不兼容（宿主没有它要的能力，装上也是错的）。
pub fn is_api_compatible(min_api_version : Int32) -> Bool {
  min_api_version <= PLUGIN_API_VERSION
}

///|
pub extend PluginAbi with Eq::{not_equal, equal}

///|
pub extend PluginAbi with @debug.Debug::{to_repr}

///|
pub extend PluginCapability with Eq::{not_equal, equal}

///|
pub extend PluginCapability with @debug.Debug::{to_repr}

///|
pub extend PluginManifest with Eq::{not_equal, equal}

///|
pub extend PluginManifest with @debug.Debug::{to_repr}

///|
pub extend PluginManifestError with Eq::{not_equal, equal}

///|
pub extend PluginManifestError with @debug.Debug::{to_repr}

///|
/// 错误可读文本——插件错误原因要进 UI 提示，必须人能读。
pub fn PluginManifestError::message(self : PluginManifestError) -> String {
  match self {
    InvalidJson => "清单不是合法 JSON"
    BadFormat => "清单格式标识不匹配"
    UnsupportedVersion(version) =>
      "清单版本 \{version} 不受支持（宿主支持 \{PLUGIN_FORMAT_VERSION}）"
    MissingField(field) => "清单缺少字段 \{field}"
    BadCapability(token) => "未知能力 \{token}"
    BadAbi(token) => "未知 ABI 形态 \{token}"
    BadPluginId(id) => "非法插件 id：\{id}"
    BadEntry(entry) => "非法入口路径：\{entry}"
  }
}

///|
pub impl Show for PluginManifestError with fn to_string(
  self : PluginManifestError,
) -> String {
  self.message()
}

///|
pub extend PluginManifestError with Show::{to_string, output}
