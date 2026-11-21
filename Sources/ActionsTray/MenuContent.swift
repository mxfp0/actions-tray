import SwiftUI

struct MenuContent: View {
    @Bindable var store: RunStore
    @State private var showingSettings = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    if showingSettings {
                        SettingsView(store: store)
                    } else {
                        RunsView(store: store, openSettings: { showingSettings = true })
                    }
                }
                .padding(10)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 80), 560))
            Divider()
            footer
        }
        .frame(width: 420)
    }

    private var header: some View {
        HStack {
            Text(showingSettings ? "Settings" : "GitHub Actions").font(.headline)
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small).frame(width: 16, height: 16)
            } else {
                iconButton("arrow.clockwise", help: "Refresh now") { Task { await store.refresh() } }
            }
            iconButton(showingSettings ? "xmark" : "gearshape", help: showingSettings ? "Close settings" : "Settings") {
                showingSettings.toggle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            if let lastRefresh = store.lastRefresh {
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    Text("Updated \(Format.ago(lastRefresh, now: context.date))")
                }
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct RunsView: View {
    let store: RunStore
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let authError = store.authError {
                Label(authError, systemImage: "key.slash")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if store.repos.isEmpty {
                VStack(spacing: 8) {
                    Text("No repositories watched yet.").foregroundStyle(.secondary)
                    Button("Add a repository", action: openSettings)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            ForEach(store.repos, id: \.self) { repo in
                RepoSection(repo: repo, state: store.states[repo], store: store)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RepoSection: View {
    let repo: String
    let state: RepoState?
    let store: RunStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(destination: URL(string: "https://github.com/\(repo)/actions")!) {
                HStack(spacing: 4) {
                    Text(repo).font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            if let error = state?.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
            }

            if let state {
                let runs = state.runs.boardRuns().prefix(8)
                if runs.isEmpty, state.error == nil {
                    Text("No workflow runs.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                }
                ForEach(runs) { run in
                    RunRow(run: run, repo: repo, store: store)
                }
            } else {
                Text("Loading…").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
        }
    }
}

struct RunRow: View {
    let run: WorkflowRun
    let repo: String
    let store: RunStore
    @State private var hovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(run.htmlUrl) } label: {
            HStack(alignment: .top, spacing: 8) {
                StatusIcon(state: run.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.displayTitle).lineLimit(1).truncationMode(.tail)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: run.state.isActive ? 1 : 30)) { context in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.duration(from: run.startedAt, to: run.state.isActive ? context.date : run.updatedAt))
                            .monospacedDigit()
                        Text(run.state.isActive ? label(for: run.state) : Format.ago(run.updatedAt, now: context.date))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(run.workflowName) #\(run.runNumber) · \(run.event) by \(run.actor?.login ?? "unknown")")
        .contextMenu {
            Button("Open in Browser") { openURL(run.htmlUrl) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(run.htmlUrl.absoluteString, forType: .string)
            }
            Divider()
            if run.state.isActive {
                Button("Cancel Run") { Task { await store.cancel(run, repo: repo) } }
            } else if run.state == .failure || run.state == .cancelled {
                Button("Re-run Failed Jobs") { Task { await store.rerunFailedJobs(run, repo: repo) } }
            }
        }
    }

    private var subtitle: String {
        [run.workflowName, run.headBranch, "#\(run.runNumber)"].compactMap(\.self).joined(separator: " · ")
    }

    private func label(for state: RunState) -> String {
        state == .queued ? "queued" : "running"
    }
}

struct StatusIcon: View {
    let state: RunState

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .symbolEffect(.rotate, isActive: state == .running)
            .frame(width: 16)
            .padding(.top, 1)
    }

    private var symbol: String {
        switch state {
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .cancelled: "slash.circle"
        case .skipped: "minus.circle"
        case .actionRequired: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .queued, .actionRequired: .yellow
        case .running: .orange
        case .success: .green
        case .failure: .red
        case .cancelled, .skipped: .secondary
        }
    }
}

enum Format {
    static func duration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let (h, m, s) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86400)d ago"
        }
    }
}
