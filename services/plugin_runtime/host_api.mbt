///|
/// 宿主函数门面：Studio 能力对插件暴露的**受控入口**。
///
/// 白名单式暴露：**清单没声明的能力一律不给**。插件 import 了一个
/// 宿主没提供的函数 → 实例化失败（缺 import）→ 该插件 Failed。
/// 这比「给了但拒绝调用」强：没给的函数插件连引用都做不到。
///
/// 每个插件一份注册表（按能力装配），互不共享——插件 A 的 import 面
/// 与插件 B 不同，一个插件拿不到另一个插件的数据。

///|
/// 宿主提供的能力集合（由组合根按 profile 决定）。
///
/// 「能力是请求不是许可」：清单声明了 `CapWorkspaceWrite` 只说明插件
/// 想要写权限；宿主是否给，看这里的 `allow_workspace_write`。
pub(all) struct HostCapabilities {
  allow_log : Bool
  allow_workspace_read : Bool
  allow_workspace_write : Bool
  allow_state_read : Bool
  allow_actions : Bool
  allow_events : Bool
}

///|
/// 默认能力面：日志 + 状态 + 动作 + 事件；**不给**工程读写
/// （读写工程 = 改用户代码，是需要显式信任的动作）。
pub fn HostCapabilities::default() -> HostCapabilities {
  {
    allow_log: true,
    allow_workspace_read: false,
    allow_workspace_write: false,
    allow_state_read: true,
    allow_actions: true,
    allow_events: true,
  }
}

///|
/// 宽松能力面：含工程读写（供可信插件 profile 使用）。
pub fn HostCapabilities::trusted() -> HostCapabilities {
  {
    allow_log: true,
    allow_workspace_read: true,
    allow_workspace_write: true,
    allow_state_read: true,
    allow_actions: true,
    allow_events: true,
  }
}

///|
/// 插件可用的工程读写回调（由组合根注入；None = 不可用）。
///
/// 路径安全由**宿主**负责（限工程根内、禁 `..`）——插件拿到的路径
/// 永远是相对工程根的相对路径。
pub(all) struct HostWorkspace {
  read : (String) -> String?
  write : (String, String) -> Bool
}

///|
/// 宿主提供的插件私有状态存储（每个插件一份，互不可见）。
pub(all) struct HostStateStore {
  values : Map[String, String]
}

///|
/// 新建一个插件的状态存储。
pub fn HostStateStore::new() -> HostStateStore {
  { values: Map([], capacity=8), }
}

///|
/// 宿主动作分发回调：插件请求触发宿主动作 → 宿主转成消息。
///
/// 回调返回 true = 已受理（插件可以期待回执）；false = 宿主不受理。
pub type HostActionDispatch = (String, String) -> Bool

///|
/// 宿主事件回调：插件发事件到事件总线。
pub type HostEventEmit = (String, String) -> Unit

///|
/// 宿主日志回调：插件写日志（进 Studio 控制台/审计）。
pub type HostLog = (String) -> Unit

///|
/// 宿主能力门面：一插件一份，持有组合根注入的实际回调。
pub(all) struct HostBridge {
  capabilities : HostCapabilities
  workspace : HostWorkspace?
  state : HostStateStore
  dispatch : HostActionDispatch
  emit : HostEventEmit
  log : HostLog
}

///|
/// 建宿主门面。
pub fn HostBridge::new(
  capabilities~ : HostCapabilities = HostCapabilities::default(),
  workspace~ : HostWorkspace? = None,
  state~ : HostStateStore = HostStateStore::new(),
  dispatch~ : HostActionDispatch = fn(_action, _payload) { false },
  emit~ : HostEventEmit = fn(_name, _payload) { () },
  log~ : HostLog = fn(_message) { () },
) -> HostBridge {
  { capabilities, workspace, state, dispatch, emit, log, }
}

///|
/// 门面是否给某能力（宿主策略 ∩ 插件声明）。
///
/// 双重条件：宿主**允许** 且 插件**声明**。任一不满足 → 不给。
pub fn HostBridge::grants(
  self : HostBridge,
  capabilities : Array[@plugin_contract.PluginCapability],
  capability : @plugin_contract.PluginCapability,
) -> Bool {
  if !capabilities.contains(capability) {
    return false
  }
  match capability {
    @plugin_contract.CapWorkspaceRead => self.capabilities.allow_workspace_read
    @plugin_contract.CapWorkspaceWrite =>
      self.capabilities.allow_workspace_write
    @plugin_contract.CapEvents => self.capabilities.allow_events
    @plugin_contract.CapCommands => self.capabilities.allow_actions
    _ => true
  }
}
