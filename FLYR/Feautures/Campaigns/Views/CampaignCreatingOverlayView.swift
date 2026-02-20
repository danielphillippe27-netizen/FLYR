import SwiftUI
import Lottie

/// Full-screen blocking overlay shown while a campaign is being created.
/// Shows FLYR lottie (same size as login) and "Creating campaign" below. Screen is frozen; user cannot dismiss.
struct CampaignCreatingOverlayView: View {
    var useDarkStyle: Bool

    var body: some View {
        ZStack {
            Color(useDarkStyle ? .black : .white)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // FLYR lottie — same size as login screen (SignInView)
                CampaignCreatingLottieView(name: useDarkStyle ? "splash" : "splash_black")
                    .frame(width: 340, height: 227)
                    .clipped()

                Text("Creating campaign")
                    .font(.flyrTitle2)
                    .fontWeight(.semibold)
                    .foregroundColor(useDarkStyle ? .white : .primary)
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
    }
}

// MARK: - FLYR Lottie (same as login: 340×227)

private struct CampaignCreatingLottieView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        let lottie = LottieAnimationView(name: name, bundle: .main)
        lottie.loopMode = .loop
        lottie.contentMode = .scaleAspectFit
        lottie.backgroundBehavior = .pauseAndRestore
        lottie.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lottie)
        NSLayoutConstraint.activate([
            lottie.topAnchor.constraint(equalTo: container.topAnchor),
            lottie.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lottie.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lottie.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        lottie.play()
        context.coordinator.lottieView = lottie
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.lottieView?.contentMode = .scaleAspectFit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var lottieView: LottieAnimationView?
    }
}

#Preview("Dark") {
    CampaignCreatingOverlayView(useDarkStyle: true)
}

#Preview("Light") {
    CampaignCreatingOverlayView(useDarkStyle: false)
}
