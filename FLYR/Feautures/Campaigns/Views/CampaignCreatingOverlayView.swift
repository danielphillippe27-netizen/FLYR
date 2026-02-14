import SwiftUI
import AVKit

/// Full-screen blocking overlay shown while a campaign is being created.
/// Plays Black.mp4 in dark mode, White.mp4 in light mode; shows "Creating campaign" and "This can take up to 5 minutes".
/// User cannot dismiss or interact with anything else.
struct CampaignCreatingOverlayView: View {
    var useDarkStyle: Bool

    var body: some View {
        ZStack {
            Color(useDarkStyle ? .black : .white)
                .ignoresSafeArea()

            LoopingVideoView(filename: useDarkStyle ? "Black" : "White", extension: "mp4")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Creating campaign")
                    .font(.flyrTitle2)
                    .fontWeight(.semibold)
                    .foregroundColor(useDarkStyle ? .white : .primary)
                Text("This can take up to 5 minutes")
                    .font(.flyrSubheadline)
                    .foregroundColor(useDarkStyle ? .white.opacity(0.9) : .secondary)
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
    }
}

// MARK: - Looping video (Black.mp4 / White.mp4 from bundle)

private struct LoopingVideoView: UIViewRepresentable {
    let filename: String
    let `extension`: String

    func makeUIView(context: Context) -> UIView {
        let view = PlayerView()
        view.setup(filename: filename, ext: `extension`)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class PlayerView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopToken: Any?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    func setup(filename: String, ext: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: ext)
            ?? Bundle.main.url(forResource: filename, withExtension: ext, subdirectory: "CampaignLoading") else {
            return
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        (layer as? AVPlayerLayer)?.player = player
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        self.player = player

        loopToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        player.play()
    }

    deinit {
        if let t = loopToken {
            NotificationCenter.default.removeObserver(t)
        }
    }
}

#Preview("Dark") {
    CampaignCreatingOverlayView(useDarkStyle: true)
}

#Preview("Light") {
    CampaignCreatingOverlayView(useDarkStyle: false)
}
