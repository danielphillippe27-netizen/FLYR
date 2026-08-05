import SwiftUI

/// Accent color: red (used for CTA, plan border, Most popular pill, feature icons, gradient).
private let paywallAccentRed = Color(red: 1.0, green: 0.05, blue: 0.02)

// MARK: - Region/currency helper (Canada = CAD, else USD).
private var isCanadianLocale: Bool {
    Locale.current.region?.identifier == "CA" || Locale.current.currency?.identifier == "CAD"
}

// MARK: - Display pricing for web checkout. Canada = CAD, US = USD.
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
    /// When true, show workspace upgrade copy while still allowing the user to subscribe.
    var memberInactive: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var entitlementsService: EntitlementsService
    @EnvironmentObject var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared

    @State private var selectedPlan: PlanKind = .monthly
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isWaitingForPayment = false

    private let fallback = FallbackPricing.current

    enum PlanKind: String, CaseIterable {
        case annual
        case monthly
    }

    private var ctaTitle: String {
        "Continue on Web"
    }

    private var selectedPlanDisclosureText: String {
        switch selectedPlan {
        case .annual:
            return "\(annualPriceText)/year through secure web checkout. Your workspace unlocks after payment."
        case .monthly:
            return "\(monthlyBilledPrimaryText) through secure web checkout. Your workspace unlocks after payment."
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
        Text("Your first workspace campaign is included. Subscribe here to create more campaigns and unlock full access.")
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
            Text("One campaign included")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(paywallAccentRed)
                .clipShape(Capsule())
            Text("Upgrade to create more campaigns.")
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("Choose monthly or annual when you are ready to scale.")
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

    /// Full yearly price as shown to user.
    private var annualPriceText: String {
        return fallback.formattedPrice(fallback.annualYearTotal)
    }

    private var annualBilledPrimaryText: String {
        "\(annualPriceText)/year"
    }

    private var annualPerMonthEquivalentText: String {
        return "\(fallback.formattedPrice(fallback.annualPerMonth))/month equivalent"
    }

    private var monthlyBilledPrimaryText: String {
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
        VStack(spacing: 10) {
            Button {
                Task { await openWebCheckout() }
            } label: {
                HStack {
                    if isWaitingForPayment {
                        ProgressView()
                            .tint(.white)
                        Text("Opening checkout…")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.9))
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
            .disabled(isWaitingForPayment)

            Text(selectedPlanDisclosureText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Button {
                    openLegalURL("https://wolfgrid.app/terms")
                } label: {
                    Text("Terms")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }

                Button {
                    openLegalURL("https://wolfgrid.app/privacy")
                } label: {
                    Text("Privacy Policy")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Button {
                Task {
                    await auth.signOut()
                    routeState.clearPendingJoinToken()
                    routeState.clearPendingChallengeToken()
                    routeState.clearPasswordResetFlow()
                    routeState.setRoute(.login)
                }
            } label: {
                Text("Log out")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(Color.black)
    }

    // MARK: - Actions

    private func openWebCheckout() async {
        errorMessage = nil
        isWaitingForPayment = true
        do {
            let checkoutURL = try await AccessAPI.shared.createCheckoutSession(
                plan: selectedPlan.rawValue,
                currency: fallback.currencyCode,
                priceId: nil
            )
            await MainActor.run {
                openURL(checkoutURL)
            }
        } catch {
            await MainActor.run {
                isWaitingForPayment = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func openLegalURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        openURL(url)
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
                let plan = state.plan?.lowercased() ?? ""
                if state.isFounder || state.isAmbassador || plan == "pro" || plan == "team" || plan == "ambassador" {
                    await MainActor.run {
                        isWaitingForPayment = false
                        routeState.setRoute(.dashboard)
                        dismiss()
                    }
                    _ = await entitlementsService.fetchEntitlement()
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
