import Foundation
import Combine
import KeyRecordAnalysis

@MainActor
struct PhysicalSourceObservation {
    let input: PhysicalSourceInput
    let evidence: PhysicalEvidence
    let isCurrent: @MainActor () -> Bool
}

@MainActor
struct PhysicalSourceDependencies {
    var observe: @MainActor (PhysicalSourceInput) async throws -> PhysicalSourceObservation? = { _ in nil }
    var observeChanges: @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void) = { _ in {} }
}

@MainActor
final class PhysicalSourcesModel: ObservableObject {
    var input: @MainActor (RecommendationScope) -> PhysicalSourceInput? = { _ in nil }
    var onChange: @MainActor () -> Void = {}
    var dependencies = PhysicalSourceDependencies() { didSet { invalidate() } }
    private var session = UUID()
    private var entries: [String: PhysicalSourceObservation] = [:]
    private var pending: [String: UUID] = [:]
    private var jobs: [String: Task<PhysicalSourceObservation?, Never>] = [:]
    private var references: [String: (PhysicalSourceInput, PhysicalSourceReport)] = [:]
    private var changed = false
    private var stopObserving: (@MainActor () -> Void)?

    func invalidate() {
        changed = changed || !entries.isEmpty || !pending.isEmpty
        session = UUID(); entries.removeAll(); pending.removeAll(); references.removeAll()
        jobs.values.forEach { $0.cancel() }; jobs.removeAll()
        let stop = stopObserving; stopObserving = nil; stop?()
        objectWillChange.send(); onChange()
    }
    func isLoading(_ scope: RecommendationScope) -> Bool { pending[key(scope)] != nil }
    func report(_ scope: RecommendationScope) -> PhysicalSourceReport? {
        guard let current = input(scope) else { return nil }
        if let observation = entries[key(scope)] {
            let ticket = session
            if observation.input == current, observation.evidence.scope == scope, observation.isCurrent(), ticket == session {
                return .observed(observation.evidence)
            }
            entries[key(scope)] = nil; references.removeAll(); changed = true
        }
        if let cached = references[key(scope)], cached.0 == current { return cached.1 }
        let report = PhysicalSourceReport.references(current, changed: changed)
        references[key(scope)] = (current, report)
        return report
    }
    func refresh(_ scope: RecommendationScope) async {
        guard let current = input(scope), !isLoading(scope) else { return }
        let ticket = session, request = UUID(), id = key(scope)
        entries[id] = nil; pending[id] = request; references.removeAll(); changed = false
        objectWillChange.send(); onChange()
        if stopObserving == nil {
            let stop = dependencies.observeChanges { [weak self] in self?.invalidate() }
            guard ticket == session else { stop(); return }
            stopObserving = stop
        }
        let read = dependencies.observe
        let job = Task { try? await read(current) }
        jobs[id] = job
        let observed = await job.value
        guard ticket == session, pending[id] == request else { return }
        let latest = input(scope)
        let valid = observed?.isCurrent() == true
        guard ticket == session, pending[id] == request else { return }
        pending[id] = nil; jobs[id] = nil
        if latest == current, let observed, observed.input == current,
           observed.evidence.scope == scope, valid {
            entries[id] = observed
        } else if observed != nil { references.removeAll(); changed = true }
        objectWillChange.send(); onChange()
    }
    private func key(_ scope: RecommendationScope) -> String {
        if case .application(let id) = scope { return "app:" + id }
        return "global"
    }
}
