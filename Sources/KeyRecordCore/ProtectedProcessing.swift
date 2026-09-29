public enum ProtectedProcessing {
    @inline(__always)
    public static func observe<T>(_ operation: () throws -> T) rethrows -> T {
        #if DEBUG
        return try ProtectedReadActivity.process.observe(.plaintextProcessing, operation)
        #else
        return try operation()
        #endif
    }
}
