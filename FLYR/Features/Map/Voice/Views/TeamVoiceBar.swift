import SwiftUI

struct TeamVoiceBar: View {
    let participants: [VoiceParticipant]
    let isVoiceConnected: Bool
    let onConnectionToggle: () -> Void
    let onPTTStart: () -> Void
    let onPTTEnd: () -> Void

    @State private var isPressing = false
    @State private var isPulseAnimating = false

    private let connectedGreen = Color(hex: "3B6D11")
    private let barBackground = Color(hex: "111111")
    private let buttonBackground = Color(hex: "1C1C1E")
    private let talkingBackground = Color(hex: "163A12")
    private let disconnectedBackground = Color(hex: "202224")
    private let disconnectedRed = Color(hex: "B3261E")

    private var liveCount: Int {
        participants.count
    }

    private var displayedParticipants: [VoiceParticipant] {
        Array(participants.prefix(4))
    }

    private var overflowCount: Int {
        max(0, participants.count - 4)
    }

    private var localParticipant: VoiceParticipant? {
        participants.first(where: \.isLocalUser)
    }

    private var connectionIndicatorColor: Color {
        (localParticipant?.isVoiceEnabled ?? isVoiceConnected) ? connectedGreen : disconnectedRed
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(connectionIndicatorColor)
                .frame(width: 8, height: 8)

            avatarStack

            VStack(alignment: .leading, spacing: 0) {
                Text("\(liveCount)live")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            holdToTalkButton

            Button(action: onConnectionToggle) {
                Text(isVoiceConnected ? "On" : "Off")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 54)
                    .frame(height: 36)
                    .background(isVoiceConnected ? connectedGreen : disconnectedRed)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVoiceConnected ? "Voice on" : "Voice off")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(barBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            isPulseAnimating = true
        }
    }

    private var avatarStack: some View {
        HStack(spacing: 0) {
            ForEach(Array(displayedParticipants.enumerated()), id: \.element.id) { index, participant in
                avatarView(for: participant)
                    .padding(.leading, index == 0 ? 0 : -6)
            }

            if overflowCount > 0 {
                overflowAvatar(count: overflowCount)
                    .padding(.leading, displayedParticipants.isEmpty ? 0 : -6)
            }
        }
    }

    private func avatarView(for participant: VoiceParticipant) -> some View {
        let ringColor = participant.isVoiceEnabled ? connectedGreen : disconnectedRed.opacity(participant.isLocalUser ? 1 : 0.7)
        let fillColor = participant.isVoiceEnabled ? connectedGreen.opacity(0.28) : disconnectedRed.opacity(participant.isLocalUser ? 0.24 : 0.14)
        let textColor = participant.isVoiceEnabled ? Color(hex: "9AD55E") : Color.white.opacity(participant.isLocalUser ? 0.92 : 0.74)

        return ZStack {
            if participant.isSpeaking {
                Circle()
                    .stroke(connectedGreen.opacity(0.7), lineWidth: 2)
                    .scaleEffect(isPulseAnimating ? 1.28 : 1.02)
                    .opacity(isPulseAnimating ? 0 : 0.85)
                    .frame(width: 34, height: 34)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: isPulseAnimating)
            }

            Circle()
                .fill(fillColor)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(ringColor, lineWidth: 1.5)
                )

            Text(participant.initials)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(textColor)
        }
    }

    private func overflowAvatar(count: Int) -> some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.55), lineWidth: 1.5)
                )

            Text("+\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
        }
    }

    private var holdToTalkButton: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressing else { return }
                isPressing = true
                onPTTStart()
            }
            .onEnded { _ in
                guard isPressing else { return }
                isPressing = false
                onPTTEnd()
            }

        return Text(isPressing ? "Talking..." : "Hold to talk")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isPressing ? connectedGreen : .white.opacity(0.92))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minWidth: 118)
            .frame(height: 36)
            .background(isPressing ? talkingBackground : buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .gesture(gesture)
    }
}
