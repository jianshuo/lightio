# Lightio

> 写作 / UI 上叫 **Lightio**，binary 叫 `Lightio`（`/Applications/Lightio.app`），
> CLI 命令叫 `lightio`（`/usr/local/bin/lightio`）。

借用 Mac 灵动岛作为 Claude Code 状态指示器：
低调的细线带着晕光环绕刘海。

## 状态颜色

- **WORKING** — amber `#f5a623`（Claude 在跑）
- **WAITING** — green `#5fcf7a`（等你输入）
- **IDLE** — white（完成 / 长时间无活动）

WAITING 持续 5 分钟无动作 → 自动降级为 IDLE。
任何 session 超过 10 分钟没更新 → 视为已死，自动从列表移除。

## 多 session

刘海下方的 U 形线分成 1–4 段，每段对应一个 session，按 session id 排序。
session 多于 4 个时只显示最近活跃的 4 个。
每段独立着色，每段有自己的晕光。

## 菜单栏

- 状态栏小圆点显示所有 session 的合并状态（任一 working 就 amber；
  否则任一 waiting 就 green；全 idle 才 white）。
- 点开菜单：每个 session 一行，前面带对应颜色的小圆点；
每个session有一个比较合理的名字，
Hooks子菜单包括了安装和uninstall  
下方下方是 「Launch at Login」「About」「Quit」。

## 视觉规格

- 透明 borderless NSWindow，跨 Space 常驻，鼠标穿透
- 自动检测刘海位置（`NSScreen.safeAreaInsets` + `auxiliaryTopLeftArea/RightArea`）
- U 形 path：右侧↓ → 右下圆角弧 → 底部← → 左下圆角弧 → 左侧↑
- 每段两层 CAShapeLayer 叠加：内层 shadowRadius=8、外层 22；line width 2.5pt

## 接入 Claude Code

一次性把 hooks 写到 `~/.claude/settings.json`：

| Hook | Command |
|---|---|
| `SessionStart` | `lightio set waiting` |
| `UserPromptSubmit` | `lightio set working` |
| `Stop` | `lightio set waiting` |
| `Notification` | `lightio set waiting` |
| `SessionEnd` | `lightio clear` |

CLI 读 stdin JSON 取 `session_id` + `cwd`，原子写入 `~/.lightio/state.json`。
Mac app 通过 FSEvents 监听这个文件实时响应。

CLI 安装到 `/usr/local/bin/lightio`（symlink 到 app bundle 内），
首次启动时弹对话框走管理员授权。
