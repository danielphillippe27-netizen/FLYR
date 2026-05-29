import SwiftUI
import Lottie
import MapKit

/// Full-screen progress view shown while a campaign is being created.
/// Shows the FLYR lottie, live provision progress, and destructive cleanup.
struct CampaignCreatingOverlayView: View {
    var useDarkStyle: Bool
    var progressPercent: Int = 0
    var activityText: String = "Creating campaign"
    var polygonCoordinates: [CLLocationCoordinate2D] = []
    var isCancelling: Bool = false
    var errorText: String?
    var onCancel: (() -> Void)?
    var onReadyRevealComplete: (() -> Void)?

    @State private var didScheduleFallbackCompletion = false

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
                // FLYR lottie — same size as login screen (SignInView)
                CampaignCreatingLottieView(
                    name: useDarkStyle ? "splash" : "splash_black",
                    isCompleting: isReady
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

            if isReady, polygonCoordinates.count >= 3 {
                CampaignReadyMapRevealView(
                    polygonCoordinates: polygonCoordinates,
                    useDarkStyle: useDarkStyle,
                    onComplete: {
                        onReadyRevealComplete?()
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .onAppear {
            scheduleFallbackCompletionIfNeeded(isReady)
        }
        .onChange(of: isReady) { _, ready in
            scheduleFallbackCompletionIfNeeded(ready)
        }
    }

    private func scheduleFallbackCompletionIfNeeded(_ ready: Bool) {
        guard ready, polygonCoordinates.count < 3, !didScheduleFallbackCompletion else { return }
        didScheduleFallbackCompletion = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            onReadyRevealComplete?()
        }
    }
}

// MARK: - FLYR Lottie (same as login: 340×227)

private struct CampaignCreatingLottieView: UIViewRepresentable {
    let name: String
    let isCompleting: Bool

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
        guard isCompleting,
              !context.coordinator.didPlayCompletion,
              let lottie = context.coordinator.lottieView else {
            return
        }
        context.coordinator.didPlayCompletion = true
        let startProgress = min(max(lottie.currentProgress, 0), 0.92)
        lottie.loopMode = .playOnce
        lottie.play(fromProgress: startProgress, toProgress: 1, loopMode: .playOnce)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var lottieView: LottieAnimationView?
        var didPlayCompletion = false
    }
}

// MARK: - Ready Map Reveal

private struct CampaignReadyMapRevealView: UIViewRepresentable {
    let polygonCoordinates: [CLLocationCoordinate2D]
    let useDarkStyle: Bool
    let onComplete: () -> Void

    func makeUIView(context: Context) -> CampaignReadyMapRevealUIView {
        let view = CampaignReadyMapRevealUIView()
        view.configure(
            polygonCoordinates: polygonCoordinates,
            useDarkStyle: useDarkStyle,
            onComplete: onComplete
        )
        return view
    }

    func updateUIView(_ uiView: CampaignReadyMapRevealUIView, context: Context) {
        uiView.configure(
            polygonCoordinates: polygonCoordinates,
            useDarkStyle: useDarkStyle,
            onComplete: onComplete
        )
    }
}

private final class CampaignReadyMapRevealUIView: UIView {
    private let imageView = UIImageView()
    private let circleMaskView = UIView()
    private let strokeLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()

    private var polygonCoordinates: [CLLocationCoordinate2D] = []
    private var useDarkStyle = false
    private var onComplete: (() -> Void)?
    private var hasStarted = false
    private var didComplete = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        alpha = 0

        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        fillLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.26).cgColor
        fillLayer.strokeColor = UIColor.clear.cgColor
        fillLayer.opacity = 0

        strokeLayer.fillColor = UIColor.clear.cgColor
        strokeLayer.strokeColor = UIColor.systemGreen.cgColor
        strokeLayer.lineWidth = 4
        strokeLayer.lineJoin = .round
        strokeLayer.lineCap = .round
        strokeLayer.strokeEnd = 0

        imageView.layer.addSublayer(fillLayer)
        imageView.layer.addSublayer(strokeLayer)

        circleMaskView.backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        fillLayer.frame = imageView.bounds
        strokeLayer.frame = imageView.bounds
        startIfPossible()
    }

    func configure(
        polygonCoordinates: [CLLocationCoordinate2D],
        useDarkStyle: Bool,
        onComplete: @escaping () -> Void
    ) {
        self.polygonCoordinates = polygonCoordinates.filter(CLLocationCoordinate2DIsValid)
        self.useDarkStyle = useDarkStyle
        self.onComplete = onComplete
        startIfPossible()
    }

    private func startIfPossible() {
        guard !hasStarted, bounds.width > 1, bounds.height > 1, polygonCoordinates.count >= 3 else { return }
        hasStarted = true
        prepareSnapshot()
    }

    private func prepareSnapshot() {
        let options = MKMapSnapshotter.Options()
        options.size = bounds.size
        options.scale = UIScreen.main.scale
        options.mapType = .mutedStandard
        options.traitCollection = UITraitCollection(userInterfaceStyle: useDarkStyle ? .dark : .light)
        options.region = snapshotRegion(for: polygonCoordinates)

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { [weak self] snapshot, _ in
            guard let self else { return }
            guard let snapshot else {
                DispatchQueue.main.async {
                    self.finishOnce()
                }
                return
            }
            let pathPoints = self.polygonCoordinates.map { snapshot.point(for: $0) }
            DispatchQueue.main.async {
                self.imageView.image = snapshot.image
                self.installPolygonPath(from: pathPoints)
                self.startRevealAnimation()
            }
        }
    }

    private func snapshotRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let validCoordinates = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard let first = validCoordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }

        let bounds = validCoordinates.reduce(
            into: (minLat: first.latitude, maxLat: first.latitude, minLon: first.longitude, maxLon: first.longitude)
        ) { result, coordinate in
            result.minLat = min(result.minLat, coordinate.latitude)
            result.maxLat = max(result.maxLat, coordinate.latitude)
            result.minLon = min(result.minLon, coordinate.longitude)
            result.maxLon = max(result.maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (bounds.minLat + bounds.maxLat) / 2,
            longitude: (bounds.minLon + bounds.maxLon) / 2
        )
        let latitudeDelta = max((bounds.maxLat - bounds.minLat) * 1.9, 0.006)
        let longitudeDelta = max((bounds.maxLon - bounds.minLon) * 1.9, 0.006)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private func installPolygonPath(from points: [CGPoint]) {
        guard let first = points.first else { return }
        let path = UIBezierPath()
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.close()

        fillLayer.path = path.cgPath
        strokeLayer.path = path.cgPath
        strokeLayer.strokeEnd = 0
        fillLayer.opacity = 0
    }

    private func startRevealAnimation() {
        configureInitialMask()
        alpha = 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { [weak self] in
            guard let self else { return }
            let finalRadius = self.finalRevealRadius()
            let animator = UIViewPropertyAnimator(duration: 0.82, dampingRatio: 0.82) {
                self.circleMaskView.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: finalRadius * 2,
                    height: finalRadius * 2
                )
                self.circleMaskView.layer.cornerRadius = finalRadius
            }
            animator.addCompletion { [weak self] _ in
                self?.mask = nil
                self?.animatePolygonDraw()
            }
            animator.startAnimation()
        }
    }

    private func configureInitialMask() {
        let radius: CGFloat = 26
        circleMaskView.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        circleMaskView.center = revealOrigin
        circleMaskView.layer.cornerRadius = radius
        mask = circleMaskView
    }

    private var revealOrigin: CGPoint {
        CGPoint(
            x: bounds.midX,
            y: max(bounds.minY + 120, bounds.midY - 130)
        )
    }

    private func finalRevealRadius() -> CGFloat {
        let origin = revealOrigin
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ]
        return (corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? max(bounds.width, bounds.height)) + 40
    }

    private func animatePolygonDraw() {
        let strokeAnimation = CABasicAnimation(keyPath: "strokeEnd")
        strokeAnimation.fromValue = 0
        strokeAnimation.toValue = 1
        strokeAnimation.duration = 0.6
        strokeAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        strokeLayer.strokeEnd = 1
        strokeLayer.add(strokeAnimation, forKey: "strokeEnd")

        let fillAnimation = CABasicAnimation(keyPath: "opacity")
        fillAnimation.fromValue = 0
        fillAnimation.toValue = 1
        fillAnimation.beginTime = CACurrentMediaTime() + 0.22
        fillAnimation.duration = 0.36
        fillAnimation.fillMode = .backwards
        fillAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fillLayer.opacity = 1
        fillLayer.add(fillAnimation, forKey: "opacity")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.86) { [weak self] in
            self?.finishOnce()
        }
    }

    private func finishOnce() {
        guard !didComplete else { return }
        didComplete = true
        onComplete?()
    }
}

#Preview("Dark") {
    CampaignCreatingOverlayView(
        useDarkStyle: true,
        progressPercent: 35,
        activityText: "Saving addresses",
        polygonCoordinates: [
            CLLocationCoordinate2D(latitude: 43.651, longitude: -79.383),
            CLLocationCoordinate2D(latitude: 43.654, longitude: -79.378),
            CLLocationCoordinate2D(latitude: 43.649, longitude: -79.374),
            CLLocationCoordinate2D(latitude: 43.646, longitude: -79.381)
        ],
        onCancel: {}
    )
}

#Preview("Light") {
    CampaignCreatingOverlayView(
        useDarkStyle: false,
        progressPercent: 68,
        activityText: "Preparing map",
        polygonCoordinates: [
            CLLocationCoordinate2D(latitude: 43.651, longitude: -79.383),
            CLLocationCoordinate2D(latitude: 43.654, longitude: -79.378),
            CLLocationCoordinate2D(latitude: 43.649, longitude: -79.374),
            CLLocationCoordinate2D(latitude: 43.646, longitude: -79.381)
        ],
        onCancel: {}
    )
}
