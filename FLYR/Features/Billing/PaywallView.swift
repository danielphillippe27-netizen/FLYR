import SwiftUI
import StoreKit

/// Accent color: red (used for CTA, plan border, Most popular pill, feature icons, gradient).
private let paywallAccentRed = Color(red: 1.0, green: 0.05, blue: 0.02)

// MARK: - Region/currency helper (Canada = CAD, else USD).
private var isCanadianLocale: Bool {
    Locale.current.region?.identifier == "CA" || Locale.current.currency?.identifier == "CAD"
}

// MARK: - Fallback pricing (when StoreKit not loaded yet). Canada = CAD, US = USD.
private struct FallbackPricing {
    let monthly: String
    let annualPerMonth: String
    let annualYearTotal: String
    let currencyCode: String

    static var current: FallbackPricing {
        if isCanadianLocale {
            return FallbackPricing(
                monthly: "39.99",
                annualPerMonth: "34.99",
                annualYearTotal: "419.99",
                currencyCode: "CAD"
            )
        }
        return FallbackPricing(
            monthly: "29.99",
            annualPerMonth: "24.99",
            annualYearTotal: "299.99",
            currencyCode: "USD"
        )
    }

    /// Formatted price string with correct symbol (e.g. CA$39.99 or $29.99).
    func formattedPrice(_ amount: String) -> String {
        let style: Decimal.FormatStyle.Currency = currencyCode == "CAD"
            ? .currency(code: "CAD")
            : .currency(code: "USD")
        return (Decimal(string: amount) ?? 0).formatted(style)
    }
}

struct PaywallView: View {
    /// When true, show member-inactive copy (contact workspace owner); hide checkout CTA.
    var memberInactive: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var entitlementsService: EntitlementsService
    @EnvironmentObject var routeState: AppRouteState
    @ObservedObject private var storeKit = StoreKitManager.shared

    @State private var selectedPlan: PlanKind = .annual
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isWaitingForPayment = false

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
                        if memberInactive {
                            memberInactiveBanner
                        }
                        headerSection
                        planCardsSection
                        featuresSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                // Bottom header: CTA + recurring billing only (hidden when member-inactive)
                if !memberInactive {
                    bottomSubscribeSection
                } else {
                    bottomMemberInactiveSection
                }
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
            if canUse, !isWaitingForPayment { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isWaitingForPayment {
                Task { await pollAccessUntilGranted() }
            }
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
            // Red gradient glow at top (compact, red-toned)
            RadialGradient(
                colors: [
                    paywallAccentRed.opacity(0.6),
                    paywallAccentRed.opacity(0.3),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 200
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Member inactive

    private var memberInactiveBanner: some View {
        Text("Your workspace doesn't have an active subscription. Contact your workspace owner to activate access.")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding()
            .background(Color.orange.opacity(0.3))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("Track your outreach.")
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("Your business will reward you.")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 44)
        .padding(.bottom, 28)
    }

    // MARK: - Plan cards

    private var planCardsSection: some View {
        VStack(spacing: 12) {
            // Annual
            PlanCard(
                title: "Annual",
                billedYearText: annualBilledYearText,
                rightPriceText: annualPerMonthText,
                isSelected: selectedPlan == .annual,
                isMostPopular: false,
                isLarge: false,
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
        return "Billed at \(fallback.formattedPrice(fallback.annualYearTotal))/year"
    }

    private var annualPerMonthText: String {
        if let p = annualProduct, p.price > 0 {
            let perMonth = p.price / Decimal(12)
            let formatStyle: Decimal.FormatStyle.Currency =
                isCanadianLocale ? .currency(code: "CAD") : .currency(code: "USD")
            return "\(perMonth.formatted(formatStyle))/month"
        }
        return "\(fallback.formattedPrice(fallback.annualPerMonth))/month"
    }

    private var monthlyPriceText: String {
        if let p = monthlyProduct {
            return "\(p.displayPrice)/month"
        }
        return "\(fallback.formattedPrice(fallback.monthly))/month"
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 32) {
            Text("Unlock your full potential")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 28) {
                FeatureRow(icon: "desktopcomputer", text: "Desktop Dashboard")
                FeatureRow(icon: "flag.fill", text: "Unlimited Campaigns")
                FeatureRow(icon: "qrcode", text: "Smart QR Codes (see homes that scan)")
                FeatureRow(icon: "link.circle.fill", text: "CRM Integration")
                FeatureRow(icon: "calendar", text: "Set Appointments")
                FeatureRow(icon: "arrow.uturn.right", text: "Create Follow Up's")
                FeatureRow(icon: "map.fill", text: "Optimized routes using AI")
                FeatureRow(icon: "ellipsis.circle", text: "& much more")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    // MARK: - Bottom section (Subscribe button + recurring billing only)

    private var bottomSubscribeSection: some View {
        VStack(spacing: 4) {
            Button {
                Task { await performPurchase() }
            } label: {
                HStack {
                    if storeKit.isPurchasing || isWaitingForPayment {
                        ProgressView()
                            .tint(.white)
                        if storeKit.isPurchasing {
                            Text("Complete with Apple…")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                        } else if isWaitingForPayment {
                            Text("Complete payment in browser…")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                        }
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
            .disabled(storeKit.isPurchasing || selectedProduct == nil || isWaitingForPayment)

            Text("Recurring billing. Cancel anytime.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Restore purchases") {
                Task { await restorePurchases() }
            }
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.8))
            .disabled(storeKit.isRestoring)

            Button("Skip for now") {
                routeState.setRoute(.dashboard)
            }
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.black)
    }

    private var bottomMemberInactiveSection: some View {
        VStack(spacing: 12) {
            Text("Ask your workspace owner to subscribe so you can access the app.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Sign out") {
                Task {
                    await AuthManager.shared.signOut()
                }
            }
            .foregroundColor(.white.opacity(0.9))
        }
        .padding(24)
        .background(Color.black)
    }

    // MARK: - Actions

    private func performPurchase() async {
        guard !memberInactive else { return }
        errorMessage = nil
        do {
            // Prefer in-app Pay with Apple (solo users stay in app).
            if let product = selectedProduct {
                try await storeKit.purchase(product)
                await MainActor.run {
                    routeState.setRoute(.dashboard)
                }
                return
            }
            // Fallback: Stripe checkout in browser (e.g. products not loaded yet).
            let plan = selectedPlan == .annual ? "annual" : "monthly"
            let currency = isCanadianLocale ? "CAD" : "USD"
            let checkoutURL = try await AccessAPI.shared.createCheckoutSession(plan: plan, currency: currency, priceId: nil)
            await MainActor.run { isWaitingForPayment = true }
            _ = await UIApplication.shared.open(checkoutURL)
            // Polling happens on scenePhase .active when user returns to app
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func restorePurchases() async {
        guard !memberInactive else { return }
        errorMessage = nil
        do {
            try await storeKit.restorePurchases()
            if entitlementsService.canUsePro {
                routeState.setRoute(.dashboard)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func pollAccessUntilGranted() async {
        let maxAttempts = 60
        let interval: UInt64 = 2_000_000_000 // 2 seconds
        for _ in 0..<maxAttempts {
            do {
                let state = try await AccessAPI.shared.getState()
                if state.hasAccess {
                    await MainActor.run {
                        isWaitingForPayment = false
                        routeState.setRoute(.dashboard)
                        dismiss()
                    }
                    await entitlementsService.fetchEntitlement()
                    return
                }
            } catch {}
            try? await Task.sleep(nanoseconds: interval)
        }
        await MainActor.run {
            isWaitingForPayment = false
            errorMessage = "Payment may still be processing. Check back in a moment."
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
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(paywallAccentRed)
                .frame(width: 28, alignment: .center)
            Text(text)
                .font(.system(size: 19))
                .foregroundColor(.white.opacity(0.9))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environmentObject(EntitlementsService())
        .environmentObject(AppRouteState())
}
