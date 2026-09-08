import Foundation

/// 停止当前实例：`stop`。
struct StopCommand: Command {
    let name = "stop"
    let summary = "停止当前实例"

    func execute(arguments: [String]) -> Int32 {
        let pidFile = PIDFile.shared
        guard let pid = pidFile.pid else {
            Console.info("没有正在运行的实例")
            return 0
        }

        guard pidFile.isLiveSelf(pid) else {
            Console.info("记录中的 PID \(pid) 并非本程序实例，已清理")
            pidFile.remove()
            return 0
        }

        kill(pid, SIGTERM)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if !pidFile.isLiveSelf(pid) {
                pidFile.remove()
                Console.info("已停止")
                return 0
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        Console.error("进程 \(pid) 未在 3 秒内退出，可尝试 `kill -9 \(pid)`")
        return 1
    }
}
