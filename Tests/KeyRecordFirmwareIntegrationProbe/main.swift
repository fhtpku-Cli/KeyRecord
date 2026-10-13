import Foundation
import Darwin
import KeyRecordCore
import KeyRecordStore
import KeyRecordMappings

private actor FixtureKeys: ObjectStoreKeySource {
    private var present = false
    func seed() { present = true }
    func namespaceKeyVersions() -> Set<KeyVersion> { present ? [.init(rawValue: 1)] : [] }
    func material(for version: KeyVersion) throws -> Data { Data(repeating: 0xa7, count: 32) }
}
private struct OfflineTransport: VialReadTransport {
    let uid: UInt64
    let layers: UInt8
    let keymap: [UInt8]
    func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8] {
        var bytes = request.bytes
        switch bytes[0] {
        case 1: bytes[1] = 0; bytes[2] = 9
        case 0xfe:
            bytes[0] = 6; bytes[1] = 0
            for index in 0..<8 { bytes[index + 4] = UInt8(truncatingIfNeeded: uid >> (index * 8)) }
        case 0x11: bytes[1] = layers
        case 0x12:
            let offset = Int(bytes[1]) << 8 | Int(bytes[2]), length = Int(bytes[3])
            guard offset + length <= keymap.count else { throw VialReadbackError.invalidRequest }
            bytes.replaceSubrange(4..<(4 + length), with: keymap[offset..<(offset + length)])
        default: throw VialReadbackError.invalidRequest
        }
        return bytes
    }
}
@main
struct FirmwareIntegrationProbe {
    static func main() async {
        do { try await run() }
        catch { fputs("offline firmware integration failed: \(error)\n", stderr); exit(2) }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] { print("Usage: KeyRecordFirmwareIntegrationProbe <synthetic-original.vil> <patched-output.vil>\nOffline only: in-memory keys and simulated read transport; no HID."); return }
        guard args.count == 2 else { throw FirmwareError.invalidDocument }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: args[0]))
        let document = try FirmwareDocument(bytes: bytes, backend: .vial)
        guard let shape = document.matrixDimensions, let uid = UInt64(document.device), let layers = UInt8(exactly: shape.layers),
              shape.layers * shape.rows * shape.columns * 2 <= 65_536 else { throw VialReadbackError.invalidMatrix }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-firmware-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = FixtureKeys(), store = ObjectStore(root: root.appendingPathComponent("objects"), keySource: keys)
        _ = try await store.bootstrap(); await keys.seed(); try await store.initializeFreshInstallation(version: .init(rawValue: 1))
        let gate = KeyAvailabilityGate(); gate.update(.unlocked)
        let axes = try FirmwareVersionProvider.axes(bytes: bytes, backend: .vial, definitionSchema: "offline-official-source-matrix", importer: "offline-official-source-importer")
        let support = FirmwareSupportDirectory(entries: [.init(backend: .vial, device: document.device, axes: axes, supportedOutputs: ["KC_C"])])
        let operations = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        let record = try await operations.retainOriginal(bytes, backend: .vial, axes: axes, confirmedAt: Date(timeIntervalSince1970: 1))
        let change = FirmwareSlotChange(slot: .init(layer: 0, column: 1), output: "KC_C", automatic: true)
        let preview = try await operations.preview(record.id, changes: [change])
        guard preview.differences.count == 1 else { throw FirmwareError.invalidState }
        let artifact = try await operations.prepare(record.id, changes: [change])
        _ = try await operations.export(record.id, changes: [change], destination: FirmwareFileDestination(target: URL(fileURLWithPath: args[1]), gate: gate))
        _ = try await operations.claimImport(record.id, at: Date(timeIntervalSince1970: 2))
        var keymap = [UInt8](repeating: 0, count: shape.layers * shape.rows * shape.columns * 2)
        let patched = try FirmwareDocument(bytes: artifact, backend: .vial)
        for layer in 0..<shape.layers {
            for row in 0..<shape.rows {
                for column in 0..<shape.columns {
                    let slot = FirmwareSlot(layer: layer, row: row, column: column)
                    let token: String
                    do { token = try patched.value(at: slot) }
                    catch FirmwareError.invalidSlot { continue }
                    let raw = try VialKeycodeDialect.rawValue(token), offset = ((layer * shape.rows + row) * shape.columns + column) * 2
                    keymap[offset] = UInt8(raw >> 8); keymap[offset + 1] = UInt8(raw & 255)
                }
            }
        }
        let adapter = try VialReadbackAdapter(transport: OfflineTransport(uid: uid, layers: layers, keymap: keymap),
            matrixRows: shape.rows, matrixColumns: shape.columns)
        let observation = try await adapter.observe(record: record, original: bytes, at: { Date(timeIntervalSince1970: 3) })
        let result = try await operations.confirmVialReadback(record.id, observation: observation)
        guard result.records.last?.state == .verified, try await operations.original(record.id) == bytes else { throw FirmwareError.invalidState }
        let reopened = try FirmwareOperationCoordinator(store: store, support: support, resolve: { try FirmwareFileDestination(reference: $0, gate: gate) })
        guard try await reopened.reconcile().records.last?.state == .verified else { throw FirmwareError.invalidState }
        print("PASS: public API retained official export, previewed one change, exported, claimed import, read \(observation.values.count) slots, verified and reopened encrypted result")
    }
}
