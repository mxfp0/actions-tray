import Foundation
import Observation

enum NotifyMode: String, CaseIterable, Identifiable {
    case all, failures, off

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "All finished runs"
        case .failures: "Failures only"
        case .off: "Off"
        }
    }
}

struct RepoState {
    var runs: [WorkflowRun] = []
    var etag: String?
    var error: String?
}

enum AddRepositoryError: LocalizedError {
    case invalid, duplicate, noToken

    var errorDescription: String? {
        switch self {
        case .invalid: "Use owner/repo or a GitHub URL."
        case .duplicate: "Already watching that repository."
        case .noToken: "No GitHub token available."
        }
    }
}

@MainActor
@Observable
final class RunStore {
    private(set) var repos: [String] {
        didSet { UserDefaults.standard.set(repos, forKey: Keys.repos) }
    }
    var pollInterval: Int {
        didSet {
            UserDefaults.standard.set(pollInterval, forKey: Keys.pollInterval)
            start()
        }
    }
    var notifyMode: NotifyMode {
        didSet { UserDefaults.standard.set(notifyMode.rawValue, forKey: Keys.notifyMode) }
    }
    private(set) var states: [String: RepoState] = [:]
    private(set) var isRefreshing = false
    private(set) var authError: String?
    private(set) var tokenSource: TokenSource?
    private(set) var lastRefresh: Date?

    @ObservationIgnored let notifier = Notifier()
    @ObservationIgnored private var client: GitHubClient?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Last observed state of each run, per repo. Absent until the repo's first successful fetch,
    /// so runs that already finished before launch don't trigger notifications.
    @ObservationIgnored private var seen: [String: [Int: RunState]] = [:]

    private enum Keys {
        static let repos = "repos"
        static let pollInterval = "pollInterval"
        static let notifyMode = "notifyMode"
    }

    init() {
        let defaults = UserDefaults.standard
        repos = defaults.stringArray(forKey: Keys.repos) ?? []
        pollInterval = defaults.object(forKey: Keys.pollInterval) as? Int ?? 5
        notifyMode = defaults.string(forKey: Keys.notifyMode).flatMap(NotifyMode.init) ?? .all
    }

    var allRuns: [WorkflowRun] {
        repos.flatMap { states[$0]?.runs ?? [] }
    }

    var activeCount: Int {
        allRuns.count { $0.state.isActive }
    }

    var overall: RunState? {
        let board = repos.flatMap { (states[$0]?.runs ?? []).boardRuns() }
        guard !board.isEmpty else { return nil }
        if board.contains(where: \.state.isActive) { return .running }
        if board.contains(where: { $0.state == .failure }) { return .failure }
        if board.contains(where: { $0.state == .actionRequired }) { return .actionRequired }
        return .success
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let delay = self.activeCount > 0 ? min(5, self.pollInterval) : self.pollInterval
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(repos)
        lastRefresh = .now
    }

    func addRepository(_ input: String) async throws {
        guard let slug = Self.slug(from: input) else { throw AddRepositoryError.invalid }
        guard let client = await authorizedClient() else { throw AddRepositoryError.noToken }
        let fullName = try await client.repositoryFullName(slug)
        guard !repos.contains(where: { $0.caseInsensitiveCompare(fullName) == .orderedSame }) else {
            throw AddRepositoryError.duplicate
        }
        repos.append(fullName)
        await fetch([fullName])
    }

    func removeRepository(_ repo: String) {
        repos.removeAll { $0 == repo }
        states[repo] = nil
        seen[repo] = nil
    }

    func moveRepository(_ repo: String, by offset: Int) {
        guard let index = repos.firstIndex(of: repo), repos.indices.contains(index + offset) else { return }
        repos.swapAt(index, index + offset)
    }

    func setToken(_ token: String?) {
        TokenProvider.save(token?.trimmingCharacters(in: .whitespacesAndNewlines))
        client = nil
        tokenSource = nil
        start()
    }

    func rerunFailedJobs(_ run: WorkflowRun, repo: String) async {
        await perform(on: repo) { try await $0.rerunFailedJobs(repo: repo, runID: run.id) }
    }

    func cancel(_ run: WorkflowRun, repo: String) async {
        await perform(on: repo) { try await $0.cancel(repo: repo, runID: run.id) }
    }

    private func perform(on repo: String, _ action: (GitHubClient) async throws -> Void) async {
        guard let client = await authorizedClient() else { return }
        do {
            try await action(client)
            states[repo]?.error = nil
        } catch {
            states[repo]?.error = error.localizedDescription
        }
        await fetch([repo])
    }

    private func fetch(_ targets: [String]) async {
        guard !targets.isEmpty, let client = await authorizedClient() else { return }
        let requests = targets.map { repo in
            let etag = states[repo]?.etag
            return (repo, Task { try await client.runs(repo: repo, etag: etag) })
        }

        for (repo, request) in requests {
            let outcome = await request.result
            guard repos.contains(repo) else { continue }
            switch outcome {
            case .success(.notModified):
                states[repo]?.error = nil
            case .success(.updated(let runs, let etag)):
                notifyFinished(runs, repo: repo)
                states[repo] = RepoState(runs: runs, etag: etag)
            case .failure(GitHubClient.APIError.unauthorized):
                self.client = nil
                authError = GitHubClient.APIError.unauthorized.localizedDescription
            case .failure(let error):
                states[repo, default: RepoState()].error = error.localizedDescription
            }
        }
    }

    private func notifyFinished(_ runs: [WorkflowRun], repo: String) {
        let previous = seen[repo]
        seen[repo] = Dictionary(runs.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        guard let previous, notifyMode != .off else { return }

        for run in runs where !run.state.isActive {
            let before = previous[run.id]
            guard before == nil || before!.isActive else { continue }
            if notifyMode == .all || run.state == .failure {
                notifier.runFinished(run, repo: repo)
            }
        }
    }

    private func authorizedClient() async -> GitHubClient? {
        if let client { return client }
        guard let resolved = await Task.detached(operation: { TokenProvider.resolve() }).value else {
            authError = "No GitHub token. Run `gh auth login`, or add a token in Settings."
            return nil
        }
        authError = nil
        tokenSource = resolved.source
        let client = GitHubClient(token: resolved.token)
        self.client = client
        return client
    }

    static func slug(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www.", "github.com/"] where text.lowercased().hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        let parts = text.split(separator: "/").prefix(2).map(String.init)
        guard parts.count == 2 else { return nil }
        let owner = parts[0]
        let name = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard [owner, name].allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            return nil
        }
        return "\(owner)/\(name)"
    }
}
