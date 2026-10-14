///|
/// 代码工程写盘的壳侧集成测试（M6①）。纯生成逻辑（双腿文本/落点/diff/
/// 迁移器）已迁至 @proj 插件，对应单测在 plugins/project/code_project_wbtest.mbt；
/// 本文件只保留「选择模板 → 事件总线发出写盘」的组合根编排契约。

///|
test "select template emits code project write only with a write target" {
  // 无在册工程、无迁移目录：与旧「置位后组合根静默清位」同语义——不发事件
  let applied = @app.load_template_program(@app.initial_model(), 1)
  assert_eq(applied.outbox.length(), 0)
  // 有在册工程：事件带目标目录与双腿全文（M1 事件化，组合根监听器写盘）
  let imported = @app.update_with_services(
      @app.initial_model(compile_track_available=true),
      ProjectScanCompleted(Success(Ok(Single(counter_source())))),
      @services.AppServices::new(),
    ).0
  let emitted = @app.load_template_program(imported, 1)
  match emitted.outbox {
    // import 步已入队 EvProjectsDirty(真实程序每趟排空)；装载尾部是
    // 代码工程写盘 + IR 快照两个事件
    [
      ..,
      EvCodeProjectWrite(dir, form_mbt, handlers_mbt, _),
      EvProgramSnapshotWrite(_, _),
    ] => {
      assert_true(dir.contains("/"))
      assert_true(form_mbt.contains("place(@views."))
      assert_true(handlers_mbt.contains("fn studio_"))
    }
    _ => fail("应发出代码工程写盘事件")
  }
}
