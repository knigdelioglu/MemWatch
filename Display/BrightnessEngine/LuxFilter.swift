import AppKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import SwiftUI

final class LuxFilter {
    private var samples: [Double] = []
    private var smoothed: Double?
    private let sampleWindowSize = 5

    func reset() {
        samples.removeAll(keepingCapacity: true)
        smoothed = nil
    }

    func push(_ lux: Double, baseSmoothing: Double) -> Double {
        let clampedLux = min(max(lux, 0), 120_000)
        samples.append(clampedLux)
        if samples.count > sampleWindowSize {
            samples.removeFirst(samples.count - sampleWindowSize)
        }

        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]

        guard let previous = smoothed else {
            let initial = median
            smoothed = initial
            return initial
        }

        let delta = abs(median - previous)
        let base = min(max(baseSmoothing, 0.05), 0.92)
        let adaptive = min(0.98, base + min(0.20, delta / 1800.0))
        let next = previous + ((median - previous) * adaptive)
        smoothed = next
        return next
    }
}
