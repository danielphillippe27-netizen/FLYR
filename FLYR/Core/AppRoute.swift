import Foundation

/// Backend-driven app root route after auth/gate check.
enum AppRoute: Equatable {
    case login
    case onboarding
    case join(token: String)
    case subscribe(memberInactive: Bool)
    case dashboard
}
