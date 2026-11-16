# iOS（苹果）打包说明

> 2026-10-24 做的 iOS 适配。**iOS 包只能在 Mac 上编译**（需要 Xcode），这台 Windows 电脑上
> 只能把工程和代码准备好——下面列的每一项都还没在真机上跑过，第一次在 Mac 上编译时
> 可能还要修一两处小问题，属正常。

## 已经做好的

| 项 | 说明 |
|---|---|
| iOS 工程 | `app/ios/`（`flutter create --platforms=ios` 生成） |
| 名称 / 包名 | `KataMemo` · `com.katamemo.open` |
| 图标 | `scripts/make_ios_icon.py` 用安卓同一套缎带 K 素材合成（iOS 要求方形、不透明、系统自己裁圆角） |
| 屏幕方向 | iPhone 只竖屏 |
| 权限说明 | 相册、相机（给助记加图用）；通知权限在 App 启动时由系统弹窗请求 |
| 导出文件 | iPhone 没有外部存储，导出的学习数据包 / 词单 / 自建词改存到 App「文稿」目录，在「文件」App → 我的 iPhone → KataMemo Pro 里能看到 |
| 每日提醒 | 通知加了 iOS 配置 |
| 发音 | iPhone 的系统播放器**不认 Ogg**，所以 iOS 包要放同名 AAC（.m4a），见下面第 2、3 步 |

## 暂不支持（iPhone 上）

- **自建词「导入音频文件」**：安卓用的是自己写的原生选择器，iOS 端还没写；iPhone 上点了会提示「iPhone 版暂不支持导入自定义音频」。

## 在 Mac 上打包的步骤

**准备**：一台 Mac（装好 Xcode 15 以上、Homebrew）、和这台电脑**同一版本**的 Flutter、一个 Apple ID。

1. 把本仓库拷到 Mac。

2. 转换音频（约 3.7 万个文件，全部转完约 260 MB，20～40 分钟，可中断续跑）：
   ```bash
   brew install ffmpeg
   python3 scripts/ios_audio.py
   ```
   也可以在 Windows 上先转好：`python scripts\ios_audio.py --ffmpeg "ffmpeg.exe 的路径"`，再把
   `app/assets/audio/edge/ardi_m4a/` 一起拷过去。原来的 Ogg 一个不删。

3. 把 pubspec 的音频目录切到 iOS：
   ```bash
   python3 scripts/ios_prepare.py --ios
   ```

4. 装依赖：
   ```bash
   cd app
   flutter pub get
   cd ios && pod install && cd ..
   ```
   如果 `pod install` 报最低系统版本不够，打开 `ios/Podfile` 把第一行改成 `platform :ios, '13.0'` 再装一次。

5. 签名：用 Xcode 打开 `app/ios/Runner.xcworkspace` → 左侧选 Runner → Signing & Capabilities →
   Team 选你的 Apple ID。包名如果提示已被占用，改成别的（比如加个后缀）。

6. 装到 iPhone：手机连 Mac，在 `app` 目录里
   ```bash
   flutter run --release
   ```
   第一次装好后，在 iPhone「设置 → 通用 → VPN 与设备管理」里信任你的开发者账号，才能打开。

7. **打完立刻切回安卓**（否则下次打安卓包会没有声音）：
   ```bash
   python3 scripts/ios_prepare.py --android
   ```

## 要知道的限制

- **免费 Apple ID** 装到自己手机上的 App **7 天后失效**，要重新连 Mac 装一次；
  想长期用或分发给别人（TestFlight / App Store），要加入 Apple 开发者计划（每年 99 美元）。
- iOS 包体积大约 300 MB（音频占大头）。
- 上架 App Store 时，审核会看「使用须知」、隐私说明等；音频和 KBBI 数据的授权问题（见开源说明）在上架时风险更高。
