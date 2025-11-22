import Foundation

enum AppError: LocalizedError {
    case networkError(String)
    case authenticationError(String)
    case databaseError(String)
    case validationError(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network Error: \(message)"
        case .authenticationError(let message):
            return "Authentication Error: \(message)"
        case .databaseError(let message):
            return "Database Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        case .unknown(let message):
            return "Unknown Error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Please check your internet connection and try again."
        case .authenticationError:
            return "Please sign in again."
        case .databaseError:
            return "Please try again later."
        case .validationError:
            return "Please check your input and try again."
        case .unknown:
            return "Please try again or contact support."
        }
    }
}

// Extension to convert any Error to AppError
extension Error {
    func toAppError() -> AppError {
        if let appError = self as? AppError {
            return appError
        }
        return .unknown(self.localizedDescription)
    }
}


