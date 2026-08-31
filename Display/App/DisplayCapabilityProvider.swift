import Foundation

struct DisplayCapabilityInputs {
    let hasAmbientLightSensor: Bool
    let hasInternalBrightness: Bool
    let hasExternalDisplay: Bool
    let hasDDCExecutable: Bool
    let hasHiDPIPrivateAPI: Bool
    let hasSoftwareDisconnect: Bool
}

/// Owns capability policy and user-facing explanations. Hardware probing stays
/// with the relevant backend; this type only maps the latest cached facts to a
/// stable, fail-closed capability snapshot.
struct DisplayCapabilityProvider {
    func capabilities(for input: DisplayCapabilityInputs) -> DisplayCapabilities {
        let external: DisplayCapability = input.hasExternalDisplay
            ? .available
            : .unavailable("No supported external display is connected.")

        let ddc: DisplayCapability
        if !input.hasDDCExecutable {
            ddc = .unavailable("DDC is unavailable. Install m1ddc at /opt/homebrew/bin/m1ddc or /usr/local/bin/m1ddc.")
        } else if input.hasExternalDisplay {
            ddc = .available
        } else {
            ddc = .degraded("m1ddc is installed, but no supported external display is connected.")
        }

        let hiDPI: DisplayCapability
        if !input.hasExternalDisplay {
            hiDPI = .unavailable("HiDPI requires a supported external display.")
        } else if input.hasHiDPIPrivateAPI {
            hiDPI = .available
        } else {
            hiDPI = .unavailable("HiDPI private display APIs are unavailable on this macOS configuration.")
        }

        let connection: DisplayCapability
        if !input.hasSoftwareDisconnect {
            connection = .unavailable("Software display connection control is unavailable on this macOS configuration.")
        } else if input.hasExternalDisplay {
            connection = .available
        } else {
            connection = .degraded("No supported external display is connected.")
        }

        return DisplayCapabilities(
            ambientLightSensor: input.hasAmbientLightSensor
                ? .available
                : .unavailable("Ambient light sensor symbols are unavailable on this Mac."),
            internalBrightness: input.hasInternalBrightness
                ? .available
                : .unavailable("Internal display brightness is unavailable."),
            externalDisplay: external,
            ddc: ddc,
            volume: ddc,
            hiDPI: hiDPI,
            softwareDisconnect: connection,
            keepAwake: .available
        )
    }
}
