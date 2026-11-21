import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var store: RunStore
    @State private var newRepo = ""
    @State private var addError: String?
    @State private var isAdding = false
    @State private var token = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Repositories") {
                ForEach(Array(store.repos.enumerated()), id: \.element) { index, repo in
                    HStack {
                        Text(repo)
                        Spacer()
                        smallButton("chevron.up", disabled: index == 0) { store.moveRepository(repo, by: -1) }
                        smallButton("chevron.down", disabled: index == store.repos.count - 1) { store.moveRepository(repo, by: 1) }
                        smallButton("minus.circle", disabled: false) { store.removeRepository(repo) }
                    }
                }
                HStack {
                    TextField("owner/repo or GitHub URL", text: $newRepo)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(isAdding || newRepo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let addError {
                    Text(addError).font(.caption).foregroundStyle(.red)
                }
            }

            section("Authentication") {
                Text(tokenStatus).font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField("Personal access token (optional)", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveToken)
                    Button("Save", action: saveToken).disabled(token.isEmpty)
                }
                if store.tokenSource == .personal {
                    Button("Remove saved token and use gh CLI") { store.setToken(nil) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            section("Behavior") {
                Picker("Refresh every", selection: $store.pollInterval) {
                    ForEach([5, 10, 15, 30, 60, 300], id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) min").tag(seconds)
                    }
                }
                Text("Polls every 5 seconds while runs are in progress.").font(.caption).foregroundStyle(.secondary)
                Picker("Notifications", selection: $store.notifyMode) {
                    ForEach(NotifyMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tokenStatus: String {
        switch store.tokenSource {
        case .personal: "Using the saved personal access token."
        case .ghCLI: "Using the token from the gh CLI. Save a token below to override it."
        case nil: "No token found. Run `gh auth login`, or paste a token with repo and workflow scopes."
        }
    }

    private func add() {
        let input = newRepo
        isAdding = true
        addError = nil
        Task {
            do {
                try await store.addRepository(input)
                newRepo = ""
            } catch {
                addError = error.localizedDescription
            }
            isAdding = false
        }
    }

    private func saveToken() {
        guard !token.isEmpty else { return }
        store.setToken(token)
        token = ""
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func smallButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .disabled(disabled)
    }
}
