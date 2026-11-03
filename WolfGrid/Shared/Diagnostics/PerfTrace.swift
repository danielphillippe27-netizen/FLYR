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
    private static let timingLogQueue = DispatchQueue(label: "wolfgrid.field-timings")
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
        if ["farm_live", "farm_list", "address_picker", "home_tap_card"].contains(flow) {
            // Persist timings, never addresses, provider payloads, coordinates or credentials.
            let diagnosticKeys: Set<String> = ["count", "targets", "accepted", "pending", "shortlist", "visible", "matches", "zoom", "identityGroups", "ambiguousTargets", "ambiguousAddresses", "postalRejected", "geometryRejected", "max_ms"]
            let diagnostics = fields.keys.sorted().compactMap { key -> String? in
                guard flow == "farm_live", diagnosticKeys.contains(key), let number = fields[key] as? NSNumber else { return nil }
                return "\(key)=\(number)"
            }.joined(separator: " ")
            let line = "\(Date().timeIntervalSince1970) flow=\(sanitize(flow)) phase=\(sanitize(phase)) status=\(sanitize(status)) durationMs=\(durationMs ?? -1) \(diagnostics)\n"
            timingLogQueue.async {
                guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
                let url = directory.appendingPathComponent("wolfgrid-field-timings.log")
                if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
                   size.intValue > 1_000_000 { try? FileManager.default.removeItem(at: url) }
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: " ", with: "_")
    }
    #endif
}

/// Measures the user-facing interval from opening a map through its first
/// usable frame, independent of the cache and backend phase timings.
@MainActor
enum MapOpenTrace {
    private static var start: (campaign: String, time: Date)?
    static func begin(campaign: String) {
        start = (campaign.lowercased(), Date())
        PerfTrace.event("map_open_user", "tap", fields: ["campaign": campaign])
    }
    static func event(_ phase: String, campaign: String, fields: [String: Any] = [:]) {
        guard let start, start.campaign == campaign.lowercased() else { return }
        var values = fields
        values["campaign"] = campaign
        values["elapsedMs"] = Int(Date().timeIntervalSince(start.time) * 1000)
        PerfTrace.event("map_open_user", phase, fields: values)
    }
}
