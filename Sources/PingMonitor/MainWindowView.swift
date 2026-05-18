import SwiftUI
import AppKit

extension Notification.Name {
    static let resetColumnLayout = Notification.Name("JTsPingMonitor.resetColumnLayout")
}

private let columnCustomizationKey = "columnCustomizationData"

private struct PingRow: Identifiable {
    let id: UUID
    let address: String
    let label: String
    let stats: HostStats
    let status: HostStatus
    let latencyDecimals: Int
    let monochrome: Bool

    private var latencyFormat: String { "%.\(latencyDecimals)f" }

    var iconName: String {
        switch status {
        case .up: return monochrome ? "checkmark" : "checkmark.circle.fill"
        case .down: return monochrome ? "xmark" : "xmark.circle.fill"
        case .unknown: return "circle.dotted"
        }
    }

    var iconColor: Color {
        if monochrome { return .primary }
        switch status {
        case .up: return .green
        case .down: return .red
        case .unknown: return .secondary
        }
    }

    var errorColor: Color { monochrome ? .primary : .red }

    var delayText: String {
        if let ms = stats.currentMs { return String(format: latencyFormat, ms) }
        return "—"
    }

    var percentText: String {
        guard stats.sentCount > 0 else { return "—" }
        return String(format: "%.2f", stats.successRate)
    }

    var minText: String { stats.minMs.map { String(format: latencyFormat, $0) } ?? "—" }
    var avgText: String { stats.avgMs.map { String(format: latencyFormat, $0) } ?? "—" }
    var maxText: String { stats.maxMs.map { String(format: latencyFormat, $0) } ?? "—" }
    var errorText: String { stats.lastError ?? "" }
}

private enum EditField: Hashable { case address, label }

private enum SortColumn: String, CaseIterable {
    case host, description, delay, sent, percentOk, min, avg, max

    func comparator(ascending: Bool) -> KeyPathComparator<PingRow> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch self {
        case .host:        return KeyPathComparator(\PingRow.address, order: order)
        case .description: return KeyPathComparator(\PingRow.label, order: order)
        case .delay:       return KeyPathComparator(\PingRow.stats.currentMsSortable, order: order)
        case .sent:        return KeyPathComparator(\PingRow.stats.sentCount, order: order)
        case .percentOk:   return KeyPathComparator(\PingRow.stats.successRate, order: order)
        case .min:         return KeyPathComparator(\PingRow.stats.minMsSortable, order: order)
        case .avg:         return KeyPathComparator(\PingRow.stats.avgMsSortable, order: order)
        case .max:         return KeyPathComparator(\PingRow.stats.maxMsSortable, order: order)
        }
    }

    static func identify(from comparator: KeyPathComparator<PingRow>) -> SortColumn? {
        switch comparator.keyPath {
        case \PingRow.address:                  return .host
        case \PingRow.label:                    return .description
        case \PingRow.stats.currentMsSortable:  return .delay
        case \PingRow.stats.sentCount:          return .sent
        case \PingRow.stats.successRate:        return .percentOk
        case \PingRow.stats.minMsSortable:      return .min
        case \PingRow.stats.avgMsSortable:      return .avg
        case \PingRow.stats.maxMsSortable:      return .max
        default: return nil
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var statusStore: StatusStore
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferences: Preferences

    @State private var sortOrder: [KeyPathComparator<PingRow>] = [
        KeyPathComparator(\.address)
    ]
    @State private var selection: Set<UUID> = []
    @State private var showAddPopover: Bool = false
    @State private var columnCustomization = TableColumnCustomization<PingRow>()
    @AppStorage("sortColumn") private var sortColumnRaw: String = SortColumn.host.rawValue
    @AppStorage("sortAscending") private var sortAscending: Bool = true

    @State private var pendingResetIDs: Set<UUID> = []
    @State private var showResetConfirm: Bool = false

    @State private var editingHostID: UUID? = nil
    @State private var editAddress: String = ""
    @State private var editLabel: String = ""
    @State private var doubleClickMonitor: Any? = nil
    @State private var clickMonitor: Any? = nil
    @FocusState private var focusedField: EditField?

    private var rows: [PingRow] {
        let decimals = preferences.latencyDecimals
        let monochrome = preferences.monochrome
        let raw = state.hosts.map { host in
            PingRow(
                id: host.id,
                address: host.address,
                label: host.label,
                stats: statsStore.stats[host.id] ?? HostStats(),
                status: statusStore.statuses[host.id] ?? .unknown,
                latencyDecimals: decimals,
                monochrome: monochrome
            )
        }
        let sorted = raw.sorted(using: sortOrder)
        guard preferences.pushTimeoutsToBottom else { return sorted }
        let up = sorted.filter { if case .down = $0.status { return false } else { return true } }
        let down = sorted.filter { if case .down = $0.status { return true } else { return false } }
        return up + down
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("") { row in
                Image(systemName: row.iconName)
                    .foregroundStyle(row.iconColor)
            }
            .width(24)
            .customizationID("status")

            TableColumn("Host", value: \.address) { row in
                if editingHostID == row.id {
                    TextField("hostname or IP", text: $editAddress)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .address)
                        .onSubmit(commitEdit)
                        .onExitCommand(perform: cancelEdit)
                } else {
                    Text(row.address)
                }
            }
            .width(min: 60, ideal: 140)
            .customizationID("host")

            TableColumn("Description", value: \.label) { row in
                if editingHostID == row.id {
                    TextField("description", text: $editLabel)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .label)
                        .onSubmit(commitEdit)
                        .onExitCommand(perform: cancelEdit)
                } else {
                    Text(row.label)
                }
            }
            .width(min: 60, ideal: 180)
            .customizationID("description")

            TableColumn("Delay (ms)", value: \.stats.currentMsSortable) { row in
                Text(row.delayText)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 80)
            .customizationID("delay")

            TableColumn("Sent", value: \.stats.sentCount) { row in
                Text("\(row.stats.sentCount)").monospacedDigit()
            }
            .width(min: 40, ideal: 70)
            .customizationID("sent")

            TableColumn("% OK", value: \.stats.successRate) { row in
                Text(row.percentText).monospacedDigit()
            }
            .width(min: 40, ideal: 70)
            .customizationID("percentOk")

            TableColumn("Min (ms)", value: \.stats.minMsSortable) { row in
                Text(row.minText).monospacedDigit()
            }
            .width(min: 40, ideal: 70)
            .customizationID("min")

            TableColumn("Avg (ms)", value: \.stats.avgMsSortable) { row in
                Text(row.avgText).monospacedDigit()
            }
            .width(min: 40, ideal: 70)
            .customizationID("avg")

            TableColumn("Max (ms)", value: \.stats.maxMsSortable) { row in
                Text(row.maxText).monospacedDigit()
            }
            .width(min: 40, ideal: 70)
            .customizationID("max")

            TableColumn("Error") { row in
                Text(row.errorText).foregroundStyle(row.errorColor)
            }
            .width(min: 60, ideal: 140)
            .customizationID("error")
        }
        .frame(minWidth: 820, minHeight: 320)
        .opacity(preferences.dimMode ? preferences.dimOpacity : 1.0)
        .onDeleteCommand(perform: deleteSelected)
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Edit") { if let id = ids.first { beginEdit(id: id) } }
                .disabled(ids.count != 1)
            Button("Delete") { delete(ids: ids) }
            Button("Reset stats") { askReset(ids: ids) }
        } primaryAction: { ids in
            if let id = ids.first { beginEdit(id: id) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddPopover = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add host")
                .popover(isPresented: $showAddPopover, arrowEdge: .bottom) {
                    AddHostPopover(isPresented: $showAddPopover)
                        .environmentObject(state)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: deleteSelected) {
                    Label("Delete", systemImage: "minus.circle")
                }
                .disabled(selection.isEmpty)
                .help("Delete selected (⌫)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    askReset(ids: selection)
                } label: {
                    Label("Reset Stats", systemImage: "eraser")
                }
                .help(selection.isEmpty ? "Reset stats for all hosts" : "Reset stats for selected hosts")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Settings (⌘,)")
            }
        }
        .navigationTitle(navTitle)
        .onChange(of: focusedField) { _, newField in
            // Focus left both text fields while still in edit mode → abandon.
            if newField == nil && editingHostID != nil {
                cancelEdit()
            }
        }
        .onChange(of: preferences.showStatusIcons) { _, show in
            columnCustomization[visibility: "status"] = show ? .visible : .hidden
        }
        .onAppear {
            // Restore sort order
            if let col = SortColumn(rawValue: sortColumnRaw) {
                sortOrder = [col.comparator(ascending: sortAscending)]
            }
            // Restore column layout (order + visibility)
            if let data = UserDefaults.standard.data(forKey: columnCustomizationKey),
               let decoded = try? JSONDecoder().decode(TableColumnCustomization<PingRow>.self, from: data) {
                columnCustomization = decoded
            }
            // Re-apply showStatusIcons after restoring layout so the preference wins.
            columnCustomization[visibility: "status"] = preferences.showStatusIcons ? .visible : .hidden
            installDoubleClickMonitor()
        }
        .onDisappear {
            uninstallDoubleClickMonitor()
        }
        .onChange(of: sortOrder) { _, new in
            guard let first = new.first, let col = SortColumn.identify(from: first) else { return }
            sortColumnRaw = col.rawValue
            sortAscending = first.order == .forward
        }
        .onChange(of: columnCustomization) { _, new in
            if let data = try? JSONEncoder().encode(new) {
                UserDefaults.standard.set(data, forKey: columnCustomizationKey)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetColumnLayout)) { _ in
            columnCustomization = TableColumnCustomization<PingRow>()
            columnCustomization[visibility: "status"] = preferences.showStatusIcons ? .visible : .hidden
        }
        .confirmationDialog(resetTitle, isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive, action: confirmReset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetMessage)
        }
    }

    private var resetTitle: String {
        pendingResetIDs.isEmpty
            ? "Reset stats for all hosts?"
            : "Reset stats for \(pendingResetIDs.count) host\(pendingResetIDs.count == 1 ? "" : "s")?"
    }

    private var resetMessage: String {
        "Sent, % OK, Min, Avg, Max, and current Delay will all be cleared. This can't be undone."
    }

    private func askReset(ids: Set<UUID>) {
        pendingResetIDs = ids
        showResetConfirm = true
    }

    private func confirmReset() {
        if pendingResetIDs.isEmpty {
            statsStore.resetAll()
        } else {
            statsStore.reset(pendingResetIDs)
        }
        pendingResetIDs = []
    }

    private var navTitle: String { "JT's Ping Monitor" }

    private func deleteSelected() {
        delete(ids: selection)
        selection.removeAll()
    }

    private func delete(ids: Set<UUID>) {
        for id in ids {
            if let host = state.hosts.first(where: { $0.id == id }) {
                state.removeHost(host)
            }
        }
    }

    private func beginEdit(id: UUID, focus: EditField = .address) {
        guard let host = state.hosts.first(where: { $0.id == id }) else { return }
        editAddress = host.address
        editLabel = host.label
        editingHostID = id
        DispatchQueue.main.async { focusedField = focus }
        installClickMonitor()
    }

    private func commitEdit() {
        uninstallClickMonitor()
        guard let id = editingHostID,
              let index = state.hosts.firstIndex(where: { $0.id == id }) else {
            editingHostID = nil
            return
        }
        let newAddress = editAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLabel = editLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newAddress.isEmpty {
            state.hosts[index].address = newAddress
        }
        state.hosts[index].label = newLabel
        editingHostID = nil
        focusedField = nil
    }

    private func cancelEdit() {
        uninstallClickMonitor()
        editingHostID = nil
        focusedField = nil
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if !Self.clickIsInsideTextField(event: event) {
                DispatchQueue.main.async { cancelEdit() }
            }
            return event
        }
    }

    private func uninstallClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private static func clickIsInsideTextField(event: NSEvent) -> Bool {
        guard let window = event.window,
              let hit = window.contentView?.hitTest(event.locationInWindow) else { return false }
        var view: NSView? = hit
        while let current = view {
            if current is NSTextField || current is NSTextView { return true }
            view = current.superview
        }
        return false
    }

    private func installDoubleClickMonitor() {
        guard doubleClickMonitor == nil else { return }
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2,
                  editingHostID == nil,
                  Self.clickIsInsideTable(event: event) else { return event }
            DispatchQueue.main.async {
                if let id = selection.first {
                    beginEdit(id: id)
                }
            }
            return event
        }
    }

    private func uninstallDoubleClickMonitor() {
        if let monitor = doubleClickMonitor {
            NSEvent.removeMonitor(monitor)
            doubleClickMonitor = nil
        }
    }

    private static func clickIsInsideTable(event: NSEvent) -> Bool {
        guard let window = event.window,
              let hit = window.contentView?.hitTest(event.locationInWindow) else { return false }
        var view: NSView? = hit
        while let current = view {
            if current is NSScrollView { return true }
            view = current.superview
        }
        return false
    }
}

private struct AddHostPopover: View {
    @EnvironmentObject private var state: AppState
    @Binding var isPresented: Bool
    @State private var address: String = ""
    @State private var label: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Host").font(.headline)
            TextField("hostname or IP", text: $address)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(submit)
            TextField("description (optional)", text: $label)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(14)
    }

    private var canAdd: Bool {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return !state.hosts.contains { $0.address.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func submit() {
        guard canAdd else { return }
        state.addHost(address: address, label: label)
        isPresented = false
    }
}
