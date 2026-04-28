import SwiftUI
import UIKit
import Lottie

struct MapLoadingOverlayCard: View {
    let title: String?
    let message: String
    var lottieName: String? = nil
    var usesCardBackground: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedLottieName: String {
        if let lottieName {
            return lottieName
        }
        return colorScheme == .dark ? "splash" : "splash_black"
    }

    private var scrimColor: Color {
        colorScheme == .dark ? .black.opacity(0.58) : .white.opacity(0.58)
    }

    private var cardFillColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.96)
            : Color.white.opacity(0.96)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    var body: some View {
        ZStack {
            scrimColor
                .ignoresSafeArea()

            VStack(spacing: 18) {
                MapLoadingLottieView(name: resolvedLottieName)
                    .frame(width: 220, height: 148)
                    .clipped()
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.flyrHeadline)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.primary)
                    }
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 332)
            .padding(.horizontal, 24)
            .background(cardBackground)
            .shadow(color: usesCardBackground ? .black.opacity(0.28) : .clear, radius: 18, x: 0, y: 10)
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .transition(.opacity)
    }

    private var accessibilityLabel: String {
        if let title, !title.isEmpty {
            return "\(title). \(message)"
        }
        return message
    }

    @ViewBuilder
    private var cardBackground: some View {
        if usesCardBackground {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardStrokeColor, lineWidth: 1)
                )
        }
    }
}

struct MapLoadingLottieView: UIViewRepresentable {
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
            lottie.bottomAnchor.constraint(equalTo: container.bottomAnchor)
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

    final class Coordinator {
        weak var lottieView: LottieAnimationView?
    }
}
