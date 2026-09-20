# 掌心密匣 PalmVault

面向 HarmonyOS 6.0+（API 20+）的纯本地加密个人信息保险箱。

## 阶段 1 已实现

- 首次启动创建密码，后续使用密码解锁。
- PBKDF2-SHA256（210,000 次迭代）派生 256 位数据库密钥。
- AES-256-GCM 加密关系型数据库，使用 S4 数据安全等级。
- 自定义分组，以及账号密码、私密笔记、身份信息、图片和视频条目。
- 条目的创建、读取、编辑、搜索与软删除。
- 相册媒体导入加密数据库；阶段 1 单个文件上限为 64MB。
- 应用进入后台立即锁定并关闭数据库连接。
- 使用 `PRIVACY_WINDOW` 保护窗口，禁止系统截屏。
- 深色自适应手机界面，组件和数据操作集中复用。

## 工程结构

- `entry/src/main/ets/models`：保险库领域模型。
- `entry/src/main/ets/services/VaultSecurityService.ets`：密码派生和密码验证。
- `entry/src/main/ets/services/VaultRepository.ets`：加密数据库、数据表和 CRUD。
- `entry/src/main/ets/services/MediaPickerService.ets`：系统相册导入。
- `entry/src/main/ets/pages/Index.ets`：启动、解锁和保险库交互界面。
- `dist/index.html`：前期交互原型。

## 构建

使用 DevEco Studio 打开工程，选择 HarmonyOS 6.0.1 SDK 后构建 `entry` 模块。命令行构建需要配置 `DEVECO_SDK_HOME` 和 `JAVA_HOME`，然后执行 Hvigor 的 `assembleHap` 任务。

当前命令行产物为未签名 HAP；真机运行前请在 DevEco Studio 中为 `com.palmvault.app` 配置自己的调试签名。

## 下一阶段

接入 User Authentication Kit，把人脸／指纹验证作为密码解锁后的便捷入口；随后完成锁定超时、认证失败策略和安全状态审计。
