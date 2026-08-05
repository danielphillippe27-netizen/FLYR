import Foundation

enum PerfTrace {
    struct Span: @unchecked Sendable {
        private let flow: String
        private let phase: String
        private let startedAt: Date
        private let fields: [String: Any]

        fileprivate init(flow: String, phase: String, fields: [String: Any]) {
            self.flow = flow
            self.phase = phase
            self.startedAt = Date()
            self.fields = fields
        }

        func end(status: String = "ok", fields endFields: [String: Any] = [:]) {
            #if DEBUG
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            var mergedFields = fields
            for (key, value) in endFields {
                mergedFields[key] = value
            }
            PerfTrace.log(flow: flow, phase: phase, durationMs: durationMs, status: status, fields: mergedFields)
            #endif
        }
    }

    static func begin(_ flow: String, _ phase: String, fields: [String: Any] = [:]) -> Span {
        #if DEBUG
        log(flow: flow, phase: "\(phase).begin", durationMs: nil, status: "begin", fields: fields)
        #endif
        return Span(flow: flow, phase: phase, fields: fields)
    }

    static func event(_ flow: String, _ phase: String, fields: [String: Any] = [:]) {
        #if DEBUG
        log(flow: flow, phase: phase, durationMs: nil, status: "event", fields: fields)
        #endif
    }

    #if DEBUG
    private static func log(
        flow: String,
        phase: String,
        durationMs: Int?,
        status: String,
        fields: [String: Any]
    ) {
        var parts = [
            "flow=\(sanitize(flow))",
            "phase=\(sanitize(phase))",
            "status=\(sanitize(status))"
        ]
        if let durationMs {
            parts.append("durationMs=\(durationMs)")
        }
        parts.append(contentsOf: fields
            .sorted { $0.key < $1.key }
            .map { "\(sanitize($0.key))=\(sanitize(String(describing: $0.value)))" })
        print("⏱️ [PERF] \(parts.joined(separator: " "))")
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: " ", with: "_")
    }
    #endif
}
