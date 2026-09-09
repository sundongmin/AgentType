# AgentType — GhosttyInputMethod Spoon

此目录是 AgentType 的 Ghostty 适配器。为兼容早期版本，保留 `GhosttyInputMethod` 名称。

需要 macOS、Hammerspoon、支持 AppleScript 终端接口的 Ghostty，以及本地交互 zsh。这里只包含手动集成所需内容；自动安装 Hammerspoon、交互选择中文输入法和托管卸载请使用 AgentType 完整发行包。

## 手动安装

1. 双击 `.spoon` 让 Hammerspoon 导入，或复制到 `~/.hammerspoon/Spoons/`。
2. 在 Hammerspoon 配置中加入：

```lua
hs.loadSpoon("GhosttyInputMethod")
spoon.GhosttyInputMethod.terminalSource = "com.apple.keylayout.ABC"
spoon.GhosttyInputMethod.agentSource = "com.tencent.inputmethod.wetype.pinyin"
spoon.GhosttyInputMethod.pollInterval = 0.15
spoon.GhosttyInputMethod:start()
```

输入源 ID 以本机为准。在 Hammerspoon Console 中用 `hs.keycodes.layouts(true)` 和 `hs.keycodes.methods(true)` 查询。

3. 独立 Spoon 发行包附带 `shell/`。将其中的 `ghostty-im` 和 `ghostty-input-method.zsh` 放在同一个固定目录，对 `ghostty-im` 设置执行权限，并在 `.zshrc` 中 source 该目录的 `ghostty-input-method.zsh`。源码仓库中的 shell 文件位于仓库根目录的 `shell/`。
4. 重载 Hammerspoon、授予权限、退出已有 Agent，再打开新的 Ghostty 终端。

单独加载 Spoon 不会配置 shell。旧的同类切换脚本需要先移除，其他输入法管理工具应排除 Ghostty。

## API

- `:start()` / `:stop()`：启动或停止后台工作。
- `:status()`：返回状态与诊断信息。
- `:resolveTTY(tty)`：将来源 TTY 解析为 Ghostty terminal ID。
- `:setState(id, "agent" | "terminal")`：更新已绑定终端的状态。

MIT License，见同目录的 `LICENSE`。
