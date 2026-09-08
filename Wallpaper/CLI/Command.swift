import Foundation

/// 命令协议：所有子命令都实现该接口。
protocol Command {
    /// 命令名，如 `run`、`stop`。
    var name: String { get }

    /// 帮助摘要。
    var summary: String { get }

    /// 执行命令，返回退出码。
    func execute(arguments: [String]) -> Int32
}
