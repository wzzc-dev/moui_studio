# 目标积木画布模式 · 界面文本（增量 catalog）

对标图（ Scratch 画布）的要素，以 MoUI Studio 现有风格与
既有 i18n 约定（`app/i18n/{zh-Hans,en}.json`，生成 `i18n_catalog_generated.mbt`）
产出的**新增文本集**。新键 31 条，零改动既有键；落地时把两个 JSON 的
`messages` 合并进 `app/i18n/{zh-Hans,en}.json` 后重跑 catalog 生成即可。

## 1. 图中要素 → 键位映射

| 图中要素 | 落地 | 键 | zh-Hans / en |
|---|---|---|---|
| 模式名「积木」 | 复用 | `app.mode.blocks` | 积木 / Blocks |
| 画布标题 | 复用 | `app.blocks.canvas` | 积木画布 / Blocks canvas |
| 左栏积木面板 | 新 | `app.blocks.palette.search` | 搜索积木… / Search blocks… |
| 左栏面板拖放引导 | 新 | `app.blocks.palette.drag_hint` | 拖到画布，松手放入脚本 |
| 左栏「自制积木」组 | 新 | `app.blocks.palette.group.custom` | 自制积木 / My blocks（对应用户自定义函数，DSL 已支持） |
| 左栏五个分类 | 复用 | `app.blocks.cat.block.*` / `app.blocks.cat.all` | 事件/流程/变量/命令/运算 + 全部 |
| 分类面板骨架列表 | 复用 | `app.stmt.palette.*` + `app.stmt.tpl.*` | 插入语句 / Insert statement 等 24 条骨架 |
| 画布工具条：撤销/重做 | 新 | `app.blocks.canvas.undo` / `.redo` | 撤销 / 重做 |
| 画布工具条：缩放 | 新 | `.zoom_in` / `.zoom_out` / `.zoom_fit` / `.zoom_reset` / `.zoom_readout` | 放大/缩小/适应屏幕/重置为 100%/{percent}% |
| 画布工具条：新事件头（+） | 新 | `.new_script` | 新事件头 / New event hat |
| 画布工具条：网格/截图 | 新 | `.grid` / `.snapshot` | 网格 / 导出图片 |
| 画布空态 | 新 | `.empty` | 从左边拖一块积木到这里，开始搭程序 |
| 画布平移引导 | 新 | `.pan_hint` | 拖动空白处平移画布 |
| 吸附提示 | 新 | `.snap_hint` | 松手即吸附到凹槽 |
| 落槽成功/失败 | 新 | `.drop_ok` / `.drop_bad` | 已放入脚本 / 这里放不下 |
| 拖出删除 | 新 | `.trash_hint` | 把积木拖出脚本即删除 |
| 脚本起点说明 | 新 | `.script_hint` | 每个脚本从一块事件头开始 |
| 画布底部提示行 | 新（替换） | `.hint` | 替换 `app.blocks.reorder_hint`（线性链时代的文案） |
| 事件头「当程序启动」 | 复用 | `event.on_start` | 当程序启动 |
| 启动 hat「启动」 | 复用 | `app.blocks.hat.onstart` | 启动 / On Start |
| 「重复执行」hat | 复用 | `app.stmt.tpl.forever` | 重复执行 |
| 积木块名（如果/当循环/赋值…） | 复用 | `blocks.*` | 32 条既有块标签 |
| 右栏标题「AI 助手」 | 复用 | `app.ai.pill_label` | AI 助手 |
| 右栏分节标题 ×3 | 新 | `app.ai.section.init` / `.loop` / `.interact` | 初始化逻辑 / 主循环逻辑 / 显示与交互逻辑 |
| 右栏消息积木计数 | 新 | `app.ai.block_chip` | {count} 块积木 |
| 输入框提示词 | 新 | `app.ai.target.prompt` | 描述你想要的功能，AI 将为你生成积木块 |
| 输入框闸门口径 | 新 | `app.ai.target.hint` | AI 只提案积木改动，采纳后才写入程序 |
| 发送/采纳/拒绝/讲解 | 复用 | `app.ai.send` / `.accept` / `.reject` / `.explain` | — |
| 模型读取（deepseek-flash 位） | 复用 | `app.ai.model` + 设置面板 | 模型名 |
| 顶栏「项目」菜单 | 新 | `app.topbar.project` | 项目 / Project |
| 顶栏「设备 · 未连接」 | 新 + 复用 | `app.topbar.device` + `app.ai.disconnected` / `app.topbar.device.connected` | 设备 / 未连接 / 已连接 |

## 2. 明确不采纳的图中要素

- **硬件域积木**（GPIO / ADC / 屏幕 / 灯珠 / 按钮 / 舵机 / 无源蜂鸣）：
  属于 Scratch 的 OpenHarmony 硬件域。Studio 的 IR 域是 MoUI 窗体应用
  （控件 + 事件 + 变量），硬件词汇需要新的域 facet，不在本轮文本范围；
  若后续要做，按 `domain/blocks` 的 spec 表驱动扩展，键名前缀建议
  `blocks.hw.*` 与 `app.blocks.palette.group.hw`。
- **图中右栏的纯叙述式 AI 回复**（无 diff、无采纳门）：与 Studio
  「AI 只提案结构化 IR 改动、逐条采纳」的硬纪律冲突，不采纳；右栏文案
  按现有 transcript 卡片形态落 `app.ai.*`。

## 3. 落地位置（实现阶段对照）

| 文本组 | 代码落点 |
|---|---|
| 画布工具条 / 空态 / 交互提示 | `app/blocks_pane.mbt`（画布头部工具条 + `blocks_canvas` 空态层） |
| 左栏面板（搜索/拖放引导/自定义组） | `plugins/blocks/statement_palette.mbt`（拖放起点） |
| 缩放/平移/命中几何 | `plugins/blocks/blocks_geometry.mbt` + `blocks_slot_hit.mbt`（已有 `palette_drag` 拖拽骨架与受控滚动） |
| AI 分节标题 / 积木计数 / 提示词 | `plugins/ai` 消息卡 + `app/ide_ai_views.mbt` composer |
| 顶栏项目/设备 | `app/ide_chrome.mbt` 顶栏 |

## 4. 校验

合并后按仓库既有流程：重跑 catalog 生成 → `i18n --check`（双语键集合
一致、无 drift）。两个文件键集合已对齐（各 31 条），占位符
`{count}` / `{percent}` 与既有约定一致。
