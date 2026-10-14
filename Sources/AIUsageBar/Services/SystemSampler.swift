import Foundation
import Darwin
import UsageCore

final class SystemSampler {
    private var previous: [UInt64]?
    private var pressure = "Unknown"
    private var pressureSource: DispatchSourceMemoryPressure?
    init() {
        var level: Int32 = 0; var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            pressure = level == 1 ? "Normal" : level == 2 ? "Warning" : level == 4 ? "Critical" : "Unknown"
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            self?.pressure = source.data.contains(.critical) ? "Critical" : source.data.contains(.warning) ? "Warning" : "Normal"
        }
        source.resume(); pressureSource = source
    }
    deinit { pressureSource?.cancel() }
    func sample() -> SystemMetrics {
        var cpu = host_cpu_load_info(); var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cpuCount) }
        }
        var percent: Double?
        if cpuResult == KERN_SUCCESS {
            let current = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3].map(UInt64.init)
            if let old = previous {
                let delta = zip(current, old).map { $0 >= $1 ? $0 - $1 : UInt64(0) }
                let total = delta.reduce(0, +)
                if total > 0 { percent = Double(total - delta[2]) / Double(total) * 100 }
            }
            previous = current
        }
        var vm = vm_statistics64(); var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        var pageSize: vm_size_t = 0; host_page_size(mach_host_self(), &pageSize)
        let usedPages = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
        var task = mach_task_basic_info(); var taskCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let taskResult = withUnsafeMutablePointer(to: &task) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(taskCount)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &taskCount) }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        return SystemMetrics(cpuPercent: percent, memoryUsedBytes: vmResult == KERN_SUCCESS ? min(total, usedPages * UInt64(pageSize)) : 0,
                             memoryTotalBytes: total, appResidentBytes: taskResult == KERN_SUCCESS ? task.resident_size : 0,
                             pressure: pressure)
    }
}
