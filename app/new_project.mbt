///|
/// 新建工程（folder projects）的**壳侧状态机**：选目录 → 生成骨架 →
/// 逐文件写盘 → 完成态注册工程并装载模板程序；写盘中途失败/取消则把同一
/// 队列翻到删除相（回滚）。落盘计划的生成口径在 `@scaffold`
/// （`services/scaffold`），这里只有 Effect 编排。
///
/// 布局真源 form.mbt **尚未**进骨架（`on_click` 与 @views 的 Msg 类型
/// 不兼容，见 `@scaffold.skeleton_files` 内的注释）——ADR 0037 的这条
/// 目前只有事件真源 handlers.mbt 兑现。

///|
/// 新建工程进行中的草稿：模板 IR + 待处理文件队列（游标推进，与
/// PreviewWriteState 同款节奏——逐文件 ServiceTask，回执推进游标）。
/// `root` / `module_name` 在目录选定后回填，完成态按**路径**取工程身份。
/// 同一个队列有两种相位：写入相逐项 `write_text`，回滚相把队列换成
/// 「已写前缀」后逐项 `delete_file`——游标机器只有一套。
pub(all) struct NewProjectDraft {
  /// 模板下标（-1 = 空白程序）；完成步取它装载程序内存态
  template_index : Int
  /// 模板 IR（骨架文件与完成态程序的同源快照）
  program : @ir.StudioProgram
  /// 工程根绝对路径（空 = 目录尚未选定）
  root : String
  /// 模块名：`root` 的目录名归一，与骨架内容同源
  module_name : String
  /// 待处理文件队列：绝对路径 → 内容（回滚相只用到路径）
  mut files : Array[(String, String)]
  /// 队列游标（回滚相 = 已发删除数）
  mut done : Int
  /// 回滚相：写盘中途失败/取消后翻真，此后游标推进靠删除回执
  mut rolling_back : Bool
}

///|
/// 队列推进：游标未到队尾就发下一项（写或删，回执回到
/// NewProjectQueueResult 推游标）；写完收尾——注册工程、装载模板程序，
/// 删完收尾——清草稿（通知在翻相时已给过）。
fn advance_new_project_queue(
  model : Model,
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  match model.new_project {
    Some(draft) =>
      if draft.done < draft.files.length() {
        let (path, content) = draft.files[draft.done]
        let task = if draft.rolling_back {
          services
          .files()
          .delete_file(path)
          .effect(map=r => NewProjectQueueResult(r))
        } else {
          services
          .files()
          .write_text(path, content)
          .effect(map=r => NewProjectQueueResult(r))
        }
        (model, task)
      } else if draft.rolling_back {
        ({ ..model, new_project: None, }, @moui.Effect::none())
      } else {
        (finish_new_project(model, services), @moui.Effect::none())
      }
    None => (model, @moui.Effect::none())
  }
}

///|
/// 翻到回滚相：队列截成「已写前缀」、游标归零、逐项删。Studio 的
/// FileServices 没有删目录能力，`ensure_parent_dirs` 建的空目录留在原地——
/// 由下次 `dir_is_writable` 守卫与重新生成覆盖，不再留「半套骨架」的文件。
fn start_new_project_rollback(
  model : Model,
  services : @services.AppServices,
  message? : String = "",
) -> (Model, @moui.Effect[Msg]) {
  match model.new_project {
    Some(draft) => {
      draft.files = draft.files[:draft.done].to_owned()
      draft.done = 0
      draft.rolling_back = true
      let next = if message == "" {
        model
      } else {
        with_notice(model, message, true)
      }
      advance_new_project_queue(next, services)
    }
    None => (model, @moui.Effect::none())
  }
}

///|
/// 新建工程完成态：合成 ProjectSource（内容与刚落盘的骨架同源，免重读）
/// 走 import_single_source 的既有管道——注册 ProjectRecord、置活跃、写
/// 预览 harness——再装载模板程序（撤销点/运行态/选中态重置同一纪律），
/// 记 program_root。骨架文件已含 IR 快照，恢复流下次激活即可用。
fn finish_new_project(model : Model, services : @services.AppServices) -> Model {
  match model.new_project {
    Some(draft) => {
      if draft.root == "" {
        // 目录还没选定就走到完成步 = 状态机被外部打断，丢草稿不猜身份
        return { ..model, new_project: None, }
      }
      let source = @project.project_source_from_plan(draft.root, draft.files)
      let (imported, _effect) = import_single_source(
        model,
        services.files(),
        source,
      )
      let loaded = load_template_program(imported, draft.template_index)
      let done = push_toast(
        loaded,
        text_with(translator(loaded), "app.project.created", [("a", draft.root)]),
        false,
      )
      {
        ..done,
        program_root: draft.root,
        new_project: None,
        new_project_confirmed: false,
      }
    }
    None => model
  }
}

///|
/// NewProjectRequested 服务臂：一次性放行标记 / 有未保存工作转确认 /
/// Web 无目录选择能力显式降级。放行 = 置草稿并发起目录选择。
fn new_project_requested(
  model : Model,
  index : Int,
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  let proceed = model.new_project_confirmed || !program_has_work(model)
  let pending_request = model.pending_confirm is Some(_)
  if !proceed && !pending_request {
    // 有未保存工作且未确认：转确认请求（确认续行重投本消息）
    update_pure(model, RequestConfirm(CkNewProject(index)))
  } else if proceed && model.export_available {
    let program = @scaffold.template_program(index)
    let draft : NewProjectDraft = {
      template_index: index,
      program,
      root: "",
      module_name: "",
      files: [],
      done: 0,
      rolling_back: false,
    }
    let options = @services.FileDialogOptions::new(
      title=text(translator(model), "app.dialog.new_project"),
    )
    (
      { ..model, new_project: Some(draft), new_project_confirmed: false, },
      services
      .files()
      .pick_directory(options~)
      .effect(map=r => NewProjectRootPicked(r)),
    )
  } else if !model.export_available {
    // Web 没有可写路径的目录选择（与导出同口径）：显式降级不假按钮
    (
      with_notice(
        model,
        text(translator(model), "app.project.new_native_only"),
        true,
      ),
      @moui.Effect::none(),
    )
  } else {
    // 确认卡已在场（先前的守卫拦截）：不再重复请求
    (model, @moui.Effect::none())
  }
}

///|
/// NewProjectRootPicked 服务臂：目录确定 → 算骨架文件集 → 建目录树 →
/// 起写盘队列。取消 = 清草稿（此时还没落一个字，无需回滚）；目录不可用
/// （已有 moon.mod 等）= 结构化拒绝。
fn new_project_root_picked(
  model : Model,
  result : @services.ServiceTaskResult[String],
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  match result {
    Success(root) =>
      match model.new_project {
        Some(draft) => {
          let module_name = @scaffold.module_name_from_root(root)
          let files = @scaffold.skeleton_files(root, module_name, draft.program)
          match @scaffold.dir_is_writable(root) {
            Err(message) =>
              (
                with_notice({ ..model, new_project: None, }, message, true),
                @moui.Effect::none(),
              )
            Ok(_) => {
              // 守卫过了才建目录树（native write_text 不建父目录）
              @scaffold.ensure_parent_dirs(files)
              let draft = { ..draft, root, module_name, files, }
              advance_new_project_queue(
                { ..model, new_project: Some(draft), },
                services,
              )
            }
          }
        }
        None => (model, @moui.Effect::none())
      }
    Failure(error) =>
      (
        with_notice({ ..model, new_project: None, }, error.message, true),
        @moui.Effect::none(),
      )
    Cancelled => ({ ..model, new_project: None, }, @moui.Effect::none())
  }
}

///|
/// NewProjectQueueResult 服务臂：回滚相只推游标（删除失败不重试、不卡队列）；
/// 写入相成功推游标、失败或取消翻到回滚相——事务边界是「要么整套骨架，要么
/// 只剩空目录」，不再有「半套骨架留在磁盘」。
fn new_project_queue_result(
  model : Model,
  result : @services.ServiceTaskResult[Unit],
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  match model.new_project {
    Some(draft) if draft.rolling_back => {
      draft.done = draft.done + 1
      advance_new_project_queue(model, services)
    }
    Some(draft) =>
      match result {
        Success(_) => {
          draft.done = draft.done + 1
          advance_new_project_queue(model, services)
        }
        Failure(error) =>
          start_new_project_rollback(model, services, message=error.message)
        Cancelled => start_new_project_rollback(model, services)
      }
    None => (model, @moui.Effect::none())
  }
}

///|
/// SetActiveProject 服务臂：纯转移照走 update_pure；目标工程与当前程序
/// 不同源时异步读 IR 快照恢复（folder projects 的「重开继续编辑」）。
/// 无快照（普通导入工程）= Failure 静默，不弹通知。
fn activate_project_with_restore(
  model : Model,
  index : Int,
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  let (next, effect) = update_pure(model, ProjectOp(SetActiveProject(index)))
  match active_project_of(next) {
    Some(record) =>
      if record.root != next.program_root {
        (
          next,
          @moui.Effect::batch([
            effect,
            services
            .files()
            .read_text("\{record.root}/\{@scaffold.PROGRAM_SNAPSHOT_REL}")
            .effect(map=r => ProjectProgramLoaded(r)),
          ]),
        )
      } else {
        (next, effect)
      }
    None => (next, effect)
  }
}

///|
/// 工程程序快照回执：有快照且当前程序无未保存工作 → 载入恢复；有未保存
/// 工作 → 不打扰，引导先保存（显式降级，不静默覆盖）；坏快照 → 结构化
/// 报错；文件不存在（普通导入工程）= 常态，静默。
fn project_program_loaded(
  model : Model,
  result : @services.ServiceTaskResult[String],
) -> (Model, @moui.Effect[Msg]) {
  match result {
    Success(json) =>
      match @codec.decode_program(json) {
        Ok(program) =>
          if program_has_work(model) {
            (
              with_notice(
                model,
                text(translator(model), "app.project.snapshot_skip"),
                true,
              ),
              @moui.Effect::none(),
            )
          } else {
            let root = match active_project_of(model) {
              Some(record) => record.root
              None => ""
            }
            (load_program_state(model, program, root), @moui.Effect::none())
          }
        Err(_) =>
          (
            with_notice(
              model,
              text(translator(model), "app.project.snapshot_bad"),
              true,
            ),
            @moui.Effect::none(),
          )
      }
    Failure(_) | Cancelled => (model, @moui.Effect::none())
  }
}

///|
/// 代码工程写盘效果组装：handlers.mbt 恒写；form.mbt / project_data.mbt
/// 按布局给载荷（空串 = 该布局不含——应用骨架无布局真源、普通导入工程
/// 无内嵌 IR，见 new_project.mbt 与 events.mbt 的发出点）。
/// 纯生成逻辑（双腿文本/落点）已在 @proj 插件，本函数只做壳侧写盘编排。
pub fn code_project_write_effect(
  files : @services.FileServices,
  dir~ : String,
  form_mbt~ : String,
  handlers_mbt~ : String,
  project_data~ : String,
) -> @moui.Effect[Msg] {
  let form_write = if form_mbt != "" {
    [
      files
      .write_text("\{dir}/form.mbt", form_mbt)
      .effect(map=r => CodeProjectSaved(r)),
    ]
  } else {
    []
  }
  let data_write = if project_data != "" {
    [
      files
      .write_text("\{dir}/project_data.mbt", project_data)
      .effect(map=r => CodeProjectSaved(r)),
    ]
  } else {
    []
  }
  @moui.Effect::batch([
    @moui.Effect::batch(form_write),
    files
    .write_text("\{dir}/handlers.mbt", handlers_mbt)
    .effect(map=r => CodeProjectSaved(r)),
    @moui.Effect::batch(data_write),
  ])
}
