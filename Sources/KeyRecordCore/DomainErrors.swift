import Foundation

public enum DomainError: Error, Equatable, Sendable {
    case invalidKeyCode(Int)
    case invalidLocalDay(String)
}

public enum CountError: Error, Equatable, Sendable {
    case negative(Int64)
    case overflow
}

public enum SchemaError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case unknownFields(Set<String>)
}

public enum GateError: Error, Equatable, Sendable {
    case closed
    case unknownInput
    case staleGeneration
    case handoffOverflow
}

public enum Phase1Error: Error, Equatable, Sendable {
    case domain(DomainError)
    case count(CountError)
    case schema(SchemaError)
    case gate(GateError)
}
