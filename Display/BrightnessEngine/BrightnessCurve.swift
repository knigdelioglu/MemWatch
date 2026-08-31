import AppKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import SwiftUI

enum BrightnessCurve {
    static func ambientNormalizedValue(for lux: Double, calibration: DisplayCalibration) -> Double {
        let normalizedLux = max(0, lux)
        let input = normalizedAnchorPoints(for: calibration)

        if normalizedLux <= 10.0 {
            return 0.0
        }

        if normalizedLux <= input[0].0 {
            let span = max(input[0].0 - 10.0, 1.0)
            let progress = min(max((normalizedLux - 10.0) / span, 0.0), 1.0)
            return progress * input[0].1
        } else if normalizedLux <= input[1].0 {
            return interpolate(normalizedLux, from: input[0], to: input[1])
        } else if normalizedLux <= input[2].0 {
            return interpolate(normalizedLux, from: input[1], to: input[2])
        } else {
            let overflowSpan = 800.0
            let progress = min(max((normalizedLux - input[2].0) / overflowSpan, 0.0), 1.0)
            let easeOut = 1.0 - pow(1.0 - progress, 2.0)
            return input[2].1 + ((input[3].1 - input[2].1) * easeOut)
        }
    }

    static func targetBrightness(for lux: Double, calibration: DisplayCalibration, profile: AmbientSyncProfile) -> Int {
        targetBrightnessPercent(for: lux, calibration: calibration, profile: profile)
    }

    static func autoTargetBrightnessPercent(for ambientNormalizedValue: Double, calibration: DisplayCalibration, profile: AmbientSyncProfile) -> Int {
        requestedDDCBrightnessPercent(for: ambientNormalizedValue, calibration: calibration, profile: profile)
    }

    static func requestedDDCBrightnessPercent(for ambientNormalizedValue: Double, calibration: DisplayCalibration, profile: AmbientSyncProfile) -> Int {
        let normalized = min(max(ambientNormalizedValue, 0.0), 100.0)
        let target: Double

        if normalized <= 25.0 {
            let progress = normalized / 25.0
            target = Double(profile.lowBrightness) * progress
        } else if normalized <= 50.0 {
            target = interpolate(
                normalized,
                from: (25.0, Double(profile.lowBrightness)),
                to: (50.0, Double(profile.midBrightness))
            )
        } else if normalized <= 75.0 {
            target = interpolate(
                normalized,
                from: (50.0, Double(profile.midBrightness)),
                to: (75.0, Double(profile.highBrightness))
            )
        } else {
            let progress = min(max((normalized - 75.0) / 25.0, 0.0), 1.0)
            let easeOut = 1.0 - pow(1.0 - progress, 2.0)
            target = Double(profile.highBrightness) + ((100.0 - Double(profile.highBrightness)) * easeOut)
        }

        return min(100, max(0, Int(target.rounded())))
    }

    private static func interpolate(_ lux: Double, from: (Double, Double), to: (Double, Double)) -> Double {
        let span = max(to.0 - from.0, 1.0)
        let progress = min(max((lux - from.0) / span, 0.0), 1.0)
        let smoothProgress = progress * progress * (3.0 - (2.0 * progress))
        return from.1 + ((to.1 - from.1) * smoothProgress)
    }

    private static func targetBrightnessPercent(for lux: Double, calibration: DisplayCalibration, profile: AmbientSyncProfile) -> Int {
        let input = normalizedAnchorPoints(for: calibration)

        let normalizedLux = max(0, lux)
        if normalizedLux <= 10.0 {
            return 0
        }

        let target: Double

        if normalizedLux <= input[0].0 {
            let span = max(input[0].0 - 10.0, 1.0)
            let progress = min(max((normalizedLux - 10.0) / span, 0.0), 1.0)
            target = 0.0 + ((Double(profile.lowBrightness) - 0.0) * progress)
        } else if normalizedLux <= input[1].0 {
            target = interpolate(normalizedLux, from: input[0], to: input[1], outputFrom: Double(profile.lowBrightness), outputTo: Double(profile.midBrightness))
        } else if normalizedLux <= input[2].0 {
            target = interpolate(normalizedLux, from: input[1], to: input[2], outputFrom: Double(profile.midBrightness), outputTo: Double(profile.highBrightness))
        } else {
            let overflowSpan = 800.0
            let progress = min(max((normalizedLux - input[2].0) / overflowSpan, 0.0), 1.0)
            let easeOut = 1.0 - pow(1.0 - progress, 2.0)
            target = Double(profile.highBrightness) + ((100.0 - Double(profile.highBrightness)) * easeOut)
        }

        return min(100, max(0, Int(target.rounded())))
    }

    private static func normalizedAnchorPoints(for calibration: DisplayCalibration) -> [(Double, Double)] {
        [
            (calibration.lowLux, 25.0),
            (calibration.midLux, 50.0),
            (calibration.highLux, 75.0),
            (calibration.highLux + 800.0, 100.0),
        ].sorted(by: { $0.0 < $1.0 })
    }

    private static func interpolate(_ value: Double, from: (Double, Double), to: (Double, Double), outputFrom: Double, outputTo: Double) -> Double {
        let span = max(to.0 - from.0, 1.0)
        let progress = min(max((value - from.0) / span, 0.0), 1.0)
        let smoothProgress = progress * progress * (3.0 - (2.0 * progress))
        return outputFrom + ((outputTo - outputFrom) * smoothProgress)
    }
}
