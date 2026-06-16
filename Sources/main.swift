import AppKit
import Foundation
import SwiftUI

private enum DualMode: String, Equatable {
    case uhd
    case fhd
    case unknown

    var title: String {
        switch self {
        case .uhd: return "UHD / 4K"
        case .fhd: return "FHD / 1080P"
        case .unknown: return "未知"
        }
    }

    var detail: String {
        switch self {
        case .uhd: return "Normal Mode"
        case .fhd: return "Dual Mode"
        case .unknown: return "未识别"
        }
    }

    var writeValue: String? {
        switch self {
        case .uhd: return "000"
        case .fhd: return "001"
        case .unknown: return nil
        }
    }

    var opposite: DualMode {
        switch self {
        case .uhd: return .fhd
        case .fhd: return .uhd
        case .unknown: return .fhd
        }
    }
}

private struct MonitorSnapshot {
    let connected: Bool
    let mode: DualMode
    let raw002E0: String
    let raw00190: String
    let message: String

    var hasCompleteStatus: Bool {
        raw002E0 != "NO_RESPONSE" && raw00190 != "NO_RESPONSE"
    }
}

private enum MSIController {
    static func readSnapshot(retries: Int = 2) -> MonitorSnapshot {
        var bestValues: [String: String] = [:]

        for attempt in 0...retries {
            if attempt > 0 {
                Thread.sleep(forTimeInterval: 0.45)
            }

            let status = MSIHID.readStatus()
            let values = status.values

            if status.connected {
                bestValues["connected"] = "1"
            } else if bestValues["connected"] == nil {
                bestValues["connected"] = "0"
            }

            for key in [MSIHID.modeRegister, MSIHID.confirmationRegister] {
                guard let value = values[key] else { continue }
                if value != "NO_RESPONSE" || bestValues[key] == nil {
                    bestValues[key] = value
                }
            }

            if bestValues["connected"] == "1",
               bestValues[MSIHID.modeRegister] != nil,
               bestValues[MSIHID.modeRegister] != "NO_RESPONSE",
               bestValues[MSIHID.confirmationRegister] != nil,
               bestValues[MSIHID.confirmationRegister] != "NO_RESPONSE" {
                break
            }
        }

        let raw002E0 = bestValues[MSIHID.modeRegister] ?? "NO_RESPONSE"
        let raw00190 = bestValues[MSIHID.confirmationRegister] ?? "NO_RESPONSE"
        let connected = bestValues["connected"] == "1"
        let mode = decodeMode(raw002E0: raw002E0, raw00190: raw00190)

        return MonitorSnapshot(
            connected: connected,
            mode: mode,
            raw002E0: raw002E0,
            raw00190: raw00190,
            message: connected ? (mode == .unknown ? "已连接，但模式值未识别" : "已连接") : "未找到 MSI Monitor MPG 274URDFW E16M"
        )
    }

    static func setMode(_ mode: DualMode) -> Bool {
        guard let value = mode.writeValue else {
            return false
        }

        return MSIHID.setModeValue(value)
    }

    private static func decodeMode(raw002E0: String, raw00190: String) -> DualMode {
        if raw002E0.hasSuffix("000") {
            return .uhd
        }
        if raw002E0.hasSuffix("001") {
            return .fhd
        }
        if raw00190.hasSuffix("001") {
            return .uhd
        }
        if raw00190.hasSuffix("000") {
            return .fhd
        }
        return .unknown
    }
}

@MainActor
private final class AppState: ObservableObject {
    @Published var connected = false
    @Published var mode: DualMode = .unknown
    @Published var raw002E0 = "-"
    @Published var raw00190 = "-"
    @Published var message = "正在读取..."
    @Published var busy = false

    func refresh() {
        guard !busy else { return }
        busy = true
        message = "正在读取..."

        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = MSIController.readSnapshot()
            DispatchQueue.main.async {
                self.apply(snapshot)
                self.busy = false
            }
        }
    }

    func toggle() {
        setMode(mode.opposite)
    }

    func setMode(_ target: DualMode) {
        guard !busy else { return }
        busy = true
        message = "正在切换到 \(target.title)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let sent = MSIController.setMode(target)
            guard sent else {
                DispatchQueue.main.async {
                    self.message = "发送失败，未找到可用 HID 设备"
                    self.busy = false
                }
                return
            }

            var latest = MSIController.readSnapshot(retries: 1)
            let delays: [TimeInterval] = [2.0, 2.0, 2.5, 2.5, 3.0]

            for (index, delay) in delays.enumerated() {
                Thread.sleep(forTimeInterval: delay)
                latest = MSIController.readSnapshot(retries: 1)

                DispatchQueue.main.async {
                    self.apply(latest)
                    if latest.mode == target && latest.hasCompleteStatus {
                        self.message = "已切换到 \(target.title)"
                    } else if latest.mode == target {
                        self.message = "已切换，正在刷新状态... \(index + 1)/\(delays.count)"
                    } else {
                        self.message = "正在确认切换结果... \(index + 1)/\(delays.count)"
                    }
                }

                if latest.mode == target && latest.hasCompleteStatus {
                    break
                }
            }

            DispatchQueue.main.async {
                self.apply(latest)
                if latest.mode == target && latest.hasCompleteStatus {
                    self.message = "已切换到 \(target.title)"
                } else if latest.mode == target {
                    self.message = "已切换到 \(target.title)，但状态未完全刷新"
                } else {
                    self.message = "已发送命令，但未自动确认，请稍后刷新"
                }
                self.busy = false
            }
        }
    }

    private func apply(_ snapshot: MonitorSnapshot) {
        connected = snapshot.connected
        mode = snapshot.mode
        raw002E0 = snapshot.raw002E0
        raw00190 = snapshot.raw00190
        message = snapshot.message
    }
}

private struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var showInfo = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MPG 274U Dual Mode")
                        .font(.system(size: 20, weight: .bold))
                    HStack(spacing: 7) {
                        Circle()
                            .fill(state.connected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(state.message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("刷新状态")
            }

            PillModeToggle(mode: state.mode) { target in
                state.setMode(target)
            }
            .frame(height: 76)

            HStack {
                if showInfo {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("002E0: \(state.raw002E0)")
                        Text("00190: \(state.raw00190)")
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showInfo.toggle()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showInfo ? Color.accentColor : .secondary)
                .help(showInfo ? "隐藏详细信息" : "显示详细信息")
            }
            .frame(minHeight: showInfo ? 34 : 28)
        }
        .padding(20)
        .frame(width: 380)
        .disabled(state.busy)
        .overlay {
            if state.busy {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .onAppear {
            state.refresh()
        }
    }

}

private struct PillModeToggle: View {
    let mode: DualMode
    let onSelect: (DualMode) -> Void

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 5
            let segmentWidth = (proxy.size.width - inset * 2) / 2
            let activeOffset = mode == .fhd ? segmentWidth : 0
            let hasKnownMode = mode != .unknown

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: segmentWidth, height: proxy.size.height - inset * 2)
                    .offset(x: inset + activeOffset, y: 0)
                    .opacity(hasKnownMode ? 1 : 0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: mode)

                HStack(spacing: 0) {
                    PillSegment(
                        title: "UHD",
                        subtitle: "4K",
                        icon: "display",
                        active: mode == .uhd
                    ) {
                        onSelect(.uhd)
                    }

                    PillSegment(
                        title: "FHD",
                        subtitle: "320Hz",
                        icon: "bolt.display",
                        active: mode == .fhd
                    ) {
                        onSelect(.fhd)
                    }
                }
                .padding(inset)
            }
        }
    }
}

private struct PillSegment: View {
    let title: String
    let subtitle: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 21, weight: .heavy))
                    Text(subtitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(active ? .white.opacity(0.85) : .secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(active ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@main
private struct MPGDualModeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
