//
//  MacWelcomeView.swift
//  Kestrel Mac
//
//  First-launch welcome flow: intro → account → Pro offer.
//

import SwiftUI

// MARK: - Onboarding Step

private enum OnboardingStep: Int, CaseIterable {
    case intro
    case account
    case offer
}

// MARK: - Account Mode

private enum AccountMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case createAccount = "Create Account"

    var id: String { rawValue }
}

// MARK: - Mac Welcome View

/// Shown once, on first launch, as a full-window overlay before the main app.
struct MacWelcomeView: View {
    /// Called when the user finishes (or skips) onboarding.
    let onComplete: () -> Void

    @EnvironmentObject private var supabase: SupabaseService
    @EnvironmentObject private var revenueCat: RevenueCatService

    @State private var step: OnboardingStep = .intro

    // Account form state
    @State private var accountMode: AccountMode = .createAccount
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var authError: String?
    @State private var showConfirmEmail = false

    // Paywall
    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            KestrelColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 28)

                Group {
                    switch step {
                    case .intro:   introStep
                    case .account: accountStep
                    case .offer:   offerStep
                    }
                }
                .frame(width: 460)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingPaywall) {
            MacPaywallView()
                .environmentObject(revenueCat)
        }
        .onChange(of: revenueCat.isProOrBundle) { _, isPro in
            // Purchase completed inside the paywall sheet — finish onboarding.
            if isPro { finish() }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue
                          ? KestrelColors.phosphorGreen
                          : KestrelColors.cardBorder)
                    .frame(width: s == step ? 22 : 7, height: 7)
                    .animation(.snappy(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Step 1: Intro

    private var introStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Text("◈ KESTREL")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(KestrelColors.phosphorGreen)

                Text("SSH · MONITOR · MANAGE")
                    .font(KestrelFonts.mono(11))
                    .tracking(2)
                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.4))
            }

            Text("Your servers,\nright on your desktop")
                .font(KestrelFonts.display(30, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 30)

            VStack(alignment: .leading, spacing: 0) {
                let highlights: [(String, String)] = [
                    ("terminal",        "Full SSH terminal with tabbed sessions"),
                    ("chart.bar",       "Live CPU, memory & disk dashboards"),
                    ("folder",          "Browse & transfer files over SFTP"),
                    ("rectangle.stack", "Run commands across multiple servers"),
                ]
                ForEach(highlights, id: \.0) { icon, text in
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .frame(width: 24)
                        Text(text)
                            .font(KestrelFonts.mono(13))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    if icon != highlights.last?.0 {
                        Rectangle()
                            .fill(KestrelColors.cardBorder)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
            .padding(.top, 30)

            Spacer()

            primaryButton(title: "Get Started") {
                advance(to: .account)
            }

            Spacer().frame(height: 28)
        }
    }

    // MARK: - Step 2: Account

    private var accountStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text(accountMode == .signIn ? "Welcome back" : "Create your account")
                .font(KestrelFonts.display(24, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .padding(.top, 18)

            Text("An account syncs your servers, keys, and commands\nsecurely across all your devices.")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 6)

            Picker("Mode", selection: $accountMode) {
                ForEach(AccountMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, 26)
            .onChange(of: accountMode) { _, _ in
                authError = nil
                showConfirmEmail = false
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .tint(KestrelColors.phosphorGreen)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(accountMode == .signIn ? .password : .newPassword)
                    .tint(KestrelColors.phosphorGreen)
                    .onSubmit { performAuth() }

                if let authError {
                    Text(authError)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.red)
                        .multilineTextAlignment(.center)
                }

                if showConfirmEmail {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.badge")
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        Text("Check your email to confirm your account, then sign in.")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }
            }
            .padding(.top, 18)

            Spacer()

            primaryButton(
                title: accountMode == .signIn ? "Sign In" : "Create Account",
                isLoading: isWorking,
                isDisabled: email.isEmpty || password.isEmpty
            ) {
                performAuth()
            }

            // Registration is required — no skip button. Replaced with a
            // brief note explaining why an account is mandatory.
            Text("An account is required to use Kestrel — it’s how your servers, keys, and settings sync between devices.")
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 14)

            Spacer().frame(height: 28)
        }
    }

    // MARK: - Step 3: Pro Offer

    private var offerStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(KestrelColors.phosphorGreenDim)
                    .frame(width: 72, height: 72)
                Text("◈")
                    .font(.system(size: 34))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }

            Text("Unlock Kestrel Pro")
                .font(KestrelFonts.display(26, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .padding(.top, 18)

            Text("Unlimited servers & keys, multi-server execution,\nsession recording, and more.")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 6)

            VStack(spacing: 11) {
                ForEach([
                    "Unlimited servers & SSH keys",
                    "Multi-server command execution",
                    "Service monitor & process manager",
                    "Session recording & audit trail",
                ], id: \.self) { text in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        Text(text)
                            .font(KestrelFonts.mono(13))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Spacer()
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
            .padding(.top, 26)

            Spacer()

            primaryButton(title: "See Plans & Pricing") {
                showingPaywall = true
            }

            Button("Continue with Free Plan") {
                finish()
            }
            .buttonStyle(.plain)
            .font(KestrelFonts.mono(12))
            .foregroundStyle(KestrelColors.textMuted)
            .padding(.top, 14)

            Text("Free plan: up to \(RevenueCatService.freeServerLimit) servers and \(RevenueCatService.freeKeyLimit) SSH keys.")
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
                .padding(.top, 4)

            Spacer().frame(height: 28)
        }
    }

    // MARK: - Shared Button

    private func primaryButton(
        title: String,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(KestrelColors.background)
                }
                Text(isLoading ? "Please wait…" : title)
                    .font(KestrelFonts.monoBold(14))
            }
            .foregroundStyle(KestrelColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(KestrelColors.phosphorGreen)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isDisabled || isLoading ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }

    // MARK: - Actions

    private func advance(to next: OnboardingStep) {
        withAnimation(.snappy(duration: 0.3)) {
            step = next
        }
    }

    private func performAuth() {
        guard !email.isEmpty, !password.isEmpty, !isWorking else { return }
        isWorking = true
        authError = nil
        showConfirmEmail = false
        Task {
            do {
                switch accountMode {
                case .signIn:
                    try await supabase.signIn(email: email, password: password)
                    advance(to: .offer)
                case .createAccount:
                    let needsConfirmation = try await supabase.signUp(
                        email: email, password: password
                    )
                    if needsConfirmation {
                        showConfirmEmail = true
                    } else {
                        advance(to: .offer)
                    }
                }
            } catch {
                authError = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func finish() {
        onComplete()
    }
}
