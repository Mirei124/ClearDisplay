# ClearDisplay

ClearDisplay 是适用于 Apple Silicon Mac 的菜单栏显示器控制工具。它将分辨率、刷新率、亮度、显示器排列和部分色彩设置集中在一个面板中。当前版本仍在开发，适合在自己的设备上测试；正式签名与公证后的发行包尚未发布。

## 系统要求与安装

- Apple Silicon Mac，macOS 14 或更新版本。
- 直接分发的 macOS 应用；不通过 Mac App Store 安装。

取得发行包后，解压 `ClearDisplay-VERSION-arm64.zip`，将 `ClearDisplay.app` 放进“应用程序”文件夹并打开。应用只在菜单栏显示显示器图标，不会打开常驻主窗口；点击图标即可打开控制面板。下载或安装来源应是你信任的发行渠道。

目前也可以按下文“开发与构建”自行构建测试版。自行构建的未签名版本可能需要在 macOS 的“隐私与安全性”设置中允许打开。

## 使用

打开菜单栏面板后，先选择要调整的显示器。各项控制会根据当前显示器和系统能力显示或停用。

- **分辨率与 HiDPI：**为外接屏切换 HiDPI，并从列表中选择分辨率。内建显示屏不显示 HiDPI 开关。HiDPI 下所见的桌面大小取决于所选模式，切换前请记住原设置。
- **刷新率与图像：**选择可用刷新率；在受支持的显示器上调整 HDR、色彩配置文件、软件 Gamma 与色温。
- **亮度与 DDC：**调整内建屏亮度；在可识别的外接屏上尝试 DDC 亮度、对比度及色温。外接屏需支持对应 DDC 控制。
- **排列与连接：**在图形布局中拖动显示器并应用位置；按可用操作设置主显示器、旋转、镜像、断开或重新连接显示器。操作前请确认还有可用屏幕。
- **系统显示设置：**切换浅色或深色外观、夜览和原彩显示。原彩是 macOS 的系统级开关，无法单独控制某一台外接屏，其实际视觉效果由系统和显示器决定。

首次切换浅色或深色外观时，macOS 可能要求授权“自动化”访问。若拒绝授权，请到“系统设置 → 隐私与安全性 → 自动化”检查 ClearDisplay 的权限。

## 当前限制

- 位深选择仍在验证，当前没有可用的 8/10/12 bpc 切换控件。
- DDC 控件目前只在一台外接显示器且 DDC 通道能明确对应时启用；多外接屏场景仍需验证。
- 软件 Gamma 和色温会修改 CoreGraphics 传输曲线。应用在正常退出或下次启动时尝试恢复先前设置；某些自定义原始 Gamma 表无法由当前恢复方式完整还原。
- HDR、夜览和原彩依赖系统私有接口，系统升级后可能需要重新验证。自动外观可以识别，但当前只能手动切换浅色或深色，不设置自动日程。
- 不创建虚拟显示器，也不提供画中画、串流或显示器输入源切换。

如果某项控制没有出现，先确认选择的是内建屏还是外接屏、显示器是否支持该功能，以及连接线和扩展坞是否允许 DDC 通信。切换显示模式时屏幕可能短暂变黑；如设置不合适，可用 macOS“系统设置 → 显示器”恢复。

## 开发与构建

需要 Xcode Command Line Tools（`xcode-select --install`）。不依赖第三方包管理器；完整 Xcode 可选。

```sh
./build.sh                  # 调试应用：build/ClearDisplay.app
./format.sh                 # 格式化 Swift 代码
./check.sh                  # 严格格式检查、C 警告、plist 检查与 arm64 构建
```

`check.sh` 只构建应用，不会更改当前显示设置。`Tests/` 中的程序用于手动硬件验证。调试构建可在普通窗口预览菜单内容；预览中的控件仍会作用于真实显示器：

```sh
CONFIGURATION=debug ./build.sh ./build/preview
CLEARDISPLAY_UI_PREVIEW=1 ./build/preview/ClearDisplay.app/Contents/MacOS/ClearDisplay
```

## 打包与发布

```sh
ALLOW_UNSIGNED=1 ./package.sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./package.sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' NOTARY_PROFILE='ClearDisplay-notary' NOTARIZE=1 ./package.sh
```

脚本生成 `dist/ClearDisplay-VERSION-arm64.zip`。未签名包仅用于本地测试。签名与公证需要你自己的 Developer ID 身份及本机 `notarytool` 凭据；不要将凭据提交到仓库。发布前应确认 `HiDPIApp/Info.plist` 中的版本号与 bundle ID，并在目标 Mac 上验证签名、公证及各显示器功能。

显示模式、亮度、排列、镜像、旋转、连接状态、HDR、ICC、DDC 和软件图像调整都需要在真实硬件上逐项验证：记录原值，做一次小范围更改，确认读回值后恢复原值，再测试拔插外接屏后的状态。CI 只覆盖静态检查和构建，不会操作显示器。
