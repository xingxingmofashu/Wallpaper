import Foundation

struct UninstallCommand: Command {
    let name = "uninstall"
    let summary = "Show uninstall steps"

    func execute(arguments: [String]) -> Int32 {
        Console.info("Uninstall steps:")
        Console.info("  1. Stop the instance:      \(Version.name) stop")
        Console.info("  2. Remove the binary:      sudo rm -f /usr/local/bin/\(Version.name)")
        Console.info("  3. Remove the share dir:   sudo rm -rf /usr/local/share/\(Version.name)")
        Console.info("  4. Forget the pkg receipt: sudo pkgutil --forget \(Version.bundleID)")
        Console.info("  5. Remove runtime data:    rm -rf ~/.vw")
        return 0
    }
}
