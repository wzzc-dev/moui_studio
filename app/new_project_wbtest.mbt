///|
/// 新建工程的壳侧测试：完成态的工程身份、写盘事务相位、快照恢复。生成面
/// （骨架文件集、模块名归一、目录守卫、模板下标）的测试随代码住在
/// `services/scaffold`。

///|
/// 完成态的工程身份按**路径**从落盘计划推：每个带 moon.pkg 的目录都是包，
/// `pub fn program` 由内容探测（与 walk 同口径）。旧口径读队列下标 +
/// 硬编码文件名，骨架加文件就会静默改掉身份。
test "project identity derives from planned paths, not queue positions" {
  let root = "/tmp/folder-projects-identity"
  let module_name = @scaffold.module_name_from_root(root)
  let files = @scaffold.skeleton_files(
    root,
    module_name,
    @proposals.sample_hello(),
  )
  let source = @project.project_source_from_plan(root, files)
  assert_eq(source.root, root)
  assert_true(source.module_manifest.contains("name = \"\{module_name}\""))
  let rels : Array[String] = []
  for entry in source.package_sources {
    rels.push(entry.0)
  }
  // 内核包 + app + 两个入口包都在；`.studio` 无 moon.pkg 不算包
  assert_true(rels.contains("app"))
  assert_true(rels.contains("native_app"))
  assert_true(rels.contains("web_wasm"))
  assert_true(rels.contains("domain/ir"))
  assert_false(rels.contains(".studio"))
  // 程序包探测只看内容：组合根是唯一的 `pub fn program` 挂载点
  let program_rels : Array[String] = []
  for entry in source.package_sources {
    if entry.2 {
      program_rels.push(entry.0)
    }
  }
  assert_eq(program_rels, ["app"])
  let app_files : Array[String] = []
  for entry in source.package_sources {
    if entry.0 == "app" {
      for name in entry.3 {
        app_files.push(name)
      }
    }
  }
  assert_true(app_files.contains("handlers.mbt"))
  assert_true(app_files.contains("runner.mbt"))
  // 骨架布局探测（插件侧）：首个程序包带 runner.mbt → 提案采纳要刷新内嵌 IR
  match project_record_from_source(source) {
    Ok(record) => assert_true(@proj.is_studio_app_bundle(record))
    Err(reason) => fail("骨架应能建成工程记录：\{reason}")
  }
}

///|
/// 快照恢复：激活工程读回 `<root>/.studio/program.json` → 有快照且无未保存
/// 工作时载入（load_program_state），程序基线对齐、program_root 记账。
test "program snapshot restores the stored program" {
  let model = initial_model()
  let json = @codec.encode_program(@proposals.sample_drill())
  let restored = update_with_services(
      model,
      ProjectProgramLoaded(Success(json)),
      @services.AppServices::new(),
    ).0
  assert_eq(
    @ir.program_signature(restored.program),
    @ir.program_signature(@proposals.sample_drill()),
  )
  // 基线对齐：恢复不产生脏标记
  assert_false(program_has_work(restored))
  // 坏快照：结构化报错，不载入
  let broken = update_with_services(
      model,
      ProjectProgramLoaded(Success("不是 IR")),
      @services.AppServices::new(),
    ).0
  assert_true(broken.notice.contains("快照"))
}

///|
/// 事务边界：写盘中途失败（或取消）不再留「半套骨架」——草稿翻到删除相，
/// 队列截成已写前缀、游标归零，删除回执逐条推进，删完才清草稿。
/// 这里断的是**状态机**（相位/截断/收尾）；`delete_file` 的真落盘在假
/// FileServices 下不执行，由 native 手工验收覆盖。
test "an aborted skeleton write switches to the delete phase" {
  let root = "/tmp/folder-projects-rollback"
  let draft : NewProjectDraft = {
    template_index: -1,
    program: @proposals.sample_hello(),
    root,
    module_name: "folder-projects-rollback",
    files: [(root + "/moon.mod", "a"), (root + "/app/moon.pkg", "b")],
    done: 2,
    rolling_back: false,
  }
  let model = { ..initial_model(), new_project: Some(draft), }
  let services = @services.AppServices::new()
  let error = @services.ServiceError::new(code="fs", message="磁盘只读")
  let (rolling, _effect) = update_with_services(
    model,
    NewProjectQueueResult(Failure(error)),
    services,
  )
  match rolling.new_project {
    Some(draft) => {
      assert_true(draft.rolling_back)
      assert_eq(draft.done, 0)
      // 队列截成已写前缀；通知给的是失败原因
      assert_eq(draft.files.length(), 2)
      assert_true(rolling.notice.contains("磁盘只读"), msg=rolling.notice)
    }
    None => fail("删除相要留草稿推进游标")
  }
  let (half, _e) = update_with_services(
    rolling,
    NewProjectQueueResult(Success(())),
    services,
  )
  match half.new_project {
    Some(draft) => assert_eq(draft.done, 1)
    None => fail("一条删除回执只推进一格")
  }
  let (clean, _e) = update_with_services(
    half,
    NewProjectQueueResult(Success(())),
    services,
  )
  assert_true(clean.new_project is None)
  // 一个字都没写就取消：队列为空，直接清草稿且不弹通知
  let fresh : NewProjectDraft = {
    ..draft,
    files: [],
    done: 0,
    rolling_back: false,
  }
  let (quiet, _e) = update_with_services(
    { ..initial_model(), new_project: Some(fresh), },
    NewProjectQueueResult(Cancelled),
    services,
  )
  assert_true(quiet.new_project is None)
  assert_eq(quiet.notice, "")
}
