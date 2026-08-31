import CoreGraphics
import Darwin
import Foundation

protocol PrivateDisplaySymbolLookup: AnyObject {
    func symbol(named: String) -> UnsafeMutableRawPointer?
}

/// Resolves private framework symbols once and owns explicit dlopen handles.
final class CachedPrivateDisplaySymbolLookup: PrivateDisplaySymbolLookup, @unchecked Sendable {
    private static let frameworkPaths = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    ]

    private let lock = NSLock()
    private var handles: [UnsafeMutableRawPointer] = []
    private var symbols: [String: UnsafeMutableRawPointer] = [:]
    private var attemptedNames = Set<String>()

    init(frameworkPaths: [String] = CachedPrivateDisplaySymbolLookup.frameworkPaths) {
        for path in frameworkPaths {
            if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
                handles.append(handle)
            }
        }
    }

    deinit {
        for handle in handles {
            dlclose(handle)
        }
    }

    func symbol(named name: String) -> UnsafeMutableRawPointer? {
        lock.lock()
        defer { lock.unlock() }

        if attemptedNames.contains(name) {
            return symbols[name]
        }
        attemptedNames.insert(name)

        let globalHandle = UnsafeMutableRawPointer(bitPattern: -2)
        if let pointer = globalHandle.flatMap({ dlsym($0, name) }) {
            symbols[name] = pointer
            return pointer
        }

        for handle in handles {
            if let pointer = dlsym(handle, name) {
                symbols[name] = pointer
                return pointer
            }
        }
        return nil
    }
}

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

    private let symbolLookup: PrivateDisplaySymbolLookup
    private let getDisplayList: GetDisplayListFunc?
    private let configureDisplayEnabled: ConfigureDisplayEnabledFunc?

    init(symbolLookup: PrivateDisplaySymbolLookup = CachedPrivateDisplaySymbolLookup()) {
        self.symbolLookup = symbolLookup
        if let pointer = Self.firstSymbol(
            names: ["SLSGetDisplayList", "CGSGetDisplayList"],
            using: symbolLookup
        ) {
            getDisplayList = unsafeBitCast(pointer, to: GetDisplayListFunc.self)
        } else {
            getDisplayList = nil
        }

        if let pointer = Self.firstSymbol(
            names: ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"],
            using: symbolLookup
        ) {
            configureDisplayEnabled = unsafeBitCast(pointer, to: ConfigureDisplayEnabledFunc.self)
        } else {
            configureDisplayEnabled = nil
        }
    }

    var isAvailable: Bool { getDisplayList != nil && configureDisplayEnabled != nil }

    func allDisplayIDs() throws -> [CGDirectDisplayID] {
        guard let getDisplayList else {
            throw DisplayConnectionBackendError.missingPrivateSymbol("SLSGetDisplayList / CGSGetDisplayList")
        }

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
        guard let configureDisplayEnabled else {
            throw DisplayConnectionBackendError.missingPrivateSymbol("SLSConfigureDisplayEnabled / CGSConfigureDisplayEnabled")
        }

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

    private static func firstSymbol(
        names: [String],
        using lookup: PrivateDisplaySymbolLookup
    ) -> UnsafeMutableRawPointer? {
        names.lazy.compactMap { lookup.symbol(named: $0) }.first
    }
}
