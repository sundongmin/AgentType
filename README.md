# AgentType

**在命令行与 AI Agent 之间，自动切换到合适的输入法。**

[English](README.en.md) · [安装与配置](docs/INSTALL.md) · [贡献指南](CONTRIBUTING.md) · [更新记录](CHANGELOG.md)

AgentType 是一个 macOS 输入法工具。普通 Ghostty 命令行使用英文输入源，运行 Claude Code、Codex CLI 或 pi 时使用你选择的中文输入法，并按标签和分屏恢复规则。

当前为预览版本，仅支持 **Ghostty + 本地交互 zsh**。运行时使用 Hammerspoon；安装器会自动处理缺失的依赖。AgentType 是独立社区项目，与 Ghostty、Hammerspoon 及各 Agent 开发方没有官方关联。

## 工作方式

| 操作 | 行为 |
| --- | --- |
| 进入普通 shell | 切换到 ABC，或你指定的英文输入源 |
| 运行 `claude`、`codex`、`pi` | 切换到安装时选择的中文输入法 |
| Agent 退出并返回提示符 | 恢复英文输入源 |
| 切换 Ghostty 标签或分屏 | 按目标终端的 Agent 状态恢复 |
| 后台终端的 Agent 退出 | 只更新来源终端的状态 |
| 离开 Ghostty | 交给系统或其他输入法管理工具 |

切换规则确认后，可以临时手动更换输入法；下次焦点或该终端状态变化时重新应用规则。默认查询间隔为 **0.15 秒**，只有 Ghostty 在前台时才发起查询。

## 快速开始

需要 macOS、zsh，以及支持 AppleScript 终端接口的 Ghostty。在系统设置中启用 ABC 和至少一个中文输入法。

下载仓库源码，或下载 Releases 中的完整安装包，解压后在项目根目录运行：

```sh
/bin/zsh ./install.sh --dry-run
/bin/zsh ./install.sh
```

安装器会列出已启用的中文输入法，输入编号选择，输入 `q` 取消。即使只有一个选项，也会让你明确选择。

缺少 Hammerspoon 时：

1. 有 Homebrew：通过 Homebrew 安装。
2. 没有 Homebrew：从官方 GitHub 最新稳定版下载安装，并校验摘要与官方签名。

已有 Hammerspoon 会直接复用。预览模式不下载、不安装；不需要为此安装 Homebrew。

安装结束后打开 Hammerspoon，已运行则 Reload Config，按 macOS 提示授予辅助功能和自动化权限。退出正在运行的 Agent，再重新打开 Ghostty 终端，然后检查：

```sh
ghostty-im doctor
```

使用 KeyboardHolder 等工具时，请将 Ghostty 加入其排除列表。已有旧版脚本时，请先阅读[迁移步骤](docs/INSTALL.md#从旧版脚本迁移)。

## 配置与卸载

安装后的设置在 `~/.hammerspoon/GhosttyInputMethod/config.lua`，可以修改输入源和查询间隔。升级会保留已选输入法。

```sh
# 非交互安装：以本机实际启用的输入源 ID 为准。
/bin/zsh ./install.sh --agent-source com.apple.inputmethod.SCIM.ITABC

# 卸载插件：保留 Hammerspoon 和其他用户配置。
/bin/zsh ./uninstall.sh
```

详细步骤见[安装与配置指南](docs/INSTALL.md)。

## 支持范围

- 目前只支持本地 Ghostty + 交互式 zsh；SSH、tmux 环境跳过集成。
- 主要面向前台 Agent；后台运行、挂起/恢复、嵌套 shell 和同一终端并行 Agent 尚未完整支持。
- 已有同名别名或函数会被保留，需要通过 `ghostty_im_run` 主动接入；`command codex` 等直接调用会绕过包装。
- 检查的是系统输入源，不保证中文输入法内部中英文模式、候选框和首字符状态。
- 不承诺零延迟。自动测试覆盖安装与状态逻辑，实际输入法体验仍需在你的环境中验证。

## 项目结构

```text
GhosttyInputMethod.spoon/  Ghostty 适配器与输入源切换逻辑
shell/                    zsh 集成和诊断工具
scripts/                  安装、依赖下载和构建工具
tests/                    隔离测试
docs/                     安装、验证和发布说明
.github/                  Issue 模板、PR 模板及自动测试
```

项目名是 AgentType。为兼容早期版本，当前 Ghostty 适配器仍使用 `GhosttyInputMethod.spoon`、`ghostty-im` 和原有设置路径；这些名称是稳定的内部接口。

## 参与开发

欢迎通过 Issues 报告问题或通过 Pull Request 提交改进。运行测试与生成安装包的方法见 [CONTRIBUTING.md](CONTRIBUTING.md)，发布步骤见 [docs/RELEASING.md](docs/RELEASING.md)。

## 许可与致谢

采用 [MIT License](LICENSE)。依赖 [Ghostty](https://ghostty.org/) 与 [Hammerspoon](https://www.hammerspoon.org/) 提供终端自动化和输入源接口。第三方应用及输入法本身不包含在项目发行包中。
