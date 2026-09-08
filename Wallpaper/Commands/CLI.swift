import Foundation
import Cocoa

/// 顶层命令分发。
enum CLI {
    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count > 1 else {
            return showUsage()
        }

        switch arguments[1] {
        case "-h", "--help":
            return showUsage()
        case "-v", "--version":
            Console.info(Version.full)
            return 0
        case "run":
            return runCommand(Array(arguments.dropFirst(2)))
        case "stop":
            return stopCommand()
        case "uninstall":
            return uninstallCommand()
        default:
            // 兼容旧用法：`vw <video>` 等价于 `vw run <video>`
            if arguments[1].hasPrefix("-") {
                return showUsage()
            }
            return runCommand(Array(arguments.dropFirst(1)))
        }
    }

    // MARK: - run

    private static func runCommand(_ args: [String]) -> Int32 {
        guard let first = args.first, !first.hasPrefix("-") else {
            Console.error("缺少视频路径")
            _ = showUsage()
            return 1
        }

        let videoURL = URL(fileURLWithPath: first)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            Console.error("文件不存在: \(videoURL.path)")
            return 1
        }

        let optionArgs = Array(args.dropFirst())
        let options: RunOptions
        do {
            options = try RunOptions.parse(optionArgs)
        } catch {
            Console.error("\(error)")
            return 1
        }

        return startApplication(videoURL: videoURL, options: options)
    }

    /// 进入 AppKit 主循环并播放壁纸（阻塞直至退出）。
    private static func startApplication(videoURL: URL, options: RunOptions) -> Int32 {
        let pidFile = PIDFile.shared
        guard pidFile.acquire() else {
            if let existing = pidFile.pid {
                Console.error("另一个实例正在运行 (PID \(existing))，请先执行 `vw stop`")
            } else {
                Console.error("另一个实例正在运行，请先执行 `vw stop`")
            }
            return 1
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let wallpaper = WallpaperApp(videoURL: videoURL, options: options)
        wallpaper.start()

        // 强引用持有，确保信号 handler 在整个生命周期内有效。
        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM]) {
            wallpaper.stop()
            PIDFile.shared.remove()
            exit(0)
        }
        withExtendedLifetime(signalHandler) {
            app.run()
        }

        // app.run() 只有进程即将退出时才返回（此处几乎不会到达）。
        wallpaper.stop()
        pidFile.remove()
        return 0
    }

    // MARK: - stop

    private static func stopCommand() -> Int32 {
        let pidFile = PIDFile.shared
        guard let pid = pidFile.pid else {
            Console.info("没有正在运行的实例")
            return 0
        }

        guard pidFile.isProcessAlive(pid) else {
            Console.info("PID \(pid) 已不在运行，清理残留记录")
            pidFile.remove()
            return 0
        }

        kill(pid, SIGTERM)

        // 等待进程退出
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if !pidFile.isProcessAlive(pid) {
                pidFile.remove()
                Console.info("已停止")
                return 0
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        Console.error("进程 \(pid) 未在 3 秒内退出，可尝试 `kill -9 \(pid)`")
        return 1
    }

    // MARK: - uninstall

    private static func uninstallCommand() -> Int32 {
        Console.info("卸载说明：")
        Console.info("  1. 停止运行:   \(Version.name) stop")
        Console.info("  2. 删除二进制:  sudo rm -f /usr/local/bin/\(Version.name)")
        Console.info("  3. 删除共享目录: sudo rm -rf /usr/local/share/\(Version.name)")
        Console.info("  4. 忘记 pkg 记录: sudo pkgutil --forget \(Version.bundleID)")
        Console.info("  5. 删除运行记录: rm -rf ~/.vw")
        return 0
    }

    // MARK: - usage

    private static func showUsage() -> Int32 {
        Console.info(
            """
            \(Version.full)

            用法:
              \(Version.name) run <视频路径> [选项]   播放视频壁纸
              \(Version.name) stop                   停止当前实例
              \(Version.name) uninstall              查看卸载步骤
              \(Version.name) -h, --help             显示帮助
              \(Version.name) -v, --version          显示版本

            选项 (run):
              --single              仅覆盖主显示器 (默认: 所有屏幕)
              --rate <0.1-1.0>      播放速率上限，用于降帧降压 (默认: 1.0)
              --stall <秒>          播放停滞超过该时长自动退出，0 关闭 (默认: 8)
              --watchdog <秒>       UI 无响应超过该时长自动退出，0 关闭 (默认: 6)

            示例:
              \(Version.name) run ~/Videos/wallpaper.mov
              \(Version.name) run video.mov --single --rate 0.5
            """
        )
        return 0
    }
}
