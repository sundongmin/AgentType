# 发布 AgentType

## 上传仓库内容

将项目根目录中的文件和目录放在 GitHub 仓库根目录，包含 `.github/`、`.gitignore` 和 `.gitattributes`。不要把整个项目再嵌套到一个版本号文件夹中。`dist/` 是生成结果，不需要放入源码仓库。

源码不包含 `.git`，构建工具不会初始化仓库、创建提交、打标签或上传文件。仓库名建议使用 `agenttype`，显示名称为 AgentType；无需将个人 GitHub 用户名写入脚本。

## 准备版本

1. 更新根目录 `VERSION`。
2. 同步更新 `GhosttyInputMethod.spoon/init.lua` 中的 `obj.version`，以及 `scripts/ensure-hammerspoon.zsh` 中的 HTTP User-Agent 版本。
3. 在 `CHANGELOG.md` 描述用户可感知的变化。若安装说明包含版本号示例，同步更新。
4. 运行检查和构建：

```sh
python3 scripts/check.py
python3 scripts/build.py
```

构建产物：

```text
dist/AgentType-<version>.zip
dist/AgentType-<version>.spoon.zip
dist/AgentType-<version>-SHA256SUMS.txt
```

完整包面向普通用户；独立 Spoon 包面向手动集成的 Hammerspoon 用户。后者包含独立说明和所需 shell 文件，不包含完整安装器。

## GitHub Release

在 GitHub 界面创建对应版本的 Release，填写本版本更新说明，上传上述三个文件。处于预览阶段时，选择预发布。GitHub 自动提供的 Source code ZIP 也可以用于安装：解压后在根目录用 `/bin/zsh ./install.sh` 运行即可，不依赖脚本执行权限是否被保留。

CI 仅测试和保存构建产物，不自动创建 Release，也不会自动替你上传源码。

## 发布前验证

- 确认[自动测试和人工验收](TESTING.md)的覆盖范围，在版本说明中如实列出已验证环境与已知限制。
- 从生成的完整 ZIP 解压后进行安装预览；确认命名、安装脚本、文档和版本一致。
- 不附带个人配置、备份、临时文件、凭据或第三方 Hammerspoon 应用包。

Hammerspoon 的 GitHub 下载逻辑依赖官方资产命名、SHA-256 元数据和签名团队。若上游改变这些信息，应先从官方渠道核实，再调整校验；不要通过关闭签名检查或移除 quarantine 来解决。
