import Foundation

/// 顶层命令分发器：登记子命令、分发参数。
enum CLI {
    /// 所有子命令。
    static let commands: [any Command] = [
        RunCommand(),
        StopCommand(),
        UninstallCommand(),
        VersionCommand(),
        HelpCommand(),
    ]

    /// 入口：分发命令行参数，返回进程退出码。
    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count > 1 else {
            return HelpCommand().execute(arguments: [])
        }

        switch arguments[1] {
        case "-h", "--help":
            return HelpCommand().execute(arguments: [])
        case "-v", "--version":
            return VersionCommand().execute(arguments: [])
        default:
            if let command = find(arguments[1]) {
                return command.execute(arguments: Array(arguments.dropFirst(2)))
            }
            // 兼容旧用法：`vw <video>` 等价于 `vw run <video>`
            if arguments[1].hasPrefix("-") {
                return HelpCommand().execute(arguments: [])
            }
            return RunCommand().execute(arguments: Array(arguments.dropFirst(1)))
        }
    }

    /// 按命令名查找，找不到返回 nil。
    private static func find(_ name: String) -> (any Command)? {
        commands.first { $0.name == name }
    }
}
