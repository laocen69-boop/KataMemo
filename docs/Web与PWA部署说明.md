# Web / PWA 使用与独立部署说明

KataMemo 支持编译为纯静态 **Web / PWA（渐进式网页应用）**。iOS（iPhone / iPad）或桌面浏览器用户无需安装原生 App，打开网页即可背单词、听离线切片发音、查词与阅读语法；在 iOS Safari 中通过「添加到主屏幕」即可获得接近原生 App 的全屏体验。

---

## 1. 数据与隐私模型（先读这段）

- **纯静态前端，无后台服务器**：Web 版没有任何后台数据库。
- **一人一库，本地隔离**：无论你是打开作者部署的网址，还是自己部署了一个网址，所有学习记录、FSRS 调度进度、自建词条、笔记以及可选填入的 AI API Key，**全部只保存在访问者自己设备的浏览器本地存储（IndexedDB / OPFS）中**。
  - 网站托管方看不到你的学习记录或 API Key；
  - 多个朋友访问同一个网址时，彼此的数据也完全隔离、互不可见。
- **自由独立部署**：基于 MIT 协议，任何开发者都可以 Fork 本仓库，修改词库或图标后部署到自己名下，生成完全属于自己的独立网址。

---

## 2. iOS Safari 用户使用步骤（添加到主屏幕）

1. 用 iPhone / iPad 自带的 **Safari** 浏览器打开部署好的 `https://...` 网址；
2. 首次打开会初始化本地 SQLite 词库，请耐心等待进度条走完；
3. 点浏览器底部的 **分享** 按钮 → 选择 **「添加到主屏幕」**，桌面就会生成 KataMemo 图标，之后从桌面打开即为全屏模式；
4. **防丢提醒**：建议定期在 App 内 **导出学习数据包（`.json`）** 备份，避免系统长期未打开网页或手动清浏览器缓存时丢失学习记录。

> **关于语音播放**：由于浏览器安全策略限制，首次进入页面后请至少轻触一次屏幕（如点「去学习」或点一下卡片），即可解锁后续的自动发音（`autoSpeak`）。

---

## 3. 开发者自己部署一份（3 种方式）

### 方式 A：Cloudflare Pages（最推荐，原生支持大文件与密码门禁）

为什么推荐 Cloudflare Pages：
- 单个 `.pak` 音频分片约 `12.5 ~ 13.0 MB`，完全符合 Cloudflare Pages 单文件 `≤ 25 MB` 的免费额度；
- 原生支持 HTTP `206 Range` 请求，播放单词时只按偏移拉取 1～2 KB 音频切片，不卡首屏；
- 如果只想给少数朋友私密使用，可在 Cloudflare 控制台免费开启 **Cloudflare Access**（设置邮箱验证码或访问密码门禁）。

**部署步骤：**
1. 本地编译（在 `app/` 目录执行）：
   ```bash
   flutter pub get
   flutter build web --release --no-wasm-dry-run
   ```
2. 将 `app/build/web/` 目录上传到 Cloudflare Pages（或关联你 Fork 后的仓库，构建命令填上述指令、输出目录填 `app/build/web`）。

---

### 方式 B：GitHub Pages（Fork 后点一下即可部署）

本仓库已在 `.github/workflows/deploy-web.yml` 预置了 **手动触发** 的 GitHub Pages 部署工作流：

1. 将本仓库 **Fork** 到你自己的 GitHub 账号下；
2. 进入你的仓库 **Settings → Pages**，将 **Source** 选为 **`GitHub Actions`**；
3. 进入仓库 **Actions → Deploy Web (GitHub Pages)** → 点击 **Run workflow**；
4. 构建完成后，即可在 `https://<你的用户名>.github.io/<你的仓库名>/` 访问属于你自己的网页版。

> **手动画坑提示**：若手动编译部署到子路径（如 `/KataMemo/`），编译时必须加上 `--base-href` 参数：
> ```bash
> flutter build web --release --no-wasm-dry-run --base-href "/KataMemo/"
> ```

---

### 方式 C：本地构建与局域网自测

编译产物位于 `app/build/web/`。注意：**本地静态服务器必须支持 HTTP `206 Partial Content（Range）` 请求与 `.wasm` MIME 类型**，否则无法按偏移加载 `.pak` 中的单词发音（会自动回退为下载整片 13MB 文件）。

---

## 4. Web 版功能边界（与 Android 原生版差异）

- **完整保留**：9.6 万+ 词库检索与分层学习、FSRS-6 间隔重复、点词发音（按需加载 `.pak` 切片）、语法与写作手册（含个人笔记编辑）、自定义词单/词典导入、数据包导出备份、AI 助手（需接口支持浏览器 CORS）。
- **Web 首期自动隐藏/降级**：
  - 拍照抓词 OCR（依赖移动端 ML Kit，Web 不提供）；
  - 端内 FSRS 参数本地训练（`libfsrs.so` 依赖 `dart:ffi`，Web 自动隐藏该按钮，仍可导出 CSV 在电脑训练）；
  - 本地定时提醒通知。
