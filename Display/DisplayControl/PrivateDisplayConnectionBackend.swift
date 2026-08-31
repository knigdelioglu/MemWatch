import CoreGraphics
import Darwin
import Foundation

final class PrivateDisplayConnectionBackend: DisplayConnectionBackend, @unchecked Sendable {
    private typealias GetDisplayListFunc = @convention(c) (
        UInt32,
        UnsafeMutablePointer<CGDirectDisplayID>?,
        UnsafeMutablePointer<UInt32>?
    ) -> CGError

    private typealias ConfigureDisplayEnabledFunc = @convention(c) (
        CGDisplayConfigRef?,
        CGDirectDisplayID,
        Bool
    ) -> CGError

    private struct ResolvedSymbol {
        let name: String
        let pointer: UnsafeMutableRawPointer
    }

    var isAvailable: Bool {
        resolveFirstSymbol(["SLSGetDisplayList", "CGSGetDisplayList"]) != nil &&
            resolveFirstSymbol(["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"]) != nil
    }

    func allDisplayIDs() throws -> [CGDirectDisplayID] {
        guard let symbol = resolveFirstSymbol(["SLSGetDisplayList", "CGSGetDisplayList"]) else {
            throw DisplayConnectionBackendError.missingPrivateSymbol("SLSGetDisplayList / CGSGetDisplayList")
        }

        let getDisplayList = unsafeBitCast(symbol.pointer, to: GetDisplayListFunc.self)
        var ids = Array(repeating: CGDirectDisplayID(0), count: 32)
        var count: UInt32 = 0

        let result = ids.withUnsafeMutableBufferPointer { buffer in
            getDisplayList(UInt32(buffer.count), buffer.baseAddress, &count)
        }

        guard result == .success else {
            throw DisplayConnectionBackendError.displayEnumerationFailed(result.rawValue)
        }

        return Array(ids.prefix(min(Int(count), ids.count))).filter { $0 != 0 }
    }

    func setDisplayEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        guard let symbol = resolveFirstSymbol(["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"]) else {
            throw DisplayConnectionBackendError.missingPrivateSymbol("SLSConfigureDisplayEnabled / CGSConfigureDisplayEnabled")
        }

        let configureDisplayEnabled = unsafeBitCast(symbol.pointer, to: ConfigureDisplayEnabledFunc.self)
        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success, let config else {
            throw DisplayConnectionBackendError.beginConfigurationFailed(beginResult.rawValue)
        }

        if !enabled {
            do {
                try detachFromMirrorSetIfNeeded(displayID: displayID, config: config)
            } catch {
                CGCancelDisplayConfiguration(config)
                throw error
            }
        }

        let configureResult = configureDisplayEnabled(config, displayID, enabled)
        guard configureResult == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayConnectionBackendError.configureEnabledFailed(configureResult.rawValue)
        }

        // Session-scoped is intentionally safer than a permanent configuration:
        // a reboot restores the display even if a private API regression leaves it disabled.
        let completeResult = CGCompleteDisplayConfiguration(config, .forSession)
        guard completeResult == .success else {
            throw DisplayConnectionBackendError.completeConfigurationFailed(completeResult.rawValue)
        }
    }

    private func detachFromMirrorSetIfNeeded(
        displayID: CGDirectDisplayID,
        config: CGDisplayConfigRef
    ) throws {
        guard CGDisplayIsInMirrorSet(displayID) != 0 else { return }

        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return }

        var onlineIDs = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        let listResult = onlineIDs.withUnsafeMutableBufferPointer { buffer in
            CGGetOnlineDisplayList(count, buffer.baseAddress, &count)
        }
        guard listResult == .success else { return }

        for candidate in onlineIDs.prefix(Int(count)) {
            let mirrorMaster = CGDisplayMirrorsDisplay(candidate)
            let shouldDetach =
                (candidate == displayID && mirrorMaster != kCGNullDirectDisplay) ||
                (mirrorMaster == displayID)

            guard shouldDetach else { continue }
            let result = CGConfigureDisplayMirrorOfDisplay(config, candidate, kCGNullDirectDisplay)
            guard result == .success else {
                throw DisplayConnectionBackendError.mirrorDetachFailed(result.rawValue)
            }
        }
    }

    private func resolveFirstSymbol(_ names: [String]) -> ResolvedSymbol? {
        for name in names {
            if let pointer = resolveSymbol(name) {
                return ResolvedSymbol(name: name, pointer: pointer)
            }
        }
        return nil
    }

    private func resolveSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let globalHandle = UnsafeMutableRawPointer(bitPattern: -2),
           let pointer = dlsym(globalHandle, name) {
            return pointer
        }

        for path in [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        ] {
            guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { continue }
            if let pointer = dlsym(handle, name) {
                return pointer
            }
        }

        return nil
    }
}
