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
                options.stallLimit = try nextValue("--stall") { $0 >= 0 && $0 <= 86400 }
            case "--watchdog":
                options.watchdogLimit = try nextValue("--watchdog") { $0 >= 0 && $0 <= 86400 }
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
    let summary = "<video> [options]  Play video wallpaper in background"
    let optionsHelp = """
        Options:
          --single              Cover only the main display (default: all screens)
          --rate <0.1-1.0>      Max playback rate to lower CPU/GPU load (default: 1.0)
          --stall <seconds>     Auto-exit when playback stalls or never starts within this long, 0 disables (default: 8, max 86400)
          --watchdog <seconds>  Auto-exit if UI is unresponsive this long, 0 disables (default: 6, max 86400)

        The command returns immediately; the wallpaper keeps playing after the
        terminal is closed. Stop it with `vw stop`. Errors go to ~/.vw/vw.log.
        """

    func execute(arguments: [String]) -> Int32 {
        guard let input = validatedInput(arguments) else { return 1 }
        return startDetached(videoURL: input.videoURL, options: input.options)
    }

    /// Internal entry for the detached daemon process.
    func executeDaemon(arguments: [String]) -> Int32 {
        let args = arguments.first == "run" ? Array(arguments.dropFirst()) : arguments
        guard let input = validatedInput(args) else { return 1 }
        return runDaemon(videoURL: input.videoURL, options: input.options)
    }

    private func validatedInput(_ arguments: [String]) -> (videoURL: URL, options: RunOptions)? {
        guard let videoPath = arguments.first, !videoPath.hasPrefix("-") else {
            Console.error("Missing video path")
            Console.info(HelpCommand().usage())
            return nil
        }
        let videoURL = URL(fileURLWithPath: videoPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: videoURL.path, isDirectory: &isDirectory) else {
            Console.error("File not found: \(videoURL.path)")
            return nil
        }
        guard !isDirectory.boolValue else {
            Console.error("Not a video file: \(videoURL.path)")
            return nil
        }
        guard isReadable(videoURL) else {
            Console.error("No permission to read file: \(videoURL.path)")
            Console.error("If the file is in Downloads/Desktop/Documents, grant your terminal app access in System Settings > Privacy & Security > Files and Folders, or move the file to an unrestricted folder such as ~/Movies")
            return nil
        }
        let options: RunOptions
        do {
            options = try RunOptions.parse(Array(arguments.dropFirst()))
        } catch {
            Console.error("\(error.localizedDescription)")
            return nil
        }
        return (videoURL, options)
    }

    private func isReadable(_ url: URL) -> Bool {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    private func startDetached(videoURL: URL, options: RunOptions) -> Int32 {
        let pidFile = PIDFile.shared
        let dataDir = pidFile.url.deletingLastPathComponent()
        let logURL = dataDir.appendingPathComponent("vw.log")
        let lockURL = dataDir.appendingPathComponent("vw.lock")

        do {
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        } catch {
            Console.error("Failed to create \(dataDir.path): \(error.localizedDescription)")
            return 1
        }

        let lockFD = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else {
            Console.error("Failed to open \(lockURL.path): \(String(cString: strerror(errno)))")
            return 1
        }
        defer { close(lockFD) }

        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK {
                reportAlreadyRunning(pidFile)
            } else {
                Console.error("Failed to lock \(lockURL.path): \(String(cString: strerror(errno)))")
            }
            return 1
        }

        if let existing = pidFile.pid, pidFile.isLiveSelf(existing) {
            reportAlreadyRunning(pidFile)
            return 1
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        do {
            let command = ["run", videoURL.path] + optionArguments(options)
            let pid = try Daemon.spawn(detachedCommand: command, logURL: logURL, lockFD: lockFD)
            Console.info("Started (PID \(pid))")
            return 0
        } catch {
            Console.error("Failed to start: \(error.localizedDescription)")
            return 1
        }
    }

    private func reportAlreadyRunning(_ pidFile: PIDFile) {
        if let existing = pidFile.pid, pidFile.isLiveSelf(existing) {
            Console.error("Another instance is running (PID \(existing)), run `\(Version.name) stop` first")
        } else {
            Console.error("Another instance is running, run `\(Version.name) stop` first")
        }
    }

    private func optionArguments(_ options: RunOptions) -> [String] {
        var args: [String] = []
        if options.singleScreen { args.append("--single") }
        args.append("--rate")
        args.append(String(options.rate))
        args.append("--stall")
        args.append(String(options.stallLimit))
        args.append("--watchdog")
        args.append(String(options.watchdogLimit))
        return args
    }

    private func runDaemon(videoURL: URL, options: RunOptions) -> Int32 {
        let pidFile = PIDFile.shared

        signal(SIGHUP, SIG_IGN)

        switch pidFile.acquire() {
        case .acquired:
            break
        case .alreadyRunning(let existing):
            Console.error("Another instance is running (PID \(existing)), exiting")
            exit(1)
        case .writeFailed(let error):
            Console.error("Failed to write PID file (\(pidFile.url.path)): \(error.localizedDescription)")
            exit(1)
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
