import Foundation

protocol Command {
    var name: String { get }
    var summary: String { get }

    func execute(arguments: [String]) -> Int32
}
