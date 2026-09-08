import Foundation
import Cocoa

struct OptionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct RunOptions {
    var singleScreen = false
    var rate: Float = 1.0
    var stallLimit: TimeInterval = 8
    var watchdogLimit: TimeInterval = 6

    static func parse(_ args: [String]) throws -> RunOptions {
        var options = RunOptions()
        var index = 0

        func nextValue<T>(_ name: String, validate: (T) -> Bool) throws -> T
            where T: LosslessStringConvertible {
            guard index + 1 < args.count,
                  let value = T(args[index + 1]),
                  validate(value) else {
                throw OptionError(message: "Invalid value for \(name)")
            }
            index += 1
            return value
        }

        while index < args.count {
            switch args[index] {
            case "--single":
                options.singleScreen = true
            case "--rate":
                options.rate = try nextValue("--rate") { (0.1...1.0).contains($0) }
            case "--stall":
                options.stallLimit = try nextValue("--stall") { $0 >= 0 }
            case "--watchdog":
                options.watchdogLimit = try nextValue("--watchdog") { $0 >= 0 }
            default:
                throw OptionError(message: "Unknown option: \(args[index])")
            }
            index += 1
        }
        return options
    }
}

struct RunCommand: Command {
    let name = "run"
    let summary = "<video> [options]  Play video wallpaper"
    let optionsHelp = """
        Options:
          --single              Cover only the main display (default: all screens)
          --rate <0.1-1.0>      Max playback rate to lower CPU/GPU load (default: 1.0)
          --stall <seconds>     Auto-exit after playback stalls this long, 0 disables (default: 8)
          --watchdog <seconds>  Auto-exit if UI is unresponsive this long, 0 disables (default: 6)
        """

    func execute(arguments: [String]) -> Int32 {
        guard let videoPath = arguments.first, !videoPath.hasPrefix("-") else {
            Console.error("Missing video path")
            Console.info(HelpCommand().usage())
            return 1
        }
        let videoURL = URL(fileURLWithPath: videoPath)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            Console.error("File not found: \(videoURL.path)")
            return 1
        }

        let options: RunOptions
        do {
            options = try RunOptions.parse(Array(arguments.dropFirst()))
        } catch {
            Console.error("\(error.localizedDescription)")
            return 1
        }

        return runApplication(videoURL: videoURL, options: options)
    }

    private func runApplication(videoURL: URL, options: RunOptions) -> Int32 {
        let pidFile = PIDFile.shared
        switch pidFile.acquire() {
        case .acquired:
            break
        case .alreadyRunning(let existing):
            Console.error("Another instance is running (PID \(existing)), run `\(Version.name) stop` first")
            return 1
        case .writeFailed(let error):
            Console.error("Failed to write PID file (\(pidFile.url.path)): \(error.localizedDescription)")
            return 1
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let wallpaper = Wallpaper(videoURL: videoURL, options: options)
        wallpaper.start()

        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM]) {
            wallpaper.stop()
            PIDFile.shared.remove()
            exit(0)
        }
        withExtendedLifetime(signalHandler) {
            app.run()
        }

        wallpaper.stop()
        pidFile.remove()
        return 0
    }
}
