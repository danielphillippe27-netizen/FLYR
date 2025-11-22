import SwiftUI

/// Template 1: Minimal Black - Apple-inspired minimal design
public struct LandingPageMinimalBlack: View {
    let page: LandingPageData
    let branding: LandingPageBranding?
    
    public init(page: LandingPageData, branding: LandingPageBranding? = nil) {
        self.page = page
        self.branding = branding
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Image
                if let imageURLString = page.imageURL, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 280)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.3)
                                .frame(height: 280)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(height: 280)
                    .clipped()
                }
                
                // Title
                Text(page.title)
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Subtitle
                Text(page.subtitle)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // CTA Button
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
                        .background(branding?.ctaColorValue ?? Color.red)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // Description
                if let description = page.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Profile Footer Card
                RealtorFooterCard(profileCard: branding?.realtorProfileCard)
            }
            .padding(.vertical)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// Realtor Profile Footer Card Component
struct RealtorFooterCard: View {
    let profileCard: RealtorProfileCard?
    
    var body: some View {
        if let card = profileCard {
            VStack(spacing: 12) {
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
                
                if let name = card.name {
                    Text(name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                if let company = card.company {
                    Text(company)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                if let phone = card.phone {
                    Link(phone, destination: URL(string: "tel:\(phone)")!)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

