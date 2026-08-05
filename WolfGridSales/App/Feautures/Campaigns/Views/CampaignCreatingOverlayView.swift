import SwiftUI
import Lottie

/// Full-screen progress view shown while a campaign is being created.
/// Shows the WolfGrid lottie, live provision progress, and destructive cleanup.
struct CampaignCreatingOverlayView: View {
    var useDarkStyle: Bool
    var progressPercent: Int = 0
    var activityText: String = "Creating campaign"
    var isCancelling: Bool = false
    var errorText: String?
    var onCancel: (() -> Void)?
    var onReady: (() -> Void)?

    @State private var didNotifyReady = false

    private var foregroundColor: Color {
        useDarkStyle ? .white : .primary
    }

    private var secondaryColor: Color {
        useDarkStyle ? .white.opacity(0.68) : .secondary
    }

    private var clampedProgress: Int {
        CampaignProvisionMonitor.clampedProgress(progressPercent)
    }

    private var isReady: Bool {
        clampedProgress >= 100
    }

    private var displayActivityText: String {
        isReady ? "Your campaign is ready" : activityText
    }

    var body: some View {
        ZStack {
            Color(useDarkStyle ? .black : .white)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                // WolfGrid lottie — same size as login screen (SignInView)
                CampaignCreatingLottieView(
                    name: useDarkStyle ? "splash" : "splash_black"
                )
                    .frame(width: 340, height: 227)
                    .clipped()

                VStack(spacing: 12) {
                    Text("Creating campaign")
                        .font(.flyrTitle2)
                        .fontWeight(.semibold)
                        .foregroundColor(foregroundColor)
                        .multilineTextAlignment(.center)

                    Text("\(clampedProgress)%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(foregroundColor)
                        .monospacedDigit()

                    Text(displayActivityText)
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundColor(secondaryColor)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.25), value: displayActivityText)
                }

                if let errorText, !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(errorText)
                        .font(.flyrFootnote.weight(.semibold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onCancel, !isReady {
                    Button(role: .destructive) {
                        onCancel()
                    } label: {
                        HStack(spacing: 8) {
                            if isCancelling {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isCancelling ? "Cancelling" : "Cancel")
                                .font(.flyrSubheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isCancelling)
                    .padding(.top, 4)
                }

                Text("You can exit the app and come back when it's ready.")
                    .font(.flyrCaption)
                    .foregroundColor(secondaryColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isReady ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: isReady)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)

        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .onAppear {
            notifyReadyIfNeeded(isReady)
        }
        .onChange(of: isReady) { _, ready in
            notifyReadyIfNeeded(ready)
        }
    }

    private func notifyReadyIfNeeded(_ ready: Bool) {
        guard ready, !didNotifyReady else { return }
        didNotifyReady = true
        DispatchQueue.main.async {
            onReady?()
        }
    }
}

// MARK: - WolfGrid Lottie (same as login: 340×227)

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
    CampaignCreatingOverlayView(
        useDarkStyle: true,
        progressPercent: 35,
        activityText: "Saving addresses",
        onCancel: {}
    )
}

#Preview("Light") {
    CampaignCreatingOverlayView(
        useDarkStyle: false,
        progressPercent: 68,
        activityText: "Preparing map",
        onCancel: {}
    )
}
