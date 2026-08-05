import SwiftUI

// MARK: - Toast Component

struct Toast: View {
    let message: String
    let type: ToastType
    let duration: Double
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var offset: CGFloat = 100
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    init(
        message: String,
        type: ToastType = .info,
        duration: Double = 3.0,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.message = message
        self.type = type
        self.duration = duration
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: type.iconName)
                .font(.flyrTitle3)
                .foregroundColor(type.iconColor)
            
            // Message
            Text(message)
                .font(.body)
                .foregroundColor(.text)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            // Dismiss button
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.flyrCaption)
                    .foregroundColor(.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(type.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .offset(y: offset)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            show()
        }
    }
    
    private func show() {
        HapticManager.lightImpact()
        
        withAnimation(reduceMotion ? .reducedMotion : .flyrSpring) {
            isVisible = true
            offset = 0
        }
        
        // Auto-dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            dismiss()
        }
    }
    
    private func dismiss() {
        withAnimation(reduceMotion ? .reducedMotion : .flyrSpring) {
            isVisible = false
            offset = 100
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Toast Type

enum ToastType {
    case success
    case error
    case warning
    case info
    
    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .success:
            return .success
        case .error:
            return .error
        case .warning:
            return .warning
        case .info:
            return .info
        }
    }
    
    var borderColor: Color {
        switch self {
        case .success:
            return .success.opacity(0.3)
        case .error:
            return .error.opacity(0.3)
        case .warning:
            return .warning.opacity(0.3)
        case .info:
            return .info.opacity(0.3)
        }
    }
}

// MARK: - Toast Manager

@Observable
class ToastManager {
    var toasts: [ToastItem] = []
    
    func show(
        message: String,
        type: ToastType = .info,
        duration: Double = 3.0
    ) {
        let toast = ToastItem(
            id: UUID(),
            message: message,
            type: type,
            duration: duration
        )
        
        toasts.append(toast)
    }
    
    func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

struct ToastItem: Identifiable {
    let id: UUID
    let message: String
    let type: ToastType
    let duration: Double
}

// MARK: - Toast Container

struct ToastContainer: View {
    @State private var toastManager = ToastManager()
    
    var body: some View {
        VStack {
            Spacer()
            
            ForEach(toastManager.toasts) { toast in
                Toast(
                    message: toast.message,
                    type: toast.type,
                    duration: toast.duration
                ) {
                    toastManager.dismiss(toast.id)
                }
                .padding(.horizontal, 20)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .environment(toastManager)
    }
}

// MARK: - Environment Key

private struct ToastManagerKey: EnvironmentKey {
    static let defaultValue = ToastManager()
}

extension EnvironmentValues {
    var toastManager: ToastManager {
        get { self[ToastManagerKey.self] }
        set { self[ToastManagerKey.self] = newValue }
    }
}

// MARK: - View Extensions

extension View {
    /// Show a toast message
    func showToast(
        message: String,
        type: ToastType = .info,
        duration: Double = 3.0
    ) {
        // This would be implemented with the toast manager
        // For now, this is a placeholder for the API
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        Button("Show Success Toast") {
            // Toast would be shown here
        }
        .primaryButton()
        
        Button("Show Error Toast") {
            // Toast would be shown here
        }
        .secondaryButton()
        
        Button("Show Warning Toast") {
            // Toast would be shown here
        }
        .ghostButton()
        
        Button("Show Info Toast") {
            // Toast would be shown here
        }
        .destructiveButton()
    }
    .padding()
    .background(Color.bgSecondary)
}

