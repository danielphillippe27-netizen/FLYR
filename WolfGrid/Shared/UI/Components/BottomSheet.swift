import SwiftUI

// MARK: - Bottom Sheet Component

struct BottomSheet<Content: View>: View {
    let content: Content
    let height: BottomSheetHeight
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    init(
        height: BottomSheetHeight = .medium,
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.height = height
        self.isPresented = isPresented
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        if isPresented.wrappedValue {
            ZStack {
                // Backdrop
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }
                
                // Sheet
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        // Handle
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.muted.opacity(0.6))
                            .frame(width: 36, height: 4)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        
                        // Content
                        content
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }
                    .frame(maxHeight: height.value)
                    .background(
                        Color.bg
                            .clipShape(
                                RoundedRectangle(cornerRadius: 16)
                            )
                    )
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                }
                                
                                // Only allow downward drag
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                isDragging = false
                                
                                // Dismiss if dragged down significantly
                                if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                                    dismiss()
                                } else {
                                    // Snap back
                                    withAnimation(reduceMotion ? .reducedMotion : .flyrSpring) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
            .animation(reduceMotion ? .reducedMotion : .flyrSpring, value: isPresented.wrappedValue)
        }
    }
    
    private func dismiss() {
        withAnimation(reduceMotion ? .reducedMotion : .flyrSpring) {
            isPresented.wrappedValue = false
        }
        onDismiss?()
    }
}

// MARK: - Bottom Sheet Height

enum BottomSheetHeight {
    case small
    case medium
    case large
    case custom(CGFloat)
    
    var value: CGFloat {
        switch self {
        case .small:
            return UIScreen.main.bounds.height * 0.45 // 45%
        case .medium:
            return UIScreen.main.bounds.height * 0.65 // 65%
        case .large:
            return UIScreen.main.bounds.height * 0.90 // 90%
        case .custom(let height):
            return height
        }
    }
}

// MARK: - View Extension

extension View {
    /// Present a bottom sheet
    func bottomSheet<Content: View>(
        isPresented: Binding<Bool>,
        height: BottomSheetHeight = .medium,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        self.overlay(
            BottomSheet(
                height: height,
                isPresented: isPresented,
                onDismiss: onDismiss,
                content: content
            )
        )
    }
}

// MARK: - Bottom Sheet Manager

@Observable
class BottomSheetManager {
    var isPresented = false
    var content: AnyView?
    var height: BottomSheetHeight = .medium
    var onDismiss: (() -> Void)?
    
    func present<Content: View>(
        height: BottomSheetHeight = .medium,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = AnyView(content())
        self.height = height
        self.onDismiss = onDismiss
        self.isPresented = true
    }
    
    func dismiss() {
        isPresented = false
        onDismiss?()
    }
}

// MARK: - Environment Key

private struct BottomSheetManagerKey: EnvironmentKey {
    static let defaultValue = BottomSheetManager()
}

extension EnvironmentValues {
    var bottomSheetManager: BottomSheetManager {
        get { self[BottomSheetManagerKey.self] }
        set { self[BottomSheetManagerKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview {
    BottomSheetPreview()
}

struct BottomSheetPreview: View {
    @State private var showSheet = false
    
    var body: some View {
        VStack(spacing: 20) {
            Button("Show Small Sheet") {
                showSheet = true
            }
            .primaryButton()
            
            Button("Show Medium Sheet") {
                showSheet = true
            }
            .secondaryButton()
            
            Button("Show Large Sheet") {
                showSheet = true
            }
            .ghostButton()
        }
        .padding()
        .bottomSheet(isPresented: $showSheet, height: .medium) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bottom Sheet")
                    .heading()
                    .foregroundColor(.text)
                
                Text("This is a bottom sheet with draggable behavior. You can drag it down to dismiss or tap the backdrop.")
                    .bodyText()
                    .foregroundColor(.muted)
                
                HStack(spacing: 12) {
                    Button("Action 1") {
                        showSheet = false
                    }
                    .primaryButton()
                    
                    Button("Action 2") {
                        showSheet = false
                    }
                    .secondaryButton()
                }
                
                Spacer()
            }
        }
        .background(Color.bgSecondary)
    }
}
