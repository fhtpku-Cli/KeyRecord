import Foundation

enum CurrentCandidateCommand {
    static func execute(_ arguments: [String], repository: URL) throws {
        guard let verb = arguments.first else { throw CurrentCandidateError(.malformedInput, "usage") }
        let positional = verb == "verify-current-candidate"
        let start = positional ? 2 : 1
        guard arguments.count >= start, (arguments.count - start).isMultiple(of: 2) else { throw CurrentCandidateError(.malformedInput, "usage") }
        var options: [String: String] = [:]
        for index in stride(from: start, to: arguments.count, by: 2) {
            let key = arguments[index]
            guard options[key] == nil else { throw CurrentCandidateError(.malformedInput, "duplicate_option") }
            options[key] = arguments[index + 1]
        }
        let expected: Set<String> = positional ? ["--readiness"] : ["--plan", "--readiness", "--output"]
        guard Set(options.keys) == expected, let readiness = options["--readiness"] else { throw CurrentCandidateError(.malformedInput, "usage") }
        let binder = CurrentCandidateBinder(repository: repository)
        let base = URL(fileURLWithPath: repository.path, isDirectory: true)
        let readinessURL = URL(fileURLWithPath: readiness, relativeTo: base)
        switch verb {
        case "bind-current":
            guard let plan = options["--plan"], let output = options["--output"] else { throw CurrentCandidateError(.malformedInput, "usage") }
            let candidate = try binder.bind(plan: URL(fileURLWithPath: plan, relativeTo: base), readiness: readinessURL, output: URL(fileURLWithPath: output, relativeTo: base))
            print("CURRENT_CANDIDATE=PASS bound=true identity=\(try candidate.identity) commit=\(candidate.commitSha)")
        case "verify-current-candidate":
            try binder.verify(URL(fileURLWithPath: arguments[1], relativeTo: base), readiness: readinessURL)
            print("CURRENT_CANDIDATE=PASS verified=true")
        default: throw CurrentCandidateError(.malformedInput, "usage")
        }
    }
}
