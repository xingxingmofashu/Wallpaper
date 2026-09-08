import Foundation

/// 查看卸载步骤：`uninstall`。
struct UninstallCommand: Command {
    let name = "uninstall"
    let summary = "查看卸载步骤"

    func execute(arguments: [String]) -> Int32 {
        Console.info("卸载说明：")
        Console.info("  1. 停止运行:   \(Version.name) stop")
        Console.info("  2. 删除二进制:  sudo rm -f /usr/local/bin/\(Version.name)")
        Console.info("  3. 删除共享目录: sudo rm -rf /usr/local/share/\(Version.name)")
        Console.info("  4. 忘记 pkg 记录: sudo pkgutil --forget \(Version.bundleID)")
        Console.info("  5. 删除运行记录: rm -rf ~/.vw")
        return 0
    }
}
