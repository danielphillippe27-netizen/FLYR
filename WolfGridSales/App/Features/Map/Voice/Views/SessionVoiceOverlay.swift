import SwiftUI

struct SessionVoiceOverlay: View {
    @ObservedObject var voiceService: LiveSessionVoiceService
    let campaignId: UUID?
    let sessionId: UUID?

    var body: some View {
        TeamVoiceBar(
            participants: voiceService.participants,
            isVoiceConnected: voiceService.connectionState == .connected
                || voiceService.connectionState == .connecting
                || voiceService.connectionState == .reconnecting,
            onConnectionToggle: {
                if voiceService.connectionState == .connected
                    || voiceService.connectionState == .connecting
                    || voiceService.connectionState == .reconnecting {
                    Task { await voiceService.disconnect() }
                } else if let campaignId, let sessionId {
                    Task { await voiceService.connectIfNeeded(campaignId: campaignId, sessionId: sessionId) }
                }
            },
            onPTTStart: {
                Task { await voiceService.beginPushToTalk(campaignId: campaignId, sessionId: sessionId) }
            },
            onPTTEnd: {
                Task { await voiceService.endPushToTalk() }
            }
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
