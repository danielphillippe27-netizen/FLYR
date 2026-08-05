import Foundation
import UIKit

/// Exports field leads to CSV for share sheet or campaign export.
enum LeadsExportManager {
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
    
    /// CSV header row
    private static let header = "Address,Name,Phone,Status,Notes,QR Code,Campaign ID,Session ID,Created At\n"
    
    /// Escape a field for CSV (wrap in quotes if contains comma or newline).
    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\"") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
    
    /// Generate CSV data for the given leads.
    static func csvData(for leads: [FieldLead]) -> Data {
        var rows = header
        for lead in leads {
            let address = escape(lead.address)
            let name = escape(lead.name ?? "")
            let phone = escape(lead.phone ?? "")
            let status = escape(lead.status.displayName)
            let notes = escape(lead.notes ?? "")
            let qrCode = escape(lead.qrCode ?? "")
            let campaignId = lead.campaignId?.uuidString ?? ""
            let sessionId = lead.sessionId?.uuidString ?? ""
            let createdAt = dateFormatter.string(from: lead.createdAt)
            rows += "\(address),\(name),\(phone),\(status),\(notes),\(qrCode),\(campaignId),\(sessionId),\(createdAt)\n"
        }
        return Data(rows.utf8)
    }
    
    /// Write leads to a temporary CSV file and return its URL for share sheet.
    /// Caller is responsible for cleaning up the temp file after sharing if desired.
    static func exportToTempFile(leads: [FieldLead], filename: String = "field_leads_export.csv") throws -> URL {
        let data = csvData(for: leads)
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
    
    /// Build a plain-text summary of a single lead for Share sheet.
    static func shareableText(for lead: FieldLead) -> String {
        var lines: [String] = [
            "Address: \(lead.address)",
            "Name: \(lead.displayNameOrUnknown)",
            "Status: \(lead.status.displayName)",
            "Created: \(dateFormatter.string(from: lead.createdAt))"
        ]
        if let phone = lead.phone, !phone.isEmpty {
            lines.insert("Phone: \(phone)", at: 2)
        }
        if let notes = lead.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        if let qr = lead.qrCode, !qr.isEmpty {
            lines.append("QR: \(qr)")
        }
        return lines.joined(separator: "\n")
    }
}
