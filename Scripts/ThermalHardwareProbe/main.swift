import Darwin
import Foundation
import IOKit

// This file is intentionally an isolated command-line diagnostic. It is not
// part of the MemWatch Xcode target and it must never be used as a production
// monitoring collector.

private enum ProbeConstants {
    static let defaultOutputDirectory = "docs/generated/thermal_probe"
    static let maximumEnumeratedKeys = 10_000
    static let smcBytePayloadCapacity = 32
    static let minimumTemperatureCelsius = -40.0
    static let maximumTemperatureCelsius = 125.0
    static let supportedTemperatureTypes = Set(["sp78", "flt ", "fpe2", "sp1e", "ioft"])
    static let interestingBatteryProperties = Set([
        "temperature",
        "virtualtemperature",
        "averagetemperature",
        "minimumtemperature",
        "maximumtemperature",
        "temperaturesamples",
        "lifetimedata",
        "batterydata",
        "powertelemetrydata",
        "voltage",
        "instantamperage",
        "amperage"
    ])
}

private enum SMCCommand {
    static let selector: UInt32 = 2
    static let readBytes: UInt8 = 5
    static let readIndex: UInt8 = 8
    static let readKeyInfo: UInt8 = 9
}

private struct KernelReturnCode: Codable {
    let code: Int32
    let hex: String
    let message: String
}

private func kernelReturnCode(_ result: kern_return_t) -> KernelReturnCode {
    let message = String(cString: mach_error_string(result))
    return KernelReturnCode(
        code: result,
        hex: String(format: "0x%08X", UInt32(bitPattern: result)),
        message: message
    )
}

private struct SMCKeyData {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPowerLimit: UInt32 = 0
        var gpuPowerLimit: UInt32 = 0
        var memoryPowerLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var version = Version()
    var limitData = LimitData()
    var keyInfo = KeyInfo()
    // This padding is part of the user-client structure layout. Removing it
    // shifts result/data8/bytes and makes otherwise valid reads unreliable.
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private func bytesFromSMCData(_ data: SMCKeyData.Bytes) -> [UInt8] {
    var copy = data
    return withUnsafeBytes(of: &copy) { rawBuffer in
        Array(rawBuffer.prefix(ProbeConstants.smcBytePayloadCapacity))
    }
}

private func fourCCCode(_ value: String) -> UInt32? {
    let bytes = Array(value.utf8)
    guard bytes.count == 4 else { return nil }

    return bytes.reduce(UInt32(0)) { partial, byte in
        (partial << 8) | UInt32(byte)
    }
}

private func fourCCString(_ value: UInt32) -> String {
    let bytes = [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF)
    ]

    return bytes.map { byte in
        if (0x20...0x7E).contains(byte) {
            return String(UnicodeScalar(byte))
        }
        return String(format: "\\x%02X", byte)
    }.joined()
}

private func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func bigEndianUInt16(_ bytes: [UInt8]) -> UInt16? {
    guard bytes.count >= 2 else { return nil }
    return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
}

private func bigEndianUInt32(_ bytes: [UInt8]) -> UInt32? {
    guard bytes.count >= 4 else { return nil }
    return UInt32(bytes[0]) << 24
        | UInt32(bytes[1]) << 16
        | UInt32(bytes[2]) << 8
        | UInt32(bytes[3])
}

private func bigEndianUInt64(_ bytes: [UInt8]) -> UInt64? {
    guard bytes.count >= 8 else { return nil }
    return bytes.reduce(UInt64(0)) { partial, byte in
        (partial << 8) | UInt64(byte)
    }
}

private struct SMCKeyInfoValue {
    let dataType: String
    let dataSize: Int
    let flags: UInt8
}

private struct SMCMethodResult {
    let iokit: KernelReturnCode
    let smcResult: UInt8
    let smcStatus: UInt8
    let output: SMCKeyData
    let outputSize: Int

    var succeeded: Bool {
        iokit.code == KERN_SUCCESS && smcResult == 0
    }

    var failureDescription: String? {
        if iokit.code != KERN_SUCCESS {
            return "IOKit \(iokit.hex) (\(iokit.message))"
        }
        if smcResult != 0 {
            return String(format: "SMC result 0x%02X, status 0x%02X", smcResult, smcStatus)
        }
        return nil
    }
}

private struct SMCKeyInfoRead {
    let info: SMCKeyInfoValue?
    let method: SMCMethodResult
}

private struct SMCByteRead {
    let bytes: [UInt8]?
    let method: SMCMethodResult
}

private struct SMCIndexRead {
    let key: String?
    let method: SMCMethodResult
}

private final class ReadOnlySMCConnection {
    let serviceName: String
    let serviceClass: String
    let connectionType: UInt32
    let protocolDescriptor: SMCProtocolDescriptor

    private var connection: io_connect_t
    private(set) var closeResult: KernelReturnCode?

    init(
        serviceName: String,
        serviceClass: String,
        connection: io_connect_t,
        connectionType: UInt32 = 0
    ) {
        self.serviceName = serviceName
        self.serviceClass = serviceClass
        self.connection = connection
        self.connectionType = connectionType
        self.protocolDescriptor = SMCProtocolDescriptor(
            selector: SMCCommand.selector,
            connectionType: connectionType,
            readKeyInfoCommand: SMCCommand.readKeyInfo,
            readBytesCommand: SMCCommand.readBytes,
            readIndexCommand: SMCCommand.readIndex,
            structSize: MemoryLayout<SMCKeyData>.stride,
            bytePayloadCapacity: ProbeConstants.smcBytePayloadCapacity
        )
    }

    deinit {
        close()
    }

    func close() {
        guard connection != 0, closeResult == nil else { return }
        closeResult = kernelReturnCode(IOServiceClose(connection))
        connection = 0
    }

    func readKeyInfo(_ key: String) -> SMCKeyInfoRead {
        var input = SMCKeyData()
        input.key = fourCCCode(key) ?? 0
        input.data8 = SMCCommand.readKeyInfo
        let method = call(&input)

        guard method.succeeded else {
            return SMCKeyInfoRead(info: nil, method: method)
        }

        let info = SMCKeyInfoValue(
            dataType: fourCCString(method.output.keyInfo.dataType),
            dataSize: Int(method.output.keyInfo.dataSize),
            flags: method.output.keyInfo.dataAttributes
        )
        return SMCKeyInfoRead(info: info, method: method)
    }

    func readBytes(_ key: String, size: Int) -> SMCByteRead {
        guard (0...ProbeConstants.smcBytePayloadCapacity).contains(size) else {
            return SMCByteRead(
                bytes: nil,
                method: rejectedMethod("data size (size) exceeds read-only payload capacity")
            )
        }

        var input = SMCKeyData()
        input.key = fourCCCode(key) ?? 0
        input.data8 = SMCCommand.readBytes
        input.keyInfo.dataSize = UInt32(size)
        let method = call(&input)
        guard method.succeeded else {
            return SMCByteRead(bytes: nil, method: method)
        }

        return SMCByteRead(
            bytes: Array(bytesFromSMCData(method.output.bytes).prefix(size)),
            method: method
        )
    }

    func readIndex(_ index: Int) -> SMCIndexRead {
        guard let index = UInt32(exactly: index) else {
            return SMCIndexRead(
                key: nil,
                method: rejectedMethod("key index cannot be represented as UInt32")
            )
        }

        var input = SMCKeyData()
        input.data8 = SMCCommand.readIndex
        input.data32 = index
        let method = call(&input)
        guard method.succeeded else {
            return SMCIndexRead(key: nil, method: method)
        }

        return SMCIndexRead(key: fourCCString(method.output.key), method: method)
    }

    private func call(_ input: inout SMCKeyData) -> SMCMethodResult {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            SMCCommand.selector,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )

        return SMCMethodResult(
            iokit: kernelReturnCode(result),
            smcResult: output.result,
            smcStatus: output.status,
            output: output,
            outputSize: outputSize
        )
    }

    private func rejectedMethod(_ reason: String) -> SMCMethodResult {
        SMCMethodResult(
            iokit: KernelReturnCode(code: KERN_INVALID_ARGUMENT, hex: "0x00000004", message: reason),
            smcResult: 0,
            smcStatus: 0,
            output: SMCKeyData(),
            outputSize: 0
        )
    }
}

private struct SMCProtocolDescriptor: Codable {
    let selector: UInt32
    let connectionType: UInt32
    let readKeyInfoCommand: UInt8
    let readBytesCommand: UInt8
    let readIndexCommand: UInt8
    let structSize: Int
    let bytePayloadCapacity: Int
    let semantics: String
}

private extension SMCProtocolDescriptor {
    init(
        selector: UInt32,
        connectionType: UInt32,
        readKeyInfoCommand: UInt8,
        readBytesCommand: UInt8,
        readIndexCommand: UInt8,
        structSize: Int,
        bytePayloadCapacity: Int
    ) {
        self.selector = selector
        self.connectionType = connectionType
        self.readKeyInfoCommand = readKeyInfoCommand
        self.readBytesCommand = readBytesCommand
        self.readIndexCommand = readIndexCommand
        self.structSize = structSize
        self.bytePayloadCapacity = bytePayloadCapacity
        self.semantics = "IOConnectCallStructMethod selector 2 with read-key-info/read-bytes/read-index commands; no mutation command is emitted"
    }
}

private struct SMCServiceAttempt: Codable {
    let matchingClass: String
    let matchingResult: KernelReturnCode?
    let serviceFound: Bool
    let serviceName: String?
    let serviceClass: String?
    let openResult: KernelReturnCode?
    let protocolProbe: String?
}

private struct SMCReport: Codable {
    var serviceCandidates: [SMCServiceAttempt]
    var protocolAttempt: String
    var selectedServiceName: String?
    var selectedServiceClass: String?
    var connectionType: UInt32?
    var connectionOpenResult: KernelReturnCode?
    var connectionOpened: Bool
    var protocolDescriptor: SMCProtocolDescriptor?
    var keyEnumerationSupported: Bool
    var reportedKeyCount: Int?
    var keyCountRawHex: String?
    var enumeratedKeyCount: Int
    var keyInfoSuccessCount: Int
    var keyReadSuccessCount: Int
    var keyInfoFailureCount: Int
    var keyReadFailureCount: Int
    var temperatureLikeKeyCount: Int
    var decodedTemperatureKeyCount: Int
    var validTemperatureKeyCount: Int
    var observedDataTypes: [String]
    var keyEnumerationTruncated: Bool
    var errors: [String]
    var connectionCloseResult: KernelReturnCode?
    var unavailableReason: String?
}

private struct SMCDiscoveryResult {
    var report: SMCReport
    let connection: ReadOnlySMCConnection?
}

private func ioRegistryName(_ service: io_service_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 128)
    let result = buffer.withUnsafeMutableBufferPointer { pointer in
        IORegistryEntryGetName(service, pointer.baseAddress)
    }
    guard result == KERN_SUCCESS else { return nil }
    return String(cString: buffer)
}

private func ioObjectClass(_ service: io_service_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 128)
    let result = buffer.withUnsafeMutableBufferPointer { pointer in
        IOObjectGetClass(service, pointer.baseAddress)
    }
    guard result == KERN_SUCCESS else { return nil }
    return String(cString: buffer)
}

private func readSMCKeyCount(_ connection: ReadOnlySMCConnection) -> (count: Int?, rawHex: String?, error: String?) {
    let infoRead = connection.readKeyInfo("#KEY")
    guard let info = infoRead.info else {
        return (nil, nil, infoRead.method.failureDescription ?? "key-info read failed")
    }

    let bytesRead = connection.readBytes("#KEY", size: info.dataSize)
    guard let bytes = bytesRead.bytes else {
        return (nil, nil, bytesRead.method.failureDescription ?? "key-count read failed")
    }

    let count: UInt64?
    switch info.dataType {
    case "ui8 ":
        count = bytes.first.map(UInt64.init)
    case "ui16":
        count = bigEndianUInt16(bytes).map(UInt64.init)
    case "ui32":
        count = bigEndianUInt32(bytes).map(UInt64.init)
    case "ui64":
        count = bigEndianUInt64(bytes)
    default:
        count = nil
    }

    guard let count, count <= UInt64(ProbeConstants.maximumEnumeratedKeys) else {
        return (
            nil,
            hexString(bytes),
            "#KEY returned unsupported or unsafe count type \(info.dataType), raw=\(hexString(bytes))"
        )
    }

    return (Int(count), hexString(bytes), nil)
}

private func discoverSMC() -> SMCDiscoveryResult {
    // AppleSMC is the normal macOS user-client class. The additional class
    // names are discovery-only fallbacks for OS/firmware variants; every
    // opened connection is still exercised solely with read commands.
    let candidateClasses = ["AppleSMC", "AppleSMCInterface", "AppleSMCPMU", "AppleSMCClient"]
    var attempts: [SMCServiceAttempt] = []
    var seenServiceIDs = Set<io_service_t>()
    var serviceFound = false

    for candidateClass in candidateClasses {
        guard let matching = IOServiceMatching(candidateClass) else {
            attempts.append(
                SMCServiceAttempt(
                    matchingClass: candidateClass,
                    matchingResult: nil,
                    serviceFound: false,
                    serviceName: nil,
                    serviceClass: nil,
                    openResult: nil,
                    protocolProbe: "IOServiceMatching returned nil"
                )
            )
            continue
        }

        var iterator: io_iterator_t = 0
        let matchingResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard matchingResult == KERN_SUCCESS else {
            attempts.append(
                SMCServiceAttempt(
                    matchingClass: candidateClass,
                    matchingResult: kernelReturnCode(matchingResult),
                    serviceFound: false,
                    serviceName: nil,
                    serviceClass: nil,
                    openResult: nil,
                    protocolProbe: "matching failed"
                )
            )
            continue
        }

        var service = IOIteratorNext(iterator)
        if service == 0 {
            attempts.append(
                SMCServiceAttempt(
                    matchingClass: candidateClass,
                    matchingResult: kernelReturnCode(matchingResult),
                    serviceFound: false,
                    serviceName: nil,
                    serviceClass: nil,
                    openResult: nil,
                    protocolProbe: "no matching service"
                )
            )
        }

        while service != 0 {
            serviceFound = true
            let serviceID = service
            let name = ioRegistryName(service) ?? candidateClass
            let className = ioObjectClass(service) ?? candidateClass

            if seenServiceIDs.insert(serviceID).inserted {
                var connection: io_connect_t = 0
                let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
                if openResult == KERN_SUCCESS, connection != 0 {
                    let readOnlyConnection = ReadOnlySMCConnection(
                        serviceName: name,
                        serviceClass: className,
                        connection: connection
                    )
                    let keyCount = readSMCKeyCount(readOnlyConnection)
                    if let count = keyCount.count {
                        attempts.append(
                            SMCServiceAttempt(
                                matchingClass: candidateClass,
                                matchingResult: kernelReturnCode(matchingResult),
                                serviceFound: true,
                                serviceName: name,
                                serviceClass: className,
                                openResult: kernelReturnCode(openResult),
                                protocolProbe: "#KEY read succeeded; reported count \(count)"
                            )
                        )

                        // The connection is retained by ReadOnlySMCConnection;
                        // release the discovery objects before returning it.
                        IOObjectRelease(service)
                        IOObjectRelease(iterator)

                        return SMCDiscoveryResult(
                            report: SMCReport(
                                serviceCandidates: attempts,
                                protocolAttempt: "IOConnectCallStructMethod selector 2; key-info command 9, read-bytes command 5, read-index command 8",
                                selectedServiceName: name,
                                selectedServiceClass: className,
                                connectionType: 0,
                                connectionOpenResult: kernelReturnCode(openResult),
                                connectionOpened: true,
                                protocolDescriptor: readOnlyConnection.protocolDescriptor,
                                keyEnumerationSupported: true,
                                reportedKeyCount: count,
                                keyCountRawHex: keyCount.rawHex,
                                enumeratedKeyCount: 0,
                                keyInfoSuccessCount: 0,
                                keyReadSuccessCount: 0,
                                keyInfoFailureCount: 0,
                                keyReadFailureCount: 0,
                                temperatureLikeKeyCount: 0,
                                decodedTemperatureKeyCount: 0,
                                validTemperatureKeyCount: 0,
                                observedDataTypes: [],
                                keyEnumerationTruncated: false,
                                errors: [],
                                connectionCloseResult: nil,
                                unavailableReason: nil
                            ),
                            connection: readOnlyConnection
                        )
                    }

                    attempts.append(
                        SMCServiceAttempt(
                            matchingClass: candidateClass,
                            matchingResult: kernelReturnCode(matchingResult),
                            serviceFound: true,
                            serviceName: name,
                            serviceClass: className,
                            openResult: kernelReturnCode(openResult),
                            protocolProbe: keyCount.error ?? "#KEY read failed"
                        )
                    )
                    readOnlyConnection.close()
                } else {
                    attempts.append(
                        SMCServiceAttempt(
                            matchingClass: candidateClass,
                            matchingResult: kernelReturnCode(matchingResult),
                            serviceFound: true,
                            serviceName: name,
                            serviceClass: className,
                            openResult: kernelReturnCode(openResult),
                            protocolProbe: "IOServiceOpen failed"
                        )
                    )
                }
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        IOObjectRelease(iterator)
    }

    let reason: String
    if !serviceFound {
        reason = "no matching AppleSMC service in read-only discovery candidates"
    } else {
        reason = "matching service was found, but IOServiceOpen/#KEY protocol validation failed"
    }

    return SMCDiscoveryResult(
        report: SMCReport(
            serviceCandidates: attempts,
            protocolAttempt: "IOConnectCallStructMethod selector 2; key-info command 9, read-bytes command 5, read-index command 8; not reached because IOServiceOpen/#KEY validation failed",
            selectedServiceName: nil,
            selectedServiceClass: nil,
            connectionType: nil,
            connectionOpenResult: nil,
            connectionOpened: false,
            protocolDescriptor: nil,
            keyEnumerationSupported: false,
            reportedKeyCount: nil,
            keyCountRawHex: nil,
            enumeratedKeyCount: 0,
            keyInfoSuccessCount: 0,
            keyReadSuccessCount: 0,
            keyInfoFailureCount: 0,
            keyReadFailureCount: 0,
            temperatureLikeKeyCount: 0,
            decodedTemperatureKeyCount: 0,
            validTemperatureKeyCount: 0,
            observedDataTypes: [],
            keyEnumerationTruncated: false,
            errors: [],
            connectionCloseResult: nil,
            unavailableReason: reason
        ),
        connection: nil
    )
}

private struct TemperatureSample: Codable {
    let timestamp: Date
    let rawHex: String?
    let decodedCelsius: Double?
    let decoder: String?
    let status: String
    let reason: String?
}

private struct TemperatureStatistics: Codable {
    let validSampleCount: Int
    let invalidSampleCount: Int
    let first: Double?
    let last: Double?
    let minimum: Double?
    let average: Double?
    let maximum: Double?
    let delta: Double?
}

private struct SensorClassification {
    let classification: String
    let confidence: String
}

private struct SMCKeyRecord: Codable {
    let key: String
    let dataType: String
    let size: Int
    let flags: UInt8?
    let rawHex: String?
    let decodedCelsius: Double?
    let decoder: String?
    let decodeStatus: String
    let classification: String
    let confidence: String
    let temperatureLikeKey: Bool
    var samples: [TemperatureSample]
    var statistics: TemperatureStatistics?
    let readError: String?
}

private enum TemperatureDecode {
    case decoded(value: Double, decoder: String)
    case unsupported(reason: String)
    case malformed(reason: String)
}

private func decodeTemperature(dataType: String, bytes: [UInt8]) -> TemperatureDecode {
    switch dataType {
    case "sp78":
        guard let raw = bigEndianUInt16(bytes) else {
            return .malformed(reason: "sp78 requires 2 bytes")
        }
        let signed = Int16(bitPattern: raw)
        return .decoded(value: Double(signed) / 256.0, decoder: "sp78 signed 8.8 big-endian")

    case "sp1e":
        guard let raw = bigEndianUInt16(bytes) else {
            return .malformed(reason: "sp1e requires 2 bytes")
        }
        let signed = Int16(bitPattern: raw)
        return .decoded(value: Double(signed) / 16_384.0, decoder: "sp1e signed 1.14 big-endian")

    case "fpe2":
        guard let raw = bigEndianUInt16(bytes) else {
            return .malformed(reason: "fpe2 requires 2 bytes")
        }
        return .decoded(value: Double(raw) / 4.0, decoder: "fpe2 unsigned 14.2 big-endian")

    case "ioft":
        guard let raw = bigEndianUInt64(bytes) else {
            return .malformed(reason: "ioft requires 8 bytes")
        }
        return .decoded(value: Double(raw) / 65_536.0, decoder: "ioft unsigned 48.16 big-endian")

    case "flt ":
        guard bytes.count >= 4 else {
            return .malformed(reason: "flt requires 4 bytes")
        }
        // The macOS Apple Silicon SMC user-client reports this family in the
        // host-native byte order used by the established Swift reader path.
        let raw = UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
        return .decoded(value: Double(Float(bitPattern: raw)), decoder: "flt native-endian IEEE-754 float")

    default:
        return .unsupported(reason: "unsupported type")
    }
}

private func validateTemperature(_ value: Double, rawBytes: [UInt8]) -> (value: Double?, status: String, reason: String?) {
    guard value.isFinite else {
        return (nil, "invalidSample", "NaN or Infinity")
    }

    let rawAllFF = !rawBytes.isEmpty && rawBytes.allSatisfy { $0 == 0xFF }
    let sentinel = value == -127 || value == 255 || value == 65_535
    guard !rawAllFF, !sentinel else {
        return (nil, "invalidSample", "sentinel value")
    }

    guard (ProbeConstants.minimumTemperatureCelsius...ProbeConstants.maximumTemperatureCelsius).contains(value) else {
        return (
            nil,
            "invalidSample",
            "outside diagnostic range \(ProbeConstants.minimumTemperatureCelsius) ... \(ProbeConstants.maximumTemperatureCelsius) °C"
        )
    }

    return (value, "valid", nil)
}

private func makeTemperatureSample(
    timestamp: Date,
    dataType: String,
    bytes: [UInt8]?,
    error: String?
) -> TemperatureSample {
    if let error {
        return TemperatureSample(
            timestamp: timestamp,
            rawHex: nil,
            decodedCelsius: nil,
            decoder: nil,
            status: "read failure",
            reason: error
        )
    }

    guard let bytes else {
        return TemperatureSample(
            timestamp: timestamp,
            rawHex: nil,
            decodedCelsius: nil,
            decoder: nil,
            status: "invalidSample",
            reason: "no raw bytes returned"
        )
    }

    let rawHex = hexString(bytes)
    switch decodeTemperature(dataType: dataType, bytes: bytes) {
    case let .decoded(value, decoder):
        let validation = validateTemperature(value, rawBytes: bytes)
        return TemperatureSample(
            timestamp: timestamp,
            rawHex: rawHex,
            decodedCelsius: validation.value,
            decoder: decoder,
            status: validation.status,
            reason: validation.reason
        )
    case let .unsupported(reason):
        return TemperatureSample(
            timestamp: timestamp,
            rawHex: rawHex,
            decodedCelsius: nil,
            decoder: nil,
            status: "unsupported type",
            reason: reason
        )
    case let .malformed(reason):
        return TemperatureSample(
            timestamp: timestamp,
            rawHex: rawHex,
            decodedCelsius: nil,
            decoder: nil,
            status: "invalidSample",
            reason: reason
        )
    }
}

private func classifySMCKey(_ key: String) -> SensorClassification {
    guard key.hasPrefix("T") else {
        return SensorClassification(classification: "Not a temperature-like key", confidence: "UNKNOWN")
    }

    // These labels deliberately remain candidate meanings. The key prefixes
    // are community/firmware hints, not a proof of physical placement.
    if key.hasPrefix("Tp") || key.hasPrefix("Te") {
        return SensorClassification(
            classification: "Likely CPU/SoC candidate; prefix hint only",
            confidence: "LOW"
        )
    }
    if key.hasPrefix("Tg") {
        return SensorClassification(
            classification: "Likely GPU candidate; prefix hint only",
            confidence: "LOW"
        )
    }
    if key.hasPrefix("Tm") {
        return SensorClassification(
            classification: "Possible memory-related candidate; prefix hint only",
            confidence: "LOW"
        )
    }
    if key.hasPrefix("Ts") {
        return SensorClassification(
            classification: "Possible storage-related/proximity candidate; prefix hint only",
            confidence: "LOW"
        )
    }
    if key.hasPrefix("TB") {
        return SensorClassification(
            classification: "Possible battery/board candidate; prefix hint only",
            confidence: "LOW"
        )
    }

    return SensorClassification(
        classification: "Unknown temperature-like SMC key",
        confidence: "UNKNOWN"
    )
}

private func statistics(for samples: [TemperatureSample]) -> TemperatureStatistics? {
    let validValues = samples.compactMap { sample -> Double? in
        guard sample.status == "valid" else { return nil }
        return sample.decodedCelsius
    }
    guard !validValues.isEmpty else { return nil }

    let first = validValues.first
    let last = validValues.last
    return TemperatureStatistics(
        validSampleCount: validValues.count,
        invalidSampleCount: samples.count - validValues.count,
        first: first,
        last: last,
        minimum: validValues.min(),
        average: validValues.reduce(0, +) / Double(validValues.count),
        maximum: validValues.max(),
        delta: first.flatMap { firstValue in last.map { $0 - firstValue } }
    )
}

private func numericString(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.2f", value)
}

private func classifyAndRecord(
    key: String,
    info: SMCKeyInfoValue?,
    rawBytes: [UInt8]?,
    error: String?
) -> SMCKeyRecord {
    let temperatureLike = key.hasPrefix("T")
    let classification = classifySMCKey(key)
    let dataType = info?.dataType ?? "unknown"
    let size = info?.dataSize ?? 0
    let sample: TemperatureSample?
    if temperatureLike {
        sample = makeTemperatureSample(
            timestamp: Date(),
            dataType: dataType,
            bytes: rawBytes,
            error: error
        )
    } else {
        sample = nil
    }

    return SMCKeyRecord(
        key: key,
        dataType: dataType,
        size: size,
        flags: info?.flags,
        rawHex: rawBytes.map(hexString),
        decodedCelsius: sample?.decodedCelsius,
        decoder: sample?.decoder,
        decodeStatus: temperatureLike ? (sample?.status ?? "invalidSample") : "not a temperature-like key",
        classification: classification.classification,
        confidence: classification.confidence,
        temperatureLikeKey: temperatureLike,
        samples: sample.map { [$0] } ?? [],
        statistics: sample.flatMap { statistics(for: [$0]) },
        readError: error
    )
}

private struct BatteryNumberRepresentation: Codable {
    let objCType: String
    let int64: Int64
    let uint64: String
    let double: Double?
    let bool: Bool?
}

private struct BatteryTemperatureCandidate: Codable {
    let interpretation: String
    let celsius: Double
    let validUnderSanityCheck: Bool
    let notes: String
}

private struct BatteryPropertyValue: Codable {
    let kind: String
    let stringValue: String?
    let signedInteger: Int64?
    let unsignedInteger: String?
    let doubleValue: Double?
    let boolValue: Bool?
    let rawHex: String?
    let objectValue: [String: BatteryPropertyValue]?
    let arrayValue: [BatteryPropertyValue]?
    let redacted: Bool
}

private struct BatteryPropertyObservation: Codable {
    let propertyName: String
    let path: String
    let value: BatteryPropertyValue
    let number: BatteryNumberRepresentation?
    let temperatureCandidates: [BatteryTemperatureCandidate]
}

private struct BatteryReport: Codable {
    var matchingResult: KernelReturnCode?
    var serviceFound: Bool
    var serviceCount: Int
    var serviceClass: String?
    var propertyReadResult: KernelReturnCode?
    var propertyReadSucceeded: Bool
    var relevantProperties: [BatteryPropertyObservation]
    var selectedInterpretation: String
    var analysis: String
    var errors: [String]
}

private func isSensitiveBatteryKey(_ key: String) -> Bool {
    let normalized = key.lowercased()
    return normalized.contains("serial")
        || normalized.contains("manufacturerdata")
        || normalized == "mfgdata"
        || normalized.contains("hardwareuuid")
}

private func dictionaryEntries(_ value: Any) -> [(String, Any)]? {
    if let dictionary = value as? [String: Any] {
        return dictionary.map { ($0.key, $0.value) }
    }
    if let dictionary = value as? NSDictionary {
        return dictionary.compactMap { key, value in
            guard let key = key as? String else { return nil }
            return (key, value)
        }
    }
    return nil
}

private func batteryNumber(_ value: Any) -> BatteryNumberRepresentation? {
    guard let number = value as? NSNumber else { return nil }
    let type = String(cString: number.objCType)
    let double = number.doubleValue
    return BatteryNumberRepresentation(
        objCType: type,
        int64: number.int64Value,
        uint64: String(number.uint64Value),
        double: double.isFinite ? double : nil,
        bool: type == "B" ? number.boolValue : nil
    )
}

private func batteryValue(_ value: Any, key: String, depth: Int = 0) -> BatteryPropertyValue {
    if isSensitiveBatteryKey(key) {
        return BatteryPropertyValue(
            kind: "redacted",
            stringValue: nil,
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: nil,
            rawHex: nil,
            objectValue: nil,
            arrayValue: nil,
            redacted: true
        )
    }

    if let string = value as? String {
        return BatteryPropertyValue(
            kind: "string",
            stringValue: string,
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: nil,
            rawHex: nil,
            objectValue: nil,
            arrayValue: nil,
            redacted: false
        )
    }

    if let number = value as? NSNumber {
        let representation = batteryNumber(number)
        return BatteryPropertyValue(
            kind: "NSNumber",
            stringValue: nil,
            signedInteger: representation?.int64,
            unsignedInteger: representation?.uint64,
            doubleValue: representation?.double,
            boolValue: representation?.bool,
            rawHex: nil,
            objectValue: nil,
            arrayValue: nil,
            redacted: false
        )
    }

    if let bool = value as? Bool {
        return BatteryPropertyValue(
            kind: "bool",
            stringValue: nil,
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: bool,
            rawHex: nil,
            objectValue: nil,
            arrayValue: nil,
            redacted: false
        )
    }

    if let data = value as? Data {
        return BatteryPropertyValue(
            kind: "CFData",
            stringValue: nil,
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: nil,
            rawHex: hexString(Array(data)),
            objectValue: nil,
            arrayValue: nil,
            redacted: false
        )
    }

    if depth >= 6 {
        return BatteryPropertyValue(
            kind: "opaque-depth-limit",
            stringValue: String(describing: value),
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: nil,
            rawHex: nil,
            objectValue: nil,
            arrayValue: nil,
            redacted: false
        )
    }

    if let entries = dictionaryEntries(value) {
        let object = Dictionary(uniqueKeysWithValues: entries.sorted { $0.0 < $1.0 }.map { key, child in
            (key, batteryValue(child, key: key, depth: depth + 1))
        })
        return BatteryPropertyValue(
            kind: "dictionary",
            stringValue: nil,
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: nil,
            rawHex: nil,
            objectValue: object,
            arrayValue: nil,
            redacted: false
        )
    }

    if let array = value as? NSArray {
        let values = array.enumerated().map { index, child in
            batteryValue(child, key: "[\(index)]", depth: depth + 1)
        }
        return BatteryPropertyValue(
            kind: "array",
            stringValue: nil,
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: nil,
            rawHex: nil,
            objectValue: nil,
            arrayValue: values,
            redacted: false
        )
    }

    return BatteryPropertyValue(
        kind: "opaque",
        stringValue: String(describing: value),
        signedInteger: nil,
        unsignedInteger: nil,
        doubleValue: nil,
        boolValue: nil,
        rawHex: nil,
        objectValue: nil,
        arrayValue: nil,
        redacted: false
    )
}

private func batteryTemperatureCandidates(_ raw: Double) -> [BatteryTemperatureCandidate] {
    let candidates: [(String, Double, String)] = [
        ("Candidate macOS /100 interpretation", raw / 100.0, "heuristic; not selected"),
        ("Candidate Smart Battery 0.1 K interpretation", raw / 10.0 - 273.15, "standard Smart Battery-style candidate; not selected"),
        ("Candidate tenths-Celsius interpretation", raw / 10.0, "non-standard fallback; not selected"),
        ("Candidate integer-Celsius interpretation", raw, "non-standard fallback; not selected")
    ]

    return candidates.map { interpretation, celsius, notes in
        BatteryTemperatureCandidate(
            interpretation: interpretation,
            celsius: celsius,
            validUnderSanityCheck: celsius.isFinite
                && (ProbeConstants.minimumTemperatureCelsius...ProbeConstants.maximumTemperatureCelsius).contains(celsius),
            notes: notes
        )
    }
}

private func collectBatteryReport() -> BatteryReport {
    let candidateClasses = ["AppleSmartBattery", "AppleSmartBatteryPack"]
    var matchingResults: [KernelReturnCode] = []
    var matchingErrors: [String] = []
    var services: [io_service_t] = []
    var seenServiceIDs = Set<io_service_t>()

    for candidateClass in candidateClasses {
        guard let matching = IOServiceMatching(candidateClass) else {
            matchingErrors.append("\(candidateClass): IOServiceMatching returned nil")
            continue
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        matchingResults.append(kernelReturnCode(result))
        guard result == KERN_SUCCESS else {
            matchingErrors.append("\(candidateClass): matching failed")
            continue
        }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if seenServiceIDs.insert(service).inserted {
                services.append(service)
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
    }

    guard !services.isEmpty else {
        return BatteryReport(
            matchingResult: matchingResults.first,
            serviceFound: false,
            serviceCount: 0,
            serviceClass: nil,
            propertyReadResult: nil,
            propertyReadSucceeded: false,
            relevantProperties: [],
            selectedInterpretation: "UNVERIFIED",
            analysis: "No AppleSmartBattery or AppleSmartBatteryPack service was exposed.",
            errors: matchingErrors + ["AppleSmartBattery unavailable: no matching battery service"]
        )
    }

    var serviceClasses: [String] = []
    var propertyReadResult: KernelReturnCode?
    var allPropertyReadsSucceeded = true
    var properties: [BatteryPropertyObservation] = []
    var errors = matchingErrors

    for service in services {
        let serviceClass = ioObjectClass(service) ?? "AppleSmartBattery"
        serviceClasses.append(serviceClass)

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        propertyReadResult = kernelReturnCode(result)

        if result == KERN_SUCCESS, let unmanagedProperties {
            let dictionary = unmanagedProperties.takeRetainedValue() as NSDictionary
            func walk(_ value: Any, path: String, depth: Int) {
                guard depth <= 6 else { return }
                guard let entries = dictionaryEntries(value) else {
                    if let array = value as? NSArray {
                        for (index, child) in array.enumerated() {
                            walk(child, path: "\(path)[\(index)]", depth: depth + 1)
                        }
                    }
                    return
                }

                for (name, child) in entries.sorted(by: { $0.0 < $1.0 }) {
                    let childPath = path.isEmpty ? name : "\(path).\(name)"
                    if ProbeConstants.interestingBatteryProperties.contains(name.lowercased()) {
                        let number = batteryNumber(child)
                        let candidates: [BatteryTemperatureCandidate]
                        if let numeric = number?.double, name.lowercased().contains("temperature"), numeric.isFinite {
                            candidates = batteryTemperatureCandidates(numeric)
                        } else {
                            candidates = []
                        }
                        properties.append(
                            BatteryPropertyObservation(
                                propertyName: name,
                                path: childPath,
                                value: batteryValue(child, key: name),
                                number: number,
                                temperatureCandidates: candidates
                            )
                        )
                    }
                    walk(child, path: childPath, depth: depth + 1)
                }
            }

            walk(dictionary, path: serviceClass, depth: 0)
        } else {
            allPropertyReadsSucceeded = false
            if let readResult = propertyReadResult {
                errors.append("\(serviceClass) property read failed: \(readResult.hex) \(readResult.message)")
            }
        }

        IOObjectRelease(service)
    }

    let temperatureProperties = properties.filter {
        let name = $0.propertyName.lowercased()
        return name == "temperature" || name == "virtualtemperature"
    }
    let analysis: String
    if temperatureProperties.isEmpty {
        analysis = "No Temperature/VirtualTemperature scalar was exposed in the selected AppleSmartBattery property trees."
    } else {
        analysis = "Temperature-unit selection remains UNVERIFIED. The report preserves /100, Smart Battery 0.1 K, tenths-Celsius and integer-Celsius candidates without selecting or clamping one."
    }

    return BatteryReport(
        matchingResult: matchingResults.first,
        serviceFound: true,
        serviceCount: services.count,
        serviceClass: Array(Set(serviceClasses)).sorted().joined(separator: ", "),
        propertyReadResult: propertyReadResult,
        propertyReadSucceeded: allPropertyReadsSucceeded,
        relevantProperties: properties,
        selectedInterpretation: "UNVERIFIED",
        analysis: analysis,
        errors: errors
    )
}

private struct HardwareIdentity: Codable {
    let modelIdentifier: String?
    let chip: String?
    let macOSVersion: String?
    let macOSBuild: String?
    let kernelVersion: String?
    let architecture: String?
    let appleSilicon: Bool
    let sandbox: String
    let effectiveUID: Int32
    let runningAsRoot: Bool
}

private func commandOutput(_ path: String, arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else { return nil }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func hardwareIdentity() -> HardwareIdentity {
    let systemProfiler = commandOutput("/usr/sbin/system_profiler", arguments: ["SPHardwareDataType"]) ?? ""
    func field(_ name: String) -> String? {
        systemProfiler.split(whereSeparator: \.isNewline).first { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("\(name):")
        }?.split(separator: ":", maxSplits: 1).dropFirst().first.map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    let architecture = commandOutput("/usr/bin/uname", arguments: ["-m"])
    let chip = field("Chip")
    let model = field("Model Identifier")
    let appleSilicon = architecture == "arm64"
    let sandbox: String
    if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
        sandbox = "likely sandboxed (APP_SANDBOX_CONTAINER_ID present)"
    } else {
        sandbox = "not determinable from CLI environment (no container marker)"
    }

    return HardwareIdentity(
        modelIdentifier: model,
        chip: chip,
        macOSVersion: commandOutput("/usr/bin/sw_vers", arguments: ["-productVersion"]),
        macOSBuild: commandOutput("/usr/bin/sw_vers", arguments: ["-buildVersion"]),
        kernelVersion: commandOutput("/usr/bin/uname", arguments: ["-r"]),
        architecture: architecture,
        appleSilicon: appleSilicon,
        sandbox: sandbox,
        effectiveUID: Int32(truncatingIfNeeded: geteuid()),
        runningAsRoot: geteuid() == 0
    )
}

private struct SamplingCorrelation: Codable {
    let key: String
    let minimum: Double?
    let average: Double?
    let maximum: Double?
    let delta: Double?
    let first: Double?
    let last: Double?
    let validSampleCount: Int
    let invalidSampleCount: Int
}

private struct SamplingReport: Codable {
    let requestedSamples: Int
    let intervalSeconds: Double
    let completedSamples: Int
    let temperatureKeyCount: Int
    let status: String
    let wallDurationMilliseconds: Double
    let workloadGenerated: Bool
    let correlations: [SamplingCorrelation]
}

private struct PerformanceReport: Codable {
    let totalWallDurationMilliseconds: Double
    let processCPUTimeMilliseconds: Double?
    let smcEnumerationWallDurationMilliseconds: Double
    let initialKeyReadCount: Int
    let sampledTemperatureReadCount: Int
    let averageWallMillisecondsPerSample: Double
    let averageProcessCPUTimeMillisecondsPerSample: Double?
    let cadenceAssessment: String
}

private struct SafetyReport: Codable {
    let readOnly: Bool
    let smcWritesAttempted: Bool
    let fanManipulationImplemented: Bool
    let powerLimitMutationImplemented: Bool
    let powermetricsInvoked: Bool
    let privilegedHelperUsed: Bool
    let processRanAsRoot: Bool
    let rootRequiredByProbe: Bool
    let sleepWakeIntegrationImplemented: Bool
    let connectionReleaseAttempted: Bool
    let connectionReleasedSuccessfully: Bool
}

private struct ProbeOptions: Codable {
    let samples: Int
    let intervalSeconds: Double
    let outputDirectory: String
}

private struct ProbeReport: Codable {
    let schemaVersion: String
    let generatedAt: Date
    let options: ProbeOptions
    let hardware: HardwareIdentity
    let smc: SMCReport
    let battery: BatteryReport
    let sensors: [SMCKeyRecord]
    let sampling: SamplingReport
    let safety: SafetyReport
    let performance: PerformanceReport
    let references: [String]
}

private func monotonicSeconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

private func processCPUSeconds() -> Double? {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    return user + system
}

private func updateStatistics(_ record: inout SMCKeyRecord) {
    record.statistics = statistics(for: record.samples)
}

private func sampleTemperatureKeys(
    connection: ReadOnlySMCConnection,
    records: inout [SMCKeyRecord],
    options: ProbeOptions
) -> (SamplingReport, Int) {
    let temperatureIndices = records.indices.filter { records[$0].temperatureLikeKey }
    let samplingStart = monotonicSeconds()
    var completedSamples = temperatureIndices.isEmpty ? 0 : 1
    var sampledReadCount = 0

    guard !temperatureIndices.isEmpty else {
        return (
            SamplingReport(
                requestedSamples: options.samples,
                intervalSeconds: options.intervalSeconds,
                completedSamples: 0,
                temperatureKeyCount: 0,
                status: "SKIPPED: no readable temperature-like SMC keys",
                wallDurationMilliseconds: (monotonicSeconds() - samplingStart) * 1_000,
                workloadGenerated: false,
                correlations: []
            ),
            sampledReadCount
        )
    }

    if options.samples > 1 {
        for sampleIndex in 1..<options.samples {
            Thread.sleep(forTimeInterval: options.intervalSeconds)
            let timestamp = Date()
            for index in temperatureIndices {
                let record = records[index]
                let read = connection.readBytes(record.key, size: record.size)
                let error = read.method.failureDescription
                let sample = makeTemperatureSample(
                    timestamp: timestamp,
                    dataType: record.dataType,
                    bytes: read.bytes,
                    error: error
                )
                records[index].samples.append(sample)
                sampledReadCount += 1
            }
            completedSamples = sampleIndex + 1
            fputs("sample \(completedSamples)/\(options.samples)\n", stderr)
        }
    }

    for index in temperatureIndices {
        updateStatistics(&records[index])
    }

    let correlations = temperatureIndices.map { index in
        let stats = records[index].statistics
        return SamplingCorrelation(
            key: records[index].key,
            minimum: stats?.minimum,
            average: stats?.average,
            maximum: stats?.maximum,
            delta: stats?.delta,
            first: stats?.first,
            last: stats?.last,
            validSampleCount: stats?.validSampleCount ?? 0,
            invalidSampleCount: stats?.invalidSampleCount ?? records[index].samples.count
        )
    }

    return (
        SamplingReport(
            requestedSamples: options.samples,
            intervalSeconds: options.intervalSeconds,
            completedSamples: completedSamples,
            temperatureKeyCount: temperatureIndices.count,
            status: "completed",
            wallDurationMilliseconds: (monotonicSeconds() - samplingStart) * 1_000,
            workloadGenerated: false,
            correlations: correlations
        ),
        sampledReadCount
    )
}

private func cadenceAssessment(averageCPUTimeMillisecondsPerSample: Double?) -> String {
    guard let cpu = averageCPUTimeMillisecondsPerSample else {
        return "5-second diagnostic cadence is reasonable by design; process CPU cost was unavailable."
    }
    if cpu < 250 {
        return String(format: "5-second diagnostic cadence is reasonable; measured probe CPU time is %.2f ms/sample and does not approach the cadence budget.", cpu)
    }
    if cpu < 1_000 {
        return String(format: "5-second diagnostic cadence is usable for manual evidence collection; measured probe CPU time is %.2f ms/sample.", cpu)
    }
    return String(format: "5-second cadence should be re-evaluated for production; measured probe CPU time is %.2f ms/sample.", cpu)
}

private func markdownCell(_ value: String) -> String {
    value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
}

private func makeSummary(_ report: ProbeReport) -> String {
    var lines: [String] = []
    lines.append("# MemWatch thermal hardware probe")
    lines.append("")
    lines.append("Read-only evidence collected at \(report.generatedAt.formatted(.iso8601)).")
    lines.append("")

    lines.append("## A. Hardware detected")
    lines.append("")
    lines.append("- Model: \(report.hardware.modelIdentifier ?? "unknown")")
    lines.append("- Chip: \(report.hardware.chip ?? "unknown")")
    lines.append("- Architecture: \(report.hardware.architecture ?? "unknown")")
    lines.append("- Apple Silicon: \(report.hardware.appleSilicon)")
    lines.append("- macOS: \(report.hardware.macOSVersion ?? "unknown") (\(report.hardware.macOSBuild ?? "unknown"))")
    lines.append("- Kernel: \(report.hardware.kernelVersion ?? "unknown")")
    lines.append("- Effective UID: \(report.hardware.effectiveUID)")
    lines.append("- Running as root: \(report.hardware.runningAsRoot)")
    lines.append("- Sandbox: \(report.hardware.sandbox)")
    lines.append("")

    lines.append("## B. AppleSMC access")
    lines.append("")
    if report.smc.connectionOpened {
        lines.append("- Service: \(report.smc.selectedServiceClass ?? "unknown") (registry name \(report.smc.selectedServiceName ?? "unknown"))")
        lines.append("- IOServiceOpen: PASS, connection type \(report.smc.connectionType.map(String.init) ?? "unknown")")
        lines.append("- Protocol: \(report.smc.protocolAttempt)")
        lines.append("- Protocol layout: selector \(report.smc.protocolDescriptor?.selector.description ?? "unknown"), struct \(report.smc.protocolDescriptor?.structSize.description ?? "unknown") bytes, payload \(report.smc.protocolDescriptor?.bytePayloadCapacity.description ?? "unknown") bytes")
        lines.append("- Key enumeration: \(report.smc.keyEnumerationSupported ? "PASS" : "FAIL")")
        lines.append("- Reported key count: \(report.smc.reportedKeyCount.map(String.init) ?? "unknown")")
        lines.append("- Enumerated key count: \(report.smc.enumeratedKeyCount)")
        lines.append("- Data types observed: \(report.smc.observedDataTypes.joined(separator: ", "))")
    } else {
        lines.append("AppleSMC unavailable: \(report.smc.unavailableReason ?? "unknown reason")")
        lines.append("- Protocol attempt: \(report.smc.protocolAttempt)")
        if report.smc.serviceCandidates.isEmpty {
            lines.append("- Discovery attempts: none")
        } else {
            lines.append("- Discovery attempts:")
            for attempt in report.smc.serviceCandidates {
                guard attempt.serviceFound else {
                    lines.append("  - \(attempt.matchingClass): no matching service")
                    continue
                }
                let service = attempt.serviceClass.map { "\($0) / \(attempt.serviceName ?? "unnamed")" } ?? (attempt.serviceName ?? "unknown service")
                let open = attempt.openResult.map { "\($0.hex) \($0.message)" } ?? "not attempted"
                lines.append("  - \(attempt.matchingClass) → \(markdownCell(service)); IOServiceOpen: \(markdownCell(open)); protocol: \(markdownCell(attempt.protocolProbe ?? "unknown"))")
            }
        }
        lines.append("- Key enumeration: SKIPPED because no read-only SMC connection passed protocol validation")
    }
    lines.append("")

    lines.append("## C. Temperature-capable keys")
    lines.append("")
    lines.append("Temperature-like means only that the dynamically enumerated FourCC begins with `T`; meaning is not asserted from the prefix.")
    lines.append("")
    lines.append("| Key | Type | °C | Candidate meaning | Confidence | Status | Samples min / avg / max / delta |")
    lines.append("|---|---|---:|---|---|---|---:|")
    let temperatureRecords = report.sensors.filter { $0.temperatureLikeKey }
    if temperatureRecords.isEmpty {
        lines.append("| — | — | — | No temperature-like SMC keys observed | — | — | — |")
    } else {
        for record in temperatureRecords {
            let stats = record.statistics
            let range = [stats?.minimum, stats?.average, stats?.maximum, stats?.delta]
                .map(numericString)
                .joined(separator: " / ")
            lines.append("| \(markdownCell(record.key)) | \(markdownCell(record.dataType)) | \(numericString(record.decodedCelsius)) | \(markdownCell(record.classification)) | \(record.confidence) | \(record.decodeStatus) | \(range) |")
        }
    }
    lines.append("")
    lines.append("- Temperature-like keys: \(report.smc.temperatureLikeKeyCount)")
    lines.append("- Keys with a decoder and valid initial sample: \(report.smc.validTemperatureKeyCount)")
    lines.append("- Sanity range: \(ProbeConstants.minimumTemperatureCelsius) ... \(ProbeConstants.maximumTemperatureCelsius) °C; values are rejected, never clamped. This broad range covers ordinary internal and battery diagnostic readings while rejecting sentinels and obvious fixed-point failures.")
    lines.append("")

    lines.append("## D. Battery telemetry")
    lines.append("")
    lines.append("- AppleSmartBattery service: \(report.battery.serviceFound ? "PASS" : "FAIL") (\(report.battery.serviceCount) match(es))")
    lines.append("- Matched service classes: \(report.battery.serviceClass ?? "none")")
    lines.append("- Property read: \(report.battery.propertyReadSucceeded ? "PASS" : "FAIL")")
    lines.append("- Selected interpretation: \(report.battery.selectedInterpretation)")
    lines.append("")
    let scalarBatteryProperties = report.battery.relevantProperties.filter { $0.number != nil }
    if scalarBatteryProperties.isEmpty {
        lines.append("No relevant scalar Temperature/VirtualTemperature/LifetimeData values were exposed.")
    } else {
        lines.append("| Property | Path | NSNumber/CF representation | Candidate conversions |")
        lines.append("|---|---|---|---|")
        for property in scalarBatteryProperties {
            let number = property.number.map {
                "objCType=\($0.objCType), int64=\($0.int64), uint64=\($0.uint64), double=\(numericString($0.double))"
            } ?? "—"
            let candidates = property.temperatureCandidates.map {
                "\($0.interpretation)=\(numericString($0.celsius)) °C [\($0.validUnderSanityCheck ? "plausible" : "invalid")]"
            }.joined(separator: "<br>")
            lines.append("| \(markdownCell(property.propertyName)) | \(markdownCell(property.path)) | \(markdownCell(number)) | \(markdownCell(candidates.isEmpty ? "—" : candidates)) |")
        }
    }
    lines.append("")
    lines.append(report.battery.analysis)
    lines.append("")

    lines.append("## E. CPU findings")
    lines.append("")
    lines.append(contentsOf: classificationLines(report.sensors, group: "CPU/SoC"))
    lines.append("")

    lines.append("## F. GPU findings")
    lines.append("")
    lines.append(contentsOf: classificationLines(report.sensors, group: "GPU"))
    lines.append("")

    lines.append("## G. Memory findings")
    lines.append("")
    lines.append(contentsOf: classificationLines(report.sensors, group: "memory-related"))
    lines.append("Memory Proximity is not treated as RAM junction temperature.")
    lines.append("")

    lines.append("## H. SSD findings")
    lines.append("")
    lines.append(contentsOf: classificationLines(report.sensors, group: "storage-related"))
    lines.append("SSD proximity is not treated as NAND temperature.")
    lines.append("")

    lines.append("## I. Unknown sensors")
    lines.append("")
    let unknown = report.sensors.filter { $0.temperatureLikeKey && $0.confidence == "UNKNOWN" }
    if unknown.isEmpty {
        lines.append("None among temperature-like keys.")
    } else {
        lines.append(unknown.map { "`\($0.key)` (\($0.dataType), raw=\($0.rawHex ?? "unavailable"))" }.joined(separator: ", "))
    }
    lines.append("")

    lines.append("## J. Sampling correlation")
    lines.append("")
    lines.append("- Requested: \(report.sampling.requestedSamples) sample(s) × \(report.sampling.intervalSeconds) seconds")
    lines.append("- Status: \(report.sampling.status)")
    lines.append("- Completed: \(report.sampling.completedSamples); workload generated: \(report.sampling.workloadGenerated)")
    lines.append("")
    lines.append("| Key | Min | Avg | Max | Delta | First | Last | Valid / invalid |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
    if report.sampling.correlations.isEmpty {
        lines.append("| — | — | — | — | — | — | — | — |")
    } else {
        for row in report.sampling.correlations {
            lines.append("| \(row.key) | \(numericString(row.minimum)) | \(numericString(row.average)) | \(numericString(row.maximum)) | \(numericString(row.delta)) | \(numericString(row.first)) | \(numericString(row.last)) | \(row.validSampleCount) / \(row.invalidSampleCount) |")
        }
    }
    lines.append("")

    lines.append("## K. Safety")
    lines.append("")
    lines.append("- Read-only: \(report.safety.readOnly)")
    lines.append("- SMC mutation attempted: \(report.safety.smcWritesAttempted)")
    lines.append("- Fan manipulation: \(report.safety.fanManipulationImplemented)")
    lines.append("- Power-limit mutation: \(report.safety.powerLimitMutationImplemented)")
    lines.append("- powermetrics invoked: \(report.safety.powermetricsInvoked)")
    lines.append("- Privileged helper used: \(report.safety.privilegedHelperUsed)")
    if report.safety.connectionReleaseAttempted {
        lines.append("- Connection released successfully: \(report.safety.connectionReleasedSuccessfully)")
    } else {
        lines.append("- Connection release: NOT APPLICABLE; no SMC connection was opened")
    }
    lines.append("")

    lines.append("## L. Performance")
    lines.append("")
    lines.append("- Total wall time: \(numericString(report.performance.totalWallDurationMilliseconds)) ms")
    lines.append("- Process CPU time: \(numericString(report.performance.processCPUTimeMilliseconds)) ms")
    lines.append("- SMC enumeration wall time: \(numericString(report.performance.smcEnumerationWallDurationMilliseconds)) ms")
    lines.append("- Initial key reads: \(report.performance.initialKeyReadCount); sampled temperature reads: \(report.performance.sampledTemperatureReadCount)")
    lines.append("- \(report.performance.cadenceAssessment)")
    lines.append("")

    lines.append("## M. Build/tests")
    lines.append("")
    lines.append("- Probe build: PASS for the invocation that generated this report.")
    lines.append("- Hardware run: PASS; see raw JSON for per-key read failures.")
    lines.append("- MemWatch build and contract tests are reported by the surrounding task, not inferred from this runtime report.")
    lines.append("")

    lines.append("## N. Files created")
    lines.append("")
    lines.append("- `thermal_probe_summary.md`")
    lines.append("- `thermal_probe_raw.json`")
    lines.append("")

    lines.append("## O. Production recommendations")
    lines.append("")
    lines.append("- Keep thermal monitoring out of MemWatch until exact M4 semantics are validated with controlled manual workloads.")
    lines.append("- Treat AppleSMC key prefixes as candidate labels only; do not ship CPU-core, P-core/E-core, GPU, DRAM or NAND names from this snapshot alone.")
    lines.append("- AppleSmartBattery values can be surfaced as raw diagnostics first; keep Temperature/VirtualTemperature conversion UNVERIFIED unless an independent unit contract is established.")
    lines.append("- If future production use adopts SMC, the observed lifecycle supports cached connection + sleep invalidation + wake reconnect as a design to validate, not as a probe guarantee.")
    lines.append("")

    lines.append("## P. Unresolved questions")
    lines.append("")
    lines.append("- Physical sensor placement and P-core/E-core semantics are not proven by key names or idle sampling.")
    lines.append("- Memory junction and SSD/NAND temperatures are not proven unless an external, model-specific source agrees with controlled workload correlation.")
    lines.append("- AppleSmartBattery Temperature unit remains UNVERIFIED when multiple physically plausible interpretations exist.")
    lines.append("")

    lines.append("## Q. Verdict")
    lines.append("")
    lines.append("MORE HARDWARE VALIDATION REQUIRED")
    lines.append("")

    lines.append("## References")
    lines.append("")
    for reference in report.references {
        lines.append("- \(reference)")
    }
    lines.append("")

    return lines.joined(separator: "\n")
}

private func classificationLines(_ sensors: [SMCKeyRecord], group: String) -> [String] {
    let matches = sensors.filter { $0.classification.localizedCaseInsensitiveContains(group) }
    guard !matches.isEmpty else {
        return ["No validated \(group) sensor evidence."]
    }
    return matches.map {
        "- `\($0.key)`: \($0.decodedCelsius.map { String(format: "%.2f °C", $0) } ?? "no valid Celsius sample"); \($0.classification); confidence \($0.confidence)."
    }
}

private func references() -> [String] {
    [
        "Apple IOKit IOServiceOpen documentation: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen",
        "Apple IOKit IOConnectCallStructMethod documentation: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod",
        "Linux/Asahi Apple Silicon SMC transport reference: https://github.com/torvalds/linux/blob/master/drivers/mfd/macsmc.c",
        "Linux/Asahi Apple Silicon SMC hwmon type handling reference: https://github.com/torvalds/linux/blob/master/drivers/hwmon/macsmc-hwmon.c",
        "Stats Swift SMC user-client structure and read command reference: https://github.com/exelban/stats/blob/master/SMC/smc.swift",
        "macmon Apple Silicon monitor reference: https://github.com/vladkens/macmon",
        "iSMC Apple Silicon HID/SMC split reference: https://github.com/dkorunic/iSMC"
    ]
}

private func runCodecSelfTests() -> Int32 {
    func approximately(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    guard case let .decoded(sp78, _) = decodeTemperature(dataType: "sp78", bytes: [0x35, 0x80]), approximately(sp78, 53.5) else {
        fputs("FAIL sp78 codec\n", stderr)
        return 1
    }
    guard case let .decoded(negative, _) = decodeTemperature(dataType: "sp78", bytes: [0x81, 0x00]), negative == -127 else {
        fputs("FAIL signed sp78 codec\n", stderr)
        return 1
    }
    let floatBits = Float(42.5).bitPattern
    let floatBytes = [
        UInt8(floatBits & 0xFF),
        UInt8((floatBits >> 8) & 0xFF),
        UInt8((floatBits >> 16) & 0xFF),
        UInt8((floatBits >> 24) & 0xFF)
    ]
    guard case let .decoded(float, _) = decodeTemperature(dataType: "flt ", bytes: floatBytes), approximately(float, 42.5) else {
        fputs("FAIL flt codec\n", stderr)
        return 1
    }
    guard case let .decoded(fpe2, _) = decodeTemperature(dataType: "fpe2", bytes: [0x00, 0x04]), approximately(fpe2, 1) else {
        fputs("FAIL fpe2 codec\n", stderr)
        return 1
    }
    guard case let .decoded(ioft, _) = decodeTemperature(dataType: "ioft", bytes: [0, 0, 0, 0, 0, 0x0A, 0, 0]), approximately(ioft, 10) else {
        fputs("FAIL ioft codec\n", stderr)
        return 1
    }
    guard case .unsupported = decodeTemperature(dataType: "ui16", bytes: [0, 1]) else {
        fputs("FAIL unsupported type handling\n", stderr)
        return 1
    }
    let validation = validateTemperature(-127, rawBytes: [0x81, 0x00])
    guard validation.status == "invalidSample", validation.value == nil else {
        fputs("FAIL sentinel validation\n", stderr)
        return 1
    }

    print("PASS ThermalHardwareProbe codec and sanity self-tests")
    return 0
}

private enum ProbeArgumentError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(String)
    case unknownOption(String)

    var description: String {
        switch self {
        case let .missingValue(option): return "Missing value for \(option)"
        case let .invalidValue(value): return "Invalid option value: \(value)"
        case let .unknownOption(option): return "Unknown option: \(option)"
        }
    }
}

private func parseOptions(_ arguments: [String]) throws -> (options: ProbeOptions?, selfTest: Bool, help: Bool) {
    var samples = 1
    var interval = 5.0
    var outputDirectory = ProbeConstants.defaultOutputDirectory
    var selfTest = false
    var help = false
    var index = 1

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--samples":
            index += 1
            guard index < arguments.count else { throw ProbeArgumentError.missingValue(argument) }
            guard let value = Int(arguments[index]), (1...300).contains(value) else {
                throw ProbeArgumentError.invalidValue(arguments[index])
            }
            samples = value
        case "--interval":
            index += 1
            guard index < arguments.count else { throw ProbeArgumentError.missingValue(argument) }
            guard let value = Double(arguments[index]), value.isFinite, (0.1...3_600).contains(value) else {
                throw ProbeArgumentError.invalidValue(arguments[index])
            }
            interval = value
        case "--output-dir":
            index += 1
            guard index < arguments.count, !arguments[index].isEmpty else {
                throw ProbeArgumentError.missingValue(argument)
            }
            outputDirectory = arguments[index]
        case "--self-test":
            selfTest = true
        case "--help", "-h":
            help = true
        default:
            throw ProbeArgumentError.unknownOption(argument)
        }
        index += 1
    }

    if help || selfTest {
        return (nil, selfTest, help)
    }
    return (
        ProbeOptions(samples: samples, intervalSeconds: interval, outputDirectory: outputDirectory),
        false,
        false
    )
}

private func printHelp() {
    print("""
    ThermalHardwareProbe — read-only AppleSMC/AppleSmartBattery evidence probe

    Usage:
      thermal-hardware-probe [--samples N] [--interval SECONDS] [--output-dir PATH]
      thermal-hardware-probe --self-test

    Defaults:
      --samples 1
      --interval 5
      --output-dir docs/generated/thermal_probe

    The probe does not generate workload, invoke powermetrics, require root,
    control fans, mutate power limits, or emit SMC mutation commands.
    """)
}

private func writeReport(_ report: ProbeReport) throws {
    let directoryURL = URL(fileURLWithPath: report.options.outputDirectory, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let rawData = try encoder.encode(report)
    // The probe is often run from a removable/workspace volume where the
    // sandbox permits a direct create but rejects the temporary rename used by
    // Data.WritingOptions.atomic. The output is diagnostic-only, so write the
    // final file directly after encoding it completely in memory.
    try rawData.write(to: directoryURL.appendingPathComponent("thermal_probe_raw.json"))

    let summary = makeSummary(report)
    try summary.write(
        to: directoryURL.appendingPathComponent("thermal_probe_summary.md"),
        atomically: false,
        encoding: .utf8
    )
}

private func runProbe(options: ProbeOptions) -> Int32 {
    let totalStart = monotonicSeconds()
    let cpuStart = processCPUSeconds()
    let hardware = hardwareIdentity()
    var discovery = discoverSMC()
    var records: [SMCKeyRecord] = []
    var initialReadCount = 0
    var sampledReadCount = 0
    let enumerationStart = monotonicSeconds()

    if let connection = discovery.connection, let reportedCount = discovery.report.reportedKeyCount {
        let enumerationLimit = min(reportedCount, ProbeConstants.maximumEnumeratedKeys)
        if enumerationLimit < reportedCount {
            discovery.report.keyEnumerationTruncated = true
            discovery.report.errors.append("reported key count exceeded safety limit; enumeration truncated")
        }

        var seenKeys = Set<String>()
        for index in 0..<enumerationLimit {
            let indexRead = connection.readIndex(index)
            guard let key = indexRead.key, key.count == 4 else {
                discovery.report.errors.append("index \(index): \(indexRead.method.failureDescription ?? "invalid key returned")")
                continue
            }
            guard seenKeys.insert(key).inserted else { continue }

            let infoRead = connection.readKeyInfo(key)
            let info = infoRead.info
            if info == nil {
                discovery.report.keyInfoFailureCount += 1
            } else {
                discovery.report.keyInfoSuccessCount += 1
            }

            let readSize = min(info?.dataSize ?? 0, ProbeConstants.smcBytePayloadCapacity)
            let read: SMCByteRead?
            if info?.dataSize ?? 0 > ProbeConstants.smcBytePayloadCapacity {
                read = nil
            } else {
                read = connection.readBytes(key, size: readSize)
                initialReadCount += 1
            }

            let readError: String?
            if let info, info.dataSize > ProbeConstants.smcBytePayloadCapacity {
                readError = "data size \(info.dataSize) exceeds fixed user-client payload capacity \(ProbeConstants.smcBytePayloadCapacity)"
                discovery.report.keyReadFailureCount += 1
            } else if let read, read.bytes != nil {
                readError = nil
                discovery.report.keyReadSuccessCount += 1
            } else {
                readError = read?.method.failureDescription ?? infoRead.method.failureDescription ?? "key read failed"
                discovery.report.keyReadFailureCount += 1
            }

            let record = classifyAndRecord(
                key: key,
                info: info,
                rawBytes: read?.bytes,
                error: readError
            )
            records.append(record)
        }

        discovery.report.enumeratedKeyCount = records.count
        discovery.report.temperatureLikeKeyCount = records.filter(\.temperatureLikeKey).count
        discovery.report.decodedTemperatureKeyCount = records.filter {
            $0.temperatureLikeKey && ProbeConstants.supportedTemperatureTypes.contains($0.dataType)
        }.count
        discovery.report.validTemperatureKeyCount = records.filter {
            $0.temperatureLikeKey && $0.decodeStatus == "valid"
        }.count
        discovery.report.observedDataTypes = Array(Set(records.map(\.dataType))).sorted()
    } else if discovery.connection == nil {
        discovery.report.errors.append(discovery.report.unavailableReason ?? "AppleSMC unavailable")
    }

    let enumerationWallMilliseconds = (monotonicSeconds() - enumerationStart) * 1_000
    var sampling: SamplingReport
    if let connection = discovery.connection {
        (sampling, sampledReadCount) = sampleTemperatureKeys(
            connection: connection,
            records: &records,
            options: options
        )
        connection.close()
        discovery.report.connectionCloseResult = connection.closeResult
    } else {
        sampling = SamplingReport(
            requestedSamples: options.samples,
            intervalSeconds: options.intervalSeconds,
            completedSamples: 0,
            temperatureKeyCount: 0,
            status: "SKIPPED: AppleSMC connection unavailable",
            wallDurationMilliseconds: 0,
            workloadGenerated: false,
            correlations: []
        )
    }

    let totalWallMilliseconds = (monotonicSeconds() - totalStart) * 1_000
    let processCPUTimeMilliseconds = processCPUSeconds().flatMap { end in
        cpuStart.map { (end - $0) * 1_000 }
    }
    let averageWallPerSample = options.samples > 0
        ? sampling.wallDurationMilliseconds / Double(max(1, sampling.completedSamples))
        : 0
    let averageCPUPerSample = processCPUTimeMilliseconds.map {
        $0 / Double(max(1, sampling.completedSamples))
    }

    let safety = SafetyReport(
        readOnly: true,
        smcWritesAttempted: false,
        fanManipulationImplemented: false,
        powerLimitMutationImplemented: false,
        powermetricsInvoked: false,
        privilegedHelperUsed: false,
        processRanAsRoot: hardware.runningAsRoot,
        rootRequiredByProbe: false,
        sleepWakeIntegrationImplemented: false,
        connectionReleaseAttempted: discovery.connection != nil,
        connectionReleasedSuccessfully: discovery.report.connectionCloseResult?.code == KERN_SUCCESS
    )

    let performance = PerformanceReport(
        totalWallDurationMilliseconds: totalWallMilliseconds,
        processCPUTimeMilliseconds: processCPUTimeMilliseconds,
        smcEnumerationWallDurationMilliseconds: enumerationWallMilliseconds,
        initialKeyReadCount: initialReadCount,
        sampledTemperatureReadCount: sampledReadCount,
        averageWallMillisecondsPerSample: averageWallPerSample,
        averageProcessCPUTimeMillisecondsPerSample: averageCPUPerSample,
        cadenceAssessment: cadenceAssessment(averageCPUTimeMillisecondsPerSample: averageCPUPerSample)
    )

    let report = ProbeReport(
        schemaVersion: "1.0",
        generatedAt: Date(),
        options: options,
        hardware: hardware,
        smc: discovery.report,
        battery: collectBatteryReport(),
        sensors: records,
        sampling: sampling,
        safety: safety,
        performance: performance,
        references: references()
    )

    do {
        try writeReport(report)
        print("Thermal hardware probe completed")
        print("  Model: \(hardware.modelIdentifier ?? "unknown") / \(hardware.chip ?? "unknown")")
        print("  AppleSMC: \(discovery.report.connectionOpened ? "available" : "unavailable")")
        print("  Keys: \(discovery.report.enumeratedKeyCount), temperature-like: \(discovery.report.temperatureLikeKeyCount), valid initial temperatures: \(discovery.report.validTemperatureKeyCount)")
        print("  AppleSmartBattery: \(report.battery.serviceFound ? "available" : "unavailable")")
        print("  Summary: \(options.outputDirectory)/thermal_probe_summary.md")
        print("  Raw: \(options.outputDirectory)/thermal_probe_raw.json")
        return 0
    } catch {
        fputs("FAIL writing probe report: \(error)\n", stderr)
        return 1
    }
}

do {
    let parsed = try parseOptions(CommandLine.arguments)
    if parsed.help {
        printHelp()
        exit(0)
    }
    if parsed.selfTest {
        exit(runCodecSelfTests())
    }
    guard let options = parsed.options else {
        printHelp()
        exit(1)
    }
    exit(runProbe(options: options))
} catch {
    fputs("FAIL: \(error)\n\n", stderr)
    printHelp()
    exit(1)
}
