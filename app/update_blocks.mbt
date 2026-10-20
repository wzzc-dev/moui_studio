///|
/// 积木域状态转移：选中/编辑/提交/删除，全部经语句路径写回 IR。

///|
/// 当前选中 handler 的积木链（无选中子程序 = 空链）。
pub fn block_chain_of(model : Model) -> Array[@blocks.BlockItem] {
  // 走**统一编辑目标**（`current_target`）：事件子程序与自定义积木的体
  // 是同一种东西，画布只认「当前在编辑哪个体」。这样建出来的自定义积木
  // 立刻就能在同一个画布上编辑——不需要第二套画布。
  match current_target(model) {
    None => []
    Some(target) => @blocks.block_chain(target.body)
  }
}

///|
/// 调色板拖拽指针的**视口 → 链**换算。
///
/// 拖拽手势被发起它的调色板行捕获（runtime 捕获语义），画布的手势收不到
/// 移动事件——指针坐标只有行知道，而行的回调只能给出**视口坐标**。视口
/// → 链需要画布内容节点的**布局帧**（随滚动移动，与画布手势收到的 frame
/// 同一值），由组合根注入的锚点回调按键 "blocks-canvas" 取。换算与画布
/// 手势同一套逆映射（`blocks_to_chain` ∘ `blocks_chain_y`），两条路径
/// 不会分叉。
pub fn palette_pointer_to_chain(
  model : Model,
  canvas_frame_of : (String) -> @core.Rect?,
  pointer : @core.Point,
) -> (Double, Double)? {
  match canvas_frame_of("blocks-canvas") {
    None => None
    Some(frame) => {
      let zoom = model.blocks_ui.canvas_zoom
      let scale = if zoom > 0.0 { zoom } else { 1.0 }
      let origin = match current_handler(model) {
        Some(handler) => script_origin_of(model, handler)
        None =>
          ScriptOrigin::{
            x: @blk.BLOCKS_SCRIPT_MARGIN,
            y: @blk.BLOCKS_SCRIPT_MARGIN,
          }
      }
      let note = if target_note(model) == "" {
        0.0
      } else {
        @blk.BLOCKS_NOTE_HEIGHT
      }
      let lx = (pointer.x - frame.origin.x - origin.x) / scale
      let ly = (pointer.y - frame.origin.y - origin.y) / scale - note
      Some((lx, ly))
    }
  }
}

///|
/// 调色板拖拽中的指针回报（PaletteDragPointer）：换算成功 → 记录链坐标
/// （画布插入线的数据源）；画布帧缺席（首帧尚未布局）→ 忽略采样。
pub fn update_palette_drag_pointer(
  model : Model,
  canvas_frame_of : (String) -> @core.Rect?,
  pointer : @core.Point,
) -> (Model, @moui.Effect[Msg]) {
  match palette_pointer_to_chain(model, canvas_frame_of, pointer) {
    Some((lx, ly)) =>
      update_pure(
        model,
        BlocksUiOp(@blk.PaletteDragMoved(@geometry.Point::new(x=lx, y=ly))),
      )
    None => (model, @moui.Effect::none())
  }
}

///|
/// 调色板拖拽松手（PaletteDropAt）：指针在画布帧内 → 换算成链坐标走
/// `PaletteDrop` 落槽（语句）或首洞落表达式；画布帧缺席或指针在画布外
/// → 取消（清拖拽瞬态，不插入）——Scratch 的「拖回调色板 = 放弃」。
pub fn update_palette_drop_at(
  model : Model,
  canvas_frame_of : (String) -> @core.Rect?,
  pointer : @core.Point,
  avail_width : Double,
) -> (Model, @moui.Effect[Msg]) {
  let frame = canvas_frame_of("blocks-canvas")
  match palette_pointer_to_chain(model, canvas_frame_of, pointer) {
    Some((lx, ly)) =>
      match frame {
        Some(rect) if rect.contains(pointer) =>
          if model.blocks_ui.expr_drag is Some(_) {
            update_pure(
              model,
              palette_expression_drop_at(model, lx, ly, avail_width),
            )
          } else {
            update_pure(model, PaletteDrop(lx, ly, avail_width))
          }
        _ => update_pure(model, BlocksUiOp(@blk.PaletteDragCancel))
      }
    None => update_pure(model, BlocksUiOp(@blk.PaletteDragCancel))
  }
}

///|
/// 表达式拖拽的落点：**行命中 + 该行首洞**。
///
/// 洞的精确命中（`blocks_slot_hit`）需要 TextSystem 度量，它只在布局
/// 上下文里，update 拿不到——按「指到哪行就落进那行的第一个洞」降级
/// （单洞语句是绝对多数；多洞语句用户可以落定后再用值编辑微调）。
/// 行是装饰块或该行没有洞 → 走 `ExpressionDrop(-1, [])` 的既有拒绝
/// 提示路径。
fn palette_expression_drop_at(
  model : Model,
  lx : Double,
  ly : Double,
  avail_width : Double,
) -> Msg {
  let blocks = block_chain_of(model)
  let (display_texts, _lead_texts) = block_row_texts(translator(model), blocks)
  let hit = @blk.blocks_hit_index(blocks, lx, ly, avail_width~, display_texts~)
  let hole = if hit >= 0 {
    @blk.blocks_first_slot_path(blocks[hit])
  } else {
    None
  }
  match hole {
    Some(path) => ExpressionDrop(hit, path)
    None => ExpressionDrop(-1, [])
  }
}

///|
fn block_at(
  blocks : Array[@blocks.BlockItem],
  index : Int32,
) -> @blocks.BlockItem? {
  if index < 0 || index >= blocks.length() {
    None
  } else {
    Some(blocks[index])
  }
}

///|
/// 选中积木：把该语句的 DSL 源码预填进编辑草稿。
fn select_block(model : Model, index : Int32) -> Model {
  let blocks = block_chain_of(model)
  let draft = match block_at(blocks, index) {
    Some(item) =>
      if item.path.length() == 0 {
        ""
      } else {
        match current_target(model) {
          None => ""
          Some(target) =>
            match @blocks.stmt_at(target.body, item.path) {
              Some(stmt) =>
                @studio_lang.render_stmts([stmt], model.language.dsl_language())
                .trim_end()
                .to_owned()
              None => ""
            }
        }
      }
    None => ""
  }
  { ..model, selected_block: index, block_draft: draft, }
}

///|
/// 键盘在积木链里上下移动选中（↑/↓）。步长 `step`（+1 / -1）。
///
/// 三条纪律（与鼠标点选同源，经 `select_block` 单一漏斗）：
/// - **不停在装饰块上**：`else/end` 这类装饰块没有对应语句（`path` 为空），
///   选中它们没有可编辑的对象，所以跳过——落到下一条**可编辑**语句上。
/// - **越界不循环**：走到端点就保持原选中（循环会让「按到底」突然跳回开头，
///   用户以为选中丢了；清空则等于把用户丢到「什么都没选」）。
/// - **不写 IR**：纯选中态变更，不产生撤销点。
pub fn select_block_step(model : Model, step : Int32) -> Model {
  let blocks = block_chain_of(model)
  if blocks.length() == 0 {
    return model
  }
  let from = model.selected_block
  // 起点：没选中时按方向从端点进入
  let mut index = if from < 0 {
    if step >= 0 {
      -1
    } else {
      blocks.length()
    }
  } else {
    from
  }
  let mut remaining = if from < 0 { 1 } else { step.abs() }
  while remaining > 0 {
    let next = index + (if step >= 0 { 1 } else { -1 })
    if next < 0 || next >= blocks.length() {
      return model
    }
    index = next
    // 装饰块（没有对应语句）不是可停靠的目标，继续走
    if blocks[index].path.length() > 0 {
      remaining = remaining - 1
    }
  }
  select_block(model, index)
}

///|
/// 按语句路径选中积木（编译诊断行号 → 生成源码里的语句路径 → 此处）。
/// 与 `SelectBlock` 的区别是入口按路径而非链下标，供「编译错误点击跳积木」
/// 使用：路径是 IR 的稳定坐标，链下标随展开块（if/end）变化。
pub fn select_block_by_path(model : Model, path : Array[Int32]) -> Model {
  if path.length() == 0 {
    return model
  }
  let blocks = block_chain_of(model)
  let mut index = -1
  let mut i = 0
  while i < blocks.length() {
    if index == -1 && @blk.blocks_same_path(blocks[i].path, path) {
      index = i
    }
    i = i + 1
  }
  if index == -1 {
    model
  } else {
    select_block({ ..model, mode: ModeBlocks, }, index)
  }
}

///|
/// 积木编辑回写：草稿解析成单条语句 → 按路径替换 → IR 更新 →
/// 代码视图草稿与积木选择同步刷新（三视图同源）。
fn commit_block(model : Model) -> Model {
  match current_target(model) {
    None => model
    Some(target) => {
      let blocks = block_chain_of(model)
      match block_at(blocks, model.selected_block) {
        None => model
        Some(item) =>
          if item.path.length() == 0 {
            model
          } else {
            try {
              let body = @studio_lang.parse_handler_body(
                model.block_draft,
                model.language.dsl_language(),
              )
              if body.length() == 0 {
                model
              } else {
                // 克隆后再手术：replace_stmt_at 是就地语义，
                // 直接改 handler.body 会污染撤销快照（共享数组引用）
                let working = @blocks.clone_stmts(target.body)
                let updated = @blocks.replace_stmt_at(
                  working,
                  item.path,
                  body[0].stmt,
                )
                let next = replace_target_body(model, target.label, updated)
                // 同步代码视图（同一份 IR 的另一种渲染）
                let synced = sync_code_draft(next)
                { ..synced, notice: "", }
              }
            } catch {
              _ =>
                with_notice(
                  model,
                  text(translator(model), "app.status.parse_error"),
                  true,
                )
            }
          }
      }
    }
  }
}

///|
/// 积木删除回写：按路径删除语句并同步其他视图。
fn delete_block(model : Model) -> Model {
  match current_target(model) {
    None => model
    Some(target) => {
      let blocks = block_chain_of(model)
      match block_at(blocks, model.selected_block) {
        None => model
        Some(item) =>
          if item.path.length() == 0 {
            model
          } else {
            // 同上：克隆后再手术（撤销快照安全）
            let working = @blocks.clone_stmts(target.body)
            let updated = @blocks.delete_stmt_at(working, item.path)
            let next = replace_target_body(model, target.label, updated)
            let synced = sync_code_draft(next)
            { ..synced, selected_block: -1, block_draft: "", }
          }
      }
    }
  }
}

///|
/// 积木复制回写（Scratch/Blockly 的 Duplicate）：克隆选中语句插入其
/// 同层下一位，选中新副本。编辑卡上的复制图标与拖拽并列的第三条编辑路径。
fn duplicate_block(model : Model) -> Model {
  match current_target(model) {
    None => model
    Some(target) => {
      let blocks = block_chain_of(model)
      match block_at(blocks, model.selected_block) {
        None => model
        Some(item) =>
          if item.path.length() == 0 {
            model
          } else {
            // 克隆后再手术（撤销快照安全，同 commit/delete）
            let working = @blocks.clone_stmts(target.body)
            let stmt = match @blocks.stmt_at(working, item.path) {
              Some(stmt) => stmt
              None => return model
            }
            let parent = @blk.blocks_parent_of(item.path)
            let index = item.path[item.path.length() - 1]
            match @blocks.stmt_list_at(working, parent) {
              // 插入到原语句之后：IR 列表与积木链同序，链下标即列表下标
              Some(list) => list.insert(index + 1, @blocks.clone_stmt(stmt))
              None => return model
            }
            let next = replace_target_body(model, target.label, working)
            let synced = sync_code_draft(next)
            let new_path = {
              let path : Array[Int32] = []
              for part in parent {
                path.push(part)
              }
              path.push(index + 1)
              path
            }
            select_block_by_path(synced, new_path)
          }
      }
    }
  }
}

///|
/// 用新 body 替换选中 handler（其余 handler 原样）。
fn replace_handler_body(
  model : Model,
  handler : @ir.Handler,
  body : Array[@ir.Stmt],
) -> Model {
  // 兼容入口（仍按 handler 键写回）。新的调用点请用 `replace_target_body`：
  // 它按**当前编辑目标**分派，于是同一套积木操作对自定义积木也生效。
  replace_target_body(
    model,
    "\{handler.control_name}@\{handler.event.tag()}",
    body,
  )
}

///|
/// 积木域消息处理：未命中的消息返回 None 交还链式分发。
fn update_blocks_msgs(model : Model, msg : Msg) -> (Model, @moui.Effect[Msg])? {
  match msg {
    EditBlock(source) =>
      Some(({ ..model, block_draft: source, }, @moui.Effect::none()))
    BlocksCanvasTap(x, y, avail_width) =>
      // 点选积木（拖拽结束的 tap 以 block_drag 态区分，不重复选中）
      if model.block_drag is Some(_) {
        Some((model, @moui.Effect::none()))
      } else {
        let blocks = block_chain_of(model)
        // 展示文本与绘制同源（块宽随内容收紧后宽度进了几何）：
        // 命中不吃同一份，块尾的点击就会落空。
        let (display_texts, _lead_texts) = block_row_texts(
          translator(model),
          blocks,
        )
        let hit = @blk.blocks_hit_index(
          blocks,
          x,
          y,
          avail_width~,
          display_texts~,
        )
        if hit >= 0 {
          Some((select_block(model, hit), @moui.Effect::none()))
        } else {
          Some((model, @moui.Effect::none()))
        }
      }
    BlocksCanvasPress(x, y, avail_width) => {
      // 按上积木：建立同层拖拽态；落空清除。**按下不换选中**——选中决定
      // 编辑卡的拆分位置，手势中途换选中会让画布在手势进行时重构（上下段
      // 重新分配），指针捕获随元素重建而丢失，拖拽断在第一帧。选中交给
      // 松手后的 tap / 选中跟随。
      let blocks = block_chain_of(model)
      let (display_texts, _lead_texts) = block_row_texts(
        translator(model),
        blocks,
      )
      let hit = @blk.blocks_hit_index(
        blocks,
        x,
        y,
        avail_width~,
        display_texts~,
      )
      if hit >= 0 && blocks[hit].path.length() > 0 {
        let item = blocks[hit]
        let list_path = @blk.blocks_parent_of(item.path)
        let sibling_index = item.path[item.path.length() - 1]
        Some(
          (
            {
              ..model,
              block_drag: Some(BlocksDragState::{
                list_path,
                from_path: item.path,
                from: sibling_index,
                to: sibling_index,
                to_list: list_path,
                valid: true,
              }),
            },
            @moui.Effect::none(),
          ),
        )
      } else {
        Some(({ ..model, block_drag: None, }, @moui.Effect::none()))
      }
    }
    BlocksCanvasDragTo(_, y, avail_width) =>
      // 拖拽中：按指针 y 更新同层落槽（x 不参与纵向落槽判定）。
      // 落槽用**基础**矩形（插入位置按「行」算，不用视觉扩张后的 C 矩形）。
      match model.block_drag {
        None => Some((model, @moui.Effect::none()))
        Some(drag) => {
          let blocks = block_chain_of(model)
          // 展示文本与绘制同源：矩形（宽度）随内容收紧后，两处各算一份
          // 宽度会让落槽指示与块体错开。纵向判定只吃 y，但矩形必须同源。
          let (display_texts, _lead_texts) = block_row_texts(
            translator(model),
            blocks,
          )
          let rects = @blk.blocks_item_rects(
            blocks,
            avail_width~,
            display_texts~,
          )
          // 落点列表：指针停在哪个容器里，就落到哪个容器的语句列表。
          // 停在某个 C 形头的行上 → 落进它的**体内**（Scratch 的「拖进洞里」）；
          // 否则与源同层（同层重排）。
          let to_list = @blk.blocks_drop_list_of(
            blocks,
            rects,
            y,
            drag.list_path,
          )
          let slot = @blk.blocks_drop_slot(blocks, to_list, y, rects)
          // **落点有效性**：语言规则不允许的落点（如 `break` 放进非循环
          // 容器）在拖动过程中就标出来——用户不必「拖进去 → 运行 → 看报错」。
          // 用拖拽块的语句类型判定；取不到语句时按「接受」处理（保守：
          // 宁可放行交给语言层报错，也不要因为查不到就拒绝合法拖拽）。
          // 用 drag 里存好的**源路径**取语句（不重算链下标：那条路径在
          // 按下时就定好了，且跨层移动正是靠它）。
          let valid = match current_handler(model) {
            None => true
            Some(handler) =>
              match @blocks.stmt_at(handler.body, drag.from_path) {
                Some(stmt) =>
                  @blocks.drop_accepts_stmt(handler.body, to_list, stmt)
                None => true
              }
          }
          Some(
            (
              {
                ..model,
                block_drag: Some({ ..drag, to: slot, to_list, valid, }),
              },
              @moui.Effect::none(),
            ),
          )
        }
      }
    BlocksCanvasRelease =>
      // 松手：落槽有效（非原位/原位下一位）才重排；过撤销点
      match model.block_drag {
        None => Some((model, @moui.Effect::none()))
        Some(drag) => {
          // 「原位」判定**交给领域层**，不要在这里另算一份：
          // 同层拖动现在是**整栈**语义（抓住一块，它和下面所有块一起走），
          // 原位条件是「插入位置 == from」——而 `drag.to == from + 1` 这种
          // 单条语义的旧判据会把「拖到栈尾之后」误判成原位、整段不动
          // （实测拖到末尾毫无反应）。跨层则任何落点都是真移动（换了容器）。
          //
          // 所以这里只判「跨层」，同层是否真移动由 `reorder_stack` 返回
          // `None`（原位）来表达。
          let cross = !@blk.blocks_same_path(drag.list_path, drag.to_list)
          // **无效落点直接拒绝**（不写 IR、不给撤销点）：这是 Scratch 的
          // 「放不进去」——拖着时已经标红，松手就该什么都不发生，而不是
          // 塞进一个语言层随后会报错的语句。
          let moved = drag.valid
          let next = if moved {
            with_undo_point(model, "", m => {
              match current_handler(m) {
                None => m
                Some(handler) => {
                  // 跨层：把语句整条搬进目标列表；同层：既有重排。
                  // 源路径在按下时就存好了（链下标在跨层时不够用）。
                  let from_path = drag.from_path
                  if cross && from_path.length() > 0 {
                    match
                      @blocks.move_stmt_at(
                        handler.body,
                        from_path,
                        drag.to_list,
                        drag.to,
                      ) {
                      Some(new_body) =>
                        replace_handler_body(m, handler, new_body)
                      None => m
                    }
                  } else {
                    // 同层拖动按**整栈**语义：抓住一块，它和它下面的所有块
                    // 一起移动（Scratch 的手感）。用单条重排会把一段逻辑
                    // 拆散——实测拖第 2 块时第 3、4 块留在原地。
                    match
                      @blocks.reorder_stack(
                        handler.body,
                        drag.list_path,
                        drag.from,
                        drag.to,
                      ) {
                      Some(new_body) =>
                        replace_handler_body(m, handler, new_body)
                      None => m
                    }
                  }
                }
              }
            })
          } else {
            model
          }
          // 重排后选中跟随被移动的语句（新链下标 = list_path ++ 新语句位）
          let new_stmt_index = if drag.to > drag.from {
            drag.to - 1
          } else {
            drag.to
          }
          let new_path = {
            let path : Array[Int32] = []
            for part in drag.list_path {
              path.push(part)
            }
            path.push(new_stmt_index)
            path
          }
          let chain = block_chain_of(next)
          let mut hit = -1
          let mut i = 0
          for item in chain {
            if hit == -1 && @blk.blocks_same_path(item.path, new_path) {
              hit = i
            }
            i = i + 1
          }
          // 选中走 select_block：草稿与新选中同步（按下已不再即时选中，
          // 拖拽别的块时草稿还停留在旧选中上，直接改下标会错配）
          let cleared = { ..next, block_drag: None, }
          let result = if hit >= 0 {
            select_block(cleared, hit)
          } else {
            cleared
          }
          Some((result, @moui.Effect::none()))
        }
      }
    CommitBlock =>
      Some(
        (
          // 仅当语句真的写回 IR 时产生还原点（解析失败为 no-op）
          with_undo_point(model, "", m => commit_block(m)),
          @moui.Effect::none(),
        ),
      )
    DuplicateBlock =>
      Some(
        (
          // 与 commit/delete 同一口径：写回 IR 才产生还原点（no-op 不入栈）
          with_undo_point(model, "", m => duplicate_block(m)),
          @moui.Effect::none(),
        ),
      )
    DeleteBlock =>
      Some(
        (with_undo_point(model, "", m => delete_block(m)), @moui.Effect::none()),
      )
    EditTargetNote(note) =>
      Some((set_target_note(model, note), @moui.Effect::none()))
    EditBlockValue(block_index, expr_path) =>
      // 点值 → 就地编辑。初始文本取该叶子**当前的规范写法**（不是整行草稿），
      // 这样打开输入框时看到的就是那个值本身。打开需读 program，住壳；
      // 写进 blocks_ui 切片的值编辑态。
      Some(
        (
          match open_value_edit(model, block_index, expr_path) {
            Some((next, initial)) => {
              next.blocks_ui.block_value_edit = Some(
                (block_index, expr_path, initial),
              )
              next
            }
            None => model
          },
          @moui.Effect::none(),
        ),
      )
    // 值编辑草稿输入（BlockValueInput）/取消（BlockValueCancel）已随
    // blocks_ui 切片出壳；提交（BlockValueCommit）在壳（提交 IR）。
    BlockValueCommit => Some((commit_value_edit(model), @moui.Effect::none()))
    // 语句面板开合/分类切换（ToggleStatementPalette）已随 blocks_ui 切片出壳。
    SelectBlockStep(step) =>
      Some((select_block_step(model, step), @moui.Effect::none()))
    // 右键：先选中被点的块（菜单动作作用于它），再开菜单。点空白处
    // （index < 0）只开画布级菜单，不动选中——右键空白不该清掉用户
    // 正在编辑的块。选中块是真源留壳；菜单锚点写进 blocks_ui 切片。
    BlocksContextMenu(index, x, y) => {
      let next = if index >= 0 {
        { ..model, selected_block: index, }
      } else {
        model
      }
      next.blocks_ui.block_menu = Some((index, x, y))
      Some((next, @moui.Effect::none()))
    }
    // 菜单关闭（BlocksContextMenuClose）随 blocks_ui 切片；打开在本臂上方。
    // 先关菜单（blocks_ui 切片），再把动作消息喂回同一条 update 链——
    // 菜单动作与其它入口（右栏按钮、快捷键）走完全相同的处理路径。
    BlocksMenuAction(action) => {
      let next = update_pure(model, action).0
      next.blocks_ui.block_menu = None
      Some((next, @moui.Effect::none()))
    }
    RunSingleBlock => Some((run_single_block(model), @moui.Effect::none()))
    // 语句/表达式拖放的「开始拖骨架」（PaletteDragStart /
    // PaletteExprDragStart）与画布滚动（BlocksAutoScroll / BlocksScrolled）
    // 都是纯 UI 瞬态，已随 blocks_ui 切片出壳；落拖（Drop*）在下方提交 IR。
    ExpressionDrop(block_index, expr_path) =>
      // 洞的解析（段级命中）由**画布**完成（`TextSystem` 只在布局上下文里，
      // 而洞的位置必须与绘制用同一把尺）；这里只做落地。
      // `block_index < 0` = 没落在任何洞上：给提示而不是静默。
      match model.blocks_ui.expr_drag {
        None => Some((model, @moui.Effect::none()))
        Some(template) =>
          if block_index < 0 {
            let cleared = { ..model, }
            cleared.blocks_ui.expr_drag = None
            Some(
              (
                with_notice(
                  cleared,
                  text(translator(model), "app.expr.drop.no_slot"),
                  true,
                ),
                @moui.Effect::none(),
              ),
            )
          } else {
            let cleared = { ..model, }
            cleared.blocks_ui.expr_drag = None
            Some(
              (
                update_pure(
                  cleared,
                  DropExpression(template, block_index, expr_path),
                ).0,
                @moui.Effect::none(),
              ),
            )
          }
      }
    InsertStatement(category_index, template_index) =>
      Some(
        (
          // 与 commit/delete 同一口径：写回 IR 才产生还原点
          with_recent_undo_point(
            model,
            text(translator(model), "app.recent.action.insert_stmt"),
            "app.recent.action.insert_stmt",
            m => insert_statement(m, category_index, template_index),
          ),
          @moui.Effect::none(),
        ),
      )
    // **自制积木组**的插入：骨架文本由「函数名 + 占位实参」拼出，其余
    // （解析校验 / 落点 / 选中跟随 / 收面板）与 `insert_statement_at` 完全
    // 同一条——为它另写一套落地路径就会有两条语义分叉。
    InsertCustomFunction(function_index) =>
      Some(
        (
          with_recent_undo_point(
            model,
            text(translator(model), "app.recent.action.insert_stmt"),
            "app.recent.action.insert_stmt",
            m => insert_custom_function(m, function_index),
          ),
          @moui.Effect::none(),
        ),
      )
    DropStatement(category, template, list_path, at) =>
      Some(
        (
          with_recent_undo_point(
            model,
            text(translator(model), "app.recent.action.insert_stmt"),
            "app.recent.action.insert_stmt",
            m => {
              insert_statement_at(m, category, template, Some((list_path, at)))
            },
          ),
          @moui.Effect::none(),
        ),
      )
    PaletteDrop(x, y, avail_width) =>
      // 落点由**画布**算：调色板只记了「在拖哪条骨架」，指针位置只有这里
      // 才知道。算完派发 `DropStatement`（与点击插入共用同一条落地路径）。
      match model.blocks_ui.palette_drag {
        None => Some((model, @moui.Effect::none()))
        Some((category, template, _pointer)) => {
          let blocks = block_chain_of(model)
          // 展示文本与绘制同源（块宽随内容收紧后宽度进了几何），
          // 命中不吃同一份，「拖到块尾松手」就会落空。
          let (display_texts, _lead_texts) = block_row_texts(
            translator(model),
            blocks,
          )
          let rects = @blk.blocks_item_rects(
            blocks,
            avail_width~,
            display_texts~,
          )
          // 横向决定**容器**（拖进 C 形块的洞里），纵向决定槽位。
          let hit = @blk.blocks_hit_index(
            blocks,
            x,
            y,
            avail_width~,
            display_texts~,
          )
          let (list_path, at) = if hit >= 0 && blocks[hit].path.length() > 0 {
            let item = blocks[hit]
            let r = rects[hit]
            let lower = y >= r.origin.y + r.size.height / 2.0
            let is_head = match item.kind {
              @blocks.BkIf | @blocks.BkCountLoop | @blocks.BkWhile => true
              _ => false
            }
            if is_head && lower {
              let body : Array[Int32] = []
              for part in item.path {
                body.push(part)
              }
              body.push(0)
              (body, 0)
            } else {
              let parent = @blk.blocks_parent_of(item.path)
              let idx = item.path[item.path.length() - 1]
              (parent, if lower { idx + 1 } else { idx })
            }
          } else {
            let top : Array[Int32] = []
            (top, blocks.length())
          }
          let cleared = { ..model, }
          cleared.blocks_ui.palette_drag = None
          Some(
            (
              update_pure(
                cleared,
                DropStatement(category, template, list_path, at),
              ).0,
              @moui.Effect::none(),
            ),
          )
        }
      }
    DropExpression(template_index, block_index, expr_path) =>
      // 报告块落入洞：过 `parse_expression_text`（与手打表达式同一条校验链），
      // 解析失败只提示、不塞非法表达式；成功则走 `replace_expr_at` 这一条
      // 表达式级手术（IR 仍是唯一真源）。
      Some(
        (
          with_recent_undo_point(
            model,
            text(translator(model), "app.recent.action.insert_expr"),
            "app.recent.action.insert_expr",
            m => drop_expression(m, template_index, block_index, expr_path),
          ),
          @moui.Effect::none(),
        ),
      )
    _ => None
  }
}

///|
/// 给当前编辑目标写说明（事件子程序或自定义积木）。
///
/// 只写**当前界面语言**那一份：另一份留空，读取端（`handler_note`）已有
/// 「本语言为空则回退另一语言」的逻辑。这样切语言时不会看到一段用另一种
/// 语言写死的旧文案。
///
/// 不产生撤销点：说明是**注释性元数据**，不参与执行；为它压栈会让「撤销」
/// 在用户改了一句逻辑之后先退回「注释被改前」——那不是用户想撤的东西。
fn set_target_note(model : Model, note : String) -> Model {
  let target = match current_target(model) {
    None => return model
    Some(target) => target
  }
  let trimmed = note.trim().to_owned()
  if target.is_function {
    let functions : Array[@ir.FuncDef] = []
    for func in model.program.functions {
      if func.name == target.label {
        let updated = if model.language is ZhHans {
          @ir.FuncDef::{ ..func, note_zh: trimmed, }
        } else {
          @ir.FuncDef::{ ..func, note_en: trimmed, }
        }
        functions.push(updated)
      } else {
        functions.push(func)
      }
    }
    { ..model, program: { ..model.program, functions, }, }
  } else {
    let handlers : Array[@ir.Handler] = []
    for handler in model.program.handlers {
      if "\{handler.control_name}@\{handler.event.tag()}" == target.label {
        let updated = if model.language is ZhHans {
          @ir.Handler::{ ..handler, note_zh: trimmed, }
        } else {
          @ir.Handler::{ ..handler, note_en: trimmed, }
        }
        handlers.push(updated)
      } else {
        handlers.push(handler)
      }
    }
    { ..model, program: { ..model.program, handlers, }, }
  }
}

///|
/// 当前编辑目标的说明文本（本语言优先，回退另一语言——与
/// `update_ai.mbt` 的 `handler_note` 同一口径，两处不一致会让「看到的」
/// 与「AI 读到的」不是同一段话）。
pub fn target_note(model : Model) -> String {
  match current_target(model) {
    None => ""
    Some(target) =>
      if target.is_function {
        match selected_function(model) {
          None => ""
          Some(func) =>
            if model.language is ZhHans {
              if func.note_zh == "" {
                func.note_en
              } else {
                func.note_zh
              }
            } else if func.note_en == "" {
              func.note_zh
            } else {
              func.note_en
            }
        }
      } else {
        match current_handler(model) {
          None => ""
          Some(handler) =>
            if model.language is ZhHans {
              if handler.note_zh == "" {
                handler.note_en
              } else {
                handler.note_zh
              }
            } else if handler.note_en == "" {
              handler.note_zh
            } else {
              handler.note_en
            }
        }
      }
  }
}

///|
/// 打开值编辑：校验该位置**确实是叶子值**，返回初始文本。
///
/// 只对叶子值开放（字面量/变量）：洞（运算、调用）不接受就地编辑——那是
/// 「拖一块进去」的位置。不校验就会出现「点运算的空槽弹出文本框」，
/// 与拖拽语义冲突。
fn open_value_edit(
  model : Model,
  block_index : Int32,
  expr_path : Array[Int32],
) -> (Model, String)? {
  let target = match current_target(model) {
    None => return None
    Some(target) => target
  }
  let chain = block_chain_of(model)
  let item = match block_at(chain, block_index) {
    None => return None
    Some(item) => item
  }
  if item.path.length() == 0 {
    return None
  }
  let expr = match @blocks.expr_at(target.body, item.path, expr_path) {
    None => return None
    Some(expr) => expr
  }
  let initial = match @blocks.expr_leaf_text(expr) {
    None => return None
    Some(text) => text
  }
  Some((select_block(model, block_index), initial))
}

///|
/// 提交值编辑：把叶子换成解析后的新值，写回 IR。
///
/// 走 `replace_expr_at`（**表达式级**手术）而不是重解析整行——整行草稿会把
/// 用户没碰的部分也重写一遍（缩进、括号、内建名的规范写法都可能变），
/// 而用户只想改一个数。
///
/// 解析用 `parse_leaf_value`：打什么都存得下去（数字→数字、像变量名的→
/// 变量、其余→文本），不报「解析失败」——值格子里报错等于「改了没反应」。
/// 关闭值就地编辑（blocks_ui 切片嵌套字段的清空包装；提交/失败/取消统一用）。
fn clear_value_edit(model : Model) -> Model {
  let next = { ..model, }
  next.blocks_ui.block_value_edit = None
  next
}

///|
fn commit_value_edit(model : Model) -> Model {
  let (block_index, expr_path, draft) = match model.blocks_ui.block_value_edit {
    None => return model
    Some(state) => state
  }
  let target = match current_target(model) {
    None => return clear_value_edit(model)
    Some(target) => target
  }
  let chain = block_chain_of(model)
  let item = match block_at(chain, block_index) {
    None => return clear_value_edit(model)
    Some(item) => item
  }
  let parsed = @blocks.parse_leaf_value(draft, model.language.dsl_language())
  let updated = match
    @blocks.replace_expr_at(target.body, item.path, expr_path, parsed) {
    Some(body) => body
    None => return clear_value_edit(model)
  }
  let next = replace_target_body(model, target.label, updated)
  let synced = sync_code_draft(next)
  clear_value_edit(select_block(synced, block_index))
}

///|
/// 插入一条语句骨架（面板的默认落点：选中块之后）。
fn insert_statement(
  model : Model,
  category_index : Int32,
  template_index : Int32,
) -> Model {
  insert_statement_at(model, category_index, template_index, None)
}

///|
/// 插入一条**自定义函数调用**（自制积木组）。
///
/// 骨架 = `名字(0, 0, …)`（占位实参按形参个数生成，用 `0` 是因为它是任何
/// 形参类型都吃得下的字面量；用形参名会与程序里的变量重名、解析出来是另
/// 一回事）。拼出的文本走 `parse_handler_body` 同一条校验链——解析失败
/// 什么都不做，与模板插入的失败口径一致。
fn insert_custom_function(model : Model, function_index : Int32) -> Model {
  if function_index < 0 || function_index >= model.program.functions.length() {
    return model
  }
  let func = model.program.functions[function_index]
  let skeleton = @blk.custom_call_label(@blk.CustomEntry::{
    name: func.name,
    arity: func.params.length(),
  })
  let parsed = @studio_lang.parse_handler_body(
    skeleton,
    model.language.dsl_language(),
  ) catch {
    _ =>
      return with_notice(
        model,
        text(translator(model), "app.stmt.palette.parse_error"),
        true,
      )
  }
  if parsed.length() == 0 {
    return model
  }
  // 落点与 `insert_statement_at` 同一判据：选中块的下一行，无选中 → 顶层末尾
  let target = match current_target(model) {
    None =>
      return with_notice(
        model,
        text(translator(model), "app.stmt.palette.no_handler"),
        true,
      )
    Some(value) => value
  }
  let (list_path, at) = {
    let chain = block_chain_of(model)
    match block_at(chain, model.selected_block) {
      Some(item) if item.path.length() > 0 => {
        let parent = @blk.blocks_parent_of(item.path)
        (parent, item.path[item.path.length() - 1] + 1)
      }
      _ => {
        let top : Array[Int32] = []
        (top, target.body.length())
      }
    }
  }
  let mut working = @blocks.clone_stmts(target.body)
  let mut insert_at = at
  let mut inserted = 0
  for traced in parsed {
    match @blocks.insert_stmt_at(working, list_path, insert_at, traced.stmt) {
      Some(next) => {
        working = next
        insert_at = insert_at + 1
        inserted = inserted + 1
      }
      None => ()
    }
  }
  if inserted == 0 {
    return model
  }
  let next = replace_target_body(model, target.label, working)
  let synced = sync_code_draft(next)
  let new_path : Array[Int32] = []
  for part in list_path {
    new_path.push(part)
  }
  new_path.push(at)
  synced.blocks_ui.statement_palette_open = false
  let selected = select_block_by_path(synced, new_path)
  { ..selected, notice: "", }
}

// （BLOCKS_AUTOSCROLL_STEP 随 blocks_ui 切片迁入 plugins/blocks 的
// BLOCKS_UI_AUTOSCROLL_STEP。）

///|
/// 报告块落入洞的落地实现（与 `insert_statement_at` 同一纪律：先解析校验、
/// 再手术、失败即提示）。
///
/// 选中跟随：替换后仍选中同一条语句的**根**（洞的内容换了，但用户操作的
/// 还是那一行）——跳到别的块会让右栏编辑卡突然换内容。
fn drop_expression(
  model : Model,
  template_index : Int32,
  block_index : Int32,
  expr_path : Array[Int32],
) -> Model {
  let templates = @blk.expression_templates()
  if template_index < 0 || template_index >= templates.length() {
    return model
  }
  let target = match current_target(model) {
    None =>
      return with_notice(
        model,
        text(translator(model), "app.stmt.palette.no_handler"),
        true,
      )
    Some(target) => target
  }
  let chain = block_chain_of(model)
  let item = match block_at(chain, block_index) {
    None => return model
    Some(item) => item
  }
  if item.path.length() == 0 {
    // 装饰块没有可替换的表达式
    return model
  }
  let parsed = @studio_lang.parse_expression_text(
    templates[template_index].skeleton(model.language.dsl_language()),
    model.language.dsl_language(),
  ) catch {
    _ =>
      return with_notice(
        model,
        text(translator(model), "app.stmt.palette.parse_error"),
        true,
      )
  }
  let updated = match
    @blocks.replace_expr_at(target.body, item.path, expr_path, parsed) {
    Some(body) => body
    None =>
      return with_notice(
        model,
        text(translator(model), "app.expr.drop.rejected"),
        true,
      )
  }
  let next = replace_target_body(model, target.label, updated)
  let synced = sync_code_draft(next)
  select_block(synced, block_index)
}

///|
/// 插入一条语句骨架，**可指定落点**（`target` = (list_path, at)）。
///
/// `target` 为 `None` 时沿用面板的默认语义（选中块之后 / 无选中则顶层末尾）；
/// 给定时按落点插入——这是「从调色板拖到画布」的落地路径：拖到哪个容器的
/// 哪个位置，就插到哪里，与点击插入共用同一套校验与手术。
fn insert_statement_at(
  model : Model,
  category_index : Int32,
  template_index : Int32,
  drop_at : (Array[Int32], Int32)?,
) -> Model {
  // **统一编辑目标**：事件子程序与自定义积木的体走同一条插入路径。
  // 早先这里只认 `current_handler`，于是「在自定义积木里插一条语句」被
  // 当成「没有子程序」直接拒绝——积木建得出来却编不了。
  let target = match current_target(model) {
    None =>
      return with_notice(
        model,
        text(translator(model), "app.stmt.palette.no_handler"),
        true,
      )
    Some(target) => target
  }
  let category = match @blk.category_at(category_index) {
    None => return model
    Some(category) => category
  }
  let templates = @blk.templates_for_category(category)
  if template_index < 0 || template_index >= templates.length() {
    return model
  }
  let parsed = @studio_lang.parse_handler_body(
    templates[template_index].skeleton(model.language.dsl_language()),
    model.language.dsl_language(),
  ) catch {
    _ =>
      return with_notice(
        model,
        text(translator(model), "app.stmt.palette.parse_error"),
        true,
      )
  }
  if parsed.length() == 0 {
    return model
  }
  // 落点：显式给定优先（拖拽），否则「选中块的下一行（同层）」，
  // 无选中 → 顶层末尾。
  let (list_path, at) = match drop_at {
    Some(value) => value
    None => {
      let chain = block_chain_of(model)
      match block_at(chain, model.selected_block) {
        Some(item) if item.path.length() > 0 => {
          let parent = @blk.blocks_parent_of(item.path)
          (parent, item.path[item.path.length() - 1] + 1)
        }
        _ => {
          let top : Array[Int32] = []
          (top, target.body.length())
        }
      }
    }
  }
  // 一条骨架可能解析出多条语句（如「如果…结束」内部已有内容）——
  // 逐条按序插入，保持骨架内部的相对顺序。
  let mut working = @blocks.clone_stmts(target.body)
  let mut insert_at = at
  let mut inserted = 0
  for traced in parsed {
    match @blocks.insert_stmt_at(working, list_path, insert_at, traced.stmt) {
      Some(next) => {
        working = next
        insert_at = insert_at + 1
        inserted = inserted + 1
      }
      None => ()
    }
  }
  if inserted == 0 {
    return model
  }
  let next = replace_target_body(model, target.label, working)
  let synced = sync_code_draft(next)
  // 选中新插入的第一条语句（按路径定位，链下标随展开块变化）。
  let new_path : Array[Int32] = []
  for part in list_path {
    new_path.push(part)
  }
  new_path.push(at)
  synced.blocks_ui.statement_palette_open = false
  let selected = select_block_by_path(synced, new_path)
  { ..selected, notice: "", }
}
