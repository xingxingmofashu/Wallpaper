import Foundation

/// 安装并持有信号处理的 DispatchSource，避免被 ARC 提前释放。
final class SignalHandler {
    private var sources: [DispatchSourceSignal] = []

    /// 注册多个信号，统一回调 `onSignal`。
    /// 注意：DispatchSource 必须被强引用，否则 handler 失效且默认行为被 SIG_IGN 吞掉。
    init(signals: [Int32], onSignal: @escaping () -> Void) {
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                onSignal()
            }
            source.resume()
            sources.append(source)
        }
    }
}
