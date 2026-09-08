import Foundation

/// `vw run` 的参数解析错误。
struct OptionError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
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

    /// 解析 `run` 之后的参数。失败时抛出 OptionError。
    static func parse(_ args: [String]) throws -> RunOptions {
        var opts = RunOptions()
        var index = 0

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--single":
                opts.singleScreen = true

            case "--rate":
                guard index + 1 < args.count,
                      let value = Float(args[index + 1]),
                      (0.1...1.0).contains(value) else {
                    throw OptionError(message: "--rate 需要 0.1...1.0 之间的数值")
                }
                opts.rate = value
                index += 1

            case "--stall":
                guard index + 1 < args.count,
                      let value = TimeInterval(args[index + 1]),
                      value >= 0 else {
                    throw OptionError(message: "--stall 需要 >= 0 的秒数")
                }
                opts.stallLimit = value
                index += 1

            case "--watchdog":
                guard index + 1 < args.count,
                      let value = TimeInterval(args[index + 1]),
                      value >= 0 else {
                    throw OptionError(message: "--watchdog 需要 >= 0 的秒数")
                }
                opts.watchdogLimit = value
                index += 1

            default:
                throw OptionError(message: "未知参数: \(arg)")
            }
            index += 1
        }

        return opts
    }
}
