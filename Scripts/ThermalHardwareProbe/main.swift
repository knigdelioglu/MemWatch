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

private struct BatteryTemperatureSamplingReading: Codable {
    let serviceClass: String
    let serviceName: String?
    let propertyName: String
    let path: String
    let raw: Double?
    let dividedBy100Celsius: Double?
    let zeroPoint1KCelsius: Double?
    let status: String
    let error: String?
}

private struct BatterySamplingPoint: Codable {
    let timestamp: Date
    let serviceCount: Int
    let propertyReadSucceeded: Bool
    let readings: [BatteryTemperatureSamplingReading]
    let errors: [String]
}

private struct BatterySamplingReport: Codable {
    var requestedSamples: Int
    var intervalSeconds: Double
    var completedSamples: Int
    var status: String
    var points: [BatterySamplingPoint]
}

private struct BatteryUnitAssessment: Codable {
    let temperatureRaw: Double?
    let virtualTemperatureRaw: Double?
    let dividedBy100Celsius: Double?
    let zeroPoint1KCelsius: Double?
    let lifetimeAverageRaw: Double?
    let lifetimeMinimumRaw: Double?
    let lifetimeMaximumRaw: Double?
    let lifetimeMaximumIntegerCelsiusCandidate: Double?
    let lifetimeMaximumDividedBy100Candidate: Double?
    let lifetimeMaximumZeroPoint1KCandidate: Double?
    var selectedInterpretation: String
    var confidence: String
    var rationale: String
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
    var unitAssessment: BatteryUnitAssessment
    var sampling: BatterySamplingReport?
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

private func emptyBatteryUnitAssessment() -> BatteryUnitAssessment {
    BatteryUnitAssessment(
        temperatureRaw: nil,
        virtualTemperatureRaw: nil,
        dividedBy100Celsius: nil,
        zeroPoint1KCelsius: nil,
        lifetimeAverageRaw: nil,
        lifetimeMinimumRaw: nil,
        lifetimeMaximumRaw: nil,
        lifetimeMaximumIntegerCelsiusCandidate: nil,
        lifetimeMaximumDividedBy100Candidate: nil,
        lifetimeMaximumZeroPoint1KCandidate: nil,
        selectedInterpretation: "UNVERIFIED",
        confidence: "LOW",
        rationale: "No AppleSmartBattery temperature metadata was available."
    )
}

private func firstBatteryPropertyValue(
    _ properties: [BatteryPropertyObservation],
    name: String
) -> Double? {
    properties
        .filter { $0.propertyName.caseInsensitiveCompare(name) == .orderedSame }
        .sorted { lhs, rhs in
            let lhsPreferred = lhs.path.localizedCaseInsensitiveContains("BatteryData")
            let rhsPreferred = rhs.path.localizedCaseInsensitiveContains("BatteryData")
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return lhs.path < rhs.path
        }
        .compactMap { $0.number?.double }
        .first
}

private func makeBatteryUnitAssessment(
    from properties: [BatteryPropertyObservation]
) -> BatteryUnitAssessment {
    let temperatureRaw = firstBatteryPropertyValue(properties, name: "Temperature")
    let virtualTemperatureRaw = firstBatteryPropertyValue(properties, name: "VirtualTemperature")
    let selectedRaw = temperatureRaw ?? virtualTemperatureRaw
    let lifetimeAverageRaw = firstBatteryPropertyValue(properties, name: "AverageTemperature")
    let lifetimeMinimumRaw = firstBatteryPropertyValue(properties, name: "MinimumTemperature")
    let lifetimeMaximumRaw = firstBatteryPropertyValue(properties, name: "MaximumTemperature")
    let dividedBy100 = selectedRaw.map { $0 / 100.0 }
    let zeroPoint1K = selectedRaw.map { $0 / 10.0 - 273.15 }
    let lifetimeMaximumIntegerCelsiusCandidate = lifetimeMaximumRaw
    let lifetimeMaximumDividedBy100Candidate = lifetimeMaximumRaw.map { $0 / 100.0 }
    let lifetimeMaximumZeroPoint1KCandidate = lifetimeMaximumRaw.map { $0 / 10.0 - 273.15 }

    let rationale: String
    if let selectedRaw, let dividedBy100, let zeroPoint1K, let lifetimeMaximumRaw {
        rationale = String(
            format: "Observed Temperature raw %.0f gives /100 = %.2f °C and Smart Battery 0.1 K = %.2f °C; both pass the broad sanity range. LifetimeData.MaximumTemperature raw %.0f is not assumed to share the same unit. If it means 40 °C, /100 is internally more consistent (%.2f ≤ 40) while 0.1 K would exceed it (%.2f > 40). If the lifetime field uses another unit, this is only supporting evidence, not a unit contract.",
            selectedRaw,
            dividedBy100,
            zeroPoint1K,
            lifetimeMaximumRaw,
            dividedBy100,
            zeroPoint1K
        )
    } else if let selectedRaw, let dividedBy100, let zeroPoint1K {
        rationale = String(
            format: "Observed Temperature raw %.0f gives /100 = %.2f °C and Smart Battery 0.1 K = %.2f °C; both pass the broad sanity range, so the unit remains unverified without an independent correlation.",
            selectedRaw,
            dividedBy100,
            zeroPoint1K
        )
    } else {
        rationale = "Temperature/VirtualTemperature did not expose a finite scalar suitable for unit comparison."
    }

    return BatteryUnitAssessment(
        temperatureRaw: temperatureRaw,
        virtualTemperatureRaw: virtualTemperatureRaw,
        dividedBy100Celsius: dividedBy100,
        zeroPoint1KCelsius: zeroPoint1K,
        lifetimeAverageRaw: lifetimeAverageRaw,
        lifetimeMinimumRaw: lifetimeMinimumRaw,
        lifetimeMaximumRaw: lifetimeMaximumRaw,
        lifetimeMaximumIntegerCelsiusCandidate: lifetimeMaximumIntegerCelsiusCandidate,
        lifetimeMaximumDividedBy100Candidate: lifetimeMaximumDividedBy100Candidate,
        lifetimeMaximumZeroPoint1KCandidate: lifetimeMaximumZeroPoint1KCandidate,
        selectedInterpretation: "UNVERIFIED",
        confidence: "LOW",
        rationale: rationale
    )
}

private func batterySamplingReading(
    serviceClass: String,
    serviceName: String?,
    propertyName: String,
    path: String,
    raw: Double?
) -> BatteryTemperatureSamplingReading {
    guard let raw else {
        return BatteryTemperatureSamplingReading(
            serviceClass: serviceClass,
            serviceName: serviceName,
            propertyName: propertyName,
            path: path,
            raw: nil,
            dividedBy100Celsius: nil,
            zeroPoint1KCelsius: nil,
            status: "readFailed",
            error: "AppleSmartBattery property was not a finite NSNumber"
        )
    }
    guard raw.isFinite else {
        return BatteryTemperatureSamplingReading(
            serviceClass: serviceClass,
            serviceName: serviceName,
            propertyName: propertyName,
            path: path,
            raw: nil,
            dividedBy100Celsius: nil,
            zeroPoint1KCelsius: nil,
            status: "invalidSample",
            error: "NaN or Infinity"
        )
    }
    return BatteryTemperatureSamplingReading(
        serviceClass: serviceClass,
        serviceName: serviceName,
        propertyName: propertyName,
        path: path,
        raw: raw,
        dividedBy100Celsius: raw / 100.0,
        zeroPoint1KCelsius: raw / 10.0 - 273.15,
        status: "observed",
        error: nil
    )
}

private func initialBatterySamplingPoint(
    report: BatteryReport,
    timestamp: Date
) -> BatterySamplingPoint {
    let readings = report.relevantProperties.compactMap { property -> BatteryTemperatureSamplingReading? in
        let normalized = property.propertyName.lowercased()
        guard normalized == "temperature" || normalized == "virtualtemperature" else { return nil }
        return batterySamplingReading(
            serviceClass: property.path.split(separator: ".").first.map(String.init) ?? "AppleSmartBattery",
            serviceName: nil,
            propertyName: property.propertyName,
            path: property.path,
            raw: property.number?.double
        )
    }
    return BatterySamplingPoint(
        timestamp: timestamp,
        serviceCount: report.serviceCount,
        propertyReadSucceeded: report.propertyReadSucceeded,
        readings: readings,
        errors: report.errors
    )
}

private func collectBatterySamplingPoint(at timestamp: Date) -> BatterySamplingPoint {
    let candidateClasses = ["AppleSmartBattery", "AppleSmartBatteryPack"]
    var services: [io_service_t] = []
    var seenServiceIDs = Set<io_service_t>()
    var errors: [String] = []

    for candidateClass in candidateClasses {
        guard let matching = IOServiceMatching(candidateClass) else {
            errors.append("\(candidateClass): IOServiceMatching returned nil")
            continue
        }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            errors.append("\(candidateClass): matching failed \(kernelReturnCode(result).hex)")
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

    var readings: [BatteryTemperatureSamplingReading] = []
    var propertyReadSucceeded = true
    for service in services {
        let serviceClass = ioObjectClass(service) ?? "AppleSmartBattery"
        let serviceName = ioRegistryName(service)
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        if result == KERN_SUCCESS, let unmanagedProperties {
            let dictionary = unmanagedProperties.takeRetainedValue() as NSDictionary
            func walk(_ value: Any, path: String, depth: Int) {
                guard depth <= 6 else { return }
                if let entries = dictionaryEntries(value) {
                    for (name, child) in entries.sorted(by: { $0.0 < $1.0 }) {
                        let childPath = path.isEmpty ? name : "\(path).\(name)"
                        let normalized = name.lowercased()
                        if normalized == "temperature" || normalized == "virtualtemperature" {
                            readings.append(
                                batterySamplingReading(
                                    serviceClass: serviceClass,
                                    serviceName: serviceName,
                                    propertyName: name,
                                    path: childPath,
                                    raw: batteryNumber(child)?.double
                                )
                            )
                        }
                        walk(child, path: childPath, depth: depth + 1)
                    }
                } else if let array = value as? NSArray {
                    for (index, child) in array.enumerated() {
                        walk(child, path: "\(path)[\(index)]", depth: depth + 1)
                    }
                }
            }
            walk(dictionary, path: serviceClass, depth: 0)
        } else {
            propertyReadSucceeded = false
            errors.append("\(serviceClass): property read failed \(kernelReturnCode(result).hex) \(kernelReturnCode(result).message)")
        }
        IOObjectRelease(service)
    }

    return BatterySamplingPoint(
        timestamp: timestamp,
        serviceCount: services.count,
        propertyReadSucceeded: propertyReadSucceeded,
        readings: readings,
        errors: errors
    )
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
            unitAssessment: emptyBatteryUnitAssessment(),
            sampling: nil,
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
        analysis = "\(makeBatteryUnitAssessment(from: properties).rationale) The report preserves /100, Smart Battery 0.1 K, tenths-Celsius and integer-Celsius candidates without selecting or clamping one."
    }

    let unitAssessment = makeBatteryUnitAssessment(from: properties)

    return BatteryReport(
        matchingResult: matchingResults.first,
        serviceFound: true,
        serviceCount: services.count,
        serviceClass: Array(Set(serviceClasses)).sorted().joined(separator: ", "),
        propertyReadResult: propertyReadResult,
        propertyReadSucceeded: allPropertyReadsSucceeded,
        relevantProperties: properties,
        selectedInterpretation: "UNVERIFIED",
        unitAssessment: unitAssessment,
        sampling: nil,
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
    let hidServiceCount: Int
    let batteryServiceCount: Int
    let batteryTemperatureReadingCount: Int
    let eventReadCount: Int
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
    let initialHIDDiscoveryWallDurationMilliseconds: Double
    let initialHIDDiscoveryCPUTimeMilliseconds: Double?
    let firstHIDSampleReadWallDurationMilliseconds: Double
    let firstHIDSampleReadCPUTimeMilliseconds: Double?
    let cachedHIDSampleReadCount: Int
    let cachedHIDSampleReadWallDurationMilliseconds: Double
    let cachedHIDSampleReadCPUTimeMilliseconds: Double?
    let hidEventReadCount: Int
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
    let hidWritesAttempted: Bool
    let hidSetReportInvoked: Bool
    let voltagePowerMutationAttempted: Bool
    let authorizationServicesUsed: Bool
}

private enum ProbeBackend: String, Codable {
    case smc
    case hid
    case battery
    case all

    var includesSMC: Bool { self == .smc || self == .all }
    var includesHID: Bool { self == .hid || self == .all }
    var includesBattery: Bool { self == .battery || self == .all }
}

private struct ProbeOptions: Codable {
    let samples: Int
    let intervalSeconds: Double
    let outputDirectory: String
    let backend: ProbeBackend
    let runIdentifier: String
    var hidImplementation: String = "standard"
}

private struct ProbeReport: Codable {
    let schemaVersion: String
    let generatedAt: Date
    let options: ProbeOptions
    let hardware: HardwareIdentity
    let smc: SMCReport
    let hidBackend: HIDBackendReport
    let services: [HIDTemperatureServiceEvidence]
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

private func readSMCTemperatureSample(
    at timestamp: Date,
    connection: ReadOnlySMCConnection,
    records: inout [SMCKeyRecord]
) -> Int {
    let temperatureIndices = records.indices.filter { records[$0].temperatureLikeKey }
    for index in temperatureIndices {
        let record = records[index]
        let read = connection.readBytes(record.key, size: record.size)
        let sample = makeTemperatureSample(
            timestamp: timestamp,
            dataType: record.dataType,
            bytes: read.bytes,
            error: read.method.failureDescription
        )
        records[index].samples.append(sample)
    }
    return temperatureIndices.count
}

private func smcSamplingCorrelations(
    records: [SMCKeyRecord]
) -> [SamplingCorrelation] {
    records.filter(\.temperatureLikeKey).map { record in
        let stats = record.statistics
        return SamplingCorrelation(
            key: record.key,
            minimum: stats?.minimum,
            average: stats?.average,
            maximum: stats?.maximum,
            delta: stats?.delta,
            first: stats?.first,
            last: stats?.last,
            validSampleCount: stats?.validSampleCount ?? 0,
            invalidSampleCount: stats?.invalidSampleCount ?? record.samples.count
        )
    }
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

    func hidCurrentValue(_ service: HIDTemperatureServiceEvidence) -> Double? {
        service.samples.reversed().compactMap { sample in
            sample.status == "valid" ? sample.decodedCelsius : nil
        }.first
    }

    func hidCategoryLines(_ category: String) -> [String] {
        let matches = report.services.filter { $0.classification == category }
        guard !matches.isEmpty else { return ["- None."] }

        var result: [String] = []
        for level in ["validated", "likely", "unknown"] {
            let tier = matches.filter { $0.confidence == level }
            guard !tier.isEmpty else { continue }
            result.append("- \(level.capitalized):")
            for service in tier {
                let current = numericString(hidCurrentValue(service))
                let product = markdownCell(service.product ?? "unknown")
                let evidence = markdownCell(service.classificationEvidence)
                result.append("  - \(product) [\(markdownCell(service.id))]: \(current) °C; \(evidence).")
            }
        }
        return result
    }

    func productMentionLines(_ terms: [String]) -> [String] {
        let matches = report.services.filter { service in
            let product = (service.product ?? "").lowercased()
            return terms.contains { product.contains($0) }
        }
        guard !matches.isEmpty else {
            return ["- No matching Product string was observed."]
        }
        return matches.map { service in
            "- \(markdownCell(service.product ?? "unknown")) [\(markdownCell(service.id))]: raw classification \(service.classification)/\(service.confidence); independent physical placement is unproven."
        }
    }

    func batteryRaw(_ name: String) -> Double? {
        report.battery.relevantProperties
            .filter { $0.propertyName.caseInsensitiveCompare(name) == .orderedSame }
            .compactMap { $0.number?.double }
            .first
    }

    func hidServiceSummary(_ service: HIDTemperatureServiceEvidence) -> String {
        let current = numericString(hidCurrentValue(service))
        let stats = service.statistics.map {
            "n=\($0.sampleCount), valid=\($0.validSampleCount), min=\(numericString($0.minimum)), avg=\(numericString($0.average)), max=\(numericString($0.maximum))"
        } ?? "no statistics"
        return "\(markdownCell(service.product ?? "unknown")) [\(markdownCell(service.id))]: \(current) °C; \(stats)"
    }

    func productionAvailability(_ category: String) -> String {
        let matches = report.services.filter { $0.classification == category }
        let valid = matches.contains { ($0.statistics?.validSampleCount ?? 0) > 0 }
        if valid {
            return "diagnostic evidence exists; controlled workload correlation and semantics validation still required"
        }
        if !matches.isEmpty {
            return "service/category candidate exists but no valid decoded sample"
        }
        return "no evidence in this run"
    }

    lines.append("# MemWatch thermal hardware validation")
    lines.append("")
    lines.append("Read-only diagnostic evidence; generated at \(report.generatedAt.formatted(.iso8601)).")
    lines.append("Run identifier: \(report.options.runIdentifier)")
    lines.append("")

    lines.append("## A. Hardware")
    lines.append("")
    lines.append("- Model: \(report.hardware.modelIdentifier ?? "unknown")")
    lines.append("- Chip: \(report.hardware.chip ?? "unknown")")
    lines.append("- Architecture: \(report.hardware.architecture ?? "unknown"); Apple Silicon: \(report.hardware.appleSilicon)")
    lines.append("- macOS: \(report.hardware.macOSVersion ?? "unknown") (\(report.hardware.macOSBuild ?? "unknown"))")
    lines.append("- Kernel: \(report.hardware.kernelVersion ?? "unknown")")
    lines.append("- Effective UID: \(report.hardware.effectiveUID); root: \(report.hardware.runningAsRoot)")
    lines.append("- Sandbox marker: \(report.hardware.sandbox)")
    lines.append("")

    lines.append("## B. HID private symbol availability")
    lines.append("")
    lines.append("| Symbol | Found |")
    lines.append("|---|---|")
    for symbol in report.hidBackend.symbolAvailability.symbols.keys.sorted() {
        lines.append("| \(markdownCell(symbol)) | \(report.hidBackend.symbolAvailability.symbols[symbol] == true ? "FOUND" : "MISSING") |")
    }
    lines.append("")
    lines.append("- Library loaded: \(report.hidBackend.symbolAvailability.libraryLoaded); all required symbols: \(report.hidBackend.symbolAvailability.requiredSymbolsFound)")
    lines.append("- Matching: PrimaryUsagePage \(String(format: "0x%04X", report.hidBackend.matching.primaryUsagePage)); PrimaryUsage \(String(format: "0x%04X", report.hidBackend.matching.primaryUsage)); call result \(report.hidBackend.matching.matchingResult ?? "unavailable"); status \(report.hidBackend.matching.discoveryStatus)")
    if let error = report.hidBackend.matching.discoveryError {
        lines.append("- Discovery error: \(markdownCell(error))")
    }
    lines.append("- Provenance: Apple IOHIDFamily/Chromium declares Apple vendor page 0xFF00, temperature usage 0x0005, event type 15, and event field base type << 16. The probe records these constants and resolves private symbols at runtime.")
    lines.append("- Compared implementations: Stats, SwiftTempBar, lude-vitals, and redline use this diagnostic path; their repositories are MIT. iSMC is GPL-3.0 and was reference-only; no GPL code was copied.")
    lines.append("")

    lines.append("## C. HID temperature services")
    lines.append("")
    lines.append("| ID | Product | Current °C | Candidate category | Confidence |")
    lines.append("|---|---|---:|---|---|")
    if report.services.isEmpty {
        lines.append("| — | — | — | unknown | unknown |")
    } else {
        for service in report.services {
            lines.append("| \(markdownCell(service.id)) | \(markdownCell(service.product ?? "unknown")) | \(numericString(hidCurrentValue(service))) | \(service.classification) | \(service.confidence) |")
        }
    }
    lines.append("")
    lines.append("- Raw services are retained even when names suggest duplicates, virtual sensors, calibration, battery, memory, or storage.")
    lines.append("")

    lines.append("## D. Raw properties")
    lines.append("")
    if report.services.isEmpty {
        lines.append("No matching HID temperature service exposed properties.")
    } else {
        for service in report.services {
            lines.append("### \(markdownCell(service.product ?? "unknown"))")
            lines.append("")
            lines.append("- ID: \(markdownCell(service.id)); identity source: \(markdownCell(service.idSource))")
            if service.propertyErrors.isEmpty {
                lines.append("- Property copy errors: none reported")
            } else {
                lines.append("- Property copy errors: \(service.propertyErrors.map(markdownCell).joined(separator: "; "))")
            }
            lines.append("")
            lines.append("| Property | Kind | Value/summary |")
            lines.append("|---|---|---|")
            if service.properties.isEmpty {
                lines.append("| — | — | no property returned |")
            } else {
                for key in service.properties.keys.sorted() {
                    guard let value = service.properties[key] else { continue }
                    let summary = value.displayString ?? "<\(value.kind)>"
                    lines.append("| \(markdownCell(key)) | \(markdownCell(value.kind)) | \(markdownCell(summary)) |")
                }
            }
            lines.append("")
            lines.append("Full nested/raw values are preserved in the JSON evidence.")
        }
    }
    lines.append("")

    lines.append("## E. 12×5 sampling results")
    lines.append("")
    lines.append("- Requested: \(report.sampling.requestedSamples) sample(s) × \(numericString(report.sampling.intervalSeconds)) seconds; completed: \(report.sampling.completedSamples)")
    lines.append("- Status: \(markdownCell(report.sampling.status)); workload generated: \(report.sampling.workloadGenerated)")
    lines.append("")
    lines.append("| Product | Samples | Valid | Min | Avg | Max | Delta | Std dev |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
    if report.services.isEmpty {
        lines.append("| — | 0 | 0 | — | — | — | — | — |")
    } else {
        for service in report.services {
            let stats = service.statistics
            lines.append("| \(markdownCell(service.product ?? "unknown")) | \(stats?.sampleCount ?? service.samples.count) | \(stats?.validSampleCount ?? 0) | \(numericString(stats?.minimum)) | \(numericString(stats?.average)) | \(numericString(stats?.maximum)) | \(numericString(stats?.delta)) | \(numericString(stats?.standardDeviation)) |")
        }
    }
    lines.append("")
    lines.append("- HID events: \(report.hidBackend.eventReadCount); successful event copies: \(report.hidBackend.successfulEventReadCount); failed event copies: \(report.hidBackend.failedEventReadCount)")
    let duplicates = report.services.flatMap { service in
        service.duplicateCandidates.map { "\(service.product ?? service.id) ↔ \($0.otherServiceIdentifier): \($0.reason)\($0.correlation.map { " (\($0))" } ?? "")" }
    }
    if duplicates.isEmpty {
        lines.append("- Duplicate/derived candidates: none observed under the conservative same-Product/series-correlation rules.")
    } else {
        lines.append("- Duplicate/derived candidates:")
        duplicates.forEach { lines.append("  - \(markdownCell($0))") }
    }
    lines.append("")

    lines.append("## F. CPU candidates")
    lines.append("")
    lines.append("- HID tiers:")
    lines.append(contentsOf: hidCategoryLines("cpu"))
    lines.append("- SMC evidence:")
    lines.append(contentsOf: classificationLines(report.sensors, group: "CPU/SoC"))
    lines.append("- P-core versus E-core is not inferred.")
    lines.append("")

    lines.append("## G. GPU candidates")
    lines.append("")
    lines.append("- HID tiers:")
    lines.append(contentsOf: hidCategoryLines("gpu"))
    lines.append("- SMC evidence:")
    lines.append(contentsOf: classificationLines(report.sensors, group: "GPU"))
    lines.append("")

    lines.append("## H. Memory candidates")
    lines.append("")
    lines.append(contentsOf: productMentionLines(["memory", "dram", "ram"]))
    lines.append("- Memory/RAM junction temperature is not asserted from Product text alone; raw classification remains unknown.")
    lines.append("")

    lines.append("## I. Storage candidates")
    lines.append("")
    lines.append(contentsOf: productMentionLines(["nand", "ssd", "storage"]))
    lines.append("- NAND/SSD temperature is not asserted from Product text alone; raw classification remains unknown.")
    lines.append("")

    lines.append("## J. Battery comparison")
    lines.append("")
    lines.append("- AppleSmartBattery service: \(report.battery.serviceFound ? "available" : "unavailable"); matches: \(report.battery.serviceCount); properties: \(report.battery.propertyReadSucceeded ? "read" : "read failed")")
    lines.append("- Raw Temperature: \(numericString(report.battery.unitAssessment.temperatureRaw)); raw VirtualTemperature: \(numericString(report.battery.unitAssessment.virtualTemperatureRaw))")
    lines.append("- Candidate unit confidence: \(report.battery.unitAssessment.confidence); selected interpretation: \(report.battery.unitAssessment.selectedInterpretation)")
    lines.append("")
    lines.append("| Field | Raw | /100 candidate °C | 0.1 K candidate °C |")
    lines.append("|---|---:|---:|---:|")
    let batteryTemperatureProperties = report.battery.relevantProperties.filter {
        let name = $0.propertyName.lowercased()
        return name == "temperature" || name == "virtualtemperature" || name == "averagetemperature" || name == "minimumtemperature" || name == "maximumtemperature"
    }
    if batteryTemperatureProperties.isEmpty {
        lines.append("| — | — | — | — |")
    } else {
        for property in batteryTemperatureProperties {
            let raw = property.number?.double
            let slash100 = raw.map { $0 / 100.0 }
            let zeroPoint1K = raw.map { $0 / 10.0 - 273.15 }
            lines.append("| \(markdownCell(property.path)) | \(numericString(raw)) | \(numericString(slash100)) | \(numericString(zeroPoint1K)) |")
        }
    }
    lines.append("")
    if let raw = report.battery.unitAssessment.temperatureRaw,
       let slash100 = report.battery.unitAssessment.dividedBy100Celsius,
       let zeroPoint1K = report.battery.unitAssessment.zeroPoint1KCelsius {
        lines.append(String(format: "Temperature raw %.0f gives /100 = %.2f °C and 0.1 K = %.2f °C.", raw, slash100, zeroPoint1K))
    }
    lines.append("The first probe recorded BatteryData.Temperature raw 3329: /100 = 33.29 °C versus 0.1 K = 59.75 °C. The 59.75 °C interpretation is physically plausible as an instantaneous value, but it would not reconcile with LifetimeData.MaximumTemperature raw 40 if that lifetime field is integer °C. Because BatteryData and LifetimeData units are not guaranteed identical, this weighs against treating 0.1 K as established; it is not proof of /100.")
    lines.append("- Lifetime metadata raw: AverageTemperature \(numericString(batteryRaw("AverageTemperature"))), MinimumTemperature \(numericString(batteryRaw("MinimumTemperature"))), MaximumTemperature \(numericString(batteryRaw("MaximumTemperature"))), TemperatureSamples \(numericString(batteryRaw("TemperatureSamples")))")
    lines.append("- Assessment: \(markdownCell(report.battery.unitAssessment.rationale))")
    if let sampling = report.battery.sampling {
        let readings = sampling.points.flatMap(\.readings)
        lines.append("- Same-run AppleSmartBattery sampling: \(sampling.points.count)/\(sampling.requestedSamples) points; \(readings.count) temperature-field readings; status \(markdownCell(sampling.status))")
        lines.append("")
        lines.append("| Field | Readings | Raw min / avg / max | /100 avg °C | 0.1 K avg °C |")
        lines.append("|---|---:|---|---:|---:|")
        let fieldNames = Set(readings.map(\.propertyName)).sorted()
        if fieldNames.isEmpty {
            lines.append("| — | 0 | — | — | — |")
        } else {
            for field in fieldNames {
                let fieldReadings = readings.filter { $0.propertyName == field }
                let rawValues = fieldReadings.compactMap(\.raw)
                let slashValues = fieldReadings.compactMap(\.dividedBy100Celsius)
                let kelvinValues = fieldReadings.compactMap(\.zeroPoint1KCelsius)
                let rawAverage = rawValues.isEmpty ? nil : rawValues.reduce(0, +) / Double(rawValues.count)
                let slashAverage = slashValues.isEmpty ? nil : slashValues.reduce(0, +) / Double(slashValues.count)
                let kelvinAverage = kelvinValues.isEmpty ? nil : kelvinValues.reduce(0, +) / Double(kelvinValues.count)
                lines.append("| \(markdownCell(field)) | \(fieldReadings.count) | \(numericString(rawValues.min())) / \(numericString(rawAverage)) / \(numericString(rawValues.max())) | \(numericString(slashAverage)) | \(numericString(kelvinAverage)) |")
            }
        }
        lines.append("")
    }
    let batteryHIDServices = report.services.filter { $0.classification == "battery" }
    if batteryHIDServices.isEmpty {
        lines.append("- HID battery comparison: no Product-backed battery service was identified; no cross-backend match asserted.")
    } else {
        lines.append("- HID battery comparison:")
        for service in batteryHIDServices {
            lines.append("  - \(hidServiceSummary(service)); confidence \(service.confidence).")
        }
    }
    lines.append("")

    lines.append("## K. AppleSMC status")
    lines.append("")
    if report.smc.connectionOpened {
        lines.append("- Rootless AppleSMC connection: available; enumerated keys \(report.smc.enumeratedKeyCount), temperature-like keys \(report.smc.temperatureLikeKeyCount).")
    } else {
        lines.append("- Rootless AppleSMC: unavailable; \(markdownCell(report.smc.unavailableReason ?? "no validated read-only connection"))")
        for attempt in report.smc.serviceCandidates where attempt.serviceFound {
            let result = attempt.openResult.map { "\($0.hex) \($0.message)" } ?? "not attempted"
            lines.append("  - \(markdownCell(attempt.matchingClass)): IOServiceOpen \(markdownCell(result)); \(markdownCell(attempt.protocolProbe ?? "no protocol result"))")
        }
        lines.append("- This preserves the first probe conclusion: rootless SMC enumeration is unavailable unless new evidence says otherwise.")
    }
    lines.append("")

    lines.append("## L. Performance")
    lines.append("")
    lines.append("- Total wall: \(numericString(report.performance.totalWallDurationMilliseconds)) ms; process CPU: \(numericString(report.performance.processCPUTimeMilliseconds)) ms")
    lines.append("- Initial HID discovery: \(numericString(report.performance.initialHIDDiscoveryWallDurationMilliseconds)) ms wall / \(numericString(report.performance.initialHIDDiscoveryCPUTimeMilliseconds)) ms CPU")
    lines.append("- First HID sample read: \(numericString(report.performance.firstHIDSampleReadWallDurationMilliseconds)) ms wall / \(numericString(report.performance.firstHIDSampleReadCPUTimeMilliseconds)) ms CPU")
    lines.append("- Cached HID reads: \(report.performance.cachedHIDSampleReadCount) samples, \(numericString(report.performance.cachedHIDSampleReadWallDurationMilliseconds)) ms wall total / \(numericString(report.performance.cachedHIDSampleReadCPUTimeMilliseconds)) ms CPU total")
    lines.append("- HID service count: \(report.hidBackend.serviceCount); event read count: \(report.hidBackend.eventReadCount)")
    lines.append("- Discovery strategy: \(markdownCell(report.hidBackend.performance.discoveryStrategy)); full discovery is not repeated per sample.")
    lines.append("- 5-second cadence assessment: \(markdownCell(report.performance.cadenceAssessment))")
    lines.append("- Sampling wall: \(numericString(report.sampling.wallDurationMilliseconds)) ms; SMC key reads initial/sample: \(report.performance.initialKeyReadCount)/\(report.performance.sampledTemperatureReadCount)")
    lines.append("")

    lines.append("## M. Safety/read-only verification")
    lines.append("")
    lines.append("| Check | Result |")
    lines.append("|---|---|")
    lines.append("| Read-only contract | \(report.safety.readOnly ? "PASS" : "FAIL") |")
    lines.append("| SMC writes attempted | \(report.safety.smcWritesAttempted ? "FAIL" : "PASS") |")
    lines.append("| HID writes attempted | \(report.safety.hidWritesAttempted ? "FAIL" : "PASS") |")
    lines.append("| HID report mutation invoked | \(report.safety.hidSetReportInvoked ? "FAIL" : "PASS") |")
    lines.append("| Voltage/power mutation attempted | \(report.safety.voltagePowerMutationAttempted ? "FAIL" : "PASS") |")
    lines.append("| Authorization Services used | \(report.safety.authorizationServicesUsed ? "FAIL" : "PASS") |")
    lines.append("| Fan/power-limit controls | \(report.safety.fanManipulationImplemented || report.safety.powerLimitMutationImplemented ? "FAIL" : "PASS") |")
    lines.append("| powermetrics | \(report.safety.powermetricsInvoked ? "FAIL" : "PASS") |")
    lines.append("| Privileged helper | \(report.safety.privilegedHelperUsed ? "FAIL" : "PASS") |")
    lines.append("| Workload generated | \(report.sampling.workloadGenerated ? "FAIL" : "PASS") |")
    lines.append("| Root required | \(report.safety.rootRequiredByProbe ? "FAIL" : "PASS") (actual root: \(report.safety.processRanAsRoot)) |")
    lines.append("| Sleep/wake integration | NOT IMPLEMENTED; lifecycle test UNTESTED |")
    lines.append("")
    lines.append("- HID cleanup: service array attempted/released \(report.hidBackend.resourceCleanup.serviceArrayReleaseAttempted)/\(report.hidBackend.resourceCleanup.serviceArrayReleased); client \(report.hidBackend.resourceCleanup.clientReleaseAttempted)/\(report.hidBackend.resourceCleanup.clientReleased); dlopen handle \(report.hidBackend.resourceCleanup.libraryCloseAttempted)/\(report.hidBackend.resourceCleanup.libraryClosed).")
    lines.append("")

    lines.append("## N. Build/tests")
    lines.append("")
    lines.append("- Probe build: PASS for this run; runtime private-symbol availability is reported above.")
    lines.append("- Codec/self-test and source-contract test: run separately and recorded in the task report.")
    lines.append("- MemWatch Debug build result is reported separately; a SwiftUI macro/plugin failure is not interpreted as a thermal regression.")
    lines.append("")

    lines.append("## O. Files changed/created")
    lines.append("")
    lines.append("- Raw JSON: \(report.options.outputDirectory)/thermal_probe_\(report.options.runIdentifier)_raw.json")
    lines.append("- Markdown summary: \(report.options.outputDirectory)/thermal_probe_\(report.options.runIdentifier)_summary.md")
    lines.append("- Probe source: Scripts/ThermalHardwareProbe/main.swift and HIDTemperatureReader.swift")
    lines.append("")

    lines.append("## P. Production-ready sensor matrix")
    lines.append("")
    lines.append("| Category | Backend | Available | Confidence | Production recommendation |")
    lines.append("|---|---|---|---|---|")
    let cpuAvailable = report.services.contains { $0.classification == "cpu" && ($0.statistics?.validSampleCount ?? 0) > 0 }
    let gpuAvailable = report.services.contains { $0.classification == "gpu" && ($0.statistics?.validSampleCount ?? 0) > 0 }
    lines.append("| CPU/SoC | IOHID temperature service | \(cpuAvailable ? "yes" : "no") | \(cpuAvailable ? "likely" : "unknown") | \(markdownCell(productionAvailability("cpu"))); controlled workload still required |")
    lines.append("| GPU | IOHID temperature service | \(gpuAvailable ? "yes" : "no") | \(gpuAvailable ? "likely" : "unknown") | \(markdownCell(productionAvailability("gpu"))); controlled workload still required |")
    lines.append("| Battery | AppleSmartBattery\(batteryHIDServices.isEmpty ? "" : " + HID") | \(report.battery.serviceFound ? "yes" : "no") | \(report.battery.unitAssessment.confidence) | raw diagnostic only until unit/correlation contract is established |")
    lines.append("| Memory | IOHID/SMC | no proven sensor | unknown | do not label RAM/DRAM junction from this run |")
    lines.append("| Storage | IOHID/SMC | no proven sensor | unknown | do not label NAND/SSD from this run |")
    lines.append("| AppleSMC | AppleSMC user client | \(report.smc.connectionOpened ? "yes" : "no") | \(report.smc.connectionOpened ? "low" : "unavailable") | rootless enumeration is \(report.smc.connectionOpened ? "diagnostic-only" : "unavailable") |")
    lines.append("")

    lines.append("## Q. Remaining unknowns")
    lines.append("")
    lines.append("- HID Product names do not prove physical placement, calibration, or derived/virtual semantics; raw service identities remain available for later correlation.")
    lines.append("- CPU/GPU category evidence, if present, is not a controlled workload validation; P-core/E-core, RAM junction, and NAND semantics remain unknown.")
    lines.append("- BatteryData and LifetimeData may use different units; the /100 versus 0.1 K comparison is correlation evidence only.")
    lines.append("- Sleep/wake reference survival and the need for post-wake HID rediscovery: UNTESTED (this probe does not implement sleep/wake).")
    lines.append("")

    let hidHasValidSample = report.hidBackend.available && report.hidBackend.serviceCount > 0 && report.services.contains { ($0.statistics?.validSampleCount ?? 0) > 0 }
    let verdict = hidHasValidSample ? "READY FOR LIMITED THERMAL ARCHITECTURE" : "MORE HARDWARE VALIDATION REQUIRED"
    lines.append("## R. Verdict")
    lines.append("")
    lines.append(verdict)
    lines.append("")
    lines.append("This diagnostic does not modify MemWatch production behavior.")
    lines.append("")
    lines.append("External evidence and licenses:")
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
        "Apple IOKit IOHIDEventSystemClientCopyServices documentation: https://developer.apple.com/documentation/iokit/2269511-iohideventsystemclientcopyservic",
        "Apple IOKit IOHIDServiceClientCopyProperty documentation: https://developer.apple.com/documentation/iokit/2269430-iohidserviceclientcopyproperty",
        "Linux/Asahi Apple Silicon SMC transport reference: https://github.com/torvalds/linux/blob/master/drivers/mfd/macsmc.c",
        "Linux/Asahi Apple Silicon SMC hwmon type handling reference: https://github.com/torvalds/linux/blob/master/drivers/hwmon/macsmc-hwmon.c",
        "Stats Swift SMC user-client structure and read command reference: https://github.com/exelban/stats/blob/master/SMC/smc.swift",
        "Stats IOHID temperature reader reference (MIT): https://github.com/exelban/stats/blob/master/Modules/Sensors/reader.m",
        "SwiftTempBar IOHID temperature matching and event reference (MIT): https://github.com/WHYBBE/SwiftTempBar",
        "SwiftTempBar source declaration of the void SetMatching ABI (MIT): https://github.com/WHYBBE/SwiftTempBar/blob/main/Sources/TemperatureReader.swift",
        "lude-vitals IOHID private-symbol sampler reference (MIT): https://github.com/iamdemetris/lude-vitals",
        "redline IOHID temperature enumeration and conservative filtering reference (MIT): https://github.com/apeabody007/redline",
        "IOHID temperature usage/event declarations: https://github.com/freedomtan/sensors_cmdline/blob/main/sensors.m",
        "Chromium Apple Silicon sensor declarations: https://chromium.googlesource.com/chromium/src/+/c21e9f71d1f2e/components/power_metrics/m1_sensors_internal_types_mac.h",
        "Netdata macOS IOHID declaration comparison: https://github.com/netdata/netdata/blob/master/src/collectors/macos.plugin/macos_iohid.c",
        "macmon/mactop Apple Silicon monitor reference (MIT; optional fan-control writes are outside this probe): https://github.com/metaspartan/mactop",
        "iSMC Apple Silicon HID/SMC reference (GPL-3.0; reference only, no code copied): https://github.com/dkorunic/iSMC"
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
    guard HIDProbeConstants.primaryUsagePage == 0xFF00,
          HIDProbeConstants.primaryUsage == 0x0005,
          HIDProbeConstants.temperatureEventType == 15,
          HIDProbeConstants.temperatureEventFieldBase == 983_040 else {
        fputs("FAIL HID constant provenance contract\n", stderr)
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

private func defaultRunIdentifier() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
    return formatter.string(from: Date())
}

private func validRunIdentifier(_ value: String) -> Bool {
    !value.isEmpty
        && value.count <= 80
        && value.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            let asciiLetter = (65...90).contains(code) || (97...122).contains(code)
            let asciiNumber = (48...57).contains(code)
            return code < 128 && (asciiLetter || asciiNumber || code == 45 || code == 46 || code == 95)
        }
}

private func parseOptions(_ arguments: [String]) throws -> (options: ProbeOptions?, selfTest: Bool, help: Bool) {
    var samples = 1
    var interval = 5.0
    var outputDirectory = ProbeConstants.defaultOutputDirectory
    var backend = ProbeBackend.all
    var runIdentifier = defaultRunIdentifier()
    var hidImplementation = "standard"
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
        case "--backend":
            index += 1
            guard index < arguments.count,
                  let value = ProbeBackend(rawValue: arguments[index]) else {
                throw ProbeArgumentError.invalidValue(index < arguments.count ? arguments[index] : argument)
            }
            backend = value
        case "--hid-implementation":
            index += 1
            guard index < arguments.count else { throw ProbeArgumentError.missingValue(argument) }
            let mode = arguments[index]
            guard mode == "standard" || mode == "macmon-compatible" else {
                throw ProbeArgumentError.invalidValue(mode)
            }
            hidImplementation = mode
        case "--run-id":
            index += 1
            guard index < arguments.count, validRunIdentifier(arguments[index]) else {
                throw ProbeArgumentError.invalidValue(index < arguments.count ? arguments[index] : argument)
            }
            runIdentifier = arguments[index]
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
        ProbeOptions(
            samples: samples,
            intervalSeconds: interval,
            outputDirectory: outputDirectory,
            backend: backend,
            runIdentifier: runIdentifier,
            hidImplementation: hidImplementation
        ),
        false,
        false
    )
}

private func printHelp() {
    print("""
    ThermalHardwareProbe — read-only AppleSMC/IOHID/AppleSmartBattery evidence probe

    Usage:
      thermal-hardware-probe [--backend smc|hid|battery|all] [--hid-implementation standard|macmon-compatible] [--samples N] [--interval SECONDS] [--output-dir PATH] [--run-id ID]
      thermal-hardware-probe --self-test

    Defaults:
      --backend all
      --samples 1
      --interval 5
      --output-dir docs/generated/thermal_probe
      --run-id UTC timestamp (unique output files)

    The probe does not generate workload, invoke powermetrics, require root,
    control fans, mutate HID/SMC/power state, or use a privileged helper.
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
    let stem = "thermal_probe_\(report.options.runIdentifier)"
    try rawData.write(to: directoryURL.appendingPathComponent("\(stem)_raw.json"))

    let summary = makeSummary(report)
    try summary.write(
        to: directoryURL.appendingPathComponent("\(stem)_summary.md"),
        atomically: false,
        encoding: .utf8
    )
}

private func smcNotRequestedReport() -> SMCReport {
    SMCReport(
        serviceCandidates: [],
        protocolAttempt: "not requested by --backend \(ProbeBackend.hid.rawValue)/\(ProbeBackend.battery.rawValue)",
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
        unavailableReason: "AppleSMC not requested by selected backend"
    )
}

private func hidNotRequestedReport() -> HIDBackendReport {
    let symbols = [
        "IOHIDEventSystemClientCreate",
        "IOHIDEventSystemClientSetMatching",
        "IOHIDEventSystemClientCopyServices",
        "IOHIDServiceClientCopyProperty",
        "IOHIDServiceClientCopyEvent",
        "IOHIDEventGetFloatValue"
    ].reduce(into: [String: Bool]()) { result, name in
        result[name] = false
    }
    return HIDBackendReport(
        available: false,
        symbols: symbols,
        symbolAvailability: HIDSymbolAvailability(
            libraryPath: HIDProbeConstants.iokitPath,
            libraryLoaded: false,
            symbols: symbols,
            requiredSymbolsFound: false,
            missingSymbols: symbols.keys.sorted()
        ),
        matching: HIDMatchingReport(
            primaryUsagePage: HIDProbeConstants.primaryUsagePage,
            primaryUsage: HIDProbeConstants.primaryUsage,
            matchingConfigured: false,
            matchingResult: nil,
            discoveryStatus: "notRequested",
            discoveryError: "HID backend not requested by selected backend"
        ),
        serviceCount: 0,
        eventReadCount: 0,
        successfulEventReadCount: 0,
        failedEventReadCount: 0,
        errors: [],
        performance: HIDPerformanceReport(
            initialDiscoveryWallDurationMilliseconds: 0,
            initialDiscoveryCPUTimeMilliseconds: nil,
            firstSampleReadWallDurationMilliseconds: 0,
            firstSampleReadCPUTimeMilliseconds: nil,
            cachedSampleReadCount: 0,
            cachedSampleReadWallDurationMilliseconds: 0,
            cachedSampleReadCPUTimeMilliseconds: nil,
            serviceCount: 0,
            eventReadCount: 0,
            successfulEventReadCount: 0,
            failedEventReadCount: 0,
            discoveryStrategy: "not requested"
        ),
        resourceCleanup: HIDResourceCleanupReport(
            serviceArrayReleaseAttempted: false,
            serviceArrayReleased: false,
            clientReleaseAttempted: false,
            clientReleased: false,
            libraryCloseAttempted: false,
            libraryClosed: false
        )
    )
}

private func batteryNotRequestedReport() -> BatteryReport {
    BatteryReport(
        matchingResult: nil,
        serviceFound: false,
        serviceCount: 0,
        serviceClass: nil,
        propertyReadResult: nil,
        propertyReadSucceeded: false,
        relevantProperties: [],
        selectedInterpretation: "UNVERIFIED",
        unitAssessment: emptyBatteryUnitAssessment(),
        sampling: nil,
        analysis: "AppleSmartBattery backend was not requested by the selected backend.",
        errors: []
    )
}

private func applyBatteryHIDCorrelation(
    battery: inout BatteryReport,
    services: inout [HIDTemperatureServiceEvidence]
) {
    guard let batteryCandidate = battery.unitAssessment.dividedBy100Celsius,
          batteryCandidate.isFinite else {
        return
    }

    var matchedProducts: [(String, Double)] = []
    for index in services.indices where services[index].classification == "battery" {
        let validValues = services[index].samples.compactMap { sample -> Double? in
            guard sample.status == "valid" else { return nil }
            return sample.decodedCelsius
        }
        guard let closest = validValues.min(by: { abs($0 - batteryCandidate) < abs($1 - batteryCandidate) }) else {
            continue
        }
        let difference = abs(closest - batteryCandidate)
        guard difference <= 1.0 else { continue }

        services[index].confidence = "validated"
        services[index].classificationEvidence = String(
            format: "Product names a battery/gas-gauge service and HID value %.2f °C is within %.2f °C of AppleSmartBattery /100 candidate %.2f °C",
            closest,
            difference,
            batteryCandidate
        )
        matchedProducts.append((services[index].product ?? services[index].id, difference))
    }

    guard !matchedProducts.isEmpty else { return }
    battery.unitAssessment.selectedInterpretation = "macOS /100 candidate"
    battery.unitAssessment.confidence = "HIGH"
    let matches = matchedProducts.map { product, difference in
        String(format: "%@ (difference %.2f °C)", product, difference)
    }.joined(separator: ", ")
    battery.unitAssessment.rationale += " HID battery correlation supports /100: \(matches)."
    battery.selectedInterpretation = "macOS /100 candidate (HIGH confidence from HID correlation)"
    battery.analysis += " HID battery correlation supports /100 for this device: \(matches)."
}

private func runProbe(options: ProbeOptions) -> Int32 {
    let totalStart = monotonicSeconds()
    let cpuStart = processCPUSeconds()
    let hardware = hardwareIdentity()
    var discovery = options.backend.includesSMC
        ? discoverSMC()
        : SMCDiscoveryResult(report: smcNotRequestedReport(), connection: nil)
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
        if options.backend.includesSMC {
            discovery.report.errors.append(discovery.report.unavailableReason ?? "AppleSMC unavailable")
        }
    }

    let enumerationWallMilliseconds = (monotonicSeconds() - enumerationStart) * 1_000

    let hidReader = options.backend.includesHID ? HIDTemperatureReader(implementationMode: HIDImplementationMode(rawValue: options.hidImplementation) ?? .standard) : nil
    hidReader?.discover()
    var battery = options.backend.includesBattery
        ? collectBatteryReport()
        : batteryNotRequestedReport()

    let samplingStart = monotonicSeconds()
    let initialTimestamp = Date()
    hidReader?.readSample(at: initialTimestamp)
    if options.backend.includesBattery {
        battery.sampling = BatterySamplingReport(
            requestedSamples: options.samples,
            intervalSeconds: options.intervalSeconds,
            completedSamples: 1,
            status: "sampling",
            points: [initialBatterySamplingPoint(report: battery, timestamp: initialTimestamp)]
        )
    }

    var completedSamples = 1
    if options.samples > 1 {
        for sampleIndex in 1..<options.samples {
            Thread.sleep(forTimeInterval: options.intervalSeconds)
            let timestamp = Date()
            if let connection = discovery.connection {
                sampledReadCount += readSMCTemperatureSample(
                    at: timestamp,
                    connection: connection,
                    records: &records
                )
            }
            hidReader?.readSample(at: timestamp)
            if options.backend.includesBattery {
                let point = collectBatterySamplingPoint(at: timestamp)
                battery.sampling?.points.append(point)
            }
            completedSamples = sampleIndex + 1
            battery.sampling?.completedSamples = completedSamples
            fputs("sample \(completedSamples)/\(options.samples)\n", stderr)
        }
    }

    if let connection = discovery.connection {
        connection.close()
        discovery.report.connectionCloseResult = connection.closeResult
    }
    for index in records.indices where records[index].temperatureLikeKey {
        updateStatistics(&records[index])
    }

    let samplingWallMilliseconds = (monotonicSeconds() - samplingStart) * 1_000
    let hidServices: [HIDTemperatureServiceEvidence]
    let hidBackend: HIDBackendReport
    if let hidReader {
        hidReader.finalizeDuplicateAnalysis()
        hidServices = hidReader.evidence()
        hidReader.close()
        hidBackend = hidReader.report()
    } else {
        hidServices = []
        hidBackend = hidNotRequestedReport()
    }

    var mutableHIDServices = hidServices
    applyBatteryHIDCorrelation(battery: &battery, services: &mutableHIDServices)

    if let samplingReport = battery.sampling {
        battery.sampling = samplingReport
        battery.sampling?.status = battery.serviceFound
            ? "completed"
            : "completed: AppleSmartBattery unavailable"
    }

    let totalWallMilliseconds = (monotonicSeconds() - totalStart) * 1_000
    let processCPUTimeMilliseconds = processCPUSeconds().flatMap { end in
        cpuStart.map { (end - $0) * 1_000 }
    }
    let batteryTemperatureReadingCount = battery.sampling?.points.reduce(0) {
        $0 + $1.readings.count
    } ?? 0
    let samplingStatusParts = [
        "completed",
        options.backend.includesSMC && !discovery.report.connectionOpened ? "AppleSMC unavailable" : nil,
        options.backend.includesHID && !hidBackend.available ? "HID unavailable" : nil,
        options.backend.includesHID && hidBackend.available && hidBackend.serviceCount == 0 ? "HID returned no temperature services" : nil,
        options.backend.includesBattery && !battery.serviceFound ? "AppleSmartBattery unavailable" : nil
    ].compactMap { $0 }
    let sampling = SamplingReport(
        requestedSamples: options.samples,
        intervalSeconds: options.intervalSeconds,
        completedSamples: completedSamples,
        temperatureKeyCount: records.filter { $0.temperatureLikeKey }.count,
        hidServiceCount: hidBackend.serviceCount,
        batteryServiceCount: battery.serviceCount,
        batteryTemperatureReadingCount: batteryTemperatureReadingCount,
        eventReadCount: hidBackend.eventReadCount,
        status: samplingStatusParts.joined(separator: "; "),
        wallDurationMilliseconds: samplingWallMilliseconds,
        workloadGenerated: false,
        correlations: smcSamplingCorrelations(records: records)
    )
    let averageWallPerSample = sampling.wallDurationMilliseconds / Double(max(1, sampling.completedSamples))
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
        connectionReleasedSuccessfully: discovery.report.connectionCloseResult?.code == KERN_SUCCESS,
        hidWritesAttempted: false,
        hidSetReportInvoked: false,
        voltagePowerMutationAttempted: false,
        authorizationServicesUsed: false
    )

    let performance = PerformanceReport(
        totalWallDurationMilliseconds: totalWallMilliseconds,
        processCPUTimeMilliseconds: processCPUTimeMilliseconds,
        smcEnumerationWallDurationMilliseconds: enumerationWallMilliseconds,
        initialKeyReadCount: initialReadCount,
        sampledTemperatureReadCount: sampledReadCount,
        averageWallMillisecondsPerSample: averageWallPerSample,
        averageProcessCPUTimeMillisecondsPerSample: averageCPUPerSample,
        initialHIDDiscoveryWallDurationMilliseconds: hidBackend.performance.initialDiscoveryWallDurationMilliseconds,
        initialHIDDiscoveryCPUTimeMilliseconds: hidBackend.performance.initialDiscoveryCPUTimeMilliseconds,
        firstHIDSampleReadWallDurationMilliseconds: hidBackend.performance.firstSampleReadWallDurationMilliseconds,
        firstHIDSampleReadCPUTimeMilliseconds: hidBackend.performance.firstSampleReadCPUTimeMilliseconds,
        cachedHIDSampleReadCount: hidBackend.performance.cachedSampleReadCount,
        cachedHIDSampleReadWallDurationMilliseconds: hidBackend.performance.cachedSampleReadWallDurationMilliseconds,
        cachedHIDSampleReadCPUTimeMilliseconds: hidBackend.performance.cachedSampleReadCPUTimeMilliseconds,
        hidEventReadCount: hidBackend.eventReadCount,
        cadenceAssessment: cadenceAssessment(averageCPUTimeMillisecondsPerSample: averageCPUPerSample)
    )

    let report = ProbeReport(
        schemaVersion: "2.0",
        generatedAt: Date(),
        options: options,
        hardware: hardware,
        smc: discovery.report,
        hidBackend: hidBackend,
        services: mutableHIDServices,
        battery: battery,
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
        print("  HID: \(report.hidBackend.available ? "available" : "unavailable"), services: \(report.hidBackend.serviceCount), events: \(report.hidBackend.eventReadCount)")
        print("  AppleSmartBattery: \(report.battery.serviceFound ? "available" : "unavailable")")
        print("  Summary: \(options.outputDirectory)/thermal_probe_\(options.runIdentifier)_summary.md")
        print("  Raw: \(options.outputDirectory)/thermal_probe_\(options.runIdentifier)_raw.json")
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
