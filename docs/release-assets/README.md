# 掌心密匣 PalmKeep 发布图标说明

## 应用市场上传

在 AppGallery Connect 的“应用图标”字段中，只上传：

- `app-icon-1024.png`

该文件是 1024×1024 的完整直角图标，中央图形与工程前景层保持一致，仅将原图透明圆角区域按边缘颜色向外延展，避免与应用市场 Mask 叠加后出现双层圆角。输出不含透明像素，应用市场会通过 Mask 生成最终圆角展示效果。

不要单独上传下列分层素材：

- `app-icon-background-1024.png`：蓝色背景层。
- `app-icon-foreground-1024.png`：透明前景层。

## 工程内分层图标

HarmonyOS 安装包使用以下分层素材：

- 前景：`entry/src/main/resources/base/media/launcher_icon_foreground.png`
- 背景：`entry/src/main/resources/base/media/launcher_icon_background.png`
- 分层描述：`entry/src/main/resources/base/media/launcher_icon_layered.json`

`AppScope/app.json5` 与 `entry/src/main/module.json5` 均应引用 `$media:launcher_icon_layered`。

## 审核备注建议

图标以明亮蓝色表达清晰、可靠的本地资料管理体验；掌心承托密匣，呼应“掌心密匣”名称与 PalmKeep 品牌；锁孔和环形光效表达应用私有沙箱、访问验证与隐私界面保护。
