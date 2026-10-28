///|
/// 参考插件实现（组件形态）：贡献一个面板与一条命令，按钮点击后计数 +1。
///
/// 与 `samples/plugin_fixture`（Rust，核心模块形态）**同一套行为**，
/// 但走 **Component Model**：
/// - 字符串直接传（Canonical ABI 自动编解码），无 offset/len 手工搬运。
/// - 类型由 `wit/world.wit` 声明（`describe() -> string`、
///   `call(request: string) -> string`）。
///
/// **只有动作请求才改状态**——视图请求不动计数与「最后动作」。否则宿主
/// 每次渲染都问一次视图时，刚记下的「最后动作」会被随后的视图请求抹掉。

///|
/// 贡献描述 JSON。
const DESCRIBE : String = "{\"format\":\"moui.studio.plugin.contrib\",\"format_version\":1,\"panels\":{\"main\":\"Fixture 面板\"},\"commands\":{\"reset\":\"重置计数\"}}"

///|
/// 点击计数。
let clicks : Ref[Int] = Ref(0)

///|
/// 上一次动作。
let last_action : Ref[String] = Ref("")

///|
fn describe() -> String {
  DESCRIBE
}

///|
fn call(request : String) -> String {
  // 只有动作请求才改状态（视图请求不动状态）。
  if request.contains("moui.studio.plugin.action") {
    let action = extract_json_string(request, "action_id")
    last_action.val = action
    if action == "increment" {
      clicks.val = clicks.val + 1
    } else if action == "reset" {
      clicks.val = 0
    }
  }
  let text = "点击次数：\{clicks.val} | last=\{last_action.val}"
  let escaped = json_escape(text)
  "{\"format\":\"moui.studio.plugin.view\",\"format_version\":1,\"key\":\"fixture-root\",\"node\":\"Column\",\"children\":[{\"key\":\"fixture-count\",\"node\":\"Text\",\"text\":\"\{escaped}\"},{\"key\":\"fixture-button\",\"node\":\"Button\",\"label\":\"点我\",\"action\":\"increment\"}]}"
}

///|
fn extract_json_string(json : String, key : String) -> String {
  let needle = "\"" + key + "\":\""
  match json.find(needle) {
    None => ""
    Some(start) => {
      let tail = json[start + needle.length() :]
      match tail.find("\"") {
        None => ""
        Some(end) => tail[0:end].to_owned()
      }
    }
  }
}

///|
fn json_escape(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    if ch == '"' {
      out.write_string("\\\"")
    } else if ch == '\\' {
      out.write_string("\\\\")
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}
