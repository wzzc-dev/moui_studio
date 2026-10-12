///|
/// 资源管理器「导入后整棵树默认折叠」的行为回归（用户口径）。
///
/// 折叠集是**用户状态**:只有首次导入（或 boot 恢复）才种整棵树的键;
/// 同 root 的重扫刷新（新建/删除文件后的自动刷新、ExplorerRefresh）必须
/// 保留用户的展开态——否则树会在每次文件操作后被折回去。

///|
/// 单工程导入:默认只有根行,展开根行后只见子目录,再展开子目录才见文件。
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
  assert_false(
    rows.contains("file-0:app/app.mbt"),
    msg="子目录未展开时它的文件不应可见（整棵树逐层折叠）",
  )
  let deeper = explorer_apply(expanded, ToggleProjectDirAt(0, "app"))
  assert_true(
    explorer_rows_for_test(deeper).contains("file-0:app/app.mbt"),
    msg="逐层展开子目录后文件才可见",
  )
}

///|
/// 工作区导入同口径:默认只有工作区根一行,展开后成员目录出现;
/// 成员目录自己也是折叠的,再展开才见成员内部。
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
    ToggleProjectDirAt(@proj.WORKSPACE_ROOT_INDEX, ""),
  )
  let rows = explorer_rows_for_test(expanded)
  assert_true(
    rows.contains("dir-0:tools"),
    msg="展开工作区根后成员目录应可见",
  )
  assert_false(
    rows.contains("dir-0:app"),
    msg="成员目录未展开时它的子目录不应可见",
  )
  let deeper = explorer_apply(expanded, ToggleProjectDirAt(0, "tools"))
  assert_true(
    explorer_rows_for_test(deeper).contains("dir-0:app"),
    msg="逐层展开成员目录后它的子目录才可见",
  )
}

///|
/// 嵌套成员（`examples/terminal`）的每一层中间目录默认都折上:
/// 展开工作区根后先见 `examples`,再展开才见成员行。
test "嵌套成员:中间目录与成员行都默认折叠" {
  let services = @services.AppServices::new()
  let nested = {
    ..explorer_source(),
    root: "/ws/examples/terminal",
    module_manifest: (
      #|name = "examples/terminal"
      #|version = "0.1.0"
      #|preferred_target = "native"
    ),
  }
  let scan : @project.WorkspaceScan = {
    root: "/ws",
    loaded: [nested],
    failed: [],
    root_dirs: [],
  }
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Workspace(scan)))),
      services,
    ).0
  let expanded = explorer_apply(
    imported,
    ToggleProjectDirAt(@proj.WORKSPACE_ROOT_INDEX, ""),
  )
  let rows = explorer_rows_for_test(expanded)
  assert_true(
    rows.contains("dir--1:examples"),
    msg="展开根后应见中间目录",
  )
  assert_false(
    rows.contains("dir-0:examples/terminal"),
    msg="中间目录未展开时成员行不应可见",
  )
  let deeper = explorer_apply(
    expanded,
    ToggleProjectDirAt(@proj.WORKSPACE_ROOT_INDEX, "examples"),
  )
  assert_true(
    explorer_rows_for_test(deeper).contains("dir-0:examples/terminal"),
    msg="展开中间目录后成员行才可见",
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
  assert_false(
    expanded.project_state.project_tree_collapsed.contains(
      root_collapse_key(0, ""),
    ),
    msg="展开根后根键应被摘掉",
  )
  assert_true(
    expanded.project_state.project_tree_collapsed.contains(
      root_collapse_key(0, "app"),
    ),
    msg="根展开不影响子目录的折叠记录",
  )
  let rescanned = update_with_services(
      expanded,
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  assert_false(
    rescanned.project_state.project_tree_collapsed.contains(
      root_collapse_key(0, ""),
    ),
    msg="同 root 重扫应保留展开态,不能把根折回",
  )
  assert_true(
    rescanned.project_state.project_tree_collapsed.contains(
      root_collapse_key(0, "app"),
    ),
    msg="同 root 重扫应保留子目录折叠记录",
  )
}

///|
/// boot 恢复与导入同口径:恢复完成后整棵树默认折叠,只画根行。
test "boot 恢复后工程根默认折叠" {
  let services = @services.AppServices::new()
  let base = { ..initial_model(), projects_restore_pending: 1, }
  let (restored, _) = update_with_services(
    base,
    ProjectRestoreScanCompleted(Success(Ok(Single(explorer_source())))),
    services,
  )
  assert_true(
    restored.project_state.project_tree_collapsed.contains(
      root_collapse_key(0, ""),
    ),
    msg="恢复后工程根应种折叠键",
  )
  assert_true(
    restored.project_state.project_tree_collapsed.contains(
      root_collapse_key(0, "app"),
    ),
    msg="恢复后子目录也应种折叠键",
  )
  assert_false(
    explorer_rows_for_test(restored).contains("dir-0:app"),
    msg="恢复后默认只画根行",
  )
}
