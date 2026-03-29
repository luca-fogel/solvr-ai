import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var saveSuccess = false
    @State private var showClearConfirm = false
    @AppStorage("selectedModel") private var selectedModel: String = "claude-sonnet-4-6"
    @AppStorage("maxTokens") private var maxTokens: Int = 2048

    var body: some View {
        NavigationStack {
            List {
                // API Key
                Section("API Configuration") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Anthropic API Key")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        HStack {
                            if showAPIKey {
                                TextField("sk-ant-...", text: $apiKey)
                                    .font(Theme.Fonts.math(14))
                                    .textContentType(.password)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("sk-ant-...", text: $apiKey)
                                    .font(Theme.Fonts.math(14))
                                    .textContentType(.password)
                            }

                            Button { showAPIKey.toggle() } label: {
                                Image(systemName: showAPIKey ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }

                    Button {
                        if KeychainManager.save(apiKey: apiKey) {
                            saveSuccess = true
                            Haptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                saveSuccess = false
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: saveSuccess ? "checkmark.circle.fill" : "key.fill")
                            Text(saveSuccess ? "Saved" : "Save API Key")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(saveSuccess ? Theme.Colors.success : Theme.Colors.accent)
                    }
                }

                // Model
                Section("Model") {
                    Picker("Model", selection: $selectedModel) {
                        Text("Claude Opus 4.6").tag("claude-opus-4-6")
                        Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                    }
                    .tint(Theme.Colors.accent)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(maxTokens)")
                                .foregroundStyle(Theme.Colors.accent)
                                .font(Theme.Fonts.math(14))
                        }
                        Slider(
                            value: Binding(
                                get: { Double(maxTokens) },
                                set: { maxTokens = Int($0) }
                            ),
                            in: 512...4096,
                            step: 256
                        )
                        .tint(Theme.Colors.accent)
                    }
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
                        Text("2.0.0")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    HStack {
                        Text("Powered by")
                        Spacer()
                        Text("Claude API")
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
            .onAppear {
                apiKey = KeychainManager.retrieve() ?? ""
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
