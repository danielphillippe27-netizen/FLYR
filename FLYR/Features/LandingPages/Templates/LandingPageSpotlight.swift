import SwiftUI

/// Template 3: Neighborhood Spotlight - Community-focused design
public struct LandingPageSpotlight: View {
    let page: LandingPageData
    let branding: LandingPageBranding?
    
    public init(page: LandingPageData, branding: LandingPageBranding? = nil) {
        self.page = page
        self.branding = branding
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Local Photo
                if let imageURLString = page.imageURL, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 250)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.3)
                                .frame(height: 250)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(height: 250)
                    .clipped()
                } else {
                    // Default neighborhood image placeholder
                    Color.gray.opacity(0.2)
                        .frame(height: 250)
                        .overlay(
                            Image(systemName: "map.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                        )
                }
                
                // Title
                Text(page.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Claim Offer CTA
                Button(action: {
                    if let url = URL(string: page.ctaURL) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text(page.ctaText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(branding?.ctaColorValue ?? Color.green)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // Description Block
                if let description = page.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About This Offer")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(description)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Neighborhood List View
                if let neighborhoodItems = extractNeighborhoodItems(from: page.dynamicData) {
                    NeighborhoodListView(items: neighborhoodItems)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func extractNeighborhoodItems(from data: [String: AnyCodable]) -> [NeighborhoodItem]? {
        guard let itemsArray = data["neighborhood_items"]?.value as? [[String: Any]] else {
            return nil
        }
        
        return itemsArray.compactMap { itemDict in
            NeighborhoodItem(
                title: itemDict["title"] as? String,
                description: itemDict["description"] as? String,
                icon: itemDict["icon"] as? String
            )
        }
    }
}

/// Neighborhood Item Model
struct NeighborhoodItem: Identifiable {
    let id = UUID()
    let title: String?
    let description: String?
    let icon: String?
}

/// Neighborhood List View Component
struct NeighborhoodListView: View {
    let items: [NeighborhoodItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's Happening in Your Neighborhood")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    if let iconName = item.icon {
                        Image(systemName: iconName)
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                            .frame(width: 30)
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 30, height: 30)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = item.title {
                            Text(title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        if let description = item.description {
                            Text(description)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

