import Cocoa
import AVFoundation

/// 视频壁纸核心：在桌面层窗口循环播放视频，并内置保护。
final class Wallpaper: NSObject {
    private let player: AVQueuePlayer
    private let options: RunOptions

    private var looper: AVPlayerLooper?
    private var windows: [NSWindow] = []
    private var itemObserverTokens: [NSObjectProtocol] = []
    private var currentItemObservation: NSKeyValueObservation?

    private var heartbeatTimer: Timer?
    private var stallTimer: Timer?

    private var isRunning = false
    private var isAsleep = false

    /// 主线程心跳时间戳，供 watchdog 后台轮询判断 UI 是否卡死。
    private(set) var lastHeartbeat = Date()

    init(videoURL: URL, options: RunOptions) {
        self.options = options
        player = AVQueuePlayer(items: [AVPlayerItem(url: videoURL)])
        player.isMuted = true
        player.defaultRate = options.rate
        super.init()
        observeCurrentItem()
    }

    deinit {
        if isRunning { stop() }
    }

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeSystemEvents()
        if let item = player.currentItem {
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
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
        NotificationCenter.default.removeObserver(self)
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        itemObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemObserverTokens.removeAll()
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
            self, selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(screensDidSleep),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidWake),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func screenParametersDidChange(_ note: Notification) {
        guard isRunning else { return }
        rebuildWindows()
    }

    @objc private func screensDidSleep(_ note: Notification) {
        guard isRunning else { return }
        isAsleep = true
        player.pause()
    }

    @objc private func screensDidWake(_ note: Notification) {
        guard isRunning else { return }
        isAsleep = false
        player.play()
    }

    // MARK: - 播放监控

    /// AVPlayerLooper 每次循环都会换入新 item，只观察初始 item 会在首轮后失效，
    /// 因此对 currentItem 做 KVO，item 变化时重新挂载通知。
    private func observeCurrentItem() {
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) {
            [weak self] _, _ in
            self?.attachItemObservers()
        }
    }

    private func attachItemObservers() {
        itemObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemObserverTokens.removeAll()
        guard let item = player.currentItem else { return }

        let failure = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let detail = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "unknown"
            self?.exitWithError("解码失败: \(detail)")
        }
        itemObserverTokens.append(failure)

        let stalled = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.options.stallLimit > 0 else { return }
            self.exitWithError("播放停滞 (PlaybackStalled)")
        }
        itemObserverTokens.append(stalled)

        let didEnd = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.frozenSeconds = 0
        }
        itemObserverTokens.append(didEnd)
    }

    // MARK: - 窗口管理

    private func createWindows() {
        if options.singleScreen {
            if let main = NSScreen.main {
                windows.append(makeWindow(for: main))
            }
        } else {
            windows = NSScreen.screens.map(makeWindow(for:))
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
        windows.forEach { $0.contentView?.layer = nil }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    // MARK: - 保护机制

    private func startHeartbeat() {
        heartbeatTimer = repeatingTimer(interval: 0.5) { [weak self] in
            self?.lastHeartbeat = Date()
        }
    }

    private var lastProgress = CMTime.zero
    private var frozenSeconds: TimeInterval = 0

    private func startStallMonitor() {
        guard options.stallLimit > 0 else { return }
        stallTimer = repeatingTimer(interval: 1.0) { [weak self] in
            self?.checkStall()
        }
    }

    private func checkStall() {
        guard isRunning, !isAsleep else { return }
        let now = player.currentTime()
        let delta = CMTimeGetSeconds(CMTimeSubtract(now, lastProgress))
        lastProgress = now

        let playing = player.timeControlStatus == .playing
        if playing, delta < 0.01 {
            frozenSeconds += 1
            if frozenSeconds >= options.stallLimit {
                exitWithError("播放进度停滞超过 \(Int(options.stallLimit)) 秒")
            }
        } else {
            frozenSeconds = 0
        }
    }

    private func startWatchdog() {
        guard options.watchdogLimit > 0 else { return }
        let limit = options.watchdogLimit
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self = self {
                Thread.sleep(forTimeInterval: 0.5)
                if Date().timeIntervalSince(self.lastHeartbeat) > limit {
                    self.exitFromBackground("UI 线程无响应超过 \(Int(limit)) 秒")
                }
            }
        }
    }

    private func repeatingTimer(interval: TimeInterval, handler: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in handler() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// 主线程致命错误：清理后退出。
    private func exitWithError(_ message: String) {
        stop()
        PIDFile.shared.remove()
        Console.error(message)
        exit(2)
    }

    /// 后台线程致命错误：UI 可能已卡死，直接退出。
    private func exitFromBackground(_ message: String) {
        PIDFile.shared.remove()
        Console.error(message)
        exit(3)
    }
}
