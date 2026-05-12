import Foundation
import Darwin.Mach

/// Lightweight RSS reader. Returns the current resident-memory footprint in
/// megabytes via `mach_task_basic_info`. Used by the LazyPad status bar and
/// available from the menu for spot-checks without launching Instruments.
enum MemoryReporter {
    /// Resident set size in megabytes, or nil if the syscall fails.
    static func residentMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr -> kern_return_t in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPtr,
                    &count
                )
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / 1_048_576.0
    }

    /// Human-readable label, e.g. "248 MB". Returns "—" when unavailable.
    static func residentDisplayString() -> String {
        guard let mb = residentMB() else { return "—" }
        return String(format: "%.0f MB", mb)
    }
}
