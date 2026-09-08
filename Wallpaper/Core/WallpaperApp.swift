import Cocoa
import AVFoundation

/// 视频壁纸核心：创建桌面层窗口并循环播放视频。
///
/// 内置多重自我保护，避免在极端情况下拖垮系统：
/// - 主线程 watchdog：UI 线程无响应超时自动退出
/// - 播放停滞检测：处于播放状态但进度不前进时自动退出
/// - 解码失败监听：播放失败即干净退出
/// - 屏幕睡眠自动暂停，唤醒后恢复
final class WallpaperApp: NSObject {
    private let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private let options: RunOptions
    private let videoURL: URL

    private var windows: [NSWindow] = []
    private var isRunning = false
    private var isAsleep = false
    private var playbackObserverTokens: [NSObjectProtocol] = []

    private var heartbeatTimer: Timer?
    private var stallTimer: Timer?

    /// 主线程心跳，由 watchdog 轮询。
    private(set) var lastHeartbeat = Date()

    init(videoURL: URL, options: RunOptions) {
        self.videoURL = videoURL
        self.options = options

        let item = AVPlayerItem(url: videoURL)
        player = AVQueuePlayer(items: [item])
        player.isMuted = true
        player.defaultRate = options.rate

        super.init()
        observePlayback(of: item)
    }

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true

        observeSystemEvents()
        looper = AVPlayerLooper(player: player, templateItem: player.currentItem!)

        createWindows()
        player.play()

        startHeartbeat()
        startStallMonitor()
        startWatchdog()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        playbackObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        playbackObserverTokens.removeAll()

        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stallTimer?.invalidate()
        stallTimer = nil

        player.pause()
        looper = nil
        teardownWindows()
    }

    // MARK: - 系统事件

    private func observeSystemEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self,
                              selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification,
                              object: nil)
        workspace.addObserver(self,
                              selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification,
                              object: nil)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.rebuildWindows()
        }
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.isAsleep = true
            self.player.pause()
        }
    }

    @objc private func screensDidWake(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.isAsleep = false
            self.player.play()
        }
    }

    // MARK: - 播放错误监听

    private func observePlayback(of item: AVPlayerItem) {
        let onFailure = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let detail = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "unknown"
            self?.abort("解码失败: \(detail)")
        }
        playbackObserverTokens.append(onFailure)

        let onStall = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.options.stallLimit > 0 else { return }
            self.abort("播放停滞 (PlaybackStalled)")
        }
        playbackObserverTokens.append(onStall)

        let onEnd = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.resetStallCounter()
        }
        playbackObserverTokens.append(onEnd)
    }

    // MARK: - 窗口管理

    private func createWindows() {
        let screens = options.singleScreen ? [NSScreen.main!] : NSScreen.screens
        for screen in screens {
            windows.append(makeWindow(for: screen))
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let contentView = window.contentView ?? NSView()
        contentView.wantsLayer = true

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = contentView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentView.layer = layer
        window.contentView = contentView

        window.orderFrontRegardless()
        return window
    }

    private func rebuildWindows() {
        teardownWindows()
        createWindows()
    }

    private func teardownWindows() {
        for window in windows {
            window.contentView?.layer = nil
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    // MARK: - 保护机制

    private func startHeartbeat() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.lastHeartbeat = Date()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private var lastProgress = CMTime.zero
    private var frozenSeconds: TimeInterval = 0

    private func startStallMonitor() {
        guard options.stallLimit > 0 else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkStall()
        }
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    private func checkStall() {
        guard isRunning, !isAsleep else { return }
        let now = player.currentTime()
        let delta = CMTimeGetSeconds(CMTimeSubtract(now, lastProgress))
        lastProgress = now

        let isPlaying = player.timeControlStatus == .playing
        if isPlaying, delta < 0.01 {
            frozenSeconds += 1
            if frozenSeconds >= options.stallLimit {
                abort("播放进度停滞超过 \(Int(options.stallLimit)) 秒")
            }
        } else {
            resetStallCounter()
        }
    }

    private func resetStallCounter() {
        frozenSeconds = 0
    }

    private func startWatchdog() {
        guard options.watchdogLimit > 0 else { return }
        let timeout = options.watchdogLimit
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                guard let self = self else { return }
                if Date().timeIntervalSince(self.lastHeartbeat) > timeout {
                    self.abortFromBackground("UI 线程无响应超过 \(Int(timeout)) 秒")
                }
            }
        }
    }

    /// 主线程上的致命错误出口。
    private func abort(_ message: String) {
        stop()
        Console.error(message)
        PIDFile.shared.remove()
        exit(2)
    }

    /// 后台线程上的致命错误出口（UI 线程可能已卡死，直接退出）。
    private func abortFromBackground(_ message: String) {
        Console.error(message)
        PIDFile.shared.remove()
        exit(3)
    }
}
