import SwiftUI
import SwiftData
import SolvrCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var saveSuccess = false
    @State private var saveFailed = false
    @State private var showClearConfirm = false
    @AppStorage(ProviderFactory.backendKey) private var backend: String = ProviderFactory.Backend.anthropic.rawValue
    @AppStorage(ProviderFactory.localServerURLKey) private var localServerURL: String = ""
    @AppStorage(ProviderFactory.localServerModelKey) private var localServerModel: String = ""
    @State private var localToken: String = ""
    @State private var localTokenSaved = false
    @AppStorage("selectedModel") private var selectedModel: String = "claude-opus-5"
    @AppStorage("maxTokens") private var maxTokens: Int = 2048
    @AppStorage(DemoMode.defaultsKey) private var demoMode: Bool = false

    private var selectedBackend: ProviderFactory.Backend {
        ProviderFactory.Backend(rawValue: backend) ?? .anthropic
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Where answers come from") {
                    Picker("Backend", selection: $backend) {
                        ForEach(ProviderFactory.Backend.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedBackend.detail)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    // The on-device model can be unavailable for three reasons,
                    // and all three are the user's to fix rather than ours. Saying
                    // nothing until a solve fails would be the unhelpful option.
                    if selectedBackend == .appleOnDevice,
                       let reason = ProviderFactory.onDeviceUnavailableReason {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(reason)
                                .font(Theme.Fonts.caption)
                        }
                    }
                }

                if selectedBackend == .localServer {
                    Section("My server") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Address")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("https://my-mac.example.ts.net", text: $localServerURL)
                                .font(Theme.Fonts.math(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            // Not a compiled constant, and not committed: a home
                            // hostname or tailnet address belongs to the person
                            // who owns it, not to the repository.
                            Text("An OpenAI-compatible endpoint. Plain http works on "
                                 + "a local network; over a tailnet prefer https so "
                                 + "the token is not sent in the clear.")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Model name")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("solvr-qwen3-4b", text: $localServerModel)
                                .font(Theme.Fonts.math(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Token (optional)")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            SecureField("bearer token", text: $localToken)
                                .font(Theme.Fonts.math(14))
                            Button {
                                // Its own Keychain account, so saving this cannot
                                // overwrite the Anthropic key.
                                localTokenSaved = KeychainManager.save(
                                    apiKey: localToken, for: .localServer)
                            } label: {
                                Label(localTokenSaved ? "Saved" : "Save token",
                                      systemImage: localTokenSaved
                                        ? "checkmark.circle.fill" : "key.fill")
                            }
                            .disabled(localToken.isEmpty)
                            .tint(Theme.Colors.accent)
                        }
                    }
                }

                // API Key. Shown for the backend that needs one; the on-device
                // model and a token-free local server do not.
                if selectedBackend == .anthropic {
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
                        // A failed save has to be visible. The Keychain is the
                        // only place the key is kept, so "it did not save" means
                        // the app cannot work -- silently doing nothing here
                        // left people staring at a button that appeared broken.
                        if KeychainManager.save(apiKey: apiKey) {
                            saveSuccess = true
                            saveFailed = false
                            Haptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                saveSuccess = false
                            }
                        } else {
                            saveFailed = true
                            saveSuccess = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: saveSuccess ? "checkmark.circle.fill"
                                  : saveFailed ? "exclamationmark.triangle.fill" : "key.fill")
                            Text(saveSuccess ? "Saved" : saveFailed ? "Could not save" : "Save API Key")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(saveSuccess ? Theme.Colors.success
                                         : saveFailed ? Theme.Colors.error : Theme.Colors.accent)
                    }

                    if saveFailed {
                        Text("The key could not be written to the Keychain, so it has not "
                             + "been stored anywhere. It is never kept in plain text as a "
                             + "fallback. Try again, or restart the app.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
                }

                // Model
                Section {
                    Toggle("Demo mode", isOn: $demoMode)
                    Text("Answers come from bundled sample data instead of the API. "
                         + "No key needed, nothing leaves the device, and every "
                         + "problem shown is synthetic.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } header: {
                    Text("Try it without a key")
                }

                Section("Model") {
                    if selectedBackend == .appleOnDevice {
                        // There is no model to choose: the OS supplies one.
                        Text("Apple's on-device model. Nothing to configure — the "
                             + "system provides it and there is no alternative to pick.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        Picker("Model", selection: $selectedModel) {
                            Text("Claude Opus 5").tag("claude-opus-5")
                            Text("Claude Sonnet 5").tag("claude-sonnet-5")
                            Text("Claude Haiku 4.5").tag("claude-haiku-4-5")
                        }
                        .tint(Theme.Colors.accent)
                    }

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
                        Text("Answers from")
                        Spacer()
                        Text(demoMode ? "Bundled fixtures" : selectedBackend.displayName)
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
