import SwiftUI

struct HideTabBarModifier: ViewModifier {
    @EnvironmentObject private var uiState: AppUIState
    
    func body(content: Content) -> some View {
        content
            .onAppear { 
                withAnimation(.easeInOut(duration: 0.25)) {
                    uiState.showTabBar = false 
                }
            }
            .onDisappear { 
                withAnimation(.easeInOut(duration: 0.25)) {
                    uiState.showTabBar = true 
                }
            }
    }
}

extension View {
    func hidesTabBar() -> some View {
        modifier(HideTabBarModifier())
    }
}







