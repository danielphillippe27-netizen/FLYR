import SwiftUI

enum NetworkingShareCardVariant: Int, CaseIterable {
    case room
    case city
    case transparent

    var assetName: String {
        switch self {
        case .room:
            return "NetworkingShareBackgroundOne"
        case .city:
            return "NetworkingShareBackgroundTwo"
        case .transparent:
            return ""
        }
    }

    var usesTransparentBackground: Bool {
        self == .transparent
    }
}

/// Custom share card for networking sessions.
struct NetworkingShareCardView: View {
    let data: SessionSummaryData
    var forExport: Bool = false
    var darkCard: Bool = false
    var variant: NetworkingShareCardVariant = .room

    private var cornerRadius: CGFloat { forExport ? 0 : 24 }
    private var horizontalPadding: CGFloat { forExport ? 56 : 22 }
    private var headingFont: Font { .system(size: forExport ? 88 : 34, weight: .heavy) }
    private var statValueFont: Font { .system(size: forExport ? 56 : 22, weight: .bold) }
    private var statLabelFont: Font { .system(size: forExport ? 28 : 12, weight: .medium) }
    private var logoFont: Font { .system(size: forExport ? 82 : 31, weight: .black) }
    private var logoTopPadding: CGFloat { forExport ? 116 : 34 }
    private var logoTrailingPadding: CGFloat { forExport ? 52 : 18 }
    private var cardBottomPadding: CGFloat { forExport ? 88 : 28 }
    private var cardSpacing: CGFloat { forExport ? 20 : 10 }
    private var statsSpacing: CGFloat { forExport ? 32 : 12 }

    var body: some View {
        ZStack {
            cardBackground

            ZStack {
                if !variant.usesTransparentBackground {
                    NetworkingCardBackdrop(variant: variant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.08),
                            Color.black.opacity(0.22),
                            Color.black.opacity(0.64),
                            Color.black.opacity(0.92),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: cardSpacing) {
                        Text("Networking")
                            .font(headingFont)
                            .foregroundColor(.white)

                        HStack(alignment: .top, spacing: statsSpacing) {
                            statColumn(label: "Conversations", value: "\(data.conversations)")
                            statColumn(label: "Leads", value: "\(data.leadsCreated)")
                            statColumn(label: "Time", value: data.formattedTimeStrava)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, cardBottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Text("FLYR")
                            .font(logoFont)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.top, logoTopPadding)
                            .padding(.trailing, logoTrailingPadding)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .foregroundColor(.white)
    }

    private var cardBackground: some View {
        Group {
            if forExport {
                Color.clear
            } else if variant.usesTransparentBackground {
                CheckeredBackground(
                    squareSize: 24,
                    color1: .gray.opacity(0.35),
                    color2: .gray.opacity(0.2)
                )
            } else if darkCard {
                Color(white: 0.12)
            } else {
                CheckeredBackground(
                    squareSize: 24,
                    color1: .gray.opacity(0.35),
                    color2: .gray.opacity(0.2)
                )
            }
        }
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: forExport ? 10 : 5) {
            Text(label)
                .font(statLabelFont)
                .foregroundColor(.white.opacity(0.82))
            Text(value)
                .font(statValueFont)
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NetworkingCardBackdrop: View {
    let variant: NetworkingShareCardVariant

    var body: some View {
        ZStack {
            Color.black

            GeometryReader { proxy in
                ZStack {
                    Image(variant.assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .saturation(0)
                        .contrast(1.02)
                        .opacity(0.9)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.02),
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.28),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
        }
    }
}

#Preview {
    NetworkingShareCardView(
        data: SessionSummaryData(
            distance: 0,
            time: 4260,
            goalType: .time,
            goalAmount: 60,
            pathCoordinates: [],
            renderedPathSegments: nil,
            completedCount: 0,
            conversationsCount: 7,
            leadsCreatedCount: 3,
            startTime: Date(),
            isNetworkingSession: true
        ),
        darkCard: true,
        variant: .room
    )
}
