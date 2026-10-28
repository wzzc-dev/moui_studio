///|
/// 插件运行时宿主（native）：队列 + worker + 回调回执。
///
/// 形态照 `services/provider_native`（Owner + Queue + worker loop）：
/// UI 线程只**同步入队**，插件加载与调用全在 worker 上跑——插件是
/// 不受信任的代码，绝不能在 UI 线程同步执行（一个死循环插件会把界面
/// 冻住）。
///
/// **串行化**：wasmoon 的 `Store` 绑定创建线程 → 同一插件的调用必须
/// 串行。worker 循环本身是串行的（一次取一个 job），因此天然满足
/// 「同插件不并发」；不同插件共用一个 worker 也会串行——插件数量少
/// 的场景下这是可接受的（插件调用不是热路径）。

///|
/// 插件宿主：持有运行时与回执回调。
pub(all) struct PluginOwner {
  queue : @async.Queue[PluginJob]
}

///|
/// 一个插件作业。
pub(all) enum PluginJob {
  /// 加载全部插件（回执：加载结果数组）
  Load(
    host~ : HostBridge,
    on_result~ : (Array[@plugin_contract.PluginLoadResult]) -> Unit
  )
  /// 调用某个插件（回执：响应文本或错误）
  Call(
    plugin_id~ : String,
    request~ : String,
    on_result~ : (Result[String, String]) -> Unit
  )
  /// 卸载某个插件
  Unload(plugin_id~ : String)
  /// 安装插件（回执：插件 id 或失败原因）
  ///
  /// 走 worker 是因为要**复制整个目录**（大插件 = 大量 I/O）——
  /// 在 UI 线程做会把界面卡住。
  Install(source_dir~ : String, on_result~ : (Result[String, String]) -> Unit)
  /// 卸载插件（删目录；回执：插件 id 或失败原因）
  Remove(plugin_id~ : String, on_result~ : (Result[String, String]) -> Unit)
  /// 关闭全部（Studio 退出时）
  Shutdown
}

///|
/// 新建插件宿主。
pub fn PluginOwner::new() -> PluginOwner {
  { queue: @async.Queue(kind=Unbounded), }
}

///|
/// 同步入队（UI 线程调用）。队列无界，满不是失败模式。
pub fn plugin_submit_load(
  owner : PluginOwner,
  host : HostBridge,
  on_result : (Array[@plugin_contract.PluginLoadResult]) -> Unit,
) -> Unit {
  ignore(owner.queue.try_put(Load(host~, on_result~)) catch { _ => false })
}

///|
/// 同步入队一个插件调用。
pub fn plugin_submit_call(
  owner : PluginOwner,
  plugin_id : String,
  request : String,
  on_result : (Result[String, String]) -> Unit,
) -> Unit {
  ignore(
    owner.queue.try_put(Call(plugin_id~, request~, on_result~)) catch {
      _ => false
    },
  )
}

///|
/// 同步入队一个卸载。
pub fn plugin_submit_unload(owner : PluginOwner, plugin_id : String) -> Unit {
  ignore(owner.queue.try_put(Unload(plugin_id~)) catch { _ => false })
}

///|
/// 同步入队一个安装。
pub fn plugin_submit_install(
  owner : PluginOwner,
  source_dir : String,
  on_result : (Result[String, String]) -> Unit,
) -> Unit {
  ignore(
    owner.queue.try_put(Install(source_dir~, on_result~)) catch {
      _ => false
    },
  )
}

///|
/// 同步入队一个卸载（删目录）。
pub fn plugin_submit_remove(
  owner : PluginOwner,
  plugin_id : String,
  on_result : (Result[String, String]) -> Unit,
) -> Unit {
  ignore(
    owner.queue.try_put(Remove(plugin_id~, on_result~)) catch {
      _ => false
    },
  )
}

///|
/// 插件 worker 循环：取作业、执行、回执。
///
/// 循环体是**同步**的（一次一个作业）——插件调用不并发，Store 亲和性
/// 得到保证。
pub async fn plugin_worker_loop(
  owner : PluginOwner,
  runtime : PluginRuntime,
) -> Unit {
  while true {
    let job = owner.queue.get()
    match job {
      Load(host~, on_result~) => {
        let results = runtime.load_all(host) catch {
          error => {
            on_result([
              @plugin_contract.Failed(
                plugin_id="",
                reason="插件加载异常：\{error}",
              ),
            ])
            continue
          }
        }
        on_result(results)
      }
      Call(plugin_id~, request~, on_result~) => {
        let response = runtime.call(plugin_id, request)
        on_result(response)
      }
      Unload(plugin_id~) => runtime.unload(plugin_id)
      Install(source_dir~, on_result~) =>
        // 装完**重扫**——新插件要立刻出现在列表里（否则用户装完看不见，
        // 以为没装上）。回执先给，再由 UI 侧发起重扫。
        match install_plugin(runtime.plugins_root, source_dir) {
          Installed(plugin_id) => on_result(Ok(plugin_id))
          Rejected(reason) => on_result(Err(reason))
        }
      Remove(plugin_id~, on_result~) => {
        // 先从运行时卸载（释放内存/配额），再删目录。
        // 顺序重要：删目录后若进程崩溃，下次启动会重新扫到一个
        // 半残的插件目录。
        runtime.unload(plugin_id)
        match remove_plugin(runtime.plugins_root, plugin_id) {
          Removed(id) => on_result(Ok(id))
          Rejected(reason) => on_result(Err(reason))
        }
      }
      Shutdown => {
        runtime.unload_all()
        break
      }
    }
  }
}

///|
/// 构造给 app 用的插件运行时门面（跨平台契约）。
///
/// 门面把「入队 + 回执」包装成 app 需要的形状。
///
/// **同步 `call` 的诚实边界**：插件调用是**异步**的（worker 上跑），
/// 同步门面在 worker 尚未完成时**拿不到结果**——因此它返回明确的
/// `Err`，**不假装成功**。app 侧真正的调用路径是「经 `Effect::dispatch`
/// 走 `plugin_call_and_reply` 这条回执通道」（见 `plugin_owner.mbt` 的
/// `plugin_call_and_reply`）。
pub fn plugin_bridge_for(
  owner : PluginOwner,
  runtime : PluginRuntime,
  host : HostBridge,
) -> @plugin_contract.PluginBridge {
  {
    available: true,
    load: fn(on_result) { plugin_submit_load(owner, host, on_result) },
    unload: fn(plugin_id) { plugin_submit_unload(owner, plugin_id) },
    call: fn(plugin_id, request, on_result) {
      // 入队 → worker 上跑插件 → 回执。**不在 UI 线程同步等**（等回执
      // 会冻住界面）。
      plugin_submit_call(owner, plugin_id, request, on_result)
    },
    is_loaded: fn(plugin_id) { runtime.is_loaded(plugin_id) },
    // native 端有文件系统 → 能装能卸。
    can_install: true,
    install: fn(source_dir, on_result) {
      plugin_submit_install(owner, source_dir, on_result)
    },
    remove: fn(plugin_id, on_result) {
      plugin_submit_remove(owner, plugin_id, on_result)
    },
    plugins_root: runtime.plugins_root(),
  }
}

///|
/// 插件调用 + 回执：**在 worker 上跑**，结果经回调送回。
///
/// app 侧的 `PluginAction` 消息臂经 `Effect::dispatch` 调它——效果泵
/// 在 worker 上执行（不在 UI 线程），因此插件代码不会冻住界面。
pub fn plugin_call_and_reply(
  owner : PluginOwner,
  plugin_id : String,
  request : String,
  on_result : (Result[String, String]) -> Unit,
) -> Unit {
  plugin_submit_call(owner, plugin_id, request, on_result)
}

///|
/// 插件加载 + 回执：在 worker 上跑，结果经回调送回。
pub fn plugin_load_and_reply(
  owner : PluginOwner,
  host : HostBridge,
  on_result : (Array[@plugin_contract.PluginLoadResult]) -> Unit,
) -> Unit {
  plugin_submit_load(owner, host, on_result)
}
