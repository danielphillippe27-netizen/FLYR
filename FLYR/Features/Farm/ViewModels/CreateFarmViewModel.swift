import SwiftUI
import Combine
import CoreLocation

@MainActor
final class CreateFarmViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var timeframe: Timeframe = .sixMonths
    @Published var frequency: Int = 2 // touches per month
    @Published var polygon: [CLLocationCoordinate2D]? = nil
    @Published var areaLabel: String = ""
    
    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()
    
    @Published var isSaving = false
    @Published var errorMessage: String?
    
    private let farmService = FarmService.shared
    
    enum Timeframe: Int, CaseIterable, Identifiable {
        case threeMonths = 3
        case sixMonths = 6
        case nineMonths = 9
        case oneYear = 12
        
        var id: Int { rawValue }
        
        var displayName: String {
            switch self {
            case .threeMonths: return "3 Months"
            case .sixMonths: return "6 Months"
            case .nineMonths: return "9 Months"
            case .oneYear: return "1 Year"
            }
        }
        
        var months: Int { rawValue }
    }
    
    init() {
        calculateDates()
    }
    
    // MARK: - Calculate Dates
    
    func calculateDates() {
        let calendar = Calendar.current
        startDate = Date()
        
        if let end = calendar.date(byAdding: .month, value: timeframe.months, to: startDate) {
            endDate = end
        }
    }
    
    // MARK: - Generate Touch Schedule
    
    /// Generate a draft touch schedule based on frequency and timeframe
    func generateTouchSchedule() -> [FarmTouch] {
        let farmId = UUID() // Temporary ID, will be replaced
        
        var touches: [FarmTouch] = []
        let calendar = Calendar.current
        var currentDate = startDate
        var touchIndex = 0
        
        // Calculate touches per month based on frequency
        let touchesPerMonth = frequency
        let daysBetweenTouches = 30 / touchesPerMonth
        
        while currentDate <= endDate {
            // Add touches for this month
            for i in 0..<touchesPerMonth {
                let touchDate = calendar.date(byAdding: .day, value: i * daysBetweenTouches, to: currentDate) ?? currentDate
                
                // Determine touch type based on position in schedule
                let touchType: FarmTouchType = {
                    let monthIndex = touchIndex / touchesPerMonth
                    if monthIndex < 2 {
                        return .flyer // Awareness phase
                    } else if monthIndex < 4 {
                        return .doorKnock // Relationship building
                    } else {
                        return .event // Lead harvesting/conversion
                    }
                }()
                
                let touch = FarmTouch(
                    farmId: farmId,
                    date: touchDate,
                    type: touchType,
                    title: "\(touchType.displayName) - \(formatDate(touchDate))",
                    orderIndex: touchIndex
                )
                
                touches.append(touch)
                touchIndex += 1
            }
            
            // Move to next month
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                currentDate = nextMonth
            } else {
                break
            }
        }
        
        return touches
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // MARK: - Save Farm
    
    func saveFarm(userId: UUID) async throws -> Farm {
        guard !name.isEmpty else {
            throw NSError(domain: "CreateFarmViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Farm name is required"])
        }
        
        guard let polygon = polygon, !polygon.isEmpty else {
            throw NSError(domain: "CreateFarmViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Farm polygon is required"])
        }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            let farm = try await farmService.createFarm(
                name: name,
                userId: userId,
                startDate: startDate,
                endDate: endDate,
                frequency: frequency,
                polygon: polygon,
                areaLabel: areaLabel.isEmpty ? nil : areaLabel
            )
            
            return farm
        } catch {
            errorMessage = "Failed to create farm: \(error.localizedDescription)"
            print("❌ [CreateFarmViewModel] Error creating farm: \(error)")
            throw error
        }
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        !name.isEmpty && polygon != nil && !polygon!.isEmpty
    }
}

