///|
/// 资源管理器「导入后默认只画根行」的行为回归（用户口径）。
///
/// 折叠集是**用户状态**:只有首次导入（或 boot 恢复）才种根键;同 root 的
/// 重扫刷新（新建/删除文件后的自动刷新、ExplorerRefresh）必须保留用户的
/// 展开态——否则树会在每次文件操作后被折回去。

///|
/// 单工程导入:默认只有根行,展开根行后子树才出现。
test "导入后工程根默认折叠,展开后子树可见" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let collapsed = explorer_rows_for_test(imported)
  assert_true(collapsed.contains("root-0"), msg="导入后应画工程根行")
  assert_false(
    collapsed.contains("dir-0:app"),
    msg="导入默认折叠时子目录不应可见",
  )
  let expanded = explorer_apply(imported, ToggleProjectDirAt(0, ""))
  let rows = explorer_rows_for_test(expanded)
  assert_true(
    rows.contains("dir-0:app"),
    msg="展开根行后子目录应可见",
  )
  assert_true(
    rows.contains("file-0:app/app.mbt"),
    msg="展开根行后文件应可见",
  )
}

///|
/// 工作区导入同口径:默认只有工作区根一行,展开后成员目录出现。
test "工作区导入后根行默认折叠" {
  let services = @services.AppServices::new()
  let scan : @project.WorkspaceScan = {
    root: "/ws",
    loaded: [{ ..explorer_source(), root: "/ws/tools", }],
    failed: [],
    root_dirs: [@project.ScannedDir::{ rel_path: "", files: ["gradlew"], }],
  }
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Workspace(scan)))),
      services,
    ).0
  let collapsed = explorer_rows_for_test(imported)
  assert_true(collapsed.contains("root--1"), msg="应有工作区根行")
  assert_false(
    collapsed.contains("dir-0:tools"),
    msg="工作区导入默认折叠时成员目录不应可见",
  )
  let expanded = explorer_apply(
    imported,
    ToggleProjectDirAt(WORKSPACE_ROOT_INDEX, ""),
  )
  assert_true(
    explorer_rows_for_test(expanded).contains("dir-0:tools"),
    msg="展开工作区根后成员目录应可见",
  )
}

///|
/// 重扫刷新（同 root 反复导入）不得重置展开态——否则新建/删除文件后
/// 树会被折回去,用户每次操作都要重新展开。
test "重扫刷新保留用户的展开态" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let expanded = explorer_apply(imported, ToggleProjectDirAt(0, ""))
  assert_true(
    expanded.project_tree_collapsed.is_empty(),
    msg="展开后折叠集应为空",
  )
  let rescanned = update_with_services(
      expanded,
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  assert_true(
    rescanned.project_tree_collapsed.is_empty(),
    msg="同 root 重扫应保留展开态,不能折回",
  )
}

///|
/// boot 恢复与导入同口径:恢复完成后树默认折叠,只画根行。
test "boot 恢复后工程根默认折叠" {
  let services = @services.AppServices::new()
  let base = { ..initial_model(), projects_restore_pending: 1, }
  let (restored, _) = update_with_services(
    base,
    ProjectRestoreScanCompleted(Success(Ok(Single(explorer_source())))),
    services,
  )
  assert_true(
    restored.project_tree_collapsed.contains(root_collapse_key(0, "")),
    msg="恢复后工程根应种折叠键",
  )
  assert_false(
    explorer_rows_for_test(restored).contains("dir-0:app"),
    msg="恢复后默认只画根行",
  )
}
