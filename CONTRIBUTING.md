# 参与 AgentType

欢迎提交中文或英文 Issue 和 Pull Request。

## 开发环境

- macOS：测试使用系统自带 zsh、osascript、ditto 等工具。
- Python 3.9 或更高：只用于开发测试和打包，普通用户安装不需要 Python。
- Lua：可以使用 `lua` 命令，也可以使用已安装 Hammerspoon 自带的 LuaSkin。无需启动 Hammerspoon。

## 运行测试

在仓库根目录运行：

```sh
python3 scripts/check.py
```

检查包含 shell 语法、安装与卸载、输入法选择、依赖安装分支、Lua 状态逻辑及打包验证。测试使用临时目录、模拟对象和替身命令，不修改用户配置、不安装真实 Hammerspoon。

需要 Lua 时，可以通过 `brew install lua` 安装。已有 Hammerspoon 的开发者也可以让检查脚本自动使用 LuaSkin；非标准路径通过 `GIM_TEST_LUA_LIBRARY` 指定。

GitHub Actions 在 push、pull request 或手动触发时运行相同检查并生成安装包。CI 没有发布 Release 的权限，也不会自动发布版本。云端无法代替[真实输入法验收](docs/TESTING.md)。

## 修改原则

- 始终根据来源 TTY / terminal ID 上报 Agent 状态，不能使用通知到达时的前台终端。
- 输入法切换前必须确认应用焦点，忽略失效的异步查询结果。
- IPC 失败不能阻止 Agent 执行，包装函数必须保留参数和退出码。
- 安装器只能修改带有管理标记的配置块；维护备份、重复安装和卸载能力。
- `--dry-run` 不下载、不安装；取消选择不修改配置。
- 默认轮询为 0.15 秒。修改性能行为时请说明对响应速度和查询次数的影响。
- 项目品牌为 AgentType，现有 Spoon 名、设置键和 shell 接口保留兼容性。更改这些接口需要明确迁移方案。

## 提交改进

说明问题、触发步骤、修改后的行为和验证结果。涉及输入法时，注明 macOS、Ghostty、Hammerspoon、输入法版本，以及是否使用 tmux、SSH 或其他输入法管理工具。

不要提交私人 dotfile、终端内容、令牌或完整环境变量。诊断输出如含个人路径或终端 ID，可在提交前删去。

## 构建发行包

```sh
python3 scripts/build.py
```

结果位于 `dist/`，包含完整安装包、独立 Spoon 包和 SHA-256 校验文件。构建不依赖仓库所在目录的名称，不运行 Git，也不上传文件。版本与发布说明见 [RELEASING.md](docs/RELEASING.md)。

提交贡献即表示同意将所提交的原创贡献按项目的 [MIT License](LICENSE) 分发。
