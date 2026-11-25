import Foundation

struct WorkflowRun: Decodable, Identifiable, Hashable, Sendable {
    struct Actor: Decodable, Hashable, Sendable {
        let login: String
    }

    struct Reference: Decodable, Hashable, Sendable {
        let id: Int
    }

    struct RepositoryRef: Decodable, Hashable, Sendable {
        let fullName: String
    }

    let id: Int
    let name: String?
    let displayTitle: String
    let headBranch: String?
    let event: String
    let status: String?
    let conclusion: String?
    let htmlUrl: URL
    let runNumber: Int
    let workflowId: Int
    let createdAt: Date
    let updatedAt: Date
    let runStartedAt: Date?
    let actor: Actor?
    let pullRequests: [Reference]
    let repository: RepositoryRef
    let headRepository: RepositoryRef?

    var state: RunState { RunState(status: status, conclusion: conclusion) }
    var startedAt: Date { runStartedAt ?? createdAt }
    var workflowName: String { name ?? "Workflow" }

    /// GitHub lists only open pull requests on a run, so an empty list means the PR was merged or closed.
    /// Fork PRs never list theirs, so they can't be told apart and are kept.
    var belongsToClosedPullRequest: Bool {
        event.hasPrefix("pull_request") && pullRequests.isEmpty && headRepository == repository
    }
}

struct RunsPage: Decodable, Sendable {
    let workflowRuns: [WorkflowRun]
}

struct Repository: Decodable, Sendable {
    let fullName: String
}

enum RunState: Sendable {
    case queued, running, success, failure, cancelled, skipped, actionRequired

    init(status: String?, conclusion: String?) {
        switch status {
        case "completed":
            switch conclusion {
            case "success": self = .success
            case "failure", "timed_out", "startup_failure": self = .failure
            case "cancelled": self = .cancelled
            case "action_required": self = .actionRequired
            default: self = .skipped
            }
        case "in_progress": self = .running
        case "waiting", "action_required": self = .actionRequired
        default: self = .queued
        }
    }

    var isActive: Bool { self == .queued || self == .running }
}

extension [WorkflowRun] {
    /// Every active run plus the most recent run of each workflow, newest first,
    /// ignoring finished runs of pull requests that have since been merged or closed.
    func boardRuns() -> [WorkflowRun] {
        var seenWorkflows = Set<Int>()
        return filter { run in
            if !run.state.isActive, run.belongsToClosedPullRequest { return false }
            let firstOfWorkflow = seenWorkflows.insert(run.workflowId).inserted
            return firstOfWorkflow || run.state.isActive
        }
    }
}
