import Foundation

/// 管理运行实例的 PID 文件，用于 `vw stop` 精确定位进程。
final class PIDFile {
    /// 全局共享实例（指向当前用户 `~/.vw/vw.pid`）。
    static let shared = PIDFile()

    let url: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vw", isDirectory: true)) {
        url = directory.appendingPathComponent("vw.pid")
    }

    var isPresent: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 读取 PID；文件不存在或内容非法时返回 nil。
    var pid: pid_t? {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        return pid_t(trimmed)
    }

    /// 排他写入：若已有存活进程则返回 false。
    @discardableResult
    func acquire(pid: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        if let existing = self.pid, isProcessAlive(existing) {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try String(pid).write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// 判断指定 PID 是否存活。
    func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}
