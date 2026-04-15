import SwiftUI
import StoreKit

/// Accent color: red (used for CTA, plan border, Most popular pill, feature icons, gradient).
private let paywallAccentRed = Color(red: 1.0, green: 0.05, blue: 0.02)

/// Apple Standard EULA for auto-renewable subscriptions (App Review 3.1.2).
private let appleStandardEULAURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

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
    /// When true, show member-inactive copy while still allowing the user to start a trial or subscribe.
    var memberInactive: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var entitlementsService: EntitlementsService
    @EnvironmentObject var routeState: AppRouteState
    @ObservedObject private var storeKit = StoreKitManager.shared

    @State private var selectedPlan: PlanKind = .monthly
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isWaitingForPayment = false

    private let fallback = FallbackPricing.current

    enum PlanKind: String, CaseIterable {
        case annual
        case monthly
    }

    private var annualProduct: Product? {
        storeKit.products.first { $0.id == StoreKitManager.ProductId.annual }
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
        "Start 14-Day Free Trial"
    }

    private var selectedPlanDisclosureText: String {
        switch selectedPlan {
        case .annual:
            return "14 days free, then \(annualPriceText)/year, auto-renewing yearly unless canceled at least 24 hours before renewal."
        case .monthly:
            return "14 days free, then \(monthlyBilledPrimaryText), auto-renewing monthly unless canceled at least 24 hours before renewal."
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

                bottomSubscribeSection
            }

        }
        .preferredColorScheme(.dark)
        .onChange(of: entitlementsService.canUsePro) { _, canUse in
            if canUse {
                Task { @MainActor in
                    isWaitingForPayment = false
                    routeState.setRoute(.dashboard)
                    dismiss()
                }
            }
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
        Text("Your workspace is inactive. Start your 14-day free trial or subscribe here to unlock full access.")
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
            Text("14-day free trial")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(paywallAccentRed)
                .clipShape(Capsule())
            Text("Track your outreach.")
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("Choose monthly or annual.")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 44)
        .padding(.bottom, 28)
    }

    // MARK: - Plan cards (billed amount is primary; monthly equivalent is subordinate — App Review 3.1.2(c))

    private var planCardsSection: some View {
        VStack(spacing: 12) {
            PlanCard(
                title: "Annual",
                primaryPriceText: annualBilledPrimaryText,
                secondaryPriceText: annualPerMonthEquivalentText,
                isSelected: selectedPlan == .annual,
                isMostPopular: false,
                isLarge: false,
                onTap: { selectedPlan = .annual }
            )

            PlanCard(
                title: "Monthly",
                primaryPriceText: monthlyBilledPrimaryText,
                secondaryPriceText: nil,
                isSelected: selectedPlan == .monthly,
                isMostPopular: false,
                isLarge: false,
                onTap: { selectedPlan = .monthly }
            )
        }
        .padding(.bottom, 24)
    }

    /// Full yearly price as shown to user (same as StoreKit display price).
    private var annualPriceText: String {
        if let p = annualProduct {
            return p.displayPrice
        }
        return fallback.formattedPrice(fallback.annualYearTotal)
    }

    private var annualBilledPrimaryText: String {
        "\(annualPriceText)/year"
    }

    private var annualPerMonthEquivalentText: String {
        if let p = annualProduct, p.price > 0 {
            let perMonth = p.price / Decimal(12)
            let formatStyle: Decimal.FormatStyle.Currency =
                isCanadianLocale ? .currency(code: "CAD") : .currency(code: "USD")
            return "\(perMonth.formatted(formatStyle))/month equivalent"
        }
        return "\(fallback.formattedPrice(fallback.annualPerMonth))/month equivalent"
    }

    private var monthlyBilledPrimaryText: String {
        if let p = monthlyProduct {
            return "\(p.displayPrice)/month"
        }
        return "\(fallback.formattedPrice(fallback.monthly))/month"
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 32) {
            Text("Everything unlocks after activation")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 28) {
                FeatureRow(icon: "desktopcomputer", text: "Desktop Dashboard")
                FeatureRow(icon: "flag.fill", text: "Unlimited Campaigns")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Performance Reports")
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

    // MARK: - Bottom section

    private var bottomSubscribeSection: some View {
        VStack(spacing: 8) {
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
                            Text("Unlocking access…")
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
            .disabled(storeKit.isPurchasing || isWaitingForPayment)

            Text(selectedPlanDisclosureText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Restore purchases") {
                Task { await restorePurchases() }
            }
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.8))
            .disabled(storeKit.isRestoring)

            VStack(spacing: 6) {
                Button {
                    openLegalURL(appleStandardEULAURL)
                } label: {
                    Text("Terms of Use (EULA)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }

                Button {
                    openLegalURL("https://www.flyrpro.app/privacy")
                } label: {
                    Text("Privacy Policy")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.black)
    }

    // MARK: - Actions

    private func performPurchase() async {
        errorMessage = nil
        do {
            var product = selectedProduct
            if product == nil {
                await storeKit.loadProducts()
                product = selectedProduct
            }
            if let product {
                let completed = try await storeKit.purchase(product)
                if completed {
                    _ = await entitlementsService.fetchEntitlement()
                    await StoreKitManager.shared.refreshLocalProFromCurrentEntitlements()
                    await MainActor.run {
                        routeState.setRoute(.dashboard)
                        dismiss()
                    }
                }
                return
            }
            await MainActor.run {
                errorMessage = "Unable to load App Store products. Check Sandbox Apple ID, then try Restore Purchases."
                showError = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func openLegalURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        openURL(url)
    }

    private func restorePurchases() async {
        errorMessage = nil
        do {
            try await storeKit.restorePurchases()
            _ = await entitlementsService.fetchEntitlement()
            await StoreKitManager.shared.refreshLocalProFromCurrentEntitlements()
            await MainActor.run {
                if entitlementsService.canUsePro {
                    routeState.setRoute(.dashboard)
                    dismiss()
                }
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
            if await MainActor.run(body: { entitlementsService.canUsePro }) {
                await MainActor.run {
                    isWaitingForPayment = false
                    routeState.setRoute(.dashboard)
                    dismiss()
                }
                return
            }
            do {
                let state = try await AccessAPI.shared.getState()
                if state.hasAccess {
                    await MainActor.run {
                        isWaitingForPayment = false
                        routeState.setRoute(.dashboard)
                        dismiss()
                    }
                    _ = await entitlementsService.fetchEntitlement()
                    await StoreKitManager.shared.refreshLocalProFromCurrentEntitlements()
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
    /// Billed amount — largest, most conspicuous (e.g. "$299.99/year" or "$29.99/month").
    let primaryPriceText: String
    /// Optional subordinate line (e.g. monthly equivalent for annual).
    let secondaryPriceText: String?
    let isSelected: Bool
    let isMostPopular: Bool
    let isLarge: Bool
    let onTap: () -> Void

    private var titleFont: Font { isLarge ? .system(size: 22, weight: .bold) : .system(size: 18, weight: .bold) }
    private var primaryPriceFont: Font { isLarge ? .system(size: 22, weight: .bold) : .system(size: 20, weight: .bold) }
    private var secondaryFont: Font { isLarge ? .system(size: 13) : .system(size: 12) }
    private var padding: CGFloat { isLarge ? 20 : 16 }
    private var cornerRadius: CGFloat { isLarge ? 16 : 14 }

    private var fg: Color { isSelected ? .black : .white }
    private var fgSecondary: Color { isSelected ? .black.opacity(0.65) : .white.opacity(0.65) }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
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
                        .foregroundColor(fg)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(primaryPriceText)
                        .font(primaryPriceFont)
                        .foregroundColor(fg)
                        .multilineTextAlignment(.trailing)
                    if let secondary = secondaryPriceText {
                        Text(secondary)
                            .font(secondaryFont)
                            .foregroundColor(fgSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
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
