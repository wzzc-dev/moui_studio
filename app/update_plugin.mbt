///|
/// 插件 update 分支：加载回执、面板视图请求、插件动作。
///
/// 纯状态迁移，零 Effect——**插件调用是服务层的事**，走 `Effect::dispatch`
/// 由组合根的 worker 执行，回执再经 `Msg` 回来。这样「状态只在 update 里
/// 变」的纪律不被破坏（插件不能直接改 Model）。
///
/// 动作回环：插件 UI 交互 → `PluginAction` → update 记下动作 → 经
/// `Effect::dispatch` 回问插件 → 插件响应 → `PluginPanelSpec` → 缓存
/// → 下次渲染取新视图。

///|
/// 插件动作的请求载荷（发给插件的统一 JSON）。
///
/// **转发到契约层**——请求格式是**协议**，两端（native / web）必须发
/// 一样的请求。契约层是唯一定义处（`kernel/plugin_contract`）。
pub fn plugin_action_request(
  plugin_id : String,
  action_id : String,
  payload : String,
) -> String {
  @plugin_contract.plugin_action_request(plugin_id, action_id, payload)
}

///|
/// 插件视图请求的载荷（宿主向插件要一个面板视图）。
pub fn plugin_view_request(
  plugin_id : String,
  panel_id : String,
  payload : String,
) -> String {
  @plugin_contract.plugin_view_request(plugin_id, panel_id, payload)
}

///|
/// 处理插件扫描/加载回执：写进状态切片。
pub fn apply_plugin_scan(
  model : Model,
  results : Array[@plugin_contract.PluginLoadResult],
  available : Bool,
) -> Model {
  {
    ..model,
    plugin_state: model.plugin_state
    .apply_load_results(results)
    .set_available(available),
  }
}

///|
/// 处理插件面板视图协议到达：缓存起来（下次渲染取）。
pub fn apply_plugin_panel_spec(
  model : Model,
  plugin_id : String,
  panel_id : String,
  spec : String,
) -> Model {
  {
    ..model,
    plugin_state: model.plugin_state.set_panel_spec(plugin_id, panel_id, spec),
  }
}

///|
/// 插件管理面板：打开 / 关闭 / 选中。
pub fn apply_plugin_manager_open(model : Model) -> Model {
  { ..model, plugin_manager: model.plugin_manager.open_manager(), }
}

///|
/// 插件管理面板：关闭。
pub fn apply_plugin_manager_close(model : Model) -> Model {
  { ..model, plugin_manager: model.plugin_manager.close_manager(), }
}

///|
/// 插件管理面板：选中某个插件。
pub fn apply_plugin_manager_select(model : Model, plugin_id : String) -> Model {
  { ..model, plugin_manager: model.plugin_manager.select(plugin_id), }
}

///|
/// 插件管理面板：开始一次安装/卸载（标记忙碌）。
pub fn apply_plugin_manager_busy(model : Model, plugin_id : String) -> Model {
  { ..model, plugin_manager: model.plugin_manager.set_busy(plugin_id), }
}

///|
/// 插件管理面板：写操作回执（成功/失败都要说话）。
pub fn apply_plugin_manager_notice(
  model : Model,
  message : String,
  is_error : Bool,
) -> Model {
  {
    ..model,
    plugin_manager: model.plugin_manager.set_notice(message, is_error),
  }
}

///|
/// 插件管理面板：安装回执。
///
/// **装完要重扫**——新插件必须立刻出现在列表里（否则用户装完看不见，
/// 以为没装上）。重扫经 `Effect::dispatch` 走 worker（插件加载是
/// 不受信任代码，不能在 UI 线程跑）。
pub fn apply_plugin_installed(
  model : Model,
  result : Result[String, String],
) -> (Model, @moui.Effect[Msg]) {
  match result {
    Ok(plugin_id) => {
      let updated = apply_plugin_manager_notice(
        model,
        "已安装插件 \{plugin_id}",
        false,
      )
      (updated, @moui.Effect::dispatch(emit => emit(PluginsLoadRequested)))
    }
    Err(reason) =>
      (
        apply_plugin_manager_notice(model, "安装失败：\{reason}", true),
        @moui.Effect::none(),
      )
  }
}

///|
/// 插件管理面板：卸载回执。
///
/// **卸完要重扫**——被卸的插件要从列表里消失（否则用户卸完还看见它，
/// 以为没卸掉）。
pub fn apply_plugin_uninstalled(
  model : Model,
  result : Result[String, String],
) -> (Model, @moui.Effect[Msg]) {
  match result {
    Ok(plugin_id) => {
      // 被卸的插件若正被选中 → 取消选中（详情区不能指向不存在的插件）。
      let cleared = if model.plugin_manager.selected == plugin_id {
        apply_plugin_manager_select(model, "")
      } else {
        model
      }
      let updated = apply_plugin_manager_notice(
        cleared,
        "已卸载插件 \{plugin_id}",
        false,
      )
      (updated, @moui.Effect::dispatch(emit => emit(PluginsLoadRequested)))
    }
    Err(reason) =>
      (
        apply_plugin_manager_notice(model, "卸载失败：\{reason}", true),
        @moui.Effect::none(),
      )
  }
}

///|
/// 需要请求视图的面：插件已加载 + 启用 + 有面板贡献 + **视图还没拿到**
/// 且**还没请求过**。
///
/// 「没请求过」的守卫是必需的：面板每次重渲都会走到这里，没有守卫
/// 就会把 worker 队列打满（同一个面堆积成百上千个请求）。
pub fn panels_needing_view(model : Model) -> Array[(String, String)] {
  let pending : Array[(String, String)] = []
  for descriptor in model.plugin_state.descriptors {
    let plugin_id = descriptor.manifest.id
    if !(descriptor.status is @plugin_contract.Loaded) {
      continue
    }
    if !plugin_active(model, plugin_id) {
      continue
    }
    for (panel_id, _) in model.plugin_state.plugin_panels(plugin_id) {
      if model.plugin_state.has_panel_spec(plugin_id, panel_id) {
        continue
      }
      if model.plugin_state.is_panel_requested(plugin_id, panel_id) {
        continue
      }
      pending.push((plugin_id, panel_id))
    }
  }
  pending
}

///|
/// 标记一批面板为「已请求」。
pub fn mark_panels_requested(
  model : Model,
  panels : Array[(String, String)],
) -> Model {
  let mut state = model.plugin_state
  for (plugin_id, panel_id) in panels {
    state = state.mark_panel_requested(plugin_id, panel_id)
  }
  { ..model, plugin_state: state, }
}
