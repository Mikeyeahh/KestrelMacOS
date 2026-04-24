//
//  MacPaywallView.swift
//  Kestrel Mac
//
//  macOS paywall — presented as a sheet over the main window.
//  Same RevenueCat products and entitlements as iOS.
//

import SwiftUI
import RevenueCat

// MARK: - Plan Type

private enum PlanType: String, CaseIterable, Identifiable {
    case monthly  = "Monthly"
    case yearly   = "Yearly"
    case lifetime = "Lifetime"
    var id: String { rawValue }
}

// MARK: - Mac Paywall View

struct MacPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var revenueCatService: RevenueCatService

    @State private var selectedPlan: PlanType = .yearly
    @State private var isPurchasing = false
    @State private var showingError = false
    @State private var purchaseSucceeded = false

    var body: some View {
        VStack(spacing: 0) {
            // Close button row
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    freeTrialBanner
                    featureGrid
                    planCards
                    if !revenueCatService.hasSuiteBundle { bundleCard }
                    purchaseButton
                    footerLinks
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 520, height: 640)
        .background(KestrelColors.background)
        .alert("Welcome to Kestrel Pro!", isPresented: $purchaseSucceeded) {
            Button("Done") { dismiss() }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(revenueCatService.errorMessage ?? "Something went wrong")
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(KestrelColors.phosphorGreenDim)
                    .frame(width: 56, height: 56)
                Text("◈")
                    .font(.system(size: 26))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }

            Text("KESTREL PRO")
                .font(KestrelFonts.mono(12))
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text("Unlock the full server toolkit")
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Everything you need to manage, monitor,\nand secure your infrastructure")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Free Trial Banner

    @ViewBuilder
    private var freeTrialBanner: some View {
        if let yearly = revenueCatService.yearlyProduct,
           yearly.introductoryDiscount != nil {
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(KestrelColors.phosphorGreen)

                Text("7-DAY FREE TRIAL — then \(yearly.localizedPriceString)/yr")
                    .font(KestrelFonts.mono(10))
                    .fontWeight(.bold)
                    .foregroundStyle(KestrelColors.phosphorGreen)

                Spacer()

                Button { /* dismiss banner */ } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(KestrelColors.phosphorGreenDim)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
        }
    }

    // MARK: - Feature Grid (2 columns)

    private var featureGrid: some View {
        let features: [(String, String)] = [
            ("server.rack",       "Unlimited servers & keys"),
            ("chart.bar",         "Live server dashboard"),
            ("folder",            "SFTP file manager"),
            ("sparkles",          "AI terminal assistant"),
            ("rectangle.stack",   "Multi-server commands"),
            ("gearshape.2",       "Service monitor"),
            ("record.circle",     "Session recording"),
            ("command",           "Command library editing"),
            ("laptopcomputer",    "macOS app included"),
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(features, id: \.0) { icon, text in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .frame(width: 18, height: 18)
                        .background(KestrelColors.phosphorGreenDim)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(text)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        HStack(spacing: 8) {
            planCard(.monthly, "Monthly",
                     revenueCatService.monthlyProduct?.localizedPriceString ?? "£3.99",
                     "/mo")
            planCard(.yearly, "Yearly",
                     revenueCatService.yearlyProduct?.localizedPriceString ?? "£24.99",
                     "/yr", badge: "BEST VALUE")
            planCard(.lifetime, "Lifetime",
                     revenueCatService.lifetimeProduct?.localizedPriceString ?? "£49.99",
                     "once")
        }
    }

    private func planCard(_ type: PlanType, _ label: String, _ price: String,
                          _ period: String, badge: String? = nil) -> some View {
        let isSelected = selectedPlan == type

        return Button {
            withAnimation(.snappy(duration: 0.15)) { selectedPlan = type }
        } label: {
            VStack(spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(KestrelFonts.mono(7))
                        .fontWeight(.bold)
                        .tracking(0.5)
                        .foregroundStyle(KestrelColors.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(KestrelColors.phosphorGreen)
                        .clipShape(Capsule())
                } else {
                    Spacer().frame(height: 12)
                }

                Text(label)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(isSelected ? KestrelColors.textPrimary : KestrelColors.textMuted)

                Text(price)
                    .font(KestrelFonts.display(16, weight: .bold))
                    .foregroundStyle(isSelected ? KestrelColors.phosphorGreen : KestrelColors.textPrimary)

                Text(period)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? KestrelColors.phosphorGreen : KestrelColors.cardBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suite Bundle Card

    private var bundleCard: some View {
        Button {
            Task { await purchaseBundleAction() }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("OSPREY + KESTREL")
                            .font(KestrelFonts.mono(9))
                            .fontWeight(.bold)
                            .tracking(1)
                            .foregroundStyle(KestrelColors.amber)

                        Text("SUITE")
                            .font(KestrelFonts.mono(7))
                            .fontWeight(.bold)
                            .foregroundStyle(KestrelColors.background)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(KestrelColors.amber)
                            .clipShape(Capsule())
                    }

                    Text("The complete engineer's suite")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(revenueCatService.bundleProduct?.localizedPriceString ?? "£39.99")
                        .font(KestrelFonts.display(14, weight: .bold))
                        .foregroundStyle(KestrelColors.amber)
                    Text("/yr")
                        .font(KestrelFonts.mono(8))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: [KestrelColors.amber.opacity(0.06), KestrelColors.amber.opacity(0.02)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [KestrelColors.amber.opacity(0.5), KestrelColors.amber.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    // MARK: - CTA Button

    private var purchaseButton: some View {
        Button {
            Task { await performPurchase() }
        } label: {
            HStack(spacing: 6) {
                if isPurchasing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(KestrelColors.background)
                }
                Text(isPurchasing ? "Processing…" : "Continue with \(selectedPlan.rawValue)")
                    .font(KestrelFonts.monoBold(12))
            }
            .foregroundStyle(KestrelColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(KestrelColors.phosphorGreen)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 8) {
            Button {
                Task { await restore() }
            } label: {
                Text("Restore Purchases")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                Link("Terms of Use", destination: URL(string: "https://getosprey.app/terms")!)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
                Link("Privacy Policy", destination: URL(string: "https://getosprey.app/privacy")!)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Text("Payment charged to your Apple ID. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period.")
                .font(KestrelFonts.mono(8))
                .foregroundStyle(KestrelColors.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Actions

    private func performPurchase() async {
        isPurchasing = true
        let success: Bool
        switch selectedPlan {
        case .monthly:  success = await revenueCatService.purchaseMonthly()
        case .yearly:   success = await revenueCatService.purchaseYearly()
        case .lifetime: success = await revenueCatService.purchaseLifetime()
        }
        isPurchasing = false
        if success { purchaseSucceeded = true }
        else if revenueCatService.errorMessage != nil { showingError = true }
    }

    private func purchaseBundleAction() async {
        isPurchasing = true
        let success = await revenueCatService.purchaseBundle()
        isPurchasing = false
        if success { purchaseSucceeded = true }
        else if revenueCatService.errorMessage != nil { showingError = true }
    }

    private func restore() async {
        isPurchasing = true
        let restored = await revenueCatService.restorePurchases()
        isPurchasing = false
        if restored { purchaseSucceeded = true }
    }
}

// MARK: - Pro Locked View (Mac)

struct ProLockedView: View {
    let feature: KestrelFeature
    @State private var showingPaywall = false
    @EnvironmentObject var revenueCatService: RevenueCatService

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text("Pro Feature")
                .font(KestrelFonts.display(16, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text(feature.rawValue)
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text(feature.featureDescription)
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button { showingPaywall = true } label: {
                HStack(spacing: 5) {
                    Text("◈").font(.system(size: 10))
                    Text("Unlock with Pro").font(KestrelFonts.monoBold(11))
                }
                .foregroundStyle(KestrelColors.background)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(KestrelColors.phosphorGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.95))
        .sheet(isPresented: $showingPaywall) {
            MacPaywallView()
        }
    }
}

// MARK: - Pro Gated ViewModifier (Mac)

struct ProGatedModifier: ViewModifier {
    let feature: KestrelFeature
    @EnvironmentObject var revenueCatService: RevenueCatService

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: revenueCatService.isProOrBundle ? 0 : 6)
                .allowsHitTesting(revenueCatService.isProOrBundle)

            if !revenueCatService.isProOrBundle {
                ProLockedView(feature: feature)
            }
        }
    }
}

extension View {
    func proGated(feature: KestrelFeature) -> some View {
        modifier(ProGatedModifier(feature: feature))
    }
}

// MARK: - Pro Badge

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(KestrelFonts.mono(8))
            .fontWeight(.bold)
            .tracking(0.8)
            .foregroundStyle(KestrelColors.background)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(KestrelColors.phosphorGreen)
            .clipShape(Capsule())
    }
}
