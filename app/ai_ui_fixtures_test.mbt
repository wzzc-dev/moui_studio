///|
/// S4d 测试夹具：在 initial_model 基础上覆盖 AI UI 状态切片。provider_key /
/// composer 模式已迁 model.ai_ui（plugins/ai 的 AiUiState），旧测试平铺在
/// Model record 里的写法不再适用，统一收口到这里。

///|
fn model_with_key(key : String) -> @app.Model {
  let base = @app.initial_model()
  { ..base, ai_ui: { ..base.ai_ui, provider_key: key, }, }
}

///|
fn model_with_composer_mode(mode : @app.ComposerMode) -> @app.Model {
  let base = @app.initial_model()
  { ..base, ai_ui: { ..base.ai_ui, composer_mode: mode, }, }
}
