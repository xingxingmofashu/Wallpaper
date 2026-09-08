import Foundation
import Cocoa

/// 参数解析错误。
struct OptionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// `vw run` 的可选参数。
struct RunOptions {
    /// 仅覆盖主显示器（默认覆盖所有屏幕）。
    var singleScreen = false
    /// 播放速率上限，范围 0.1...1.0，用于降帧降压。
    var rate: Float = 1.0
    /// 播放停滞超过该秒数则自动退出；0 表示关闭。
    var stallLimit: TimeInterval = 8
    /// 主线程无响应超过该秒数则自动退出；0 表示关闭。
    var watchdogLimit: TimeInterval = 6

    /// 解析 `run` 之后的参数，非法时抛出 OptionError。
    static func parse(_ args: [String]) throws -> RunOptions {
        var options = RunOptions()
        var index = 0

        func nextValue<T>(_ name: String, validate: (T) -> Bool) throws -> T
            where T: LosslessStringConvertible {
            guard index + 1 < args.count,
                  let value = T(args[index + 1]),
                  validate(value) else {
                throw OptionError(message: "\(name) 参数非法")
            }
            index += 1
            return value
        }

        while index < args.count {
            switch args[index] {
            case "--single":
                options.singleScreen = true
            case "--rate":
                options.rate = try nextValue("--rate") { (0.1...1.0).contains($0) }
            case "--stall":
                options.stallLimit = try nextValue("--stall") { $0 >= 0 }
            case "--watchdog":
                options.watchdogLimit = try nextValue("--watchdog") { $0 >= 0 }
            default:
                throw OptionError(message: "未知参数: \(args[index])")
            }
            index += 1
        }
        return options
    }
}

/// 播放视频壁纸：`run <视频路径> [选项]`。
struct RunCommand: Command {
    let name = "run"
    let summary = "<视频路径> [选项]  播放视频壁纸"
    let optionsHelp = """
        选项:
          --single              仅覆盖主显示器 (默认: 所有屏幕)
          --rate <0.1-1.0>      播放速率上限，用于降帧降压 (默认: 1.0)
          --stall <秒>          播放停滞超过该时长自动退出，0 关闭 (默认: 8)
          --watchdog <秒>       UI 无响应超过该时长自动退出，0 关闭 (默认: 6)
        """

    func execute(arguments: [String]) -> Int32 {
        guard let videoPath = arguments.first, !videoPath.hasPrefix("-") else {
            Console.error("缺少视频路径")
            return 1
        }
        let videoURL = URL(fileURLWithPath: videoPath)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            Console.error("文件不存在: \(videoURL.path)")
            return 1
        }

        let options: RunOptions
        do {
            options = try RunOptions.parse(Array(arguments.dropFirst()))
        } catch {
            Console.error("\(error.localizedDescription)")
            return 1
        }

        return runApplication(videoURL: videoURL, options: options)
    }

    /// 进入 AppKit 主循环并播放壁纸（阻塞直至退出）。
    private func runApplication(videoURL: URL, options: RunOptions) -> Int32 {
        let pidFile = PIDFile.shared
        guard pidFile.acquire() else {
            let detail = pidFile.pid.map { " (PID \($0))" } ?? ""
            Console.error("另一个实例正在运行\(detail)，请先执行 `\(Version.name) stop`")
            return 1
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let wallpaper = Wallpaper(videoURL: videoURL, options: options)
        wallpaper.start()

        // 强引用持有信号源，确保 handler 在生命周期内有效。
        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM]) {
            wallpaper.stop()
            PIDFile.shared.remove()
            exit(0)
        }
        withExtendedLifetime(signalHandler) {
            app.run()
        }

        // app.run() 仅在进程退出时返回（通常不可达）。
        wallpaper.stop()
        pidFile.remove()
        return 0
    }
}
