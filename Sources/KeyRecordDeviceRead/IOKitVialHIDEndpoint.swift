import Foundation
import IOKit
import IOKit.hid
import KeyRecordMappings

// All mutable state and callbacks belong to queue. Retained callback ownership
// lasts until IOKit's cancel handler has drained its events; buffers never move.
public final class IOKitVialHIDEndpoint: VialHIDEndpoint, @unchecked Sendable {
    private struct Context: @unchecked Sendable { let pointer: UnsafeMutableRawPointer }
    private final class Write {
        let id = UUID()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
        let completion: @Sendable (Result<Void, VialHIDError>) -> Void
        weak var owner: IOKitVialHIDEndpoint?
        init(_ request: VialReadRequest, owner: IOKitVialHIDEndpoint,
             completion: @escaping @Sendable (Result<Void, VialHIDError>) -> Void) {
            buffer.initialize(from: request.bytes, count: 32); self.owner = owner; self.completion = completion
        }
        deinit { buffer.deallocate() }
    }
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "KeyRecord.VialHID")
    private let input = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
    private var receive: (@Sendable (Result<VialHIDFrame, VialHIDError>) -> Void)?
    private var writes: [UUID: Write] = [:]
    private var activated = false
    private var closed = false
    private var opened = true
    private init(device: IOHIDDevice) { self.device = device }
    deinit {
        input.deallocate()
        if opened, !activated { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }
    // Explicit selected registry entry only. No manager enumeration, keyboard
    // event capture, automatic discovery or production composition opens it.
    public static func open(registryEntryID: UInt64, vendorID: UInt16, productID: UInt16) throws -> IOKitVialHIDEndpoint {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryEntryID))
        guard service != 0 else { throw VialHIDError.disconnected }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { throw VialHIDError.wrongInterface }
        func property(_ key: String) -> Int? { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue }
        guard property(kIOHIDVendorIDKey) == Int(vendorID), property(kIOHIDProductIDKey) == Int(productID),
              property(kIOHIDPrimaryUsagePageKey) == 0xff60, property(kIOHIDPrimaryUsageKey) == 0x61,
              property(kIOHIDMaxInputReportSizeKey) == 32, property(kIOHIDMaxOutputReportSizeKey) == 32 else {
            throw VialHIDError.wrongInterface
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw VialHIDError.ioFailure(result) }
        return IOKitVialHIDEndpoint(device: device)
    }
    public func start(receive: @escaping @Sendable (Result<VialHIDFrame, VialHIDError>) -> Void) {
        queue.async { [self] in
            guard !closed, !activated else { receive(.failure(.closed)); return }
            self.receive = receive
            let context = Context(pointer: Unmanaged.passRetained(self).toOpaque())
            IOHIDDeviceRegisterInputReportCallback(device, input, 32, { pointer, result, _, type, id, bytes, length in
                guard let pointer else { return }
                let owner = Unmanaged<IOKitVialHIDEndpoint>.fromOpaque(pointer).takeUnretainedValue()
                guard result == kIOReturnSuccess else { owner.receive?(.failure(.ioFailure(result))); return }
                guard type == kIOHIDReportTypeInput, id == 0, length == 32 else {
                    owner.receive?(.failure(.invalidReport)); return
                }
                owner.receive?(.success(.init(reportID: 0, bytes: Array(UnsafeBufferPointer(start: bytes, count: length)))))
            }, context.pointer)
            IOHIDDeviceRegisterRemovalCallback(device, { pointer, _, _ in
                guard let pointer else { return }
                Unmanaged<IOKitVialHIDEndpoint>.fromOpaque(pointer).takeUnretainedValue().receive?(.failure(.disconnected))
            }, context.pointer)
            IOHIDDeviceSetDispatchQueue(device, queue)
            IOHIDDeviceSetCancelHandler(device) {
                let owner = Unmanaged<IOKitVialHIDEndpoint>.fromOpaque(context.pointer).takeRetainedValue()
                IOHIDDeviceClose(owner.device, IOOptionBits(kIOHIDOptionsTypeNone))
                owner.opened = false
                let writes = owner.writes; owner.writes = [:]; owner.receive = nil
                for write in writes.values { write.completion(.failure(.closed)) }
            }
            activated = true; IOHIDDeviceActivate(device)
        }
    }
    public func send(_ request: VialReadRequest, timeoutMilliseconds: Int,
                     completion: @escaping @Sendable (Result<Void, VialHIDError>) -> Void) {
        guard timeoutMilliseconds > 0, timeoutMilliseconds <= Int(UInt32.max) else {
            completion(.failure(.invalidReport)); return
        }
        queue.async { [self] in
            guard activated, !closed else { completion(.failure(.closed)); return }
            let write = Write(request, owner: self, completion: completion)
            writes[write.id] = write
            // IOKit takes report ID separately. The 00 prefix in hidapi's 33-byte
            // write is not part of this unnumbered 32-byte report.
            let result = IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput, 0, write.buffer, 32,
                CFTimeInterval(timeoutMilliseconds), { pointer, result, _, _, _, _, _ in
                    guard let pointer else { return }
                    let write = Unmanaged<Write>.fromOpaque(pointer).takeUnretainedValue()
                    write.owner?.writes[write.id] = nil
                    write.completion(result == kIOReturnSuccess ? .success(()) : .failure(.ioFailure(result)))
                }, Unmanaged.passUnretained(write).toOpaque())
            if result != kIOReturnSuccess { writes[write.id] = nil; completion(.failure(.ioFailure(result))) }
        }
    }
    public func close() {
        queue.async { [self] in
            guard !closed else { return }; closed = true
            if activated { IOHIDDeviceCancel(device) }
            else { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)); opened = false }
        }
    }
}
