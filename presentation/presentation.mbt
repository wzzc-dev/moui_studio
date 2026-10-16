///|
/// macOS 表现层验收：离屏栅格化断言（`blocks_pixel_test.mbt`）的宿主包。
/// 本包没有运行时行为——测试要用的四个依赖（app/runtime/skia 渲染器/core）
/// 全部经 `test-import` 引入，避免把渲染器依赖挂进任何产品包。
