import Foundation

/// Ensures `LeadModel` payloads meet each secure CRM route’s minimum requirements
/// (HubSpot: email or name; BoldTrail/FUB: email or phone) without losing captured data.
enum CRMLeadEnrichment {
    private static let captureEmailDomain = "capture.flyrpro.app"

    /// Synthetic but deliverable-shaped email so kvCORE/HubSpot accept address-only field leads.
    static func placeholderCaptureEmail(leadId: UUID) -> String {
        let hex = leadId.uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        return "field+\(hex)@\(captureEmailDomain)"
    }

    /// Short display name derived from the first line of the address (HubSpot when no name/email yet).
    static func displayNameFromAddress(_ address: String?) -> String? {
        guard let raw = address?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let firstLine = raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let line = firstLine else { return nil }
        let s = String(line)
        let clipped = s.count > 80 ? String(s.prefix(80)) + "…" : s
        return "Property: \(clipped)"
    }

    /// Returns a copy of `lead` with only synthetic fields filled when required for secure pushes.
    static func enrichedForSecureProviders(_ lead: LeadModel) -> LeadModel {
        let email = trim(lead.email)
        let phone = trim(lead.phone)
        let name = trim(lead.name)

        let hasEmail = email != nil
        let hasPhone = phone != nil
        let hasName = name != nil

        var outEmail = email
        var outPhone = phone
        var outName = name

        // BoldTrail + FUB: at least one of email or phone.
        if !hasEmail && !hasPhone {
            outEmail = placeholderCaptureEmail(leadId: lead.id)
        }

        // HubSpot: at least one of email or name (phone/address alone are not enough).
        let hubSpotHasIdentity = (outEmail?.isEmpty == false) || (outName?.isEmpty == false)
        if !hubSpotHasIdentity {
            outName = displayNameFromAddress(lead.address) ?? "FLYR field lead"
        } else if outName == nil || outName?.isEmpty == true,
                  let label = displayNameFromAddress(lead.address) {
            // Synthetic email alone is valid; still prefer a readable contact label from the address.
            outName = label
        }

        return LeadModel(
            id: lead.id,
            name: outName,
            phone: outPhone,
            email: outEmail,
            address: lead.address,
            source: lead.source,
            campaignId: lead.campaignId,
            notes: lead.notes,
            createdAt: lead.createdAt
        )
    }

    private static func trim(_ value: String?) -> String? {
        let t = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
}
