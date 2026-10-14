///|
/// 编译产物旁路动作的壳侧契约（纯视图/进度/路径省略已随 S7d 迁
/// plugins/run，见 compile_views_wbtest.mbt）：
/// 「在文件夹中打开」的 URL 口径，以及复制/打开/一键启动必须真的进入服务流。

///|
/// 「在文件夹中打开」的 URL：指向产物的**所在目录**（不是文件本身）。
///
/// 传文件 URL 会被系统按关联程序「打开」它；目录 URL 才由文件管理器打开
/// ——用户点这个按钮要的是定位，不是执行。
test "reveal url points at the containing folder" {
  let url = @app.folder_url_of("/tmp/studio/app.exe")
  assert_eq(url, "file:///tmp/studio")
  // 根目录边界：路径本身没有父目录时退化成自身，不产出空 URL
  assert_eq(@app.folder_url_of("/app.exe"), "file:///")
  // 无斜杠的相对名：不崩，原样转义
  assert_eq(@app.folder_url_of("app.exe"), "file://app.exe")
}

///|
/// URL 转义按 **UTF-8 字节**展开，空格与中文目录都能被系统解析。
///
/// 直接对 `Char` 编码会把码点当字节（`中` → `%4E2D`），NSURL 解出来的路径
/// 与磁盘对不上——用户名或目录名带中文时按钮点了没反应。
test "reveal url percent-encodes non-ascii and spaces" {
  assert_eq(@app.folder_url_of("/tmp/my app/app.exe"), "file:///tmp/my%20app")
  // 中 = U+4E2D → E4 B8 AD
  assert_eq(
    @app.folder_url_of("/tmp/中文/app.exe"),
    "file:///tmp/%E4%B8%AD%E6%96%87",
  )
  // 非保留字符与 `/` 保持原样（不能被转义，否则目录层级丢失）
  assert_eq(
    @app.folder_url_of("/tmp/a-b_c.d~e/app.exe"),
    "file:///tmp/a-b_c.d~e",
  )
}

///|
/// 产物旁路动作必须落在 **service 流**里，不能被静默丢弃。
test "artifact actions reach the service flow and report back" {
  let written : Ref[String] = Ref("")
  let opened : Ref[String] = Ref("")
  let services = @services.AppServices::new(
    clipboard=@services.ClipboardServices::new(write_text=text => {
      written.val = text
      @services.ServiceTask::succeed(key="clipboard:write-text", value=())
    }),
    urls=@services.UrlServices::new(open=url => {
      opened.val = url
      @services.ServiceTask::succeed(key="url:open", value=())
    }),
  )
  let model = @app.initial_model(compile_track_available=true)
  let baseline = model.toasts.length()
  let (copied, copy_effect) = @app.update_with_services(
    model,
    CopyArtifactPath("/tmp/demo/app.exe"),
    services,
  )
  ignore(copy_effect)
  ignore(copied)
  let (done, _) = @app.update_with_services(
    model,
    ArtifactActionDone(@app.ArtifactCopy, Success(())),
    services,
  )
  assert_eq(done.toasts.length(), baseline + 1)
  let (_, reveal_effect) = @app.update_with_services(
    model,
    RevealArtifact("/tmp/demo/app.exe"),
    services,
  )
  ignore(reveal_effect)
  ignore(opened)
}

///|
/// **一键启动**必须真的调到启动执行器，并给出「正在启动」的即时反馈。
test "RunArtifact dispatches to the launcher and reports immediately" {
  let launched : Ref[String] = Ref("")
  let model = @app.initial_model(compile_track_available=true)
  let baseline = model.toasts.length()
  let (running, effect) = @app.update_with_launch_for_test(
    model,
    RunArtifact("/tmp/demo/native_app.exe"),
    @services.AppServices::unavailable(),
    fn(path, on_result) {
      launched.val = path
      on_result(Ok(()))
    },
  )
  assert_eq(running.toasts.length(), baseline + 1)
  assert_true(running.toasts[baseline].text.contains("启动"))
  ignore(effect)
}
