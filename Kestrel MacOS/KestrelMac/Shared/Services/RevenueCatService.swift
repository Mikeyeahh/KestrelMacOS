//
//  RevenueCatService.swift
//  Kestrel Mac
//
//  Stub service — replace with shared Core/Services/KestrelRevenueCatService.swift from iOS target.
//

import Foundation
import RevenueCat

// MARK: - Feature Gating

enum KestrelFeature: String, CaseIterable {
    case serverDashboard    = "Server Dashboard"
    case sftpFiles          = "SFTP File Manager"
    case aiAssistant        = "AI Terminal Assistant"
    case multiServer        = "Multi-Server Actions"
    case serviceMonitor     = "Service Monitor"
    case sessionRecording   = "Session Recording"
    case commandLibraryEdit = "Command Library Editing"
    case unlimitedServers   = "Unlimited Servers"
    case unlimitedKeys      = "Unlimited SSH Keys"

    var icon: String {
        switch self {
        case .serverDashboard:    "chart.bar"
        case .sftpFiles:          "folder"
        case .aiAssistant:        "sparkles"
        case .multiServer:        "rectangle.stack"
        case .serviceMonitor:     "gearshape.2"
        case .sessionRecording:   "record.circle"
        case .commandLibraryEdit: "pencil"
        case .unlimitedServers:   "server.rack"
        case .unlimitedKeys:      "key"
        }
    }

    var featureDescription: String {
        switch self {
        case .serverDashboard:    "Live CPU, memory, disk, and network stats"
        case .sftpFiles:          "Browse and transfer files over SFTP"
        case .aiAssistant:        "AI-powered terminal output analysis"
        case .multiServer:        "Run commands across multiple servers"
        case .serviceMonitor:     "Monitor systemd services and processes"
        case .sessionRecording:   "Record and audit terminal sessions"
        case .commandLibraryEdit: "Create and edit custom commands"
        case .unlimitedServers:   "Connect to unlimited servers (free: 2)"
        case .unlimitedKeys:      "Store unlimited SSH keys (free: 3)"
        }
    }
}

// MARK: - Developer Override

/// Emails that automatically receive Pro access (the developer!).
private let kestrelDeveloperEmails: Set<String> = [
    // Add your Supabase login email here (lowercased)
    "totaladdictionxx@me.com"
]

// MARK: - RevenueCat Service

@MainActor
class RevenueCatService: ObservableObject {
    static let shared = RevenueCatService()

    /// Maximum number of servers a free-tier user can have.
    static let freeServerLimit = 5
    /// Maximum number of SSH keys a free-tier user can have.
    static let freeKeyLimit = 3

    @Published var isProUser: Bool = false
    @Published var hasSuiteBundle: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var renewalDate: Date?
    @Published var manageSubscriptionURL: URL?

    // Products from RevenueCat offerings
    @Published var monthlyProduct: StoreProduct?
    @Published var yearlyProduct: StoreProduct?
    @Published var lifetimeProduct: StoreProduct?
    @Published var bundleProduct: StoreProduct?

    private var proOverride: Bool = false
    private static let proOverrideKey = "kestrel_pro_override"

    var isProOrBundle: Bool {
        isProUser || hasSuiteBundle || proOverride || isDeveloper
    }

    /// True when the signed-in user matches a developer email.
    @Published var isDeveloper: Bool = false

    var planName: String {
        if isDeveloper { return "Developer" }
        if hasSuiteBundle { return "Suite Bundle" }
        if isProUser { return "Kestrel Pro" }
        return "Free"
    }

    private init() {
        proOverride = UserDefaults.standard.bool(forKey: Self.proOverrideKey)
        Task {
            await loadOfferings()
            await checkEntitlements()
        }
    }

    // MARK: - Developer Access

    /// Call after Supabase auth restores to check if this is the developer.
    func checkDeveloperAccess(email: String?) {
        guard let email = email?.lowercased() else {
            isDeveloper = false
            return
        }
        isDeveloper = kestrelDeveloperEmails.contains(email)
    }

    // MARK: - Entitlements

    func checkEntitlements() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            isProUser = info.entitlements["kestrel_pro"]?.isActive == true
            hasSuiteBundle = info.entitlements["suite_bundle"]?.isActive == true
            if hasSuiteBundle { isProUser = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current ?? offerings["kestrel_pro"] else { return }
            monthlyProduct = offering.monthly?.storeProduct
            yearlyProduct = offering.annual?.storeProduct
            lifetimeProduct = offering.lifetime?.storeProduct
            if let bundlePkg = offering.package(identifier: "bundle") {
                bundleProduct = bundlePkg.storeProduct
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Purchase

    func purchaseMonthly() async -> Bool {
        guard let product = monthlyProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    func purchaseYearly() async -> Bool {
        guard let product = yearlyProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    func purchaseLifetime() async -> Bool {
        guard let product = lifetimeProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    func purchaseBundle() async -> Bool {
        guard let product = bundleProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    private func purchase(_ product: StoreProduct) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Purchases.shared.purchase(product: product)
            isProUser = result.customerInfo.entitlements["kestrel_pro"]?.isActive == true
            hasSuiteBundle = result.customerInfo.entitlements["suite_bundle"]?.isActive == true
            if !result.userCancelled && !isProOrBundle {
                proOverride = true
                UserDefaults.standard.set(true, forKey: Self.proOverrideKey)
            }
            isLoading = false
            return !result.userCancelled
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    private func simulatePurchase() -> Bool {
        proOverride = true
        UserDefaults.standard.set(true, forKey: Self.proOverrideKey)
        return true
    }

    // MARK: - Restore

    func restorePurchases() async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            isProUser = info.entitlements["kestrel_pro"]?.isActive == true
            hasSuiteBundle = info.entitlements["suite_bundle"]?.isActive == true
            isLoading = false
            return isProUser
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func canAccess(_ feature: KestrelFeature) -> Bool { isProOrBundle }

    /// Clears all locally-cached pro state and re-checks entitlements against
    /// the current App Store account. Call from Supabase sign-out so a stale
    /// `proOverride` (or developer-email match) can't leak Pro into a new login.
    func resetForLogout() async {
        proOverride = false
        UserDefaults.standard.removeObject(forKey: Self.proOverrideKey)
        isProUser = false
        hasSuiteBundle = false
        isDeveloper = false
        await checkEntitlements()
    }
}
