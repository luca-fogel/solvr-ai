import SwiftUI
import SwiftData
import SolvrCore

struct SettingsView: View {

    /// `1.0.0 (1)`, from `Info.plist`.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showClearConfirm = false
    @AppStorage(DemoMode.defaultsKey) private var demoMode: Bool = false

    var body: some View {
        NavigationStack {
            List {
                // What used to be a three-way backend picker. There is one
                // backend now, so this reports rather than asks -- but it still
                // has to report, because the on-device model can be unavailable
                // for reasons that are the user's to fix and invisible until a
                // solve fails.
                Section("Where answers come from") {
                    Text("Apple Intelligence, running on this device. No API key, "
                         + "no server, no network — nothing leaves it. Photos are "
                         + "read by on-device text recognition first, which is "
                         + "weaker on handwriting than on print.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if let reason = ProviderFactory.onDeviceUnavailableReason {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(reason)
                                .font(Theme.Fonts.caption)
                        }
                    } else {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.success)
                            Text("Ready.")
                                .font(Theme.Fonts.caption)
                        }
                    }
                }

                #if DEBUG
                // Debug only. In Release there is no fixture provider to reach:
                // `ProviderFactory.current()` has no demo branch compiled into
                // it, so this toggle would toggle nothing. A switch that lies
                // about what it does is worse than no switch.
                Section {
                    Toggle("Demo mode", isOn: $demoMode)
                    Text("Answers come from bundled sample data instead of the "
                         + "on-device model. Every problem shown is synthetic, "
                         + "and the results screen says so while this is on. "
                         + "Development builds only.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } header: {
                    Text("Try it without a model")
                }
                #endif

                Section("Model") {
                    // No picker and no token slider. The system supplies the
                    // model, and its context window is a fixed 4,096 tokens
                    // covering prompt *and* completion -- so the "Max Tokens"
                    // slider that used to sit here was adjusting a number the
                    // on-device provider never reads.
                    Text("Apple's on-device model. Nothing to configure — the "
                         + "system provides it, there is no alternative to pick, "
                         + "and its context window is fixed.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                // Tab Order
                Section("Tab Order") {
                    Text("Drag to reorder how tabs appear in results")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ForEach(TabOrderManager.shared.orderedTabs.filter { $0 != .chat }) { tab in
                        HStack(spacing: 14) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 24)

                            Text(tab.label)
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Spacer()

                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        TabOrderManager.shared.moveTab(from: source, to: destination)
                        Haptics.light()
                    }

                    Button {
                        TabOrderManager.shared.resetToDefault()
                        Haptics.light()
                    } label: {
                        Text("Reset to Default Order")
                            .font(Theme.Fonts.callout)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .environment(\.editMode, .constant(.active))

                // Data
                Section("Data") {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All History")
                        }
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("solvr.")
                            .font(Theme.Fonts.title3)
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        // Read from the bundle, not typed here. This said 2.0.0
                        // while the project shipped 1.0 -- a number the app
                        // asserts about itself and cannot check is a number that
                        // drifts.
                        Text(Self.versionString)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    HStack {
                        Text("Answers from")
                        Spacer()
                        Text(demoMode ? "Bundled fixtures" : "This device")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .alert("Clear History", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) { clearHistory() }
            } message: {
                Text("This will permanently delete all solved problems. This cannot be undone.")
            }
            .frame(minWidth: Platform.isMac ? 500 : nil, minHeight: Platform.isMac ? 400 : nil)
        }
    }

    private func clearHistory() {
        do {
            try modelContext.delete(model: Problem.self)
            Haptics.success()
        } catch {}
    }
}
