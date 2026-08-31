import AppKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import SwiftUI

private typealias IODisplaySetFloatParameterFn = @convention(c) (io_service_t, IOOptionBits, CFString, Float) -> IOReturn
private typealias IODisplayGetFloatParameterFn = @convention(c) (io_service_t, IOOptionBits, CFString, UnsafeMutablePointer<Float>) -> IOReturn
private typealias IODisplayForFramebufferFn = @convention(c) (io_service_t, IOOptionBits) -> io_service_t
private typealias CGDisplayIOServicePortFn = @convention(c) (CGDirectDisplayID) -> io_service_t
private typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DisplayServicesSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias DisplayServicesCanChangeBrightnessFn = @convention(c) (CGDirectDisplayID) -> Bool
private typealias DisplayServicesBrightnessChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Void
private typealias CoreDisplayGetUserBrightnessFn = @convention(c) (CGDirectDisplayID) -> Double
private typealias CoreDisplaySetUserBrightnessFn = @convention(c) (CGDirectDisplayID, Double) -> Void

final class InternalDisplayBrightnessController {
    private let displayID: CGDirectDisplayID
    private let service: io_service_t?
    private let setFloatParameter: IODisplaySetFloatParameterFn?
    private let getFloatParameter: IODisplayGetFloatParameterFn?
    private let displayServicesGetBrightness: DisplayServicesGetBrightnessFn?
    private let displayServicesSetBrightness: DisplayServicesSetBrightnessFn?
    private let displayServicesCanChangeBrightness: DisplayServicesCanChangeBrightnessFn?
    private let displayServicesBrightnessChanged: DisplayServicesBrightnessChangedFn?
    private let coreDisplayGetUserBrightness: CoreDisplayGetUserBrightnessFn?
    private let coreDisplaySetUserBrightness: CoreDisplaySetUserBrightnessFn?

    init?() {
        guard let builtinDisplayID = Self.builtinDisplayID() else { return nil }
        displayID = builtinDisplayID

        let iokitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        let displayServicesHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        let coreDisplayHandle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        let coreGraphicsHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

        setFloatParameter = Self.symbol("IODisplaySetFloatParameter", from: iokitHandle)
        getFloatParameter = Self.symbol("IODisplayGetFloatParameter", from: iokitHandle)
        displayServicesGetBrightness = Self.symbol("DisplayServicesGetBrightness", from: displayServicesHandle)
        displayServicesSetBrightness = Self.symbol("DisplayServicesSetBrightness", from: displayServicesHandle)
        displayServicesCanChangeBrightness = Self.symbol("DisplayServicesCanChangeBrightness", from: displayServicesHandle)
        displayServicesBrightnessChanged = Self.symbol("DisplayServicesBrightnessChanged", from: displayServicesHandle)
        coreDisplayGetUserBrightness = Self.symbol("CoreDisplay_Display_GetUserBrightness", from: coreDisplayHandle)
        coreDisplaySetUserBrightness = Self.symbol("CoreDisplay_Display_SetUserBrightness", from: coreDisplayHandle)

        if
            let displayRaw: CGDisplayIOServicePortFn = Self.symbol("CGDisplayIOServicePort", from: coreGraphicsHandle),
            let displayForFramebufferRaw: IODisplayForFramebufferFn = Self.symbol("IODisplayForFramebuffer", from: iokitHandle)
        {
            let framebuffer = displayRaw(builtinDisplayID)
            if framebuffer != 0 {
                let resolvedService = displayForFramebufferRaw(framebuffer, 0)
                service = resolvedService != 0 ? resolvedService : framebuffer
            } else {
                service = nil
            }
        } else {
            service = nil
        }
    }

    func currentBrightness() -> Int? {
        if let brightness = readBrightness() {
            return brightness
        }
        return nil
    }

    func setBrightness(_ percent: Int) -> (Bool, String) {
        let clamped = min(100, max(0, percent))
        let value = Float(clamped) / 100.0

        // Prefer Apple's newer private brightness SPI, then fall back to older IOKit paths.
        if let setBrightness = displayServicesSetBrightness {
            let result = setBrightness(displayID, value)
            if result == 0 {
                return (true, "ok")
            }
        }

        if let coreDisplaySetUserBrightness {
            if let canChangeBrightness = displayServicesCanChangeBrightness,
               !canChangeBrightness(displayID) {
                return (false, "display brightness unavailable")
            }

            coreDisplaySetUserBrightness(displayID, Double(value))
            if let displayServicesBrightnessChanged {
                displayServicesBrightnessChanged(displayID, Double(value))
            }
            return (true, "ok")
        }

        if let service, let setFloatParameter {
            let result = setFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, value)
            return (result == kIOReturnSuccess, result == kIOReturnSuccess ? "ok" : "set failed: \(result)")
        }

        return (false, "internal brightness setter unavailable")
    }

    private func readBrightness() -> Int? {
        if let getBrightness = displayServicesGetBrightness {
            var value: Float = 0
            if getBrightness(displayID, &value) == 0 {
                return Self.percent(from: value)
            }
        }

        if let coreDisplayGetUserBrightness {
            return Self.percent(from: Float(coreDisplayGetUserBrightness(displayID)))
        }

        if let service, let getFloatParameter {
            var value: Float = 0
            let result = getFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
            if result == kIOReturnSuccess {
                return Self.percent(from: value)
            }
        }

        return nil
    }

    private static func percent(from brightness: Float) -> Int? {
        guard brightness.isFinite else { return nil }
        let scaled = Int((brightness * 100).rounded())
        return min(100, max(0, scaled))
    }

    private static func symbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    private static func builtinDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return nil
        }

        var displays = Array(repeating: CGDirectDisplayID(0), count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
            return nil
        }

        return displays.prefix(Int(displayCount)).first(where: { CGDisplayIsBuiltin($0) != 0 })
    }
}
