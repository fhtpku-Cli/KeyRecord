import Foundation

struct SP6AHostManifest: Decodable {
    let hostID: String
}

struct SP6AWitnessArtifact: Codable, Equatable {
    let hostID: String
    let runID: String
    let appDigest: String
    let sequence: Int
    let generation: String
    let state: String
    let observedAt: String

    init(hostID: String, runID: String, appDigest: String, sequence: Int,
         generation: String, state: String, observedAt: String) {
        self.hostID = hostID; self.runID = runID; self.appDigest = appDigest; self.sequence = sequence
        self.generation = generation; self.state = state; self.observedAt = observedAt
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case hostID, runID, appDigest, sequence, generation, state, observedAt
    }

    init(from decoder: Decoder) throws {
        let c = try SP6AStrictShape.container(CodingKeys.self, decoder: decoder)
        hostID = try c.decode(String.self, forKey: .hostID)
        runID = try c.decode(String.self, forKey: .runID)
        appDigest = try c.decode(String.self, forKey: .appDigest)
        sequence = try c.decode(Int.self, forKey: .sequence)
        generation = try c.decode(String.self, forKey: .generation)
        state = try c.decode(String.self, forKey: .state)
        observedAt = try c.decode(String.self, forKey: .observedAt)
    }
}

struct SP6AAssertionArtifact: Codable, Equatable {
    let assertionID: String
    let hostID: String
    let runID: String
    let appDigest: String
    let sequence: Int
    let generation: String
    let state: String
    let observedAt: String
    let authoritative: Bool
    let captureClosed: Bool?
    let protectedReadDelta: Int
    let publishDelta: Int
    let aggregateDelta: Int
    let accessibility: String?
    let synchronizable: Bool?
    let initialWitness: SP6AWitnessArtifact?
    let priorGeneration: String?

    init(assertionID: String, hostID: String, runID: String, appDigest: String, sequence: Int,
         generation: String, state: String, observedAt: String, authoritative: Bool, captureClosed: Bool?,
         protectedReadDelta: Int, publishDelta: Int, aggregateDelta: Int, accessibility: String?,
         synchronizable: Bool?, initialWitness: SP6AWitnessArtifact?, priorGeneration: String?) {
        self.assertionID = assertionID; self.hostID = hostID; self.runID = runID; self.appDigest = appDigest
        self.sequence = sequence; self.generation = generation; self.state = state; self.observedAt = observedAt
        self.authoritative = authoritative; self.captureClosed = captureClosed
        self.protectedReadDelta = protectedReadDelta; self.publishDelta = publishDelta
        self.aggregateDelta = aggregateDelta; self.accessibility = accessibility
        self.synchronizable = synchronizable; self.initialWitness = initialWitness
        self.priorGeneration = priorGeneration
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case assertionID, hostID, runID, appDigest, sequence, generation, state, observedAt
        case authoritative, captureClosed, protectedReadDelta, publishDelta, aggregateDelta
        case accessibility, synchronizable, initialWitness, priorGeneration
    }

    init(from decoder: Decoder) throws {
        let c = try SP6AStrictShape.container(CodingKeys.self, decoder: decoder)
        assertionID = try c.decode(String.self, forKey: .assertionID)
        hostID = try c.decode(String.self, forKey: .hostID)
        runID = try c.decode(String.self, forKey: .runID)
        appDigest = try c.decode(String.self, forKey: .appDigest)
        sequence = try c.decode(Int.self, forKey: .sequence)
        generation = try c.decode(String.self, forKey: .generation)
        state = try c.decode(String.self, forKey: .state)
        observedAt = try c.decode(String.self, forKey: .observedAt)
        authoritative = try c.decode(Bool.self, forKey: .authoritative)
        captureClosed = try c.decodeIfPresent(Bool.self, forKey: .captureClosed)
        protectedReadDelta = try c.decode(Int.self, forKey: .protectedReadDelta)
        publishDelta = try c.decode(Int.self, forKey: .publishDelta)
        aggregateDelta = try c.decode(Int.self, forKey: .aggregateDelta)
        accessibility = try c.decodeIfPresent(String.self, forKey: .accessibility)
        synchronizable = try c.decodeIfPresent(Bool.self, forKey: .synchronizable)
        initialWitness = try c.decodeIfPresent(SP6AWitnessArtifact.self, forKey: .initialWitness)
        priorGeneration = try c.decodeIfPresent(String.self, forKey: .priorGeneration)
    }

    func witnessProjection() -> SP6AWitnessArtifact {
        .init(hostID: hostID, runID: runID, appDigest: appDigest, sequence: sequence,
              generation: generation, state: state, observedAt: observedAt)
    }
}

enum SP6AStrictShape {
    struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    static func container<K: CodingKey & CaseIterable>(_ type: K.Type, decoder: Decoder) throws -> KeyedDecodingContainer<K> {
        let raw = try decoder.container(keyedBy: DynamicKey.self)
        let allowed = Set(K.allCases.map(\.stringValue))
        guard Set(raw.allKeys.map(\.stringValue)).isSubset(of: allowed) else {
            throw ValidatorError("sp6a_unknown_artifact_field")
        }
        return try decoder.container(keyedBy: K.self)
    }
}
