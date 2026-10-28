///|
/// 插件安装与卸载：文件系统操作。
///
/// **为什么在服务层**：契约层（`kernel/plugin_contract`）是**纯数据**
/// ——它不 import 文件系统，才能被 native 与 web 两端共用。装/卸插件
/// 是**平台专属的 I/O**，故落在服务层；契约层只声明能力
/// （`PluginBridge::can_install` / `install` / `remove`）。
///
/// **纪律**：
/// 1. **安装前必须校验**——源目录要有合法清单、入口文件要在目录内、
///    插件 id 要合法、不能覆盖已装插件。装坏了的插件比没装更糟。
/// 2. **复制而非移动**——用户的源目录不动（用户可能还要留着）。
/// 3. **卸载要递归**——`@x/fs.remove_dir` 用的是 `rmdir`，**非递归**
///    （只删空目录），故先删文件再删目录。
/// 4. **路径必须落在插件根目录内**——插件 id 来自清单（已过门卫），
///    但拼路径后仍要复核，防上溯。

///|
/// 安装结果。
pub(all) enum PluginInstallOutcome {
  /// 装好了：插件 id
  Installed(String)
  /// 没装成：原因（**必须能说清为什么**）
  Rejected(String)
}

///|
/// 卸载结果。
pub(all) enum PluginRemoveOutcome {
  /// 卸掉了：插件 id
  Removed(String)
  /// 没卸掉：原因
  Rejected(String)
}

///|
/// 插件 id → 插件目录名。
///
/// **为什么按 id 而不是按目录名**：扫描时目录名与清单 id 可能不一致
/// （目录叫 `foo`，清单写 `com.example.bar`）。卸载要删的是**清单
/// 声明的那个插件**，故按 id 找目录。
fn plugin_dir_of(plugins_root : String, plugin_id : String) -> String {
  "\{plugins_root}/\{plugin_id}"
}

///|
/// 安装插件：从 `source_dir` 复制到插件根目录。
///
/// 流程：校验源目录 → 读清单 → 校验 id/入口 → 检查未重复 → 复制 →
/// 回报结果。
///
/// **为什么复制而非软链/移动**：软链在 Windows 上要特权；移动会破坏
/// 用户的源目录。复制最笨但最可移植。
pub fn install_plugin(
  plugins_root : String,
  source_dir : String,
) -> PluginInstallOutcome {
  // 1. 源目录存在且是目录？
  let source_exists = @x/fs.path_exists(source_dir)
  if !source_exists {
    return Rejected("源目录不存在：\{source_dir}")
  }
  let source_is_dir = @x/fs.is_dir(source_dir) catch { _ => false }
  if !source_is_dir {
    return Rejected("源路径不是目录：\{source_dir}")
  }
  // 2. 清单存在且合法？
  let manifest_path = "\{source_dir}/\{PLUGIN_MANIFEST_NAME}"
  let source = @x/fs.read_file_to_string(manifest_path) catch {
    _ => return Rejected("读不到清单文件（\{PLUGIN_MANIFEST_NAME}）")
  }
  let manifest = match @plugin_contract.decode_manifest(source) {
    Ok(value) => value
    Err(errors) =>
      return Rejected("清单非法：\{describe_manifest_errors(errors)}")
  }
  // 3. 入口文件在源目录里存在？（清单的 entry 已过相对路径门卫）
  let entry_path = "\{source_dir}/\{manifest.entry}"
  let entry_exists = @x/fs.path_exists(entry_path)
  if !entry_exists {
    return Rejected("入口文件不存在：\{manifest.entry}")
  }
  // 4. 目标目录不能已存在（不覆盖——用户要装新版应先卸载）
  let target_dir = plugin_dir_of(plugins_root, manifest.id)
  let target_exists = @x/fs.path_exists(target_dir)
  if target_exists {
    return Rejected("插件已安装（\{manifest.id}），请先卸载")
  }
  // 5. 复制整个目录
  match copy_dir(source_dir, target_dir) {
    Ok(_) => Installed(manifest.id)
    Err(reason) => Rejected(reason)
  }
}

///|
/// 复制目录（含子目录）到目标。
fn copy_dir(source : String, target : String) -> Result[Unit, String] {
  @x/fs.create_dir(target) catch {
    _ => return Err("创建目标目录失败：\{target}")
  }
  let entries = @x/fs.read_dir(source) catch {
    _ => return Err("读源目录失败：\{source}")
  }
  for name in entries {
    let from = "\{source}/\{name}"
    let to = "\{target}/\{name}"
    let is_dir = @x/fs.is_dir(from) catch { _ => false }
    if is_dir {
      match copy_dir(from, to) {
        Ok(_) => ()
        Err(reason) => return Err(reason)
      }
    } else {
      let bytes = @x/fs.read_file_to_bytes(from) catch {
        _ => return Err("读文件失败：\{from}")
      }
      @x/fs.write_bytes_to_file(to, bytes) catch {
        _ => return Err("写文件失败：\{to}")
      }
    }
  }
  Ok(())
}

///|
/// 卸载插件：删除插件目录（递归）。
///
/// **破坏性**：调用方（UI）必须先经确认卡。
pub fn remove_plugin(
  plugins_root : String,
  plugin_id : String,
) -> PluginRemoveOutcome {
  // id 门卫：防止 `..` 之类的 id 拼出插件根目录之外的路径。
  if !@plugin_contract.is_valid_plugin_id(plugin_id) {
    return Rejected("非法插件 id：\{plugin_id}")
  }
  let target = plugin_dir_of(plugins_root, plugin_id)
  let exists = @x/fs.path_exists(target)
  if !exists {
    return Rejected("插件未安装：\{plugin_id}")
  }
  match remove_dir_recursive(target) {
    Ok(_) => Removed(plugin_id)
    Err(reason) => Rejected(reason)
  }
}

///|
/// 递归删除目录。
///
/// **`@x/fs.remove_dir` 是非递归的**（底层 `rmdir`，只删空目录）——
/// 故必须先删文件、再删子目录、最后删自己。
fn remove_dir_recursive(path : String) -> Result[Unit, String] {
  let entries = @x/fs.read_dir(path) catch {
    _ => return Err("读目录失败：\{path}")
  }
  for name in entries {
    let child = "\{path}/\{name}"
    let is_dir = @x/fs.is_dir(child) catch { _ => false }
    if is_dir {
      match remove_dir_recursive(child) {
        Ok(_) => ()
        Err(reason) => return Err(reason)
      }
    } else {
      @x/fs.remove_file(child) catch {
        _ => return Err("删文件失败：\{child}")
      }
    }
  }
  @x/fs.remove_dir(path) catch {
    _ => return Err("删目录失败：\{path}")
  }
  Ok(())
}
