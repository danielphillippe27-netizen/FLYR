import SwiftUI

/// Template 2: Real Estate Luxe Card - Luxury real estate design
public struct LandingPageLuxeCard: View {
    let page: LandingPageData
    let branding: LandingPageBranding?
    
    public init(page: LandingPageData, branding: LandingPageBranding? = nil) {
        self.page = page
        self.branding = branding
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Photo
                if let imageURLString = page.imageURL, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 300)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.3)
                                .frame(height: 300)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(height: 300)
                    .clipped()
                } else {
                    // Default house image placeholder
                    Color.gray.opacity(0.2)
                        .frame(height: 300)
                        .overlay(
                            Image(systemName: "house.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                        )
                }
                
                // Home Value CTA Card
                VStack(spacing: 16) {
                    Text("Your Home Value")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if !page.subtitle.isEmpty {
                        Text(page.subtitle)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(action: {
                        if let url = URL(string: page.ctaURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text(page.ctaText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(branding?.ctaColorValue ?? Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .offset(y: -20)
                .padding(.bottom, -20)
                
                // Market Stats
                if let marketStats = extractMarketStats(from: page.dynamicData) {
                    MarketStatsView(stats: marketStats)
                        .padding()
                }
                
                // Description
                if let description = page.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding()
                }
                
                // Contact Section
                ContactSection(profileCard: branding?.realtorProfileCard)
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func extractMarketStats(from data: [String: AnyCodable]) -> MarketStats? {
        guard let statsDict = data["market_stats"]?.value as? [String: Any] else {
            return nil
        }
        
        return MarketStats(
            averagePrice: statsDict["average_price"] as? String,
            priceChange: statsDict["price_change"] as? String,
            daysOnMarket: statsDict["days_on_market"] as? String,
            salesCount: statsDict["sales_count"] as? String
        )
    }
}

/// Market Statistics Model
struct MarketStats {
    let averagePrice: String?
    let priceChange: String?
    let daysOnMarket: String?
    let salesCount: String?
}

/// Market Stats View Component
struct MarketStatsView: View {
    let stats: MarketStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Market Insights")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                if let price = stats.averagePrice {
                    LuxeStatCard(title: "Avg Price", value: price)
                }
                if let change = stats.priceChange {
                    LuxeStatCard(title: "Price Change", value: change)
                }
                if let days = stats.daysOnMarket {
                    LuxeStatCard(title: "Days on Market", value: days)
                }
                if let sales = stats.salesCount {
                    LuxeStatCard(title: "Recent Sales", value: sales)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
}

/// Stat Card Component for Luxe Template
struct LuxeStatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(8)
    }
}

/// Contact Section Component
struct ContactSection: View {
    let profileCard: RealtorProfileCard?
    
    var body: some View {
        if let card = profileCard {
            VStack(spacing: 16) {
                Text("Contact")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 16) {
                    if let photoURLString = card.photoURL, let photoURL = URL(string: photoURLString) {
                        AsyncImage(url: photoURL) { phase in
                            switch phase {
                            case .empty:
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = card.name {
                            Text(name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        if let company = card.company {
                            Text(company)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        if let phone = card.phone {
                            Link(phone, destination: URL(string: "tel:\(phone)")!)
                                .font(.system(size: 15, weight: .regular))
                        }
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
        }
    }
}

/// Extension for rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

