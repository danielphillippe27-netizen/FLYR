import Foundation
import HealthKit

final class HealthKitManager {
    static let shared = HealthKitManager()
    private init() {}

    private let healthStore = HKHealthStore()

    var isHealthAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var stepType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .stepCount)
    }

    /// Request permission to read step count.
    func requestStepReadAuthorization() async throws {
        guard isHealthAvailable else {
            throw NSError(domain: "HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Health data not available on this device."])
        }
        guard let stepType else {
            throw NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Step count type not available."])
        }

        let toRead: Set<HKObjectType> = [stepType]
        let toShare: Set<HKSampleType> = [] // read-only for now

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: toShare, read: toRead) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard success else {
                    continuation.resume(throwing: NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "HealthKit authorization was not granted."]))
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    /// Returns today's steps from startOfDay -> now.
    func fetchTodaySteps() async throws -> Int {
        guard let stepType else {
            throw NSError(domain: "HealthKit", code: 4, userInfo: [NSLocalizedDescriptionKey: "Step count type not available."])
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sum = result?.sumQuantity()
                let steps = sum?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: Int(steps))
            }

            healthStore.execute(query)
        }
    }
}
