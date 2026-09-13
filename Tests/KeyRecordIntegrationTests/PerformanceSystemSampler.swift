import Darwin
import Foundation

struct PerformanceSystemSampler {
    struct Snapshot {
        let cpu: Double
        let wall: Double
        let footprint: Double
    }

    func sample() throws -> Snapshot {
        var cpu = timespec()
        var wall = timespec()
        guard clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &cpu) == 0,
              clock_gettime(CLOCK_MONOTONIC, &wall) == 0 else { throw PerformanceError.systemCall }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw PerformanceError.systemCall }
        return Snapshot(cpu: Double(cpu.tv_sec) + Double(cpu.tv_nsec) / 1e9,
            wall: Double(wall.tv_sec) + Double(wall.tv_nsec) / 1e9, footprint: Double(info.phys_footprint))
    }

    static func sysctl(_ name: String) throws -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { throw PerformanceError.systemCall }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { throw PerformanceError.systemCall }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func nativeArch() throws -> String {
        var translated: Int32 = 0
        var size = MemoryLayout.size(ofValue: translated)
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        guard (result == 0 && translated == 0) || (result == -1 && errno == ENOENT) else {
            throw PerformanceError.translatedHost
        }
        var host = utsname()
        guard uname(&host) == 0 else { throw PerformanceError.systemCall }
        let capacity = MemoryLayout.size(ofValue: host.machine)
        return withUnsafePointer(to: &host.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}
