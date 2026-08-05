import SwiftUI

struct LiveSessionParticipantsButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)

                Text("\(count) Live")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Color.black.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) people live")
        .accessibilityHint("Opens the list of people in this session")
    }
}

struct CompactPushToTalkButton: View {
    @ObservedObject var voiceService: LiveSessionVoiceService
    let campaignId: UUID
    let sessionId: UUID

    @State private var isPressing = false

    private var isAvailable: Bool {
        voiceService.connectionState == .connected
    }

    var body: some View {
        let holdGesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressing else { return }
                isPressing = true
                HapticManager.medium()
                Task {
                    await voiceService.beginPushToTalk(campaignId: campaignId, sessionId: sessionId)
                }
            }
            .onEnded { _ in
                guard isPressing else { return }
                isPressing = false
                Task { await voiceService.endPushToTalk() }
            }

        Image(systemName: "walkie.talkie.fill")
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 23, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 54, height: 54)
            .background((isPressing || voiceService.isTransmitting) ? Color.green : Color.black.opacity(0.94))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(isAvailable ? Color.green : Color.gray.opacity(0.72), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.34), radius: 8, x: 0, y: 3)
            .scaleEffect(isPressing ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressing)
            .contentShape(Circle())
            .gesture(holdGesture)
            .accessibilityLabel("Walkie-talkie")
            .accessibilityValue(isPressing || voiceService.isTransmitting ? "Talking" : (isAvailable ? "Available" : "Inactive"))
            .accessibilityHint("Press and hold to talk")
    }
}

struct LiveSessionParticipantsSheet: View {
    let teammates: [SharedCanvassingTeammate]
    let includesCurrentUser: Bool

    var body: some View {
        NavigationStack {
            List {
                if includesCurrentUser {
                    participantRow(name: "You", isAvailable: true)
                }

                ForEach(teammates) { teammate in
                    participantRow(
                        name: teammate.displayName,
                        isAvailable: !teammate.isStale && teammate.presenceStatus == .active
                    )
                }
            }
            .navigationTitle("Live Session")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func participantRow(name: String, isAvailable: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isAvailable ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.system(size: 16, weight: .medium))

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isAvailable ? "active" : "inactive")")
    }
}
