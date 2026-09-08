import Foundation

/// 显示帮助：`help` / `-h`。
struct HelpCommand: Command {
    let name = "help"
    let summary = "显示帮助"

    func execute(arguments: [String]) -> Int32 {
        Console.info(usage())
        return 0
    }

    /// 汇总生成完整帮助文本。
    private func usage() -> String {
        var lines = [
            Version.full,
            "",
            "用法:",
            "  \(Version.name) <命令> [参数]",
            "",
            "命令:",
        ]
        for command in CLI.commands {
            let padded = command.name.padding(toLength: 10, withPad: " ", startingAt: 0)
            lines.append("  \(Version.name) \(padded) \(command.summary)")
        }
        lines.append("")
        if let run = CLI.commands.first(where: { $0.name == "run" }) as? RunCommand {
            lines.append(run.optionsHelp)
        }
        lines.append("")
        lines.append("示例:")
        lines.append("  \(Version.name) run ~/Videos/wallpaper.mov")
        lines.append("  \(Version.name) run video.mov --single --rate 0.5")
        return lines.joined(separator: "\n")
    }
}
