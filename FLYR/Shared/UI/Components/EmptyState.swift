import SwiftUI

// MARK: - Empty State Component

struct EmptyState: View {
    let illustration: String
    let title: String
    let message: String?
    let buttonTitle: String?
    let buttonAction: (() -> Void)?
    
    init(
        illustration: String,
        title: String,
        message: String? = nil,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) {
        self.illustration = illustration
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Illustration
            Image(systemName: illustration)
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.muted)
                .opacity(0.6)
            
            // Content
            VStack(spacing: 12) {
                // Title
                Text(title)
                    .font(.subheading)
                    .foregroundColor(.text)
                    .multilineTextAlignment(.center)
                
                // Message (optional)
                if let message = message {
                    Text(message)
                        .font(.body)
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            
            // Button (optional)
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                Button(action: buttonAction) {
                    Text(buttonTitle)
                }
                .primaryButton()
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Convenience Initializers

extension EmptyState {
    /// Simple empty state with just illustration and title
    static func simple(
        illustration: String,
        title: String
    ) -> EmptyState {
        EmptyState(
            illustration: illustration,
            title: title
        )
    }
    
    /// Empty state with action button
    static func withAction(
        illustration: String,
        title: String,
        message: String? = nil,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> EmptyState {
        EmptyState(
            illustration: illustration,
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            buttonAction: action
        )
    }
}

// MARK: - Common Empty States

extension EmptyState {
    /// No campaigns empty state
    static let noCampaigns = EmptyState.withAction(
        illustration: "doc.text.magnifyingglass",
        title: "No Campaigns Yet",
        message: "Create your first campaign to start distributing flyers",
        buttonTitle: "Create Campaign"
    ) {
        // Action would be provided by parent view
    }
    
    /// No results empty state
    static let noResults = EmptyState.simple(
        illustration: "magnifyingglass",
        title: "No Results Found"
    )
    
    /// Network error empty state
    static let networkError = EmptyState.withAction(
        illustration: "wifi.slash",
        title: "Connection Error",
        message: "Check your internet connection and try again",
        buttonTitle: "Retry"
    ) {
        // Action would be provided by parent view
    }
    
    /// Loading empty state
    static let loading = EmptyState.simple(
        illustration: "arrow.clockwise",
        title: "Loading..."
    )
}

// MARK: - View Extension

extension View {
    /// Show empty state when condition is true
    @ViewBuilder
    func emptyState(
        when condition: Bool,
        illustration: String,
        title: String,
        message: String? = nil,
        buttonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        if condition {
            EmptyState(
                illustration: illustration,
                title: title,
                message: message,
                buttonTitle: buttonTitle,
                buttonAction: action
            )
        } else {
            self
        }
    }
    
    /// Show common empty states
    @ViewBuilder
    func emptyState(
        when condition: Bool,
        type: EmptyStateType,
        action: (() -> Void)? = nil
    ) -> some View {
        if condition {
            switch type {
            case .noCampaigns:
                EmptyState.noCampaigns
            case .noResults:
                EmptyState.noResults
            case .networkError:
                EmptyState.networkError
            case .loading:
                EmptyState.loading
            }
        } else {
            self
        }
    }
}

// MARK: - Empty State Type

enum EmptyStateType {
    case noCampaigns
    case noResults
    case networkError
    case loading
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Simple empty state
        EmptyState.simple(
            illustration: "doc.text.magnifyingglass",
            title: "No Campaigns Yet"
        )
        .frame(height: 200)
        .background(Color.bgSecondary)
        .cornerRadius(12)
        
        // Empty state with action
        EmptyState.withAction(
            illustration: "wifi.slash",
            title: "Connection Error",
            message: "Check your internet connection and try again",
            buttonTitle: "Retry"
        ) {
            print("Retry tapped")
        }
        .frame(height: 300)
        .background(Color.bgSecondary)
        .cornerRadius(12)
        
        // Common empty states
        EmptyState.noCampaigns
            .frame(height: 250)
            .background(Color.bgSecondary)
            .cornerRadius(12)
    }
    .padding()
    .background(Color.bg)
}
