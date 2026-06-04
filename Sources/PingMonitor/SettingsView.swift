import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: Preferences
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var showBulkEdit: Bool = false
    @State private var bulkEditText: String = ""

    private var restoreHiddenTitle: String {
        let count = state.hiddenHostCount
        return count > 0 ? "Restore Hidden Hosts (\(count))" : "Restore Hidden Hosts"
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $preferences.pingIntervalSeconds, in: 1...300) {
                    Text("Ping every \(preferences.pingIntervalSeconds) s")
                }

                Toggle("Show status icons", isOn: $preferences.showStatusIcons)

                Picker("Latency decimals", selection: $preferences.latencyDecimals) {
                    Text("3").tag(0)
                    Text("3.1").tag(1)
                    Text("3.11").tag(2)
                    Text("3.111").tag(3)
                }
                .pickerStyle(.segmented)

                Toggle("Push timeout hosts to bottom", isOn: $preferences.pushTimeoutsToBottom)

                Toggle("Compact view (Status, Delay, Host only)", isOn: $preferences.compactMode)

                Toggle("Monochrome", isOn: $preferences.monochrome)

                Toggle("Dim", isOn: $preferences.dimMode)

                if preferences.dimMode {
                    HStack {
                        Text("Dim level")
                        Slider(value: $preferences.dimOpacity, in: 0.2...0.9) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "sun.min")
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "sun.max")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.setEnabled(newValue)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let error = loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Hosts") {
                Button {
                    bulkEditText = state.hostsAsBulkText()
                    showBulkEdit = true
                } label: {
                    Label("Edit Host List…", systemImage: "list.bullet.rectangle")
                }
                Button {
                    state.restoreAllHidden()
                } label: {
                    Label(restoreHiddenTitle, systemImage: "eye")
                }
                .disabled(!state.hasHiddenHosts)
            }

            Section("Layout") {
                Button {
                    NotificationCenter.default.post(name: .shrinkColumns, object: nil)
                } label: {
                    Label("Shrink Columns", systemImage: "arrow.right.and.line.vertical.and.arrow.left")
                }
                Button {
                    NotificationCenter.default.post(name: .resetColumns, object: nil)
                } label: {
                    Label("Reset Columns", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 620)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .background(
            Button("") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        )
        .sheet(isPresented: $showBulkEdit) {
            BulkEditHostsSheet(text: $bulkEditText, isPresented: $showBulkEdit)
                .environmentObject(state)
        }
    }
}

private struct BulkEditHostsSheet: View {
    @EnvironmentObject private var state: AppState
    @Binding var text: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Edit Host List")
                    .font(.headline)
                Spacer()
                Text("one per line — \"address\" or \"address, description\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))

            Divider()

            HStack {
                Text("Lines beginning with # are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func save() {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        state.replaceHosts(rawLines: lines)
        isPresented = false
    }
}
