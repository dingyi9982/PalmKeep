# 掌心密匣发布说明

本文档用于发布 PalmVault。日常开发不需要修改版本号；只有准备生成正式安装包时才执行发布脚本。

## 一键发布

发布前先提交本次所有代码，确保 `git status` 显示工作区干净，然后双击项目根目录的 `release.cmd`。首次发布输入已配置的 `1.0.0`；后续发布输入新的三段式版本号。

也可以在 PowerShell 中执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release.ps1 1.0.0
```

脚本会依次完成：

1. 检查工作区、版本号、资源 JSON 和本机构建工具。
2. 执行一次 Debug 预检构建。
3. 首次发布直接使用已配置的 `1.0.0 / 1`；后续发布更新 `versionName` 并将 `versionCode` 自动增加 1。
4. 同步 `AppScope/app.json5`、`oh-package.json5` 和 `entry/oh-package.json5`。
5. 创建“发布 x.y.z 版本”提交和 `vx.y.z` Git 标签。
6. 使用 `default + Release` 构建已签名 HAP。
7. 将安装包和 SHA-256 校验值复制到 `release` 目录。
8. 如果存在 `origin` 远程仓库，自动推送当前分支和标签。

产物名称格式为：

```text
release/PalmVault-1.0.0-1.hap
release/PalmVault-1.0.0-1.hap.sha256
```

如果只想在本地生成版本，不推送远程仓库：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release.ps1 1.0.0 -NoPush
```

特殊情况下可以明确指定更大的 `versionCode`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release.ps1 1.0.1 -VersionCode 2
```

## 版本与构建信息

设置页会显示：

- 版本：来自 `AppScope/app.json5` 的 `versionName` 和 `versionCode`。
- 构建标识：构建时读取的 Git 提交短哈希；工作区有未提交改动时会附加 `-dirty`。

根据构建标识可定位安装包对应源码：

```powershell
git show <构建标识中的提交哈希>
```

`entry/src/main/ets/generated/BuildMetadata.ets` 由 Hvigor 自动生成并已忽略，不要手工提交。

## 首次发布前的签名配置

根目录 `build-profile.json5` 只保存在本机，已经被 Git 忽略。正式上传应用市场前，需要在 DevEco Studio 的 `File > Project Structure > Project > Signing Configs` 中配置正式发布证书、Profile 和密钥库，并确认：

- `default` 产品使用正式发布签名。
- `default` 产品绑定 `entry@default` target。
- 所有产品的 `compatibleSdkVersion` 保持为 `5.0.0(12)`；发布预检会校验构建产物的最低 API 版本。
- 不要提交 `.p12`、`.cer`、`.p7b`、签名密码或带本机绝对路径的签名配置。

目前本机配置若仍是自动调试签名，脚本虽然可以产出已签名 HAP，但该 HAP 只能用于开发验证，不能代替应用市场正式签名。

脚本默认使用以下工具路径，可通过同名参数覆盖：

```text
SDK:    D:\DevEco Studio\sdk
JDK:    D:\DevEco Studio\jbr
Node:   D:\DevEco Studio\tools\node\node.exe
Hvigor: D:\DevEco Studio\tools\hvigor\bin\hvigorw.js
```

## 版本规则

- `versionName` 必须是 `x.y.z`。首次发布允许使用当前已配置且尚未创建标签的 `1.0.0`；之后必须高于当前版本。
- 修复问题：`1.0.0 → 1.0.1`。
- 增加一般功能：`1.0.1 → 1.1.0`。
- 重大不兼容改版：`1.1.0 → 2.0.0`。
- 首次发布的 `versionCode` 为 `1`；后续版本必须大于应用市场已接收过的所有版本，脚本默认自动加 1。

## 失败处理

发布脚本不会自动删除版本文件、提交或标签，以免误删源码。失败时根据终端最后一段提示处理：

- 在“准备版本”前失败：修复问题后直接重试。
- 已更新版本文件但尚未提交：检查并提交或恢复这三个版本文件后再重试。
- 已创建提交或标签：不要直接重复运行同一版本；先确认 Git 历史、标签和产物状态。
- 已构建但推送失败：安装包仍在 `release` 目录，可在网络恢复后手动执行 `git push` 和 `git push origin vx.y.z`。

## 发布前检查清单

- [ ] 本次功能和修复已经完成并提交
- [ ] 工作区干净
- [ ] 必要的真机功能测试已完成
- [ ] `versionName` 符合发布计划
- [ ] `versionCode` 大于应用市场历史版本
- [ ] `default` 使用正式发布签名
- [ ] 一键发布脚本执行成功
- [ ] 设置页中的版本和构建标识正确
- [ ] `release` 中的 HAP 来自对应 Git 标签
- [ ] 隐私声明、权限和核心功能已复核
