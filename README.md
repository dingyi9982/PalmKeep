# 掌心密匣 PalmVault

面向 HarmonyOS 5.0+（compatible API 12，target API 21）的本地个人资料管理应用，最终包名固定为 `com.palmvault.app`。

## 当前已实现

- 首次启动设置访问密码，后续可使用密码或已配置的系统生物认证解锁。
- 支持媒体、笔记、账号、文件和音频资料，以及自定义分组、搜索、回收站与备份恢复。
- 支持系统相册导入、系统分享导入、密匣相机和文档扫描；图片单个不超过 64 MB，视频单个不超过 500 MB，一次导入或分享总大小不超过 1 GB。
- 导入视频会转码为 MP4（H.264/AAC），最高保留到 1080p，视频码率为 2.5 Mbps。
- 密匣相机支持前后摄切换、闪光灯、缩放、点按对焦和最多 50 张连续拍摄，拍摄结果不主动写入系统相册。
- 文档扫描支持增强、旋转、删除、重拍和最多 20 页；能力不可用时降级为密匣相机。
- 支持音频文件导入、应用内录音、播放和后台继续完成用户主动开始的录音。
- 支持可配置的自动锁定时间；敏感页面和应用切入后台时启用窗口隐私保护。
- 备份文件使用密码派生密钥与 AES-256-GCM 加密，并在恢复前校验内容。

## 当前数据边界

业务数据和附件保存在应用私有目录，不主动上传到网络。当前数据库和附件文件尚未实现完整的静态逐文件加密，因此发布前的产品文案不得宣称“所有资料均已加密存储”。访问密码、生物认证和窗口隐私保护不能替代设备被攻破、应用沙箱被绕过时的静态数据加密。

## 工程结构

- `entry/src/main/ets/models`：领域模型。
- `entry/src/main/ets/services/VaultSecurityService.ets`：访问密码、生物认证和自动锁定设置。
- `entry/src/main/ets/services/VaultRepository.ets`：数据库、附件目录和数据操作。
- `entry/src/main/ets/services/MediaPickerService.ets`：系统媒体、文件和音频导入。
- `entry/src/main/ets/services/ShareImportService.ets`：系统分享内容暂存与校验。
- `entry/src/main/ets/services/PrivateCameraService.ets`：Camera Kit 会话、预览与拍摄。
- `entry/src/main/ets/services/AudioRecordingService.ets`：应用内录音和后台录音任务。
- `entry/src/main/ets/components/VaultDocumentScanner.ets`：Vision Kit 文档扫描。
- `entry/src/main/ets/pages/Index.ets`：启动、解锁和主要交互界面。

## 可复现构建

仓库固定文本为 UTF-8（无 BOM）和 LF，并通过预检校验发布元数据、包名、SDK 版本和 Release 混淆配置。构建标识包含 Git 提交哈希；工作区有未提交改动时会附加 `-dirty`。

首次克隆后复制本地构建配置模板：

```powershell
Copy-Item .\build-profile.example.json5 .\build-profile.json5
```

随后在 DevEco Studio 中配置本机调试签名或正式发布签名。`build-profile.json5`、证书、Profile、密钥库和密码不得提交到仓库。

发布前执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\preflight.ps1
```

详细步骤见 [发布说明](docs/release-guide.md)。Vision Kit 文档扫描仅在支持该能力的 HarmonyOS 真机和地区可用。

## 许可证

本项目暂不开源，采用专有许可证。除非取得著作权人的事先书面授权，不得复制、修改、发布或分发本软件及其源代码，详见 [LICENSE](LICENSE)。
