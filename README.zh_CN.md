<div align="center">

# VideoWallpaper

**在终端里把一段循环视频设为 macOS 桌面壁纸。**

<p align="center">
  <a href="https://github.com/xingxingmofashu/Wallpaper/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/xingxingmofashu/Wallpaper?style=flat-square" /></a>
  <a href="https://github.com/xingxingmofashu/Wallpaper/actions/workflows/ci.yml"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/xingxingmofashu/Wallpaper/ci.yml?style=flat-square&branch=main" /></a>
</p>

<p align="center">
  <a href="README.md">English</a> |
  简体中文
</p>

[![vw 壁纸预览](https://raw.githubusercontent.com/xingxingmofashu/Wallpaper/main/.github/assets/preview.jpg)](https://raw.githubusercontent.com/xingxingmofashu/Wallpaper/main/.github/assets/preview.mp4)

<p align="center"><sub>预览图来源于艺术家 <a href="https://www.wlop.art">WLOP</a></sub></p>

</div>

---

```bash
vw run ~/Videos/wallpaper.mov      # 启动（立即返回）
vw stop                            # 停止
```

## 特性

- 播放任意本地视频并循环，支持**所有屏幕**或仅主显示器
- 守护进程运行：终端关闭后壁纸继续播放；`vw run` 立即返回 `Started (PID n)`
- 单实例锁（`flock`）；并发启动会被快速拒绝并给出明确提示
- 自我保护：解码失败、播放停滞（默认 8 秒）、主线程无响应（默认 6 秒）时自动退出，而不是让桌面永远卡住
- 显示器睡眠/唤醒、锁屏/解锁、分辨率变化时保持稳定；屏幕配置未变化时不重建窗口
- 命令行输出为纯英文

## 环境要求

- Apple Silicon Mac，macOS 26.2+
- Xcode（用于 `xcodebuild` 构建）—— 仅构建时需要，运行时不需要

## 安装

一行命令，无需 clone（自动下载最新 Release）：

```bash
curl -fsSL https://raw.githubusercontent.com/xingxingmofashu/Wallpaper/main/Scripts/install.sh | bash
```

或从源码构建：

```bash
git clone https://github.com/xingxingmofashu/Wallpaper.git
cd Wallpaper
./Scripts/install.sh
```

两种方式都会按以下顺序安装到第一个可写位置：`$VW_PREFIX`、`/usr/local/bin`
（需要时才用 sudo）、`/opt/homebrew/bin`；安装前会先删除旧二进制再复制 ——
因为原地覆盖已签名的二进制（同 inode）会导致 macOS 在下次启动时直接 SIGKILL。

卸载：

```bash
./Scripts/install.sh --uninstall                    # 在克隆的仓库内
curl -fsSL https://raw.githubusercontent.com/xingxingmofashu/Wallpaper/main/Scripts/install.sh | bash -s -- --uninstall
```

## 使用

```text
vw run <视频> [选项]   后台播放视频壁纸
vw stop                停止当前实例
vw uninstall           查看手动卸载步骤
vw version             显示版本
vw help                显示完整帮助
```

`vw <视频>`（不带 `run`）也可以作为简写。

### run 选项

| 选项 | 说明 | 默认值 |
|---|---|---|
| `--single` | 仅覆盖主显示器 | 所有屏幕 |
| `--rate <0.1-1.0>` | 限制播放速率以降低 CPU/GPU 占用 | `1.0` |
| `--stall <秒>` | 播放停滞超过该时长自动退出；`0` 关闭（上限 86400） | `8` |
| `--watchdog <秒>` | 主线程无响应超过该时长自动退出；`0` 关闭（上限 86400） | `6` |

示例：

```bash
vw run ~/Videos/wallpaper.mov --single --rate 0.5
vw run ~/Videos/wallpaper.mov --stall 0 --watchdog 0   # 关闭自动退出保护
```

## 工作原理

- `vw run` 通过 `posix_spawn`（`POSIX_SPAWN_SETSID`）重新执行自身：守护进程脱离
  终端（终端关闭不影响，忽略 SIGHUP），stdin 指向 `/dev/null`，stdout/stderr 追加
  写入 `~/.vw/vw.log`。
- 守护进程写入 `~/.vw/vw.pid`；`vw stop` 在发送 `SIGTERM` 前会用 `proc_pidpath`
  双向比对，确认 PID 确实属于 `vw`，避免误杀无关进程。
- 守护进程继承 `~/.vw/vw.lock` 上的 `flock`，单实例保证覆盖守护进程的整个生命周期，
  退出或被杀时锁自动释放。
- 每块屏幕一个无边框 `NSWindow`（桌面窗口层级）+ `AVPlayerLayer`；仅当屏幕配置
  真正变化时才重建窗口。

### 运行时文件

| 路径 | 用途 |
|---|---|
| `~/.vw/vw.pid` | 守护进程 PID |
| `~/.vw/vw.lock` | 单实例锁 |
| `~/.vw/vw.log` | 守护进程输出/错误（每次启动时清空） |

## 常见问题

- `Another instance is running` → 先执行 `vw stop`。
- 壁纸消失 → daemon 大概率已退出；检查 `ps -p "$(cat ~/.vw/vw.pid)"` 后重新
  `vw run`，异常退出的原因记录在 `~/.vw/vw.log`。
- **锁屏界面**始终显示系统静态壁纸，这是 macOS 的限制；解锁后桌面视频会继续播放。
- 若用**浏览器**下载二进制（而非 curl），macOS Gatekeeper 可能拦截（quarantine 标记）；
  用 `xattr -d com.apple.quarantine <文件>` 清除，或改用 curl 方式安装。

## 开发

```bash
xcodebuild -project Wallpaper.xcodeproj -scheme Wallpaper -configuration Debug build
```

源码结构：`Wallpaper/CLI`（命令分发与子命令），`Wallpaper/Core`（播放引擎、
守护进程化、PID/锁文件、信号处理）。
