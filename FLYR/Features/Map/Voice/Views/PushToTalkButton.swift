import SwiftUI

struct PushToTalkButton: View {
    @ObservedObject var voiceService: LiveSessionVoiceService
    @ObservedObject var controller: PushToTalkController
    let campaignId: UUID?
    let sessionId: UUID?

    var body: some View {
        let dragGesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                controller.updatePressState(true)
            }
            .onEnded { _ in
                controller.updatePressState(false)
            }

        VStack(spacing: 4) {
            Text(primaryLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(secondaryLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
        }
        .frame(width: 124, height: 124)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 6)
        .scaleEffect(controller.isPressed ? 0.96 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: controller.isPressed)
        .gesture(dragGesture)
        .simultaneousGesture(TapGesture().onEnded {
            guard let campaignId, let sessionId else { return }
            if voiceService.connectionState == .idle || voiceService.connectionState == .failed {
                Task { await voiceService.connectIfNeeded(campaignId: campaignId, sessionId: sessionId) }
            }
        })
    }

    private var backgroundColor: Color {
        if controller.isPressed || voiceService.isTransmitting {
            return .green
        }

        switch voiceService.connectionState {
        case .connected:
            return Color.black.opacity(0.88)
        case .connecting, .reconnecting:
            return Color.orange.opacity(0.92)
        case .failed:
            return Color.red.opacity(0.92)
        case .idle:
            return Color.black.opacity(0.82)
        }
    }

    private var primaryLabel: String {
        if voiceService.isTransmitting || controller.isPressed {
            return "Talking"
        }
        switch voiceService.connectionState {
        case .connected:
            return "Hold to Talk"
        case .connecting:
            return "Joining"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Retry Voice"
        case .idle:
            return "Join Voice"
        }
    }

    private var secondaryLabel: String {
        if voiceService.microphonePermission == .denied {
            return "Mic access needed"
        }
        switch voiceService.connectionState {
        case .connected:
            return "Session channel"
        case .connecting, .reconnecting:
            return "Stand by"
        case .failed:
            return "Map stays live"
        case .idle:
            return "Session channel"
        }
    }
}
