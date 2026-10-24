// The process's memory footprint (eval prints it: the Core ML decoder's must fit an iOS keyboard extension).

import Darwin
import Foundation

/// The process's physical footprint (what jetsam limits on iOS) and its peak, in MB.
func physicalFootprintMB() -> (current: Double, peak: Double) {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
  // task_info is a C API that fills a struct through a pointer; no safe alternative.
  let kr = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  guard kr == KERN_SUCCESS else { return (-1, -1) }
  return (Double(info.phys_footprint) / 1_048_576, Double(info.ledger_phys_footprint_peak) / 1_048_576)
}
