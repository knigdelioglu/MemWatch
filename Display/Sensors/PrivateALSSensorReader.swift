import AppKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import SwiftUI

private enum AmbientSensorConstants {
    static let eventType: Int64 = 12
    static let fieldBase: Int32 = Int32(eventType << 16)
    static let fieldOffsets: [Int32] = [0, 7, 8, 9]
    static let maxValidLux: Double = 120_000
}

private enum PrivateSymbols {
    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        let handles: [UnsafeMutableRawPointer?] = [
            dlopen("/System/Library/PrivateFrameworks/BezelServices.framework/BezelServices", RTLD_LAZY),
            dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
        ]
        for handle in handles {
            if let handle, let raw = dlsym(handle, name) {
                return unsafeBitCast(raw, to: T.self)
            }
        }
        return nil
    }
}


private typealias ALCALSCopyALSServiceClientFn = @convention(c) () -> Unmanaged<AnyObject>?
private typealias IOHIDServiceClientCopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
private typealias IOHIDEventGetFloatValueFn = @convention(c) (CFTypeRef, Int32) -> Double
private typealias IODisplaySetFloatParameterFn = @convention(c) (io_service_t, IOOptionBits, CFString, Float) -> IOReturn
private typealias CGDisplayIOServicePortFn = @convention(c) (CGDirectDisplayID) -> io_service_t
final class AmbientLightReader {
    private let client: CFTypeRef
    private let copyEvent: IOHIDServiceClientCopyEventFn
    private let readFloatValue: IOHIDEventGetFloatValueFn

    init?() {
        guard
            let copyClient: ALCALSCopyALSServiceClientFn = PrivateSymbols.symbol("ALCALSCopyALSServiceClient", as: ALCALSCopyALSServiceClientFn.self),
            let copyEvent: IOHIDServiceClientCopyEventFn = PrivateSymbols.symbol("IOHIDServiceClientCopyEvent", as: IOHIDServiceClientCopyEventFn.self),
            let readFloatValue: IOHIDEventGetFloatValueFn = PrivateSymbols.symbol("IOHIDEventGetFloatValue", as: IOHIDEventGetFloatValueFn.self),
            let unmanaged = copyClient()
        else {
            return nil
        }
        client = unmanaged.takeRetainedValue() as CFTypeRef
        self.copyEvent = copyEvent
        self.readFloatValue = readFloatValue
    }

    func readLux() -> Double? {
        guard let unmanaged = copyEvent(client, AmbientSensorConstants.eventType, 0, 0) else {
            return nil
        }
        let event = unmanaged.takeRetainedValue() as CFTypeRef

        let samples = AmbientSensorConstants.fieldOffsets.compactMap { offset -> Double? in
            let value = readFloatValue(event, AmbientSensorConstants.fieldBase + offset)
            guard value.isFinite else { return nil }
            guard value >= 0, value <= AmbientSensorConstants.maxValidLux else { return nil }
            return value
        }
        guard !samples.isEmpty else { return nil }

        let nonZero = samples.filter { $0 >= 0.1 }
        let values = nonZero.isEmpty ? samples : nonZero
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        if values.count <= 2 {
            return median
        }

        // Remove both extremes to suppress sudden sensor spikes.
        let trimmed = values.sorted().dropFirst().dropLast()
        guard !trimmed.isEmpty else { return median }
        let average = trimmed.reduce(0.0, +) / Double(trimmed.count)
        return (median * 0.65) + (average * 0.35)
    }
}
