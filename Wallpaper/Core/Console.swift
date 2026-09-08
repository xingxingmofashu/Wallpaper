import Foundation

/// 统一的控制台输出入口。
enum Console {
    static func info(_ message: String) {
        FileHandle.standardOutput.write("\(message)\n".data(using: .utf8)!)
    }

    static func error(_ message: String) {
        FileHandle.standardError.write("\(Version.name): error: \(message)\n".data(using: .utf8)!)
    }
}
