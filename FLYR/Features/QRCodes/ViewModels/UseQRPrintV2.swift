import Foundation
import Combine

/// ViewModel for QR Print View V2
@MainActor
final class UseQRPrintV2: ObservableObject {
    @Published var qrSets: [QRSet] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let api = QRCodeAPI.shared
    
    /// Load all QR sets for the current user
    func loadQRSets() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            qrSets = try await api.fetchQRSets()
        } catch {
            errorMessage = "Failed to load QR sets: \(error.localizedDescription)"
            print("❌ [QR Print V2] Error loading QR sets: \(error)")
        }
    }
    
    /// Load QR codes for a specific set
    /// - Parameter setId: The ID of the QR set
    /// - Returns: Array of QR codes in the set
    func loadQRCodesForSet(setId: UUID) async -> [QRCode] {
        do {
            return try await api.fetchQRCodesForSet(setId: setId)
        } catch {
            errorMessage = "Failed to load QR codes: \(error.localizedDescription)"
            print("❌ [QR Print V2] Error loading QR codes for set \(setId): \(error)")
            return []
        }
    }
}

