///|
/// v4 IDE 壳消息域：工作区编排、面板显隐、审计/Console/最近修改、
/// AI 浮动层、快速操作、对话框与 toast。
///
/// 与既有消息域的关系：这里是**壳的状态**（谁可见、选中哪个页签、
/// 浮动层停在哪），不改 IR 语义；改 IR 的动作（快速插入、对齐）
/// 仍走 with_undo_point + 既有 commit 通道，保证撤销栈连续。

///|
/// AI 插件的会话切片挂载（M3，settings 样板同构）：lens 对 + wrap。
/// 视图由壳组装（切片的 Feature view 域刻意 abort，见插件包注释）。
fn ai_sessions_scope() -> @moui.ScopedFeature[
  Model,
  @ai.AiSessions,
  @ai.AiSessionMsg,
  Msg,
] {
  @ai.ai_sessions_feature().scope(
    read=model => model.ai_sessions,
    write=(sessions, model) => { ..model, ai_sessions: sessions, },
    wrap=message => AiSessionOp(message),
  )
}

///|
/// AI 域 UI 偏好切片挂载（S4d）：lens 对 + wrap，ai_sessions/project 同构。
/// composer/provider/转录滚动/会话列表 UI/对话框开合纯态臂住插件，零副作用。
fn ai_ui_scope() -> @moui.ScopedFeature[Model, @ai.AiUiState, @ai.AiUiMsg, Msg] {
  @ai.ai_ui_feature().scope(
    read=model => model.ai_ui,
    write=(ui, model) => { ..model, ai_ui: ui, },
    wrap=message => AiUiOp(message),
  )
}

///|
/// 积木域 UI 状态切片挂载（S5e，ADR 0040/0041）：语句面板开合/分类、画布
/// 滚动、值编辑草稿、拖放骨架、右键菜单锚点等纯 UI 态住在 @blk.BlocksUiState；
/// 画布手势/值提交/落拖/打开菜单等需读 program 或提交 IR 的臂仍住壳（契约 3）。
fn blocks_ui_scope() -> @moui.ScopedFeature[
  Model,
  @blk.BlocksUiState,
  @blk.BlocksUiMsg,
  Msg,
] {
  @blk.blocks_ui_feature().scope(
    read=model => model.blocks_ui,
    write=(ui, model) => { ..model, blocks_ui: ui, },
    wrap=message => BlocksUiOp(message),
  )
}

///|
/// 代码编辑器 UI 状态切片挂载（S5g，ADR 0040/0041）：受控编辑面的光标/选区/
/// 滚动与补全弹层（候选词/开关）住在 @code.CodeUiState；编辑代码、采纳补全、
/// 触发补全/跳转声明（读 code_draft/program）与 IR 高亮/悬停仍住壳（契约 3）。
fn code_ui_scope() -> @moui.ScopedFeature[
  Model,
  @code.CodeUiState,
  @code.CodeUiMsg,
  Msg,
] {
  @code.code_ui_feature().scope(
    read=model => model.code_ui,
    write=(ui, model) => { ..model, code_ui: ui, },
    wrap=message => CodeUiOp(message),
  )
}

///|
/// 运行域 UI 切片挂载（S5i）：编译输出展开 + 预览 Frame/Web 档位。
/// 预览导航/构建回执等服务/Effect 编排仍住壳。
fn run_ui_scope() -> @moui.ScopedFeature[
  Model,
  @run.RunUiState,
  @run.RunUiMsg,
  Msg,
] {
  @run.run_ui_feature().scope(
    read=model => model.run_ui,
    write=(ui, model) => { ..model, run_ui: ui, },
    wrap=message => RunUiOp(message),
  )
}

///|
/// 工程域插件的会话切片挂载(S2b-2):lens 对 + wrap,ai_sessions 同构。
/// 14 个纯态臂住在插件 update;跨域臂(装载/保存/扫描/导入/改名/构建/
/// 存储)仍是壳消息,不经包装直接路由。
fn project_scope() -> @moui.ScopedFeature[
  Model,
  @proj.ProjectState,
  @proj.ProjectMsg,
  Msg,
] {
  @proj.project_feature().scope(
    read=model => model.project_state,
    write=(state, model) => { ..model, project_state: state, },
    wrap=message => ProjectOp(message),
  )
}

///|
/// 壳消息分发：未命中返回 None（链式交给其他域）。
pub fn update_ide_msgs(model : Model, msg : Msg) -> (Model, @moui.Effect[Msg])? {
  match msg {
    ProjectOp(op) => {
      // 工程域切片经 Feature::scope 委托(S2b-2):纯态臂零副作用,effect
      // 原样丢弃(ai_sessions 先例)。折叠的「展开揭示滚动」需要行推导 +
      // translator,切片拿不到——根臂后处理补上。
      let scope = project_scope()
      let (next, _) = scope.update(model, op)
      let next = match op {
        ToggleProjectDirAt(index, rel) => {
          let key = @proj.root_collapse_key(index, rel)
          let mut now_collapsed = false
          for item in next.project_state.project_tree_collapsed {
            if item == key {
              now_collapsed = true
            }
          }
          if !now_collapsed {
            let target = explorer_dir_scroll_target(next, index, rel)
            {
              ..next,
              project_state: { ..next.project_state, explorer_scroll: target, },
            }
          } else {
            next
          }
        }
        _ => next
      }
      Some((next, @moui.Effect::none()))
    }
    AiSessionOp(op) => {
      // AI 插件会话切片经 Feature::scope 委托（M3）：lens 对 + wrap，
      // 与 settings 样板同构；切片 update 零副作用，effect 原样丢弃。
      let scope = ai_sessions_scope()
      let (next, effect) = scope.update(model, op)
      // 切换会话 = 换一条时间线：滚动复位到顶 + 恢复自动跟随
      // （贴底由新内容到达时触发，终端同款口径）。
      let next = match op {
        // 新建/切换/删除都会改变「当前时间线」——滚动复位 + 恢复跟随
        AiSessionCreate(_) | AiSessionSwitch(_) | AiSessionRemove(_) => {
          next.ai_ui.transcript_scroll = @geometry.Point::new(x=0.0, y=0.0)
          next.ai_ui.transcript_scroll_seq = next.ai_ui.transcript_scroll_seq +
            1
          next.ai_ui.transcript_follow = true
          // 结构性事件：会话存储脏标（切换也存——active 指针在存储里）
          mark_ai_sessions_dirty(next)
          next
        }
        AiSessionPin(_, _) => {
          mark_ai_sessions_dirty(next)
          next
        }
        // composer 重新输入即清上一次的校验/发送错误（错误态跨域，仍住壳）。
        SetPromptDraft(_) => { ..next, prompt_error: "", }
        _ => next
      }
      Some((next, effect))
    }
    // AI 域纯 UI 偏好切片（S4d）：零副作用，effect 原样丢弃。
    AiUiOp(op) => {
      let scope = ai_ui_scope()
      let (next, _) = scope.update(model, op)
      Some((next, @moui.Effect::none()))
    }
    // 积木域纯 UI 状态切片（S5e）：零副作用，effect 原样丢弃。
    BlocksUiOp(op) => {
      let scope = blocks_ui_scope()
      let (next, _) = scope.update(model, op)
      Some((next, @moui.Effect::none()))
    }
    // 代码编辑器纯 UI 状态切片（S5g）：零副作用，effect 原样丢弃。
    CodeUiOp(op) => {
      let scope = code_ui_scope()
      let (next, _) = scope.update(model, op)
      Some((next, @moui.Effect::none()))
    }
    // 运行域 UI 切片（S5i）：编译输出展开、预览 Frame/Web 档位，零副作用。
    RunUiOp(op) => {
      let scope = run_ui_scope()
      let (next, _) = scope.update(model, op)
      Some((next, @moui.Effect::none()))
    }
    SetPerspective(p) => Some(set_perspective(model, p))
    SetWorkSpace(workspace) => Some(set_workspace(model, workspace))
    // 编辑工作台的纯迁移（文档/窗格/分隔比）。ShowPane* 的壳策略——
    // 切回可视化工作区、积木窗格自动选第一个子程序——在纯迁移之后补。
    WorkbenchOp(op) => {
      let next = {
        ..model,
        workbench: @wb.update_workbench(model.workbench, op),
      }
      let next = match op {
        @wb.ShowPaneLive => { ..next, workspace: WsVisual, mode: ModeDesign, }
        @wb.ShowPaneBlocks => show_pane_blocks_policy(next)
        _ => next
      }
      Some((next, @moui.Effect::none()))
    }
    SetLeftView(view) => Some(set_left_view(model, view))
    ProjectFileLoaded(rel, result) =>
      match result {
        Success(content) =>
          // 文件仍处于选中态才挂载编辑器（再点同文件 = 取消选中）;
          // 文档库同 id 原位替换（重新读取 = 刷新内容），否则追加并激活。
          if model.project_state.selected_project_file is Some(current) &&
            current == rel {
            let (docs, _) = model.workbench.docs.upsert_file(
              @wb.file_document(rel, @code.file_tab_label(rel)),
              @wb.TextBuffer::new(rel, content),
            )
            let next = { ..model, workbench: { ..model.workbench, docs, }, }
            // AI 中心不挂文件 tab：点文件时切回代码预设（文档仍保持激活）。
            let (next, _) = if next.perspective is PsAi {
              set_perspective(next, PsCode)
            } else {
              (next, @moui.Effect::none())
            }
            Some((next, @moui.Effect::none()))
          } else {
            Some((model, @moui.Effect::none()))
          }
        Failure(error) =>
          Some((with_notice(model, error.message, true), @moui.Effect::none()))
        Cancelled => Some((model, @moui.Effect::none()))
      }
    ProjectFileSaveFinished(rel, result) =>
      // 落盘完成:按资源定位文档,脏基准对齐草稿（写盘任务在服务层）。
      // F4 live 诊断:保存 .mbt 即自动起一次 web 构建（build 通道原样复用,
      // 诊断汇 Problems）——保存是天然节流点,不做独立防抖计时器。
      match result {
        Success(_) =>
          if model.workbench.docs.find_file(rel) < 0 {
            Some((model, @moui.Effect::none()))
          } else {
            let aligned = with_notice(
              {
                ..model,
                workbench: {
                  ..model.workbench,
                  docs: model.workbench.docs.mark_saved(rel),
                },
              },
              "已保存",
              false,
            )
            let (with_build, build_effect) = auto_build_after_save(aligned, rel)
            Some((with_build, build_effect))
          }
        Failure(error) =>
          Some((with_notice(model, error.message, true), @moui.Effect::none()))
        Cancelled => Some((model, @moui.Effect::none()))
      }
    // tab 切换/关闭与文档编辑已迁 workbench（WorkbenchOp）；文件 CRUD
    // 输入态（FileCreateDraft/Dismiss、FileRenameStart/Draft/Dismiss）与
    // 全文搜索草稿（SearchQueryDraft）仍走 project_state 切片（ProjectOp）。
    // 断点（G7.4）：行号槽点击切换断点集
    ToggleBreakpoint(line) => {
      let next : Array[Int32] = if model.breakpoints.contains(line) {
        let kept : Array[Int32] = []
        for bp in model.breakpoints {
          if bp != line {
            kept.push(bp)
          }
        }
        kept
      } else {
        model.breakpoints + [line]
      }
      Some(({ ..model, breakpoints: next, }, @moui.Effect::none()))
    }
    SelectProjectFile(rel) =>
      // 再点同一个文件 = 取消选中(与图标栏「再点一次」同一心智)
      Some(
        (
          {
            ..model,
            project_state: {
              ..model.project_state,
              selected_project_file: if model.project_state.selected_project_file
                is Some(current) &&
                current == rel {
                None
              } else {
                Some(rel)
              },
            },
          },
          @moui.Effect::none(),
        ),
      )
    SelectProjectFileAt(index, rel) => {
      // 点某个文件 = 选中它,并把**活动工程**切到它归属的那一个。
      //
      // 归属不直接用行上的 index:工作区导入时树的根是工作区根
      // （@proj.WORKSPACE_ROOT_INDEX）,而根上的 `gradlew` 不属于任何成员——
      // 把 -1 写进 active_project 会让「当前工程」这个语义失效。归属改成
      // 由**路径**反查（`project_index_of_tree_rel`）:成员目录下的文件归属
      // 该成员,根上的文件保持原活动工程不变。
      let owner = match project_index_of_tree_rel(model, rel) {
        Some(found) => found
        None =>
          if index >= 0 && index < model.project_state.projects.length() {
            index
          } else {
            model.project_state.active_project
          }
      }
      Some(
        (
          {
            ..model,
            project_state: {
              ..model.project_state,
              active_project: owner,
              selected_project_file: if model.project_state.selected_project_file
                is Some(current) &&
                current == rel {
                None
              } else {
                Some(rel)
              },
            },
          },
          @moui.Effect::none(),
        ),
      )
    }
    RemoveProject(index) => {
      let removed = remove_project_at(model, index)
      mark_projects_dirty(removed)
      Some((removed, @moui.Effect::none()))
    }
    // 扫描进度(G2):节流回调读数,一行显示;完成臂统一清 None
    ProjectScanProgress(p) =>
      Some(
        (
          {
            ..model,
            project_state: {
              ..model.project_state,
              scan_progress: Some(
                text_with(translator(model), "app.project.scanning", [
                  ("n", p.scanned_dirs.to_string()),
                  ("path", p.current),
                ]),
              ),
            },
          },
          @moui.Effect::none(),
        ),
      )
    SelectSemanticNode(index) => {
      // 选中语义节点:label 预填进编辑草稿(空 label 也能选中,草稿为空);
      // 再点同一个 = 取消选中
      let current = match model.selected_semantic {
        Some(value) => value
        None => -1
      }
      if index == current {
        Some(
          (
            { ..model, selected_semantic: None, semantic_draft: "", },
            @moui.Effect::none(),
          ),
        )
      } else {
        let draft = match model.preview_frame {
          Some(frame) => {
            let nodes = @run.semantic_hit_nodes(frame)
            if index >= 0 && index < nodes.length() {
              nodes[index].label
            } else {
              ""
            }
          }
          None => ""
        }
        Some(
          (
            { ..model, selected_semantic: Some(index), semantic_draft: draft, },
            @moui.Effect::none(),
          ),
        )
      }
    }
    SemanticLabelInput(text) =>
      Some(({ ..model, semantic_draft: text, }, @moui.Effect::none()))
    // 预览 Frame/Web 切换已迁 RunUiOp(SetPreviewMode)（S5i 运行域切片）。
    // 直达目标外观（实测反馈：单个循环胶囊太隐蔽，用户找不到 DSL 入口）
    SetCodeAppearance(appearance) =>
      Some(
        (
          sync_code_draft({ ..model, code_appearance: appearance, }),
          @moui.Effect::none(),
        ),
      )
    // 布局页签开关（M4 收尾）：进入布局设计时若无会话则自动加载 form.mbt
    //（FormDesignOpen 走服务层读盘链）。
    SetPreviewDesignOpen(open) => {
      let next = { ..model, preview_design_open: open, }
      if open && model.form_designer is None {
        Some((next, @moui.Effect::dispatch(emit => emit(FormDesignOpen))))
      } else {
        Some((next, @moui.Effect::none()))
      }
    }
    SelectFormControl(index) => {
      let current = match model.selected_form_control {
        Some(value) => value
        None => -1
      }
      if index == current {
        Some(({ ..model, selected_form_control: None, }, @moui.Effect::none()))
      } else {
        Some(
          (
            { ..model, selected_form_control: Some(index), },
            @moui.Effect::none(),
          ),
        )
      }
    }
    SetRightView(view) => Some(set_right_view(model, view))
    // 列间 sash 拖拽：视图层已按当帧布局夹取，这里再兜底夹一次静态界限
    // （窗口在拖拽中途变小等时序差）。纯布局状态：不进撤销、不标脏。
    ResizeLeftPanel(width) =>
      Some(
        (
          {
            ..model,
            left_width: width.clamp(
              min=@chrome.LEFTBAR_MIN_WIDTH,
              max=@chrome.LEFTBAR_MAX_WIDTH,
            ),
          },
          @moui.Effect::none(),
        ),
      )
    ResizeRightPanel(width) =>
      Some(
        (
          {
            ..model,
            right_width: width.clamp(
              min=@chrome.RIGHTBAR_MIN_WIDTH,
              max=@chrome.RIGHTBAR_MAX_WIDTH,
            ),
          },
          @moui.Effect::none(),
        ),
      )
    // 结构树搜索/分组折叠（SetTreeQuery/ToggleTreeGroup）已并入
    // project_state 切片（ProjectOp 委托）。
    TriggerCompletion => {
      let (word, _) = @code.word_at_caret(model.code_draft, model.code_ui.caret)
      let candidates = @code.completions_for(
        model.language.dsl_language(),
        model.program.controls,
        model.code_draft,
        word,
      )
      if candidates.length() > 0 {
        let (next, _) = code_ui_scope().update(
          model,
          @code.SetCompletions(candidates),
        )
        Some((next, @moui.Effect::none()))
      } else {
        Some((model, @moui.Effect::none()))
      }
    }
    ApplyCompletion(word) => {
      let (text, caret) = @code.apply_completion(
        model.code_draft,
        model.code_ui.caret,
        word,
      )
      let (next, _) = code_ui_scope().update(
        with_draft_diagnostics({ ..model, code_draft: text, }),
        @code.ApplyCompletion(caret),
      )
      Some((next, @moui.Effect::none()))
    }
    JumpToDeclaration => {
      let line = @code.declaration_line_of(
        model.language.dsl_language(),
        model.code_draft,
        model.code_ui.caret,
      )
      if line > 0 {
        Some((goto_line(model, line), @moui.Effect::none()))
      } else {
        Some((model, @moui.Effect::none()))
      }
    }
    // 补全弹层关闭（DismissCompletion）已并入 code_ui 切片（CodeUiOp）。
    SetContextTab(tab) =>
      Some(({ ..model, ctx_tab: tab, }, @moui.Effect::none()))
    SetBottomTab(tab) =>
      Some((select_bottom_tab(model, tab), @moui.Effect::none()))
    ToggleBottom =>
      Some(
        (
          // **收起/展开底栏只动底栏**——绝不偷偷把 AI 输入面挪去右栏。
          //
          // 折叠面板是面板级动作，与「AI 输入面的宿主」是两件事：收起时
          // 输入面跟着收起（和审计/控制台页签一样），展开后原样回来。
          // 宿主由 right_view × 当前模式推导（M2），不存在
          // 「收起把 AI 挪走」的联动（历史事故记录见计划文档）。
          { ..model, bottom_open: !model.bottom_open, },
          @moui.Effect::none(),
        ),
      )
    AuditOpen(index) =>
      Some(
        (
          { ..model, bottom_open: true, bottom_tab: BtAudit, },
          jump_audit(model, index),
        ),
      )
    AuditSettle(index, note) => Some(settle_audit(model, index, note))
    AuditSettleAll(note) => Some(settle_all_audit(model, note))
    ClearConsole => Some(({ ..model, log_lines: [], }, @moui.Effect::none()))
    // 工作卡折叠 / 设置 / 历史对话框开合已迁 AiUiOp（S4d 状态切片）。
    AlignControlLeft(name) => Some(align_control(model, name, AlignLeft))
    AlignControlCenter(name) => Some(align_control(model, name, AlignCenter))
    AlignControlRight(name) => Some(align_control(model, name, AlignRight))
    DismissToast(index) => Some(dismiss_toast(model, index))
    ToastTick => Some((age_toasts(model), @moui.Effect::none()))
    StudioCommandRun(id) => Some(run_studio_command(model, id))
    // 积木分类条切换（SelectBlockCategory）已随 blocks_ui 切片（BlocksUiOp）。
    HighlightIrPath(path) => {
      let same = @blk.blocks_same_path(model.ir_highlight, path)
      Some(
        (
          { ..model, ir_highlight: if same { [] } else { path }, },
          @moui.Effect::none(),
        ),
      )
    }
    HoverIrPath(path) =>
      Some(({ ..model, hover_path: path, }, @moui.Effect::none()))
    RestoreCodeDraft => Some(restore_code_draft(model))
    _ => None
  }
}

// ============================================================================
// 资源管理器（VS Code 口径）
// ============================================================================

// ============================================================================
// 工作区与面板
// ============================================================================

///|
/// 中心工作区切换（M2 起降为中心形态机制——模式切换走 `SetPerspective`，
/// 活动栏不再有工作区按钮）。**「再点当前 = 空舞台」的语义已删除**（设计
/// 契约 1：五种再点语义收敛为一种；空舞台只作为两窗格全关的自然结果出现）。
/// 同值请求 = no-op。切可视化时两个窗格都显（从收起态恢复要有内容，
/// 否则点了没反应）。
fn set_workspace(
  model : Model,
  workspace : WorkSpace,
) -> (Model, @moui.Effect[Msg]) {
  if model.workspace == workspace {
    return (model, @moui.Effect::none())
  }
  let next = match workspace {
    WsPreview => { ..model, workspace: WsPreview, mode: ModeDesign, }
    WsVisual =>
      {
        ..model,
        workspace: WsVisual,
        mode: ModeDesign,
        workbench: {
          ..model.workbench,
          layout: {
            ..model.workbench.layout,
            pane_live: true,
            pane_blocks: true,
          },
        },
      }
    WsCode => { ..model, workspace: WsCode, mode: ModeCode, }
    // WsEmpty 不再是任何入口的目标（空舞台 = 两窗格全关的自然结果，
    // 恢复入口是空舞台上的「+ 窗格」按钮）；防御性保留：照原样置位。
    WsEmpty => { ..model, workspace: WsEmpty, }
  }
  (next, @moui.Effect::none())
}

///|
/// 显示积木窗格后，壳还要保证**有选中的子程序**才画得出来
/// （`blocks_pane_wanted` 判据）。从空舞台进来时如果没有选中的子程序，
/// 就顺手选上第一个——否则用户点了「+ 积木窗格」而屏幕上只有 Live App，
/// 看起来就是按钮没反应。
fn show_pane_blocks_policy(model : Model) -> Model {
  let mut next = { ..model, workspace: WsVisual, mode: ModeDesign, }
  if current_handler(next) is None {
    match next.program.handlers {
      [first, ..] =>
        next = {
          ..next,
          selected_control: first.control_name,
          selected_handler: handler_key(first.control_name, first.event.tag()),
        }
      [] => ()
    }
  }
  next
}

///|
/// 左栏切换：点当前图标 = 收起（设计稿 setLeft 语义）。
fn set_left_view(model : Model, view : LeftView) -> (Model, @moui.Effect[Msg]) {
  let target = match (model.left_view, view) {
    (LeftTree, LeftTree) | (LeftData, LeftData) | (LeftProject, LeftProject) =>
      LeftHidden
    (_, wanted) => wanted
  }
  ({ ..model, left_view: target, }, @moui.Effect::none())
}

///|
/// 会话内移除导入的工程(不动磁盘)。active_project 随之修正:
/// 移除的正是当前选中 → 清空选中;移除在选中之前 → 下标左移一位。
fn remove_project_at(model : Model, index : Int32) -> Model {
  if index < 0 || index >= model.project_state.projects.length() {
    return model
  }
  let projects : Array[ProjectRecord] = []
  let mut i = 0
  for project in model.project_state.projects {
    if i != index {
      projects.push(project)
    }
    i = i + 1
  }
  // 选中修正:移除的正是当前选中 → 落到**同位的下一个工程**(IDE 移除
  // 选中标签页的惯例;列表空了才清空选中);移除在选中之前 → 下标左移。
  let remaining = projects.length()
  let active = if model.project_state.active_project == index {
    if remaining == 0 {
      -1
    } else if index >= remaining {
      remaining - 1
    } else {
      index
    }
  } else if model.project_state.active_project > index {
    model.project_state.active_project - 1
  } else {
    model.project_state.active_project
  }
  {
    ..model,
    project_state: {
      ..model.project_state,
      projects,
      active_project: active,
      selected_project_file: None,
    },
  }
}

///|
/// 右栏当前视图（M2）：右栏头的 ✕ 关（RvHidden），重开与换页走页块切换器
/// 与命令面板（studio.right.context / studio.right.ai 等）。幂等。
///
/// 输入面（只有 `RvAi` 与 `PsAi` 中心有）随视图自动进出场——不需要再为
/// 「切页时把别处的 stale AI 页签复位」打补丁，底栏根本没有 AI 页签。
fn set_right_view(
  model : Model,
  view : RightView,
) -> (Model, @moui.Effect[Msg]) {
  ({ ..model, right_view: view, }, @moui.Effect::none())
}

///|
/// 能力缺席归一化：AI 插件被禁用时，停在 `RvAi` 的右栏退回检查器页。
///
/// 与「禁用终端时 `BtTerminal` 退回 `BtAudit`」「禁用 AI 时 `PsAi` 退回
/// `PsVisual`」同一条纪律：**能力没了就把状态从那个入口搬走**，否则会留下
/// 一个「切过去什么都没有」的死页（AI 页的转录与输入面全部由插件贡献）。
/// `TogglePlugin` 与 boot 恢复（`PluginsLoaded`）两条路径共用。
pub fn normalize_disabled_plugins(model : Model) -> Model {
  if !plugin_active(model, "ai") && model.right_view is RvAi {
    return { ..model, right_view: RvContext, }
  }
  model
}

///|
/// 任务模式切换（M2 三模式工作台）：**进模式 = 应用预设**——一次性置位
/// 左栏视图、右栏视图与中心形态。同值再点 no-op（设计契约 1：不再有
/// 「再点 = 空舞台」）。模式内的临时收放不回写预设（契约 3），预设也不
/// 跨模式记忆（v1）。
fn set_perspective(
  model : Model,
  perspective : StudioPerspective,
) -> (Model, @moui.Effect[Msg]) {
  if model.perspective == perspective {
    return (model, @moui.Effect::none())
  }
  // 教学版 profile（M7）：只开放图形化模式——切其它模式 no-op（能力
  // 缺席而非隐藏报错；活动栏对应图标也不渲染）
  if model.profile is Teaching && !(perspective is PsVisual) {
    return (model, @moui.Effect::none())
  }
  // 插件管理（G7.3）：AI 插件被禁用时切到 AI 模式 no-op（入口同被隐藏）
  if perspective is PsAi && !plugin_active(model, "ai") {
    return (model, @moui.Effect::none())
  }
  (apply_perspective_preset(model, perspective), @moui.Effect::none())
}

///|
/// 预设表（唯一事实，与计划文档的表格一一对应）。中心形态：PsVisual →
/// 可视化画布（预览走 `SetWorkSpace(WsPreview)` 的中心切换，不占活动栏）；
/// PsCode → 代码编辑器；PsAi 不改 workspace——中心渲染以 perspective 优先
/// （M2 过渡 = 全幅 composer，M3 升级会话流）。
fn apply_perspective_preset(
  model : Model,
  perspective : StudioPerspective,
) -> Model {
  match perspective {
    PsVisual =>
      {
        ..model,
        perspective,
        left_view: LeftTree,
        right_view: RvContext,
        workspace: WsVisual,
        mode: ModeDesign,
      }
    PsCode =>
      {
        ..model,
        perspective,
        left_view: LeftProject,
        right_view: RvContext,
        workspace: WsCode,
        mode: ModeDesign,
      }
    PsAi =>
      {
        ..model,
        perspective,
        // AI 会话列表（M3 插件贡献的左栏视图）
        left_view: LeftAiSessions,
        right_view: RvHidden,
        mode: ModeDesign,
        // 真终端页签（M5/M8）：AI 模式预设选中终端页签；底栏默认收起
        // （M8④ 用户反馈：需要时再展开——页签头常在，点终端页签即展开）
        bottom_tab: BtTerminal,
        bottom_open: false,
      }
    // 设计工作台（M5）：全幅设计画布（易语言式拖拽）——中心复用组合
    // 工作区的 `live_pane` 构造器（同一拖放/属性编辑路径，验收口径
    // 「与组合一致」由构造保证），只撤掉左栏结构树与积木窗格；
    // 右栏保留检查器页（拖放后的属性编辑去处）。
    PsDesign =>
      {
        ..model,
        perspective,
        left_view: LeftHidden,
        right_view: RvContext,
        workspace: WsVisual,
        mode: ModeDesign,
      }
    // 积木工作台（M5）：全幅积木画布（分类面板/自由画布/AI 右栏）
    // ——「完全积木界面」的宿主形态；画布宽度不再受中心列对半分制约。
    PsBlocks =>
      {
        ..model,
        perspective,
        left_view: LeftHidden,
        right_view: RvAi,
        workspace: WsVisual,
        mode: ModeBlocks,
      }
  }
}

// ============================================================================
// 审计时间线
// ============================================================================

///|
/// 追加审计条目（会话内，超 AUDIT_LIMIT 丢最旧）。
/// 视图层与 update 层共用：所有条目都带单调序号，稳定 key。
pub fn push_audit(
  model : Model,
  kind : AuditKind,
  text : String,
  detail : String,
) -> Model {
  let entries = model.audit_entries
  entries.push(AuditEntry::{
    kind,
    seq: model.audit_seq,
    text,
    detail,
    stack: "",
    settled: false,
    settled_note: "",
  })
  while entries.length() > AUDIT_LIMIT {
    ignore(entries.remove(0))
  }
  { ..model, audit_entries: entries, audit_seq: model.audit_seq + 1, }
}

///|
/// 追加带调用栈的审计错误卡。
pub fn push_audit_error(model : Model, text : String, stack : String) -> Model {
  let entries = model.audit_entries
  entries.push(AuditEntry::{
    kind: AuditError,
    seq: model.audit_seq,
    text,
    detail: "",
    stack,
    settled: false,
    settled_note: "",
  })
  while entries.length() > AUDIT_LIMIT {
    ignore(entries.remove(0))
  }
  { ..model, audit_entries: entries, audit_seq: model.audit_seq + 1, }
}

///|
/// 追加副作用待确认卡（AuditWarn）。
pub fn push_audit_side_effect(
  model : Model,
  text : String,
  detail : String,
) -> Model {
  push_audit(model, AuditWarn, text, detail)
}

///|
/// 点击审计条目：整数下标 → 该条目的序号，再反查对应积木块。
/// 审计条目记的是「第几条事实」，跳转需要的是「哪条语句」——
/// 这里按条目序号定位到最近一条带语句路径的事实（detail 里存的
/// 是规范文本，用 current_spotlight 同源的匹配）。
fn jump_audit(model : Model, index : Int32) -> @moui.Effect[Msg] {
  ignore(model)
  ignore(index)
  @moui.Effect::none()
}

///|
/// 处理单条审计卡（确认/拒绝）：标记 settled + 记 Console。
fn settle_audit(
  model : Model,
  index : Int32,
  note : String,
) -> (Model, @moui.Effect[Msg]) {
  if index < 0 || index >= model.audit_entries.length() {
    return (model, @moui.Effect::none())
  }
  let entries : Array[AuditEntry] = []
  let mut cursor = 0
  for entry in model.audit_entries {
    if cursor == index {
      entries.push(AuditEntry::{ ..entry, settled: true, settled_note: note, })
    } else {
      entries.push(entry)
    }
    cursor = cursor + 1
  }
  let next = { ..model, audit_entries: entries, }
  (log_line(next, LogInfo, "app.log.settled"), @moui.Effect::none())
}

///|
/// 一键确认全部副作用卡：把「待确认」清空（仍不改闸门语义——真实
/// 外发只在运行时点确认按钮时才发生）。
fn settle_all_audit(model : Model, note : String) -> (Model, @moui.Effect[Msg]) {
  let entries : Array[AuditEntry] = []
  let mut changed = false
  for entry in model.audit_entries {
    if entry.kind is AuditWarn && !entry.settled {
      entries.push(AuditEntry::{ ..entry, settled: true, settled_note: note, })
      changed = true
    } else {
      entries.push(entry)
    }
  }
  if !changed {
    return (model, @moui.Effect::none())
  }
  let next = { ..model, audit_entries: entries, }
  (log_line(next, LogInfo, "app.log.settled_all"), @moui.Effect::none())
}

// ============================================================================
// Console
// ============================================================================

///|
/// 追加 Console 日志行（超 LOG_LIMIT 丢最旧）。
pub fn log_line(model : Model, level : LogLevel, text : String) -> Model {
  let lines = model.log_lines
  lines.push(LogLine::{ level, seq: model.log_seq, text, })
  while lines.length() > LOG_LIMIT {
    ignore(lines.remove(0))
  }
  { ..model, log_lines: lines, log_seq: model.log_seq + 1, }
}

// ============================================================================
// 最近修改
// ============================================================================

///|
/// 追加最近修改条目（会话内，超 RECENT_LIMIT 丢最旧）。
/// by_agent 区分「你」与「Agent」——教学上这是最重要的一列。
pub fn push_recent(
  model : Model,
  target : String,
  action : String,
  by_agent : Bool,
) -> Model {
  let changes = model.recent_changes
  changes.push(RecentChange::{
    target,
    by_agent,
    action,
    seq: model.recent_seq,
  })
  while changes.length() > RECENT_LIMIT {
    ignore(changes.remove(0))
  }
  { ..model, recent_changes: changes, recent_seq: model.recent_seq + 1, }
}

// ============================================================================
// AI 浮动层
// ============================================================================

///|
/// 切换底栏页签。
///
/// **只读页签绝不搬动 AI 输入面**：点「运行审计」「Console」「问题」只是
/// 想看一眼那个面板。M2 起 AI 的宿主由 `right_view` 与当前模式**推导**
/// （右栏停靠 > AI 模式中心 > 底栏页签），「页签与落点互相联动」的整套
/// reconciliation（sync_ai_placement / apply_ai_anchor）随之删除——
/// 推导出的状态天然自洽，没有需要收敛的矛盾态。

///|
fn select_bottom_tab(model : Model, tab : BottomTab) -> Model {
  // 终端页签（M8）：**关闭态**再点 = 重开（terminal_open 恢复，句柄已清
  // → 下次 update 重派生）；选中态的关闭走 TerminalTabClose（kill 需要
  // 服务，在 update_with_services）。其余页签照常选中。
  if tab is BtTerminal && !model.terminal_open {
    model.terminal_open = true
    return { ..model, bottom_tab: tab, bottom_open: true, }
  }
  { ..model, bottom_tab: tab, bottom_open: true, }
}

///|
/// 追加 AI 会话卡（超 AI_CARD_LIMIT 丢最旧）：写进**当前会话**的线程
/// （M3 会话切片化，经 amend 原位替换活跃会话）。`at` 戳在这里统一盖——
/// 构造点不必各自取钟，时间线的时间与时长口径单一。
pub fn push_ai_card(model : Model, card : AiCard) -> Model {
  let session = model.ai_sessions.current()
  let cards = session.cards
  cards.push(AiCard::{
    ..card,
    seq: session.card_seq,
    at: civil_seconds(model.clock),
  })
  while cards.length() > AI_CARD_LIMIT {
    ignore(cards.remove(0))
  }
  model.ai_sessions.amend({ ..session, cards, card_seq: session.card_seq + 1, })
  // 新内容到达：跟随态下强制时间线贴底（对白转录；非跟随态不动）
  follow_transcript(model)
}

// ============================================================================
// 快速操作（对齐）
// ============================================================================

///|
/// 对齐目标：设计稿口径是 24pt 边距、640 设计宽。
priv enum AlignTarget {
  AlignLeft
  AlignCenter
  AlignRight
}

///|
/// 对齐单个选中控件：改 x，宽度不变。
/// 24pt 边距与「居中 = round((640 − w) / 2)」直接来自设计稿的 qaBar。
/// 走 with_undo_point（coalesce 键按控件+对齐方式，连续对齐合并为一个还原点）。
fn align_control(
  model : Model,
  name : String,
  target : AlignTarget,
) -> (Model, @moui.Effect[Msg]) {
  match @ir.find_control(model.program, name) {
    None => (model, @moui.Effect::none())
    Some(control) => {
      let x = match target {
        AlignLeft => ALIGN_MARGIN
        AlignCenter => (@ir.DESIGN_WIDTH - control.width) / 2
        AlignRight => @ir.DESIGN_WIDTH - control.width - ALIGN_MARGIN
      }
      let clamped = x.max(0)
      if clamped == control.x {
        return (model, @moui.Effect::none())
      }
      let undo = with_undo_point(model, "align:\{name}", m => {
        let controls : Array[@ir.Control] = []
        for item in m.program.controls {
          if item.name == name {
            controls.push(item.with_rect_field(@ir.RectX, clamped))
          } else {
            controls.push(item)
          }
        }
        { ..m, program: { ..m.program, controls, }, }
      })
      let next = { ..undo, selected_control: name, }
      (
        log_line(
          push_recent(next, name, "app.recent.align", false),
          LogInfo,
          "app.log.align",
        ),
        @moui.Effect::none(),
      )
    }
  }
}

///|
/// 设计稿的快速操作对齐边距。
pub const ALIGN_MARGIN : Int32 = 24

// ============================================================================
// 对话框与命令
// ============================================================================

///|
fn dismiss_toast(model : Model, index : Int32) -> (Model, @moui.Effect[Msg]) {
  if index < 0 || index >= model.toasts.length() {
    return (model, @moui.Effect::none())
  }
  let toasts : Array[ToastEntry] = []
  let mut cursor = 0
  for toast in model.toasts {
    if cursor != index {
      toasts.push(toast)
    }
    cursor = cursor + 1
  }
  ({ ..model, toasts, }, @moui.Effect::none())
}

///|
/// 追加 toast（超 TOAST_LIMIT 丢最旧）。
pub fn push_toast(model : Model, text : String, warning : Bool) -> Model {
  let toasts = model.toasts
  toasts.push(ToastEntry::{ text, warning, age: 0, })
  while toasts.length() > TOAST_LIMIT {
    ignore(toasts.remove(0))
  }
  { ..model, toasts, }
}

///|
/// notice 的唯一写入漏斗：写 `model.notice` 的同时补推一条 toast。
///
/// 为什么必须有这个漏斗：`notice` 在视图层**没有任何渲染点**（状态栏不画
/// 它），直接写结构体字段等于把成功/失败静默吞掉——保存失败、解析失败、
/// 预算超限、Web 端编译轨不可达，用户全都看不到。所有 notice 写入必须
/// 走这里；警告类（warning=true）用暖色条。空串（settings 写入的哑回调
/// `SetNotice("")`）只清字段，不产生 toast。长文本按 toast 文案宽度截断
/// （toast 视图是定宽 300 的单行）。
pub fn with_notice(model : Model, notice : String, warning : Bool) -> Model {
  if notice == "" {
    return { ..model, notice: "", }
  }
  push_toast({ ..model, notice, }, @chrome.fit_label(notice, 280.0), warning)
}

///|
/// Studio 自有命令：贡献表（M5）是唯一事实来源——id 不在表里就是未知命令
/// （no-op），表与处理器不再可能成对漂移。Apply 走纯更新，Dispatch 走
/// 效果派发回程序环（服务臂接住），与点按钮完全同一条状态转移。
fn run_studio_command(model : Model, id : String) -> (Model, @moui.Effect[Msg]) {
  let ctx : StudioCtx = { model, t: translator(model), }
  match @wb.find_command(studio_command_registry(), id) {
    None => (model, @moui.Effect::none())
    Some(command) =>
      match (command.run)(ctx) {
        @wb.Apply(msg) => update_pure(model, msg)
        @wb.Dispatch(msg) => (model, @moui.Effect::dispatch(emit => emit(msg)))
        @wb.Unavailable => (model, @moui.Effect::none())
      }
  }
}

///|
/// 代码草稿回归 IR 渲染：丢弃手改，按**当前外观**重新渲染当前子程序。
/// 外观感知（实测缺陷）：旧实现无条件按 DSL 语言渲染——MoonBit 外观下
/// 点「按 IR 重渲染」会把草稿打回中文 DSL 且没有回去的入口。
fn restore_code_draft(model : Model) -> (Model, @moui.Effect[Msg]) {
  match current_handler(model) {
    None => (model, @moui.Effect::none())
    Some(handler) => {
      let rendered = render_code_appearance(model, handler)
      (
        log_line(
          { ..model, code_draft: rendered, code_error: "", },
          LogInfo,
          "app.log.restore",
        ),
        @moui.Effect::none(),
      )
    }
  }
}

///|
/// toast 老化：每秒 +1，满 TOAST_SECONDS 秒即消失（自动，无需手点）。
fn age_toasts(model : Model) -> Model {
  let kept : Array[ToastEntry] = []
  for toast in model.toasts {
    if toast.age + 1 < TOAST_SECONDS {
      kept.push(ToastEntry::{
        text: toast.text,
        warning: toast.warning,
        age: toast.age + 1,
      })
    }
  }
  { ..model, toasts: kept, }
}
