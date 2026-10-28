///|
/// MoUI Studio Web 入口（wasm-gc）：薄组合根。
/// 浏览器没有 HTTP 通道（真实 provider 仅 native worker），AI 显式降级：
/// `ai_available=false` → composer 隐藏 + native 引导文案，不出假按钮。
/// apply_locale 经 Ref 后置绑定（runtime 构造时还不存在）。

///|
/// 平台墙钟 → app 的 StudioClock 纯数据映射（mo_desktop 的 DesktopClock
/// 同款先例；web 的 FFI 在 moui/backend/web/web_host.mbt）。
fn web_studio_clock() -> @studio_app.StudioClock {
  let clock = @web.web_wall_clock()
  {
    year: clock.year,
    month: clock.month,
    day: clock.day,
    weekday: clock.weekday,
    hour: clock.hour,
    minute: clock.minute,
    second: clock.second,
  }
}

///|
/// 宿主 → JS 方向的推送入口（JS 侧插件就绪后调用）。
///
/// **方向**：JS 调**宿主导出的**这个函数（与 `web_dispatch_event` 同款
/// 机制——MoonBit 导出函数给 JS 调）。wasm 的 import 是单向的：宿主
/// 声明 `extern "wasm" fn` 时由 JS 提供实现，JS 想知道「宿主那边发生
/// 了什么」得靠宿主**导出**函数。
///
/// 插件就绪比宿主构造 runtime 晚（浏览器 instantiate 是异步的，实测
/// 约 90ms），故宿主「拉」插件列表必然拉到空——改由 JS 就绪后主动推。

///|
/// JS → 宿主方向的推送入口（JS 侧插件就绪后调用）。
///
/// **方向**：这是宿主**导出**给 JS 调的函数（照 `web_dispatch_event`
/// 同款机制——`link.exports` 里列出的函数由 JS 直接调用）。wasm 的
/// import 是单向的：宿主声明 `extern "wasm" fn` 时由 JS 提供实现；
/// JS 想告诉宿主「插件好了」，得靠宿主导出函数。
///
/// **为什么需要推送**：浏览器 `WebAssembly.instantiate` 是异步的，
/// 插件就绪时刻晚于宿主构造 runtime 的时刻（实测约 90ms）——宿主
/// 「拉」插件列表必然拉到空。改由 JS 就绪后主动推。
pub fn studio_push_contributions(
  plugin_id : Int32,
  contributions : Int32,
) -> Unit {
  let id = studio_read_string(plugin_id)
  let json = studio_read_string(contributions)
  @studio_app.install_web_plugin_contributions(id, json)
}

///|
/// 宿主 → JS：**插件 ABI 描述**（内存偏移、导出名）。
///
/// **为什么需要它**：ABI 常量的唯一真源在
/// `kernel/plugin_contract/plugin_abi.mbt`（native 与 web 共用）。
/// JS 侧**不硬编码**这些值——宿主在启动时经本 import 把描述推过去，
/// JS 的 `registerAbi` 收下。
///
/// 这样「native 与 web 用同一份 ABI 定义」就不只是约定，而是**机制
/// 保证**：改契约层的常量，两端同时跟着变；JS 侧再抄一份导致的漂移
/// 从此不可能发生。
///
/// **为什么用 import 而不是导出**：wasm → JS 本来就是 import 方向
/// （`studio_host_log` 等同款），字符串经**字符串句柄**逐字符传（wasm-gc
/// 的 import 只能传标量）。宿主主动推 = JS 侧不需要反向读 wasm 内存。
extern "wasm" fn studio_set_abi_descriptor(
  descriptor : @plugin_runtime_web.WebString,
) -> Unit = "studio" "set_abi_descriptor"

///|
/// JS → 宿主：「插件列表变了，请刷新」（JS 侧插件就绪后调用）。
///
/// **为什么需要这个反向通道**：wasm 的 import 是单向的（宿主 → JS），
/// JS 无法直接驱动 app 的 update。而 web 端的浏览器事件循环是**按需
/// 驱动**的——没有重绘就没有 rAF 帧，定时器订阅不派发。于是：
///
/// ```text
/// 宿主首帧加载插件 → 插件还没就绪（浏览器 instantiate 是异步的）
/// JS 侧插件就绪   → 但没人告诉宿主，宿主不重查、也不重绘
/// 结果            → 底栏的「插件」页签永远不出现
/// ```
///
/// 宿主侧的定时器重试**救不了这个**：静止时定时器根本不派发（实测
/// 首帧 `ready=0` 之后直到用户点击界面才出现 `ready=1`）。
///
/// 故由 JS 主动调本导出：宿主重查插件贡献 → 触发一次 root rebuild
/// （`Resize` 同尺寸）→ 界面重绘 → 插件页签随之出现。
///
/// **同尺寸 Resize 的含义**：`RuntimeState::dispatch_event` 的
/// `Resize` 分支会 `request_root_rebuild` + 置脏重绘，而尺寸赋值是
/// 同值——故它只当「强制重建并重绘」用，不改视口。
pub fn studio_plugins_changed() -> Unit {
  @studio_app.notify_web_plugins_changed()
}

///|
/// JS → 宿主：「请重新加载插件列表」。
///
/// **为什么需要它**：宿主侧的定时器重试救不了 web 端——静止时
/// 浏览器事件循环**不派发定时器**（web 端的 rAF 由 `window.request_redraw`
/// 排起，而那条路只在 wasm 自己的事件循环里生效；JS 从 wasm 外部
/// 同步调宿主导出函数时，wasm 的事件循环并没有在跑）。
///
/// 故由 JS 用 **`setTimeout`** 轮询调用本导出——JS 的定时器**独立于**
/// wasm 的事件循环（浏览器自己的任务队列），故必定会被触发。
/// 宿主每次收到就重查一次插件列表并更新 model。
///
/// 宿主的回复（插件是否就绪）经 `plugin_bridge.load` 的回执 →
/// `PluginsScanned` 消息 → model 缓存。
pub fn studio_reload_plugins() -> Int32 {
  @studio_app.reload_web_plugins()
}

///|
/// 按下标读 JS 侧字符串句柄的一个字符（宿主读 JS 字符串用；不推进句柄偏移）。
extern "wasm" fn studio_string_read_char_at(
  handle : Int32,
  index : Int32,
) -> Int32 = "studio" "string_read_char_at"

///|
/// 读 JS 侧字符串句柄（逐字符；wasm-gc 的 import 只能传标量）。
fn studio_read_string(handle : Int32) -> String {
  let buffer = StringBuilder()
  let index = Ref(0)
  while true {
    let code = studio_string_read_char_at(handle, index.val)
    if code == -1 {
      break
    }
    buffer.write_char(code.unsafe_to_char())
    index.val = index.val + 1
  }
  buffer.to_string()
}

///|
fn main {
  // 实时查插件贡献（web 端）：宿主向 JS 侧问「哪些插件就绪了」。
  //
  // **插件调用不再走这个通道**：宿主→插件的调用统一经 `plugin_bridge`
  // （契约层的 `PluginBridge`）——`PluginPanelRequest` / `PluginAction`
  // 都在 update 的 effect 里走它，回执经消息回填 model 的视图缓存。
  // 渲染路径**不碰插件**（插件是不受信任的代码，只在 effect 里跑）。
  let web_runtime = @plugin_runtime_web.PluginRuntimeWeb::new()
  @studio_app.install_web_plugin_provider(fn() {
    web_runtime.ready_contributions()
  })
  // **把插件 ABI 描述推给 JS**：ABI 常量的唯一真源在契约层
  // （`kernel/plugin_contract/plugin_abi.mbt`），native 与 web 共用。
  // JS 侧不硬编码这些值——否则两处手写副本会漂移，表现为「web 能加载、
  // native 报 ABI 不兼容」这类只在单端暴露的 bug。
  studio_set_abi_descriptor(
    @plugin_runtime_web.string_to_js(@plugin_contract.plugin_abi_descriptor()),
  )

  let runtime_ref : Ref[@runtime.AppRuntime?] = Ref(None)
  // 「重载插件列表」触发器：JS 侧轮询时调用 → 经 program command 驱动
  // app update（`PluginsLoadRequested` → `PluginsScanned` → model）。
  //
  // **为什么走 program command**：wasm 的 import 是单向的，JS 无法直接
  // 驱动 app 的 update；而 `dispatch_action_command` 会**同步**调 runtime
  // 的 dispatch 闭包（`handle()` → `dispatch(消息)`），**不依赖 rAF**——
  // 故从 wasm 外部调用也必定生效。
  //
  // （宿主侧的定时器重试救不了：静止时浏览器事件循环不派发定时器。）
  @studio_app.install_web_plugin_reload_trigger(fn() {
    match runtime_ref.val {
      Some(runtime) =>
        ignore(
          runtime.dispatch_action_command(@studio_app.plugin_reload_command()),
        )
      None => ()
    }
    // 返回**已就绪的插件数**（JS 侧据此停止轮询）。判据取 JS 侧的
    // 实例表——那是「插件真的能用」的唯一权威。
    web_runtime.ready_plugin_ids().length()
  })
  // 「插件就绪」通知器：JS 侧插件就绪后调宿主导出 `studio_plugins_changed`
  // → 本通知器触发一次**强制重建 + 重绘**。
  //
  // **为什么必须触发重绘**：web 端的浏览器事件循环是**按需驱动**的
  // ——没有重绘就没有 rAF 帧，`web_timer_dispatch_due()` 不跑，定时器
  // 订阅（含插件重试节拍）就不派发。实测：页面加载后首帧 `ready=0`，
  // 直到用户点击界面才出现 `ready=1`——静止时那条重试链是死的。
  //
  // 故插件就绪这一事实必须**由 JS 主动送来**（wasm import 单向，JS
  // 无法驱动 app 的 update），宿主据此唤醒事件循环。
  @studio_app.install_web_plugin_ready_notifier(fn() {
    match runtime_ref.val {
      Some(runtime) =>
        // **同尺寸 Resize**：只当「强制重建并重绘」用。`Resize` 分支会
        // `request_root_rebuild` + 置脏重绘；尺寸赋值是同值，视口不变。
        runtime.dispatch_event(@core.Resize(runtime.size()))
      None => ()
    }
  })
  let runtime = @runtime.new_program_with_dimensions(
    program=@studio_app.program(
      // WASM 插件系统(M8)：浏览器原生 WebAssembly 后端。
      // JS 侧在页面启动时**预实例化**插件（浏览器 instantiate 是异步的，
      // 而宿主→插件的调用必须同步）——宿主侧读已就绪的插件 id 列表。
      plugin_bridge=@plugin_runtime_web.plugin_bridge_for(
        @plugin_runtime_web.PluginRuntimeWeb::new(),
      ),
      // 画布锚点帧：调色板拖拽的视口→链换算在 update 侧经它取画布
      // 布局帧（键 = "blocks-canvas"）。runtime_ref 在 program 之前
      // 填充（窗口任务创建 runtime 后写回）。
      canvas_frame=fn(key) {
        match runtime_ref.val {
          Some(runtime) => runtime.anchor_frame(key)
          None => None
        }
      },
      environment=@web.app_environment(),
      ai_available=false,
      wall_clock=Some(web_studio_clock),
      apply_locale=tag => {
        match runtime_ref.val {
          Some(runtime) =>
            runtime.set_environment(runtime.environment().with_locale(tag))
          None => ()
        }
      },
      // 运行时检查器：Web 与 native 同权（moui_devtools wasm-gc 安全）。
      runtime_snapshot=() => {
        match runtime_ref.val {
          Some(runtime) => {
            let snapshot = runtime.inspector_snapshot()
            Some({
              summary: @devtools.snapshot_summary(snapshot).text(),
              report: @devtools.inspector_report_text(snapshot),
            })
          }
          None => None
        }
      },
    ),
    width=1280.0,
    height=800.0,
  )
  runtime_ref.val = Some(runtime)
  @runtime.run_app("MoUI Studio", runtime)
  .render_all(@webgpu_adapter.from_env())
  .backend(@web.entry())
  .run()
}
