import Foundation

struct UninstallCommand: Command {
    let name = "uninstall"
    let summary = "Stop the instance, remove the binary and runtime data"

    func execute(arguments: [String]) -> Int32 {
        let stopStatus = StopCommand().execute(arguments: [])
        guard stopStatus == 0 else { return 1 }

        var failed = false

        if let binaryPath = ProcessInfo.processInfo.processIdentifier.executablePath {
            do {
                try FileManager.default.removeItem(atPath: binaryPath)
                Console.info("Removed \(binaryPath)")
            } catch {
                Console.error("Failed to remove \(binaryPath): \(error.localizedDescription)")
                Console.error("Run manually: sudo rm -f \(binaryPath)")
                failed = true
            }
        } else {
            Console.error("Could not locate the running binary")
            failed = true
        }

        let dataDir = PIDFile.shared.url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: dataDir.path) {
            do {
                try FileManager.default.removeItem(at: dataDir)
                Console.info("Removed \(dataDir.path)")
            } catch {
                Console.error("Failed to remove \(dataDir.path): \(error.localizedDescription)")
                failed = true
            }
        }

        if failed {
            Console.error("Uninstall incomplete")
            return 1
        }
        Console.info("Uninstalled")
        return 0
    }
}
