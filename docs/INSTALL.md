# AgentType 安装与配置指南

一个 Hammerspoon Spoon：在 Ghostty 普通命令行使用英文输入源，运行 `claude`、`codex`、`pi` 时使用指定输入法，并按标签和分屏恢复规则。

当前版本仅支持 Ghostty + 本地交互 zsh，运行时需要 Hammerspoon；缺少时安装器会自动安装。输入法切换体验请按文末清单在实际环境中验收。

## 使用效果

| 场景 | 默认行为 |
| --- | --- |
| 普通 Ghostty shell | ABC |
| 前台运行 claude、codex、pi | 安装时选择的中文输入法 |
| Agent 退出 | ABC |
| 切换标签或分屏 | 按目标终端的 Agent 状态选择输入源 |
| 后台标签的 Agent 退出 | 只修改来源终端的状态 |
| 离开 Ghostty | 停止发起查询，不管理其他应用 |
| 自动选择已经确认后，手动切换输入法 | 保留到下次焦点或该终端状态变化 |

这不是逐分屏记忆用户任意手动输入法的工具。输入源正确，也不代表微信输入法内部中英文模式或候选框已经就绪。

## 安装前

1. macOS、自带 zsh、本地 Ghostty；Ghostty 需要支持 AppleScript 的 `terminals`、`id`、`tty`、`focused terminal`。
2. 无需预先安装 [Hammerspoon](https://www.hammerspoon.org/)；安装器会按下一节的规则处理。安装结束后打开它，在“隐私与安全性 → 辅助功能”中允许它。
3. 在系统设置中启用 ABC 和你想用的中文输入法。安装器会读取本机已启用的中文输入法，按名称列出供你选择。
4. 使用 KeyboardHolder 等输入法管理工具时，将 Ghostty 加入其**排除应用**列表，避免两套规则争抢。

工具会自动寻找 Hammerspoon 自带的 CLI，以及 Apple Silicon / Intel 常见安装路径。无需额外安装 Python、Lua 或 Homebrew，也无需给安装脚本使用 `sudo`。非标准 Hammerspoon 安装路径可按手动集成流程处理，并通过 `GHOSTTY_IM_HS` 指向它的 CLI。

## Hammerspoon 自动安装

正式安装会先完成旧配置检查、输入法选择和 zsh 配置语法检查，然后按以下顺序处理依赖：

1. `/Applications` 或当前用户的 `~/Applications` 已有完整 Hammerspoon：直接复用，不更新或重装。
2. 没有 Hammerspoon，但找到 Homebrew：运行 `brew install --cask` 安装 Hammerspoon。会查找命令搜索路径，以及 `/opt/homebrew/bin/brew`、`/usr/local/bin/brew`。
3. 两者都没有：读取官方 `Hammerspoon/hammerspoon` GitHub 仓库的最新稳定版，通过 HTTPS 下载官方通用 ZIP，校验发布信息中的 SHA-256、应用标识、官方开发者签名和最低 macOS 版本后安装。

优先安装到可写的 `/Applications`；不可写时使用 `~/Applications`。官方通用应用支持 Apple Silicon 和 Intel。不会自动安装 Homebrew，不会绕过系统安全检查，也不会删除 quarantine 属性。GitHub API、下载或校验失败时停止并显示原因，不改动插件配置。Homebrew 已存在但安装失败时也会停止，修复 Homebrew 后重试，不再悄悄改用另一种安装方式。

`--dry-run` 只显示将采用的安装方式与位置，**不联网下载、不安装**。输入法选择阶段取消安装也不会安装依赖。

Hammerspoon 安装后仍需用户打开并授予 macOS 权限，脚本不自动重载正在运行的 Hammerspoon。若依赖安装成功后，后续插件文件写入失败，插件配置会尝试回滚，但已安装的 Hammerspoon 会保留。卸载本插件也会保留 Hammerspoon，避免影响其他 Spoon 或配置。

## 从旧版脚本迁移

如果已经使用使用 `ghosttyIM` 与 `_ai_agent_im_*` 函数的旧版 Hammerspoon + zsh 脚本，不能直接叠加安装。安装工具发现旧代码时会停止，且不会写入配置。

1. 先退出所有正在运行的 Agent。
2. 备份 `~/.hammerspoon/init.lua` 和实际使用的 `.zshrc`。此步骤在删除旧代码前完成；安装工具之后的备份不会包含你已经手动删去的旧代码。
3. 从 `init.lua` 中移除旧的 `ghosttyIM` 管理对象、`ghosttyIMResolveTTY` / `ghosttyIMSet` / `ghosttyIMSetFocused` 函数及相关 timer、watcher、stop 代码。保留其他 Hammerspoon 配置和其他功能需要的 `require("hs.ipc")`。
4. 从 `.zshrc` 中移除旧的 `_ai_agent_im_*`、`_ai_agent_run`、对应的 `claude` / `codex` / `pi` 包装函数，以及旧 `precmd` 钩子的注册代码。其他用途的自定义函数应保留并按后文接入。
5. 按下一节安装，然后重载 Hammerspoon，并重新打开 Ghostty 终端。不要仅在旧 shell 中重新 source：旧函数和 hook 仍可能残留。

安装工具不会猜测多用途配置的代码边界并自动删除。通过其他文件间接加载的旧逻辑也需要自行移除，静态检查不能发现所有间接引用。

## 快速安装

解压完整发行包 `AgentType-0.1.3.zip`，在该文件夹打开终端，先预览再安装：

```sh
/bin/zsh ./install.sh --dry-run
/bin/zsh ./install.sh
```

普通终端默认使用 ABC。正式安装时，安装器会直接读取 macOS 输入源列表，无需 Hammerspoon 已经启动或 IPC 已经配置。它只展示已启用、可切换且语言属于中文的输入源；不会把输入法 App 的父项或表情面板当作可选中文输入法。

有多个中文输入法时，菜单类似：

```text
请选择 Agent 中使用的中文输入法（已启用）：
  1) 微信输入法  [com.tencent.inputmethod.wetype.pinyin]
  2) 简体拼音  [com.apple.inputmethod.SCIM.ITABC]
  q) 取消安装
输入编号，或 q 取消:
```

实际名称和选项以你的 Mac 为准。即使只有一个中文输入法，也需要输入编号确认；不会按回车自动选择。输入 `q` 可取消，配置不会被修改。`--dry-run` 只列出选项，不要求选择。

没有找到中文输入法时，请先到“系统设置 → 键盘 → 文本输入”添加。只安装输入法 App、还未启用其输入源时，不会列入菜单。检测过程只读取系统状态，不切换输入法。

无人值守安装必须明确指定输入源，例如 macOS 简体拼音：

```sh
/bin/zsh ./install.sh --agent-source com.apple.inputmethod.SCIM.ITABC
```

安装器会校验显式指定的 Agent 和普通终端输入源是否已启用、可切换。上述 ID 只是示例，以本机为准。如果只想查看本机已启用的中文输入法，可以在解压目录运行：

```sh
/usr/bin/osascript -l JavaScript scripts/input-sources.js
```

也可在 Hammerspoon Console 中查询所有输入源 ID：

```lua
hs.inspect({layouts = hs.keycodes.layouts(true), methods = hs.keycodes.methods(true)})
```

安装后：

1. 打开 Hammerspoon；如果它已经运行，菜单 → **Reload Config**。
2. 第一次访问 Ghostty 时，允许相关自动化请求；可在“隐私与安全性 → 自动化”核对。查询可能由 Hammerspoon 发起或由其启动的 `osascript` 执行，按系统实际显示的请求授权。
3. 确保 Agent 已退出，再新开 Ghostty 终端。
4. 运行诊断：

```sh
ghostty-im doctor
```

如果 shell 尚未加载集成，可直接运行：

```sh
"$HOME/.hammerspoon/GhosttyInputMethod/ghostty-im" doctor
```

诊断应显示 `running = true`、两个 `SourceEnabled = true`，并在 Ghostty 运行且权限正确时显示 `ghosttyQueryOK = true`。`doctor` 会读取 Ghostty 接口，首次执行可能触发授权提示，但不会切换输入法。`status` 只读取状态，`sources` 列出已启用输入源。

插件配置写入当前用户目录；依赖应用安装到上述 Applications 目录。脚本不会重载 Hammerspoon 或修改 KeyboardHolder。自动启用需要现有 `init.lua` 和 `.zshrc` 能执行到新增的末尾配置块；若原文件提前 `return`，请手动调整位置。自定义 Hammerspoon 配置目录请使用手动集成。

## 配置与自定义命令

安装后的设置文件为：

```text
~/.hammerspoon/GhosttyInputMethod/config.lua
```

```lua
return {
    terminalSource = "com.apple.keylayout.ABC",
    agentSource = "com.tencent.inputmethod.wetype.pinyin",
    pollInterval = 0.15,
    queryTimeout = 3,
    cleanupInterval = 30,
}
```

以上 `agentSource` 只是微信输入法的配置示例，实际文件使用安装时选择的 ID。编辑后重载 Hammerspoon。重复安装保留已选输入法，不再次弹出选择；已有配置时，安装器拒绝用输入源命令行选项覆盖它。升级时，会将配置中独立一行的旧默认 `pollInterval = 0.25,` 更新为 `0.15`，其他自定义周期保留。

默认自动包装 `claude`、`codex`、`pi`。如果你已经定义同名函数或别名，插件会保留它们并提示。此时需要让原函数主动接入：

```zsh
mycodex() { ghostty_im_run codex "$@"; }
```

`ghostty_im_run` 的第一个参数必须是外部可执行命令，其余参数原样传递。`command codex`、绝对路径直接调用和其他未接入的 wrapper 会绕过自动规则。

单个新 shell 可在加载前设置 `GHOSTTY_IM_DISABLED=1` 来跳过集成；对已经加载的 shell，仅修改这个变量不会删除现有函数，需要重新打开终端。

## 安装位置、更新与备份

工具安装以下内容：

```text
~/.hammerspoon/Spoons/GhosttyInputMethod.spoon/
~/.hammerspoon/GhosttyInputMethod/config.lua
~/.hammerspoon/GhosttyInputMethod/ghostty-im
~/.hammerspoon/GhosttyInputMethod/ghostty-input-method.zsh
```

在 `init.lua` 和 `.zshrc` 中只添加带 `BEGIN/END GhosttyInputMethod managed v1` 标记的加载块。其余行保留；没有末尾换行的文件会补齐换行。安装器不会执行用户配置，仅对修改后的 zsh 文件做语法检查。Lua 配置整体是否能够运行，以 Hammerspoon 重载结果为准。

更新：退出 Agent，用新版完整包再次运行 `/bin/zsh ./install.sh`，重载 Hammerspoon，重新打开终端。保留已选输入法，并按上一节说明迁移旧版默认轮询周期。同版本重复运行不会重复添加加载块。自有命名空间目录会被更新；不要把无关文件放进去，它们只会保存在操作前备份中。

每次真正安装或卸载前，会备份这四个目标到权限受限的目录：

```text
~/.hammerspoon/GhosttyInputMethod-backups/时间戳.随机后缀/
```

`paths.txt` 说明编号 `1`～`4` 对应的原路径，`previously-absent.txt` 列出操作前不存在的目标。提交阶段失败会尝试恢复这些备份；断电或 `kill -9` 等无法运行清理逻辑的情况，需要手动恢复。恢复完整 dotfile 会覆盖备份之后的其他修改，请先比较内容。

`.zshrc` 默认跟随 `ZDOTDIR`。也可明确指定：

```sh
/bin/zsh ./install.sh --zshrc /absolute/path/to/.zshrc
```

卸载器会记住安装时的路径。符号链接管理的 dotfile 不会被自动覆盖，请用手动集成。

## 卸载

在完整发行包文件夹中运行：

```sh
/bin/zsh ./uninstall.sh --dry-run
/bin/zsh ./uninstall.sh
```

然后重载 Hammerspoon，并在 Agent 退出后重新打开终端。工具只移除托管加载块和自己的两个安装目录，保留其他配置、Hammerspoon、输入法、历史备份。卸载不会自动终止正在运行的 Agent。

Hammerspoon 保存的历史状态会保留。如需彻底清除，在卸载并重载后，在 Hammerspoon Console 执行：

```lua
hs.settings.clear("GhosttyInputMethod.states.v1")
```

备份可能包含个人 dotfile 内容，请只保留在自己电脑上，不要随发行包上传。

## 手动 Spoon 集成

适用于已经安装同名 Spoon、使用符号链接管理 dotfile，或采用自定义 Hammerspoon 配置目录的用户。

1. 解压 `AgentType-0.1.3.spoon.zip`，双击其中的 `.spoon`，让 Hammerspoon 导入；也可复制完整包里的同名目录到自己的 `Spoons/`。
2. 在自己的 Hammerspoon 配置中加入：

```lua
hs.loadSpoon("GhosttyInputMethod")
spoon.GhosttyInputMethod.terminalSource = "com.apple.keylayout.ABC"
spoon.GhosttyInputMethod.agentSource = "com.tencent.inputmethod.wetype.pinyin"
spoon.GhosttyInputMethod:start()
```

3. 把完整包 `shell/` 中的两个文件放到同一个固定目录，保留 `ghostty-im` 执行权限，在 `.zshrc` 中 source 其中的 `ghostty-input-method.zsh`。
4. 重载 Hammerspoon，重新打开终端。手动安装也需要 shell 集成，单独双击 Spoon 不会自动配置 `.zshrc`。

独立 Spoon 包也附带 `shell/` 和本说明，可将那两个 shell 文件复制到固定目录使用。手动安装不受安装器管理，卸载时手动移除自己添加的加载代码和文件。

## 实现和性能边界

- 以来源 TTY 解析 Ghostty terminal ID；启动与退出通知绑定同一个 ID。
- shell 首次解析成功后缓存 ID；普通提示符不再反复解析。首次加载及通知失败后会尝试校正状态；提示符修复失败后至少间隔 10 秒再试。
- Agent 通知仍使用 Hammerspoon CLI，正常连接时 CLI 请求设置 2 秒超时；首次解析还涉及同步 AppleScript。系统服务或权限异常时，实际等待可能更长，因此不能承诺故障下严格两秒返回。
- 默认轮询为 **0.15 秒**，与旧教程一致。Ghostty 在前台、查询足够快时理论上约每秒 6～7 次；可自行调大周期，最小允许 `0.1`。
- 仍使用外部 `osascript` 查询，没有宣称消除轮询或已验证节电比例。一次只允许一个查询，查询有看门狗，失败后退避 2 秒。
- 每个终端独立记录状态修订；其他终端的后台通知不再触发当前终端重新应用输入源。
- Ghostty 前台时，每隔约 30 秒通过一次查询附带的终端清单清理关闭终端状态；查询失败或 Ghostty 一直在后台时清理会推迟。收到 Ghostty 退出事件时清空状态。
- 只支持本地交互 zsh 和前台 Agent。SSH、tmux 环境主动跳过集成；后台 `codex &`、嵌套 shell、并行 Agent、挂起/恢复和异常进程退出不保证完整支持。不能从已保存状态自动发现所有运行中的进程。
- 输入法不可用时每次焦点/状态周期最多尝试三次，通过 `ghostty-im status` 查看错误。
- 插件运行时不拦截键盘、不读取终端内容、不访问外部网络。只有缺少 Hammerspoon 时，安装阶段会通过 Homebrew 或官方 GitHub 下载依赖。记录终端 ID 和 Agent/terminal 状态；诊断输出会包含终端 ID、输入源 ID 和错误。

## 验收清单

安装到实际 Mac 后，至少验证：

1. 普通终端 ABC → 运行 Agent 后目标输入法 → 退出后 ABC。
2. 两个标签和同一标签的两个分屏来回切换。
3. 后台终端的 Agent 退出时，不错误切换当前终端。
4. 切到飞书等其他应用，现有输入法规则正常。
5. 手动改输入源后，停留在同一终端时不会被反复覆盖。
6. 重载 Hammerspoon 后，已上报的 Agent 状态恢复。
7. 卸载、重载、重开终端后，不再运行本插件。

隔离自动测试（仅开发验证需要 Python 3；Lua 测试读取 Hammerspoon 自带 LuaSkin，不连接正在运行的 App）：

```sh
python3 tests/test_distribution.py
python3 tests/test_dependency.py
python3 tests/run_lua.py
```

也可用自己的 Lua 运行 `lua tests/test_state.lua GhosttyInputMethod.spoon/init.lua`。这些自动测试全部在临时目录或 mock 对象中执行，不会安装真实 Homebrew 软件包，真实输入法体验需按上述清单另行验收。

## 项目文档

- [项目首页](../README.md)
- [贡献与测试](../CONTRIBUTING.md)
- [发布流程](RELEASING.md)
- [MIT 许可](../LICENSE)

## 参考

- [Hammerspoon Spoon 规范](https://github.com/Hammerspoon/hammerspoon/blob/master/SPOONS.md)
- [Ghostty AppleScript 接口](https://ghostty.org/docs/features/applescript)
- [Hammerspoon 官方发行](https://github.com/Hammerspoon/hammerspoon/releases/latest)
