//
//  MacDashboardView.swift
//  Kestrel Mac
//
//  macOS server dashboard — multi-column grid layout that takes advantage
//  of the Mac screen width. Same data as iOS ServerDetailView dashboard.
//

import SwiftUI
import Charts

// MARK: - Mac Dashboard View

struct MacDashboardView: View {
    let server: Server

    @EnvironmentObject var sessionManager: SSHSessionManager

    @State private var statsEngine: ServerStatsEngine?
    @State private var cpuHistory: [CPUReading] = []
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var processSearchText = ""
    @State private var processSortKey: ProcessSortKey = .cpu
    @State private var serviceFilter: ServiceFilter = .all
    @State private var processToKill: ServerStatsEngine.ProcessInfo?
    @State private var showingKillConfirmation = false
    @State private var lastRefreshed: Date?

    private var session: SSHSession? {
        sessionManager.activeSession(for: server.id)
    }

    private var isConnected: Bool {
        session?.isConnected == true
    }

    private var stats: ServerStatsEngine.Stats? {
        statsEngine?.stats
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if isConnected {
                if stats != nil {
                    dashboardGrid
                } else {
                    skeletonGrid
                }
            } else {
                offlineState
            }
        }
        .proGated(feature: .serverDashboard)
        .background(KestrelColors.background)
        .onAppear { startStatsIfConnected() }
        .onDisappear { statsEngine?.stopPolling() }
        .onChange(of: session?.isConnected) { _, connected in
            if connected == true { startStatsIfConnected() }
            else { statsEngine?.stopPolling() }
        }
        .onChange(of: statsEngine?.stats?.cpuPercent) { _, cpu in
            if let cpu { appendCPUReading(cpu) }
            lastRefreshed = .now
        }
        .confirmationDialog(
            "Kill Process",
            isPresented: $showingKillConfirmation,
            titleVisibility: .visible
        ) {
            if let proc = processToKill {
                Button("Kill (SIGTERM)", role: .destructive) {
                    killProcess(pid: proc.pid, signal: "TERM")
                }
                Button("Force Kill (SIGKILL)", role: .destructive) {
                    killProcess(pid: proc.pid, signal: "KILL")
                }
                Button("Cancel", role: .cancel) { processToKill = nil }
            }
        } message: {
            if let proc = processToKill {
                Text("Terminate \(proc.command) (PID \(proc.pid))?")
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Server name + OS
            HStack(spacing: 6) {
                Text(server.name)
                    .font(KestrelFonts.monoBold(14))
                    .foregroundStyle(KestrelColors.textPrimary)
                if let stats, !stats.osName.isEmpty {
                    Text(stats.osName)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }

            Spacer()

            // Uptime
            if let stats, !stats.uptime.isEmpty && stats.uptime != "—" {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Text("up \(stats.uptime)")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(KestrelColors.phosphorGreenDim)
                .clipShape(Capsule())
            }

            // Connect / Disconnect
            Button {
                if isConnected { disconnect() } else { connect() }
            } label: {
                HStack(spacing: 4) {
                    if isConnecting {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Image(systemName: isConnected ? "bolt.slash.fill" : "bolt.fill")
                            .font(.system(size: 10))
                    }
                    Text(isConnecting ? "Connecting…" : isConnected ? "Disconnect" : "Connect")
                        .font(KestrelFonts.mono(10))
                }
                .foregroundStyle(isConnected ? KestrelColors.red : KestrelColors.phosphorGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((isConnected ? KestrelColors.red : KestrelColors.phosphorGreen).opacity(0.1))
                .clipShape(Capsule())
            }
            .disabled(isConnecting)

            // Last refreshed
            if let lastRefreshed {
                Text(lastRefreshed, style: .time)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(KestrelColors.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KestrelColors.cardBorder).frame(height: 1)
        }
    }

    // MARK: - Dashboard Grid

    private var dashboardGrid: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Top row: CPU (wide) + Memory
                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 380)),
                    GridItem(.flexible(minimum: 220)),
                ], spacing: 12) {
                    cpuCard
                    memoryCard
                }

                // Middle row: Disk + Network + Services
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 220), spacing: 12)
                ], spacing: 12) {
                    diskCard
                    networkCard
                    servicesCard
                }

                // Bottom: full-width processes table
                processesCard
            }
            .padding(16)
        }
    }

    // MARK: - CPU Card

    private var cpuCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CPU USAGE")
                        .font(KestrelFonts.mono(9))
                        .tracking(1.2)
                        .foregroundStyle(KestrelColors.textFaint)
                    Spacer()
                    // Live indicator
                    Circle()
                        .fill(KestrelColors.phosphorGreen)
                        .frame(width: 5, height: 5)
                        .shadow(color: KestrelColors.phosphorGreen.opacity(0.6), radius: 3)
                }

                HStack(spacing: 16) {
                    // Ring gauge
                    cpuRingGauge(size: 52)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(stats?.cpuPercent ?? 0))")
                                .font(KestrelFonts.display(28, weight: .bold))
                                .foregroundStyle(cpuColor)
                            Text("%")
                                .font(KestrelFonts.mono(13))
                                .foregroundStyle(KestrelColors.textMuted)
                        }

                        // Load averages
                        if let s = stats {
                            HStack(spacing: 10) {
                                loadItem("1m", s.load1m)
                                loadItem("5m", s.load5m)
                                loadItem("15m", s.load15m)
                            }
                        }
                    }

                    Spacer()

                    // Sparkline
                    if cpuHistory.count > 1 {
                        cpuSparkline
                            .frame(width: 140, height: 48)
                    }
                }
            }
        }
    }

    private func cpuRingGauge(size: CGFloat) -> some View {
        let progress = (stats?.cpuPercent ?? 0) / 100.0
        return ZStack {
            Circle()
                .stroke(KestrelColors.textFaint.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(cpuColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
        .frame(width: size, height: size)
    }

    private var cpuSparkline: some View {
        Chart(cpuHistory) { reading in
            LineMark(x: .value("T", reading.timestamp), y: .value("CPU", reading.value))
                .foregroundStyle(cpuColor.gradient)
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("T", reading.timestamp), y: .value("CPU", reading.value))
                .foregroundStyle(
                    LinearGradient(
                        colors: [cpuColor.opacity(0.2), cpuColor.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func loadItem(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%.2f", value))
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(KestrelFonts.mono(8))
                .foregroundStyle(KestrelColors.textFaint)
        }
    }

    private var cpuColor: SwiftUI.Color {
        guard let cpu = stats?.cpuPercent else { return KestrelColors.phosphorGreen }
        if cpu > 90 { return KestrelColors.red }
        if cpu > 70 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    // MARK: - Memory Card

    private var memoryCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("MEMORY")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(KestrelColors.textFaint)

                if let s = stats {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(formatBytes(s.memoryUsed))
                            .font(KestrelFonts.display(22, weight: .bold))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Text("/ \(formatBytes(s.memoryTotal))")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                    }

                    // Segmented bar
                    memoryBar(s)

                    HStack(spacing: 8) {
                        legendDot(KestrelColors.phosphorGreen, "Used")
                        legendDot(KestrelColors.blue, "Cached")
                        legendDot(KestrelColors.textFaint.opacity(0.3), "Free")
                        Spacer()
                        Text("\(Int(s.memoryUsedPercent))%")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(memColor(s.memoryUsedPercent))
                    }
                }
            }
        }
    }

    private func memoryBar(_ s: ServerStatsEngine.Stats) -> some View {
        let total = max(Double(s.memoryTotal), 1)
        let usedFrac = Double(s.memoryUsed) / total
        let freeFrac = Double(max(total - Double(s.memoryUsed), 0)) / total
        let cachedFrac = max(0, 1.0 - usedFrac - freeFrac)

        return GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(KestrelColors.phosphorGreen)
                    .frame(width: geo.size.width * usedFrac)
                RoundedRectangle(cornerRadius: 3)
                    .fill(KestrelColors.blue)
                    .frame(width: geo.size.width * cachedFrac)
                RoundedRectangle(cornerRadius: 3)
                    .fill(KestrelColors.textFaint.opacity(0.3))
                    .frame(width: geo.size.width * freeFrac)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    private func legendDot(_ color: SwiftUI.Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(KestrelFonts.mono(8)).foregroundStyle(KestrelColors.textFaint)
        }
    }

    private func memColor(_ percent: Double) -> SwiftUI.Color {
        if percent > 90 { return KestrelColors.red }
        if percent > 70 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    // MARK: - Disk Card

    private var diskCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("DISK")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(KestrelColors.textFaint)

                if let s = stats {
                    ForEach(s.diskMounts) { mount in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(mount.mountPoint)
                                    .font(KestrelFonts.mono(11))
                                    .foregroundStyle(KestrelColors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(mount.usedPercent))%")
                                    .font(KestrelFonts.mono(10))
                                    .foregroundStyle(diskColor(mount.usedPercent))
                                    .monospacedDigit()
                                if mount.usedPercent > 85 {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(KestrelColors.red)
                                }
                            }
                            MiniBar(
                                progress: mount.usedPercent / 100,
                                color: diskColor(mount.usedPercent)
                            )
                            Text("\(formatBytes(mount.used)) / \(formatBytes(mount.size))")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                        .padding(.vertical, 2)
                    }

                    if s.diskMounts.isEmpty {
                        Text("No mounts detected")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }
            }
        }
    }

    private func diskColor(_ percent: Double) -> SwiftUI.Color {
        if percent > 85 { return KestrelColors.red }
        if percent > 70 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    // MARK: - Network Card

    private var networkCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("NETWORK")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(KestrelColors.textFaint)

                if let s = stats {
                    ForEach(s.netInterfaces) { iface in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(iface.name)
                                .font(KestrelFonts.monoBold(11))
                                .foregroundStyle(KestrelColors.textPrimary)
                            HStack(spacing: 14) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 8))
                                        .foregroundStyle(KestrelColors.phosphorGreen)
                                    Text(String(format: "%.2f Mbps", iface.rxMbps))
                                        .font(KestrelFonts.mono(10))
                                        .foregroundStyle(KestrelColors.textMuted)
                                }
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 8))
                                        .foregroundStyle(KestrelColors.blue)
                                    Text(String(format: "%.2f Mbps", iface.txMbps))
                                        .font(KestrelFonts.mono(10))
                                        .foregroundStyle(KestrelColors.textMuted)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if s.netInterfaces.isEmpty {
                        Text("No interfaces detected")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }
            }
        }
    }

    // MARK: - Services Card

    private var servicesCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SERVICES")
                        .font(KestrelFonts.mono(9))
                        .tracking(1.2)
                        .foregroundStyle(KestrelColors.textFaint)
                    Spacer()
                    Picker("", selection: $serviceFilter) {
                        ForEach(ServiceFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // Placeholder services — replace with real systemctl data
                ForEach(placeholderServices, id: \.name) { svc in
                    if serviceFilter == .all
                        || (serviceFilter == .running && svc.isRunning)
                        || (serviceFilter == .failed && !svc.isRunning)
                    {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(svc.isRunning ? KestrelColors.phosphorGreen : KestrelColors.red)
                                .frame(width: 6, height: 6)
                            Text(svc.name)
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textMuted)
                            Spacer()
                            if svc.isRunning {
                                Button {
                                    executeServiceCommand("sudo systemctl restart \(svc.name)")
                                } label: {
                                    Text("Restart")
                                        .font(KestrelFonts.mono(9))
                                        .foregroundStyle(KestrelColors.amber)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    executeServiceCommand("sudo systemctl stop \(svc.name)")
                                } label: {
                                    Text("Stop")
                                        .font(KestrelFonts.mono(9))
                                        .foregroundStyle(KestrelColors.red)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    executeServiceCommand("sudo systemctl start \(svc.name)")
                                } label: {
                                    Text("Start")
                                        .font(KestrelFonts.mono(9))
                                        .foregroundStyle(KestrelColors.phosphorGreen)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Processes Card (full width)

    private var processesCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TOP PROCESSES")
                        .font(KestrelFonts.mono(9))
                        .tracking(1.2)
                        .foregroundStyle(KestrelColors.textFaint)

                    Spacer()

                    // Search
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(KestrelColors.textFaint)
                        TextField("Filter…", text: $processSearchText)
                            .font(KestrelFonts.mono(10))
                            .textFieldStyle(.plain)
                            .frame(width: 120)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                    )
                }

                if let s = stats {
                    // Table header (sortable)
                    HStack(spacing: 0) {
                        sortableHeader("NAME", key: .name, flex: true)
                        sortableHeader("PID", key: .pid, width: 60)
                        sortableHeader("USER", key: .user, width: 70)
                        sortableHeader("CPU%", key: .cpu, width: 60)
                        sortableHeader("MEM%", key: .mem, width: 60)
                        Text("")
                            .frame(width: 40)
                    }

                    let filtered = filteredProcesses(s.processes)
                    ForEach(filtered.prefix(20)) { proc in
                        HStack(spacing: 0) {
                            Text(processName(proc.command))
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(proc.pid)")
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textFaint)
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                            Text("—")
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textFaint)
                                .frame(width: 70, alignment: .trailing)
                            Text(String(format: "%.1f", proc.cpuPercent))
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(proc.cpuPercent > 50 ? KestrelColors.red : KestrelColors.textMuted)
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                            Text(String(format: "%.1f", proc.memPercent))
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(proc.memPercent > 50 ? KestrelColors.amber : KestrelColors.textMuted)
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                            Button {
                                processToKill = proc
                                showingKillConfirmation = true
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(KestrelColors.textFaint)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 40)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func sortableHeader(_ title: String, key: ProcessSortKey, flex: Bool = false, width: CGFloat? = nil) -> some View {
        Button {
            processSortKey = key
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if processSortKey == key {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
            }
            .font(KestrelFonts.mono(9))
            .foregroundStyle(processSortKey == key ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: flex ? .infinity : nil, alignment: .leading)
        .frame(width: flex ? nil : width, alignment: .trailing)
    }

    private func filteredProcesses(_ procs: [ServerStatsEngine.ProcessInfo]) -> [ServerStatsEngine.ProcessInfo] {
        var result = procs
        if !processSearchText.isEmpty {
            let q = processSearchText.lowercased()
            result = result.filter { $0.command.lowercased().contains(q) }
        }
        switch processSortKey {
        case .name: result.sort { $0.command < $1.command }
        case .pid: result.sort { $0.pid < $1.pid }
        case .user: break
        case .cpu: result.sort { $0.cpuPercent > $1.cpuPercent }
        case .mem: result.sort { $0.memPercent > $1.memPercent }
        }
        return result
    }

    private func processName(_ command: String) -> String {
        let components = command.components(separatedBy: "/")
        let name = components.last ?? command
        return name.components(separatedBy: " ").first ?? name
    }

    // MARK: - Skeleton Grid

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    DashboardCard {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(KestrelColors.textFaint.opacity(0.15))
                                .frame(width: 70, height: 10)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(KestrelColors.textFaint.opacity(0.1))
                                .frame(height: 18)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(KestrelColors.textFaint.opacity(0.08))
                                .frame(height: 6)
                        }
                    }
                    .redacted(reason: .placeholder)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Offline State

    private var offlineState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32))
                .foregroundStyle(KestrelColors.textFaint)
            Text("Server Offline")
                .font(KestrelFonts.display(16, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)
            Text("Connect to view live metrics")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func connect() {
        isConnecting = true
        connectionError = nil
        Task {
            do { _ = try await sessionManager.openSession(for: server) }
            catch { connectionError = error.localizedDescription }
            isConnecting = false
        }
    }

    private func disconnect() {
        statsEngine?.stopPolling()
        statsEngine = nil
        sessionManager.closeSession(serverID: server.id)
    }

    private func startStatsIfConnected() {
        guard session?.isConnected == true, statsEngine == nil else { return }
        statsEngine = sessionManager.statsEngine(for: server.id)
    }

    private func appendCPUReading(_ value: Double) {
        cpuHistory.append(CPUReading(timestamp: .now, value: value))
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
    }

    private func killProcess(pid: Int, signal: String) {
        Task {
            _ = try? await session?.execute("kill -\(signal) \(pid)")
        }
        processToKill = nil
    }

    private func executeServiceCommand(_ command: String) {
        Task { _ = try? await session?.execute(command) }
    }
}

// MARK: - Supporting Types

struct CPUReading: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum ProcessSortKey {
    case name, pid, user, cpu, mem
}

enum ServiceFilter: String, CaseIterable {
    case all = "All"
    case running = "Running"
    case failed = "Failed"
}

struct PlaceholderService {
    let name: String
    let isRunning: Bool
}

private let placeholderServices: [PlaceholderService] = [
    .init(name: "sshd", isRunning: true),
    .init(name: "nginx", isRunning: true),
    .init(name: "docker", isRunning: true),
    .init(name: "postgresql", isRunning: false),
    .init(name: "redis", isRunning: true),
]

// MARK: - Dashboard Card Component

struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
    }
}

// MARK: - Byte Formatter

private func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var i = 0
    while value >= 1024 && i < units.count - 1 {
        value /= 1024
        i += 1
    }
    return i == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[i])
}
