# 掌心密匣 PalmVault

面向 HarmonyOS 6.0+（API 20+）的纯本地加密个人信息保险箱。

## 当前已实现

- 首次启动创建密码，后续使用密码解锁。
- PBKDF2-SHA256（210,000 次迭代）派生 256 位数据库密钥。
- AES-256-GCM 加密关系型数据库，使用 S4 数据安全等级。
- 自定义分组，以及账号密码、私密笔记、身份信息、图片和视频条目。
- 条目的创建、读取、编辑、搜索与软删除。
- 相册媒体导入及应用内密匣相机；单个文件上限为 64MB。
- 密匣相机支持前后摄切换、闪光灯、缩放、点按对焦和最多 50 张连续拍摄，原图不写入系统相册。
- 文档扫描默认由用户手动拍摄，支持增强、旋转、删除、重拍和最多 20 页；不支持 Vision Kit 时自动降级为密匣相机。
- 拍摄与扫描统一复用图片压缩、OCR、应用私有附件目录和数据库索引流程。
- 应用进入后台立即锁定并关闭数据库连接。
- 使用 `PRIVACY_WINDOW` 保护窗口，禁止系统截屏。
- 深色自适应手机界面，组件和数据操作集中复用。

## 工程结构

- `entry/src/main/ets/models`：保险库领域模型。
- `entry/src/main/ets/services/VaultSecurityService.ets`：密码派生和密码验证。
- `entry/src/main/ets/services/VaultRepository.ets`：加密数据库、数据表和 CRUD。
- `entry/src/main/ets/services/MediaPickerService.ets`：系统相册导入。
- `entry/src/main/ets/services/PrivateCameraService.ets`：Camera Kit 会话、预览与拍摄。
- `entry/src/main/ets/services/PrivateCaptureService.ets`：私密采集缓存与临时文件清理。
- `entry/src/main/ets/components/VaultDocumentScanner.ets`：Vision Kit 文档扫描。
- `entry/src/main/ets/pages/Index.ets`：启动、解锁和保险库交互界面。
- `dist/index.html`：前期交互原型。

## 构建

使用 DevEco Studio 打开工程，选择 HarmonyOS 6.0.1 SDK 后构建 `entry` 模块。命令行构建需要配置 `DEVECO_SDK_HOME` 和 `JAVA_HOME`，然后执行 Hvigor 的 `assembleHap` 任务。

当前命令行产物为未签名 HAP；真机运行前请在 DevEco Studio 中为 `com.palmvault.app` 配置自己的调试签名。

Vision Kit 文档扫描仅支持中国大陆地区的 HarmonyOS 真机 Phone/Tablet，不支持时应用会提示并进入密匣相机连续拍摄。
