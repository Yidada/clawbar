import Darwin
import Foundation

enum ClawbarEventLogger {
    static func emit(_ name: String, fields: [String: String] = [:]) {
        let payload = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(render(value))"
            }
            .joined(separator: " ")
        let line = payload.isEmpty ? "CLAWBAR_EVENT \(name)\n" : "CLAWBAR_EVENT \(name) \(payload)\n"
        fputs(line, stderr)
        fflush(stderr)
    }

    private static func render(_ value: String) -> String {
        if value.contains(where: \.isWhitespace) || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
