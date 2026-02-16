import SwiftUI
import StoreKit

/// Accent color: red (used for CTA, plan border, Most popular pill, feature icons).
private let paywallAccentRed = Color(red: 1.0, green: 0.22, blue: 0.15)

// MARK: - Fallback pricing (when StoreKit not loaded yet)
private struct FallbackPricing {
    let monthly: String
    let annualPerMonth: String
    let annualYearTotal: String
    let currency: String

    static var current: FallbackPricing {
        let region = Locale.current.region?.identifier ?? "US"
        if region == "CA" {
            return FallbackPricing(
                monthly: "39.99",
                annualPerMonth: "34.99",
                annualYearTotal: "419.99",
                currency: "CAD"
            )
        }
        return FallbackPricing(
            monthly: "29.99",
            annualPerMonth: "24.99",
            annualYearTotal: "299.99",
            currency: "USD"
        )
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var entitlementsService: EntitlementsService
    @ObservedObject private var storeKit = StoreKitManager.shared

    @State private var selectedPlan: PlanKind = .annual
    @State private var errorMessage: String?
    @State private var showError = false

    private let fallback = FallbackPricing.current

    enum PlanKind: String, CaseIterable {
        case annual
        case monthly
    }

    private var annualProduct: Product? {
        storeKit.products.first { $0.id == StoreKitManager.ProductId.annual || $0.id == StoreKitManager.ProductId.yearly }
    }

    private var monthlyProduct: Product? {
        storeKit.products.first { $0.id == StoreKitManager.ProductId.monthly }
    }

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .annual: return annualProduct
        case .monthly: return monthlyProduct
        }
    }

    private var ctaTitle: String {
        switch selectedPlan {
        case .annual: return "Subscribe Annually"
        case .monthly: return "Subscribe Monthly"
        }
    }

    var body: some View {
        ZStack {
            // Dark background + red gradient at top
            paywallBackground

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 8)
                        headerSection
                        planCardsSection
                        featuresSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                // Bottom header: CTA + recurring billing only
                bottomSubscribeSection
            }

            // Circular X close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                }
                Spacer()
            }
            .allowsHitTesting(true)
        }
        .preferredColorScheme(.dark)
        .onChange(of: entitlementsService.canUsePro) { _, canUse in
            if canUse { dismiss() }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                errorMessage = nil
                showError = false
            }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
        .task {
            await storeKit.loadProducts()
        }
    }

    // MARK: - Background

    private var paywallBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Red gradient glow at top
            RadialGradient(
                colors: [
                    paywallAccentRed.opacity(0.5),
                    paywallAccentRed.opacity(0.25),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("Unlock your full potential.")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Track progress, market smarter, and grow your business with an optimized approach to canvassing")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 44)
        .padding(.bottom, 28)
    }

    // MARK: - Plan cards

    private var planCardsSection: some View {
        VStack(spacing: 12) {
            // Annual (first, larger card)
            PlanCard(
                title: "Annual",
                billedYearText: annualBilledYearText,
                rightPriceText: annualPerMonthText,
                isSelected: selectedPlan == .annual,
                isMostPopular: true,
                isLarge: true,
                onTap: { selectedPlan = .annual }
            )

            // Monthly
            PlanCard(
                title: "Monthly",
                billedYearText: nil,
                rightPriceText: monthlyPriceText,
                isSelected: selectedPlan == .monthly,
                isMostPopular: false,
                isLarge: false,
                onTap: { selectedPlan = .monthly }
            )
        }
        .padding(.bottom, 24)
    }

    private var annualBilledYearText: String? {
        if let p = annualProduct {
            return "Billed at \(p.displayPrice)/year"
        }
        return "Billed at $\(fallback.annualYearTotal)/year"
    }

    private var annualPerMonthText: String {
        if let p = annualProduct, p.price > 0 {
            let perMonth = p.price / Decimal(12)
            let formatStyle: Decimal.FormatStyle.Currency =
                (Locale.current.region?.identifier == "CA")
                ? .currency(code: "CAD")
                : .currency(code: "USD")
            return "\(perMonth.formatted(formatStyle))/month"
        }
        return "$\(fallback.annualPerMonth)/month"
    }

    private var monthlyPriceText: String {
        if let p = monthlyProduct {
            return "\(p.displayPrice)/month"
        }
        return "$\(fallback.monthly)/month"
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 14) {
            Text("Everything you need, all in one place")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "map.fill", text: "Optimized routes & next-door flow")
                FeatureRow(icon: "link.circle.fill", text: "CRM integrations (Follow Up Boss)")
                FeatureRow(icon: "chart.bar.fill", text: "Leaderboard + export & sync")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    // MARK: - Bottom section (Subscribe button + recurring billing only)

    private var bottomSubscribeSection: some View {
        VStack(spacing: 10) {
            Button {
                Task { await performPurchase() }
            } label: {
                HStack {
                    if storeKit.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(paywallAccentRed)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .disabled(storeKit.isPurchasing || selectedProduct == nil)

            Text("Recurring billing. Cancel anytime.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 34)
        .background(Color.black)
    }

    // MARK: - Actions

    private func performPurchase() async {
        guard let product = selectedProduct else { return }
        errorMessage = nil
        do {
            try await storeKit.purchase(product)
            if entitlementsService.canUsePro {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

}

// MARK: - Plan card

private struct PlanCard: View {
    let title: String
    let billedYearText: String?
    let rightPriceText: String
    let isSelected: Bool
    let isMostPopular: Bool
    let isLarge: Bool
    let onTap: () -> Void

    private var titleFont: Font { isLarge ? .system(size: 22, weight: .bold) : .system(size: 18, weight: .bold) }
    private var detailFont: Font { isLarge ? .system(size: 15) : .system(size: 13) }
    private var priceFont: Font { isLarge ? .system(size: 18, weight: .bold) : .system(size: 16, weight: .bold) }
    private var padding: CGFloat { isLarge ? 20 : 16 }
    private var cornerRadius: CGFloat { isLarge ? 16 : 14 }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: isLarge ? 6 : 4) {
                    if isMostPopular {
                        Text("Most popular")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(paywallAccentRed)
                            .cornerRadius(6)
                    }
                    Text(title)
                        .font(titleFont)
                        .foregroundColor(isSelected ? .black : .white)
                    if let billed = billedYearText {
                        Text(billed)
                            .font(detailFont)
                            .foregroundColor(isSelected ? .black.opacity(0.7) : .white.opacity(0.7))
                    }
                }
                Spacer()
                Text(rightPriceText)
                    .font(priceFont)
                    .foregroundColor(isSelected ? .black : .white)
                    .multilineTextAlignment(.trailing)
            }
            .padding(padding)
            .background(isSelected ? Color.white : Color.white.opacity(0.08))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isSelected ? paywallAccentRed : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(paywallAccentRed)
                .frame(width: 24, alignment: .center)
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environmentObject(EntitlementsService())
}
