///|
/// AI 模式左栏·会话列表（对白转录 M4，S4 出壳）：区头动作行（新建 ⌘N
/// + 搜索）+ 可选过滤行 + 置顶/工程分组的会话行（相对时间 + 悬停改名/
/// 置顶/删除 + 行内改名）。纯视图层：状态以参数进入，行为以 on_*~ 回调
/// 注入，不改会话状态——状态操作由壳收到回调后走 AiSessionOp。

///|
/// 双行会话行高（VS Code 智能体模式口径）：标题行 15 + 元信息行 12 + 间距与内垫。
pub const AI_SESSION_ROW_HEIGHT : Double = 36.0

///|
/// AI 会话头高度（对白转录）：标题 + 置顶/删除动作。
pub const AI_SESSION_HEADER_HEIGHT : Double = 34.0

///|
/// 相对时间桶（now/at 为 civil 秒）：返回（文案 key, 计数）。
fn relative_time_bucket(now : Int32, at : Int32) -> (String, Int32) {
  let diff = (now - at).max(0)
  if diff < 60 {
    ("app.ai.time.just_now", 0)
  } else if diff < 3600 {
    ("app.ai.time.minutes", diff / 60)
  } else if diff < 86400 {
    ("app.ai.time.hours", diff / 3600)
  } else {
    ("app.ai.time.days", diff / 86400)
  }
}

///|
/// 会话列表回调包：行为以 Msg 注入，壳侧映射到 AiSessionOp / 改名 / 搜索等。
pub(all) struct AiSessionListParams[Msg] {
  sessions : AiSessions
  query : String
  search_open : Bool
  rename : (Int32, String)?
  hover : Int32
  now : Int32
  on_create : Msg
  on_settings : Msg
  on_toggle_search : Msg
  on_query : (String) -> Msg
  on_rename_start : (Int32) -> Msg
  on_rename_draft : (String) -> Msg
  on_rename_commit : Msg
  on_hover : (Int32, Bool) -> Msg
  on_pin : (Int32, Bool) -> Msg
  on_remove : (Int32) -> Msg
  on_switch : (Int32) -> Msg
}

///|
/// AI 会话列表（M4 重写，对白转录口径）：区头动作行（新建 ⌘N + 搜索）
/// + 可选过滤行 + 置顶/工程分组的会话行（相对时间 + 悬停 ✎/★/✕ +
/// 行内改名）。面板头已有「AI 会话」标题，这里不再重复。
pub fn[Msg] ai_session_list(
  p : AiSessionListParams[Msg],
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  let header_h = 30.0
  let search_h = if p.search_open { 32.0 } else { 0.0 }
  let body_h = (height - header_h - search_h).max(80.0)
  let body : Array[@moui.View[Msg]] = [ai_session_list_header(p, t, width)]
  if p.search_open {
    body.push(ai_session_search_row(p, t, width))
  }
  body.push(
    @views.scroll_view(
      @views.column(ai_session_group_rows(p, t, width), spacing=0.0).frame(
        width=(width - 8.0).max(80.0),
      ),
      width~,
      height=body_h,
      shows_indicator=true,
    ),
  )
  @views.column(body, spacing=2.0).frame(width~, height~)
}

///|
/// 区头动作行（VS Code 口径）：新建（描边小按钮 + ⌘N 键帽）+ 模型设置
/// （滑块/Gear → studio.settings）+ 搜索开关。右对齐——标题在面板头。
fn[Msg] ai_session_list_header(
  p : AiSessionListParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  @views.container(
    @chrome.fill_row(
      [
        @views.spacer(min_length=0.0, weight=1.0),
        @views.shortcut_button(
          t.translate("app.ai.session.new_short"),
          on_click=p.on_create,
          shortcut=@core.KeyboardShortcut::new(
            key="n",
            modifiers=@core.KeyModifiers::new(meta=true),
          ),
          variant=Ghost,
          theme=@chrome.studio_theme(),
          width=52.0,
          height=22.0,
        ),
        @views.container(
          @views.center(
            @views.icon(Gear, size=13.0, color=@chrome.ide_text_muted()),
            width=22.0,
            height=22.0,
          ),
          background=@chrome.ide_panel_alt(),
          corner_radius=4.0,
          width=22.0,
          height=22.0,
          padding=0.0,
        ).on_tap(p.on_settings),
        @views.container(
          @views.center(
            @views.icon(Search, size=13.0, color=@chrome.ide_text_muted()),
            width=22.0,
            height=22.0,
          ),
          background=if p.search_open {
            @chrome.ide_selection()
          } else {
            @chrome.ide_panel_alt()
          },
          corner_radius=4.0,
          width=22.0,
          height=22.0,
          padding=0.0,
        ).on_tap(p.on_toggle_search),
      ],
      width,
      4.0,
      Center,
    ),
    width~,
    height=30.0,
    padding=0.0,
  )
}

///|
/// 过滤行：title 子串过滤（本地、即时）。
fn[Msg] ai_session_search_row(
  p : AiSessionListParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  @views.container(
    @views.padding_xy(
      @views.text_field(
        p.query,
        on_input=value => (p.on_query)(value),
        placeholder=t.translate("app.ai.search.placeholder"),
        variant=Outline,
        width=(width - 16.0).max(80.0),
        height=24.0,
      ),
      horizontal=8.0,
      vertical=4.0,
    ),
    width~,
    height=32.0,
    padding=0.0,
  )
}

///|
/// 分组行构建：置顶组在前，其余按 updated 倒序遍历、连续同工程归组
/// （组头带计数）。过滤查询命中 title 才参与。
fn[Msg] ai_session_group_rows(
  p : AiSessionListParams[Msg],
  t : @i18n.Translator,
  width : Double,
) -> Array[@moui.View[Msg]] {
  let now = p.now
  let query = p.query
  let total = p.sessions.count()
  let indices : Array[Int32] = []
  let mut i = 0
  while i < total {
    match p.sessions.session_at(i) {
      Some(session) =>
        if query == "" || session.title.contains(query) {
          indices.push(i)
        }
      None => ()
    }
    i = i + 1
  }
  // updated 倒序（稳定：同 updated 保持原下标序；n 小,插入排序够用）
  let entries : Array[(Int32, Int32)] = []
  for index in indices {
    let updated = match p.sessions.session_at(index) {
      Some(s) => s.updated
      None => 0
    }
    entries.push((updated, index))
  }
  let mut i = 1
  while i < entries.length() {
    let key = entries[i]
    let mut j = i - 1
    while j >= 0 && entries[j].0 < key.0 {
      entries[j + 1] = entries[j]
      j = j - 1
    }
    entries[j + 1] = key
    i = i + 1
  }
  let sorted : Array[Int32] = []
  for entry in entries {
    sorted.push(entry.1)
  }
  let rows : Array[@moui.View[Msg]] = []
  // 置顶组
  let pinned : Array[Int32] = []
  let rest : Array[Int32] = []
  for index in sorted {
    match p.sessions.session_at(index) {
      Some(session) =>
        if session.pinned {
          pinned.push(index)
        } else {
          rest.push(index)
        }
      None => ()
    }
  }
  if pinned.length() > 0 {
    rows.push(
      ai_group_bar(
        t,
        t.translate("app.ai.group.pinned"),
        pinned.length(),
        width,
      ),
    )
    for index in pinned {
      rows.push(ai_session_row(p, t, index, width, now))
    }
  }
  // 工程组：连续同 project 归组（排序已按 updated,组序 = 组内最新时间序）
  let mut current_project = ""
  let mut current_group : Array[Int32] = []
  for index in rest {
    match p.sessions.session_at(index) {
      Some(session) => {
        if session.project != current_project && current_group.length() > 0 {
          rows.push(
            ai_project_group(p, t, current_project, current_group, width, now),
          )
          current_group = []
        }
        current_project = session.project
        current_group.push(index)
      }
      None => ()
    }
  }
  if current_group.length() > 0 {
    rows.push(
      ai_project_group(p, t, current_project, current_group, width, now),
    )
  }
  rows
}

///|
/// 工程分组：组头 = 工程名（空 = 默认工程）+ 计数。
fn[Msg] ai_project_group(
  p : AiSessionListParams[Msg],
  t : @i18n.Translator,
  project : String,
  indices : Array[Int32],
  width : Double,
  now : Int32,
) -> @moui.View[Msg] {
  let label = if project == "" {
    t.translate("app.ai.group.default_project")
  } else {
    @chrome.fit_label(project, (width - 60.0).max(60.0))
  }
  let rows : Array[@moui.View[Msg]] = [
    ai_group_bar(t, label, indices.length(), width),
  ]
  for index in indices {
    rows.push(ai_session_row(p, t, index, width, now))
  }
  @views.column(rows, spacing=0.0).frame(width=(width - 8.0).max(80.0))
}

///|
/// 组头：文件夹图标 + 名称 + 计数（淡色）。
fn[Msg] ai_group_bar(
  t : @i18n.Translator,
  label : String,
  count : Int32,
  width : Double,
) -> @moui.View[Msg] {
  ignore(t)
  @views.container(
    @chrome.fill_row(
      [
        @views.icon(FolderOpen, size=11.0, color=@chrome.ide_text_faint()),
        @views.text(
          label,
          theme=@chrome.studio_theme(),
          width=(width - 76.0).max(40.0),
          height=16.0,
          align=TextStart,
        ).foreground(@chrome.ide_text_faint()),
        @views.spacer(min_length=4.0, weight=1.0),
        @views.text(
          "\{count}",
          theme=@chrome.studio_theme(),
          width=24.0,
          height=16.0,
        ).foreground(@chrome.ide_text_faint()),
      ],
      (width - 8.0).max(80.0),
      4.0,
      Center,
    ),
    width~,
    height=22.0,
    padding=0.0,
  )
}

///|
/// 双行会话行（VS Code 智能体模式口径）：第一行 = 气泡图标 + 标题；
/// 第二行 = 来源图标 · 相对时间（时间常显：created 优先、回退 updated、
/// 全 0 显示「刚刚」）。悬停右缘出 ✎改名 / Pin置顶 / ✕删除（时间保留）；
/// 行内改名态 = text_field（Enter 提交）。非当前行可点切换。
fn[Msg] ai_session_row(
  p : AiSessionListParams[Msg],
  t : @i18n.Translator,
  index : Int32,
  width : Double,
  now : Int32,
) -> @moui.View[Msg] {
  let session = match p.sessions.session_at(index) {
    Some(value) => value
    None =>
      return @views.container(
        @views.text("", width=1.0, height=1.0),
        width~,
        height=1.0,
        padding=0.0,
      )
  }
  let row_width = (width - 8.0).max(80.0)
  // 行内改名态
  match p.rename {
    Some((rename_index, draft)) =>
      if rename_index == index {
        return @views.container(
          @views.padding_xy(
            @views.text_field(
              draft,
              on_input=value => (p.on_rename_draft)(value),
              placeholder="",
              variant=Outline,
              width=(row_width - 16.0).max(60.0),
              height=24.0,
              on_submit=Some(p.on_rename_commit),
            ),
            horizontal=4.0,
            vertical=2.0,
          ),
          width=row_width,
          height=AI_SESSION_ROW_HEIGHT,
          padding=0.0,
        )
      }
    None => ()
  }
  let active = index == p.sessions.active_index()
  let hovering = p.hover == index
  // 时间常显回退链：created > updated > 「刚刚」
  let stamp = if session.created > 0 {
    session.created
  } else {
    session.updated
  }
  let (time_key, count) = relative_time_bucket(now, stamp)
  let time_label = if stamp == 0 {
    t.translate("app.ai.time.just_now")
  } else if time_key == "app.ai.time.just_now" {
    t.translate(time_key)
  } else {
    t.translate(time_key, values=[("n", count.to_string())])
  }
  let line_w = (row_width - 118.0).max(60.0)
  // 标题占满「行宽 − 图标 − 间距」:内容恰好填满 frame,行不会因
  // 短标题被 frame 居中而出现行首空隙（真机实测缺陷）。
  let title_w = (line_w - 15.0).max(24.0)
  let title = @chrome.fit_label(session.title, title_w)
  let time_w = (line_w - 12.0).max(30.0)
  let accent = if active {
    @chrome.ide_accent()
  } else {
    @chrome.ide_text_faint()
  }
  // 来源：有已采纳提案的会话 = Gear（Agent 干过活），否则 Chat（纯聊天）
  let source_icon : @style.IconName = if session.proposal_history.any(record => {
      record.accepted
    }) {
    Gear
  } else {
    Chat
  }
  // 行内容**自然宽、左对齐**——不套 .frame(width=…):Frame 对「量出来比
  // frame 窄」的子行会做居中放置（真机实测:标题被推到行中,行首出现
  // 一段随宽度增长的空白）。@chrome.fit_label 负责超长截断。
  let line1 = @views.row(
    [
      @views.icon(Chat, size=11.0, color=accent),
      @views.text(
        title,
        theme=@chrome.studio_theme(),
        width=title_w,
        height=15.0,
        align=TextStart,
      ).foreground(
        if active {
          @chrome.ide_text()
        } else {
          @chrome.ide_text_muted()
        },
      ),
    ],
    spacing=4.0,
    align=Start,
  )
  let line2 = @views.row(
    [
      @views.icon(source_icon, size=9.0, color=@chrome.ide_text_faint()),
      @views.text(
        time_label,
        theme=@chrome.studio_theme(),
        width=time_w,
        height=12.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
    ],
    spacing=3.0,
    align=Start,
  )
  let cells : Array[@moui.View[Msg]] = [
    @views.column([line1, line2], spacing=1.0),
    @views.spacer(min_length=4.0, weight=1.0),
  ]
  if hovering && !active {
    cells.push(
      @views.container(
        @views.center(
          @views.text(
            "✎",
            theme=@chrome.studio_theme(),
            width=12.0,
            height=14.0,
          ).foreground(@chrome.ide_text_muted()),
          width=18.0,
          height=16.0,
        ),
        width=18.0,
        height=AI_SESSION_ROW_HEIGHT,
        padding=0.0,
      ).on_tap((p.on_rename_start)(index)),
    )
    cells.push(
      @views.container(
        @views.center(
          @views.icon(
            Pin,
            size=11.0,
            color=if session.pinned {
              @chrome.ide_accent()
            } else {
              @chrome.ide_text_faint()
            },
          ),
          width=18.0,
          height=16.0,
        ),
        width=18.0,
        height=AI_SESSION_ROW_HEIGHT,
        padding=0.0,
      ).on_tap((p.on_pin)(index, !session.pinned)),
    )
    cells.push(
      @views.container(
        @views.center(
          @views.text(
            "✕",
            theme=@chrome.studio_theme(),
            width=10.0,
            height=14.0,
          ).foreground(@chrome.ide_text_faint()),
          width=18.0,
          height=16.0,
        ),
        width=18.0,
        height=AI_SESSION_ROW_HEIGHT,
        padding=0.0,
      ).on_tap((p.on_remove)(index)),
    )
  }
  let row = @views.container(
    @views.padding_edges(
      // 行显式钉宽 = 容器 − 左右内垫:不加 frame,ContainerBox 会把
      // 「自然宽较窄」的行居中放置,行首出现随容器宽度增长的空隙
      // （真机实测缺陷）。
      @views.row(cells, spacing=4.0, align=Center).frame(width=row_width - 16.0),
      left=8.0,
      right=8.0,
    ),
    background=if active {
      @chrome.ide_selection()
    } else if hovering {
      @chrome.ide_panel_alt()
    } else {
      @chrome.ide_panel()
    },
    width=row_width,
    height=AI_SESSION_ROW_HEIGHT,
    padding=0.0,
  ).on_hover(entered => (p.on_hover)(index, entered))
  // 非当前会话行才可点切换（当前行再点 = no-op,与既有口径一致）
  if active {
    row
  } else {
    row.on_tap((p.on_switch)(index))
  }
}
