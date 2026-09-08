import Foundation
import Darwin

/// 运行实例的 PID 记录（`~/.vw/vw.pid`），供 `vw stop` 定位进程。
final class PIDFile {
    static let shared = PIDFile()

    let url: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vw", isDirectory: true)) {
        url = directory.appendingPathComponent("vw.pid")
    }

    /// 当前记录的 PID。
    var pid: pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 排他获取：若已有「本程序的存活实例」则失败。
    @discardableResult
    func acquire(pid: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        if let existing = self.pid, isLiveSelf(existing) {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try String(pid).write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// 判断 PID 是否仍存活，且确属本程序。
    ///
    /// 仅 `kill(pid, 0)` 会误判：陈旧记录可能被系统复用到无关进程。
    /// 故需比对可执行文件路径，防止 `vw stop` 误杀他人进程。
    func isLiveSelf(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        guard let target = executablePath(of: pid) else { return false }
        return target == ownExecutablePath
    }

    private var ownExecutablePath: String {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        let size = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard size > 0 else { return nil }
        return String(cString: buffer)
    }
}
