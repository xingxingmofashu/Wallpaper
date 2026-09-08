import Foundation

/// 版本信息。
enum Version {
    static let number = "1.0.0"
    static let name = "vw"
    static let bundleID = "com.example.vw"
    static let full = "\(name) \(number)"
}

/// 显示版本：`version` / `-v`。
struct VersionCommand: Command {
    let name = "version"
    let summary = "显示版本"

    func execute(arguments: [String]) -> Int32 {
        Console.info(Version.full)
        return 0
    }
}
