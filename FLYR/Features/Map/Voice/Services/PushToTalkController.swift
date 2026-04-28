import Foundation
import Combine

@MainActor
final class PushToTalkController: ObservableObject {
    @Published private(set) var isPressed = false

    private let voiceService: LiveSessionVoiceService
    private var currentTask: Task<Void, Never>?

    init(voiceService: LiveSessionVoiceService) {
        self.voiceService = voiceService
    }

    func updatePressState(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            if pressed {
                await voiceService.beginPushToTalk()
            } else {
                await voiceService.endPushToTalk()
            }
        }
    }

    func cancelTransmission() {
        updatePressState(false)
    }
}
