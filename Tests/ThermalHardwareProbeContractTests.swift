import Foundation

@main
struct ThermalHardwareProbeContractTests {
    static func main() throws {
        let sourcePath = "Scripts/ThermalHardwareProbe/main.swift"
        let hidSource = try String(contentsOfFile: "Scripts/ThermalHardwareProbe/HIDTemperatureReader.swift", encoding: .utf8)
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8) + "\n" + hidSource
        let runner = try String(contentsOfFile: "Scripts/ThermalHardwareProbe/run.sh", encoding: .utf8)

        require(source.contains("candidateClasses = [\"AppleSMC\"") && source.contains("IOServiceMatching(candidateClass)"), "probe must discover AppleSMC")
        require(source.contains("IOServiceOpen"), "probe must attempt IOServiceOpen")
        require(source.contains("IOConnectCallStructMethod"), "probe must use the struct SMC read path")
        require(source.contains("IORegistryEntryCreateCFProperties"), "probe must inspect AppleSmartBattery properties")
        require(source.contains("IOServiceClose"), "probe must release the SMC connection")
        require(source.contains("IOObjectRelease"), "probe must release IOKit objects")
        require(source.contains("readIndex"), "probe must support dynamic key enumeration")
        require(source.contains("sp78") && source.contains("flt ") && source.contains("fpe2") && source.contains("sp1e") && source.contains("ioft"), "probe must name supported decoder metadata")
        require(source.contains("invalidSample"), "probe must preserve invalid temperature samples")
        require(source.contains("APP_SANDBOX_CONTAINER_ID"), "probe must report sandbox marker state")

        let hidSymbols = [
            "IOHIDEventSystemClientCreate",
            "IOHIDEventSystemClientSetMatching",
            "IOHIDEventSystemClientCopyServices",
            "IOHIDServiceClientCopyProperty",
            "IOHIDServiceClientCopyEvent",
            "IOHIDEventGetFloatValue"
        ]
        for symbol in hidSymbols {
            require(source.contains(symbol), "probe must resolve/use HID symbol: \(symbol)")
        }
        require(source.contains("dlopen"), "probe must load private HID symbols at runtime")
        require(source.contains("dlsym"), "probe must resolve private HID symbols at runtime")
        require(source.contains("primaryUsagePage: Int32 = 0xFF00"), "probe must use the validated Apple vendor usage page")
        require(source.contains("primaryUsage: Int32 = 0x0005"), "probe must use the validated temperature usage")
        require(source.contains("temperatureEventType: Int64 = 15"), "probe must use the validated temperature event type")
        require(source.contains("temperatureEventFieldBase"), "probe must use the validated temperature event field base")
        require(source.contains("HIDEventSystemClientSetMatchingFunction = @convention(c) (CFTypeRef, CFDictionary) -> Void"), "probe must preserve the void SetMatching ABI")
        require(source.contains("readFailed"), "HID event read failures must remain explicit")
        require(source.contains("duplicateCandidates"), "probe must preserve duplicate/derived candidates")
        require(source.contains("standardDeviation"), "probe must calculate HID sample standard deviation")
        require(source.contains("--backend") && source.contains("--run-id"), "probe must support backend selection and unique run identifiers")
        require(runner.contains("HIDTemperatureReader.swift"), "runner must compile the isolated HID backend")
        require(!source.contains("MonitoringService") && !source.contains("MonitoringCollector"), "thermal probe must not bind to production monitoring behavior")

        let forbiddenMutationTokens = [
            "writeBytes",
            "SMC_CMD_WRITE",
            "setKey",
            "writeKey",
            "IOConnectCallMethod(",
            "IOConnectCallScalarMethod",
            "IOHIDServiceClientSetReport",
            "IOHIDEventSystemClientSetProperty",
            "IOHIDServiceClientSetProperty",
            "IOHIDDeviceSetReport",
            "fanMode",
            "F0Tg"
        ]
        for token in forbiddenMutationTokens {
            require(!source.contains(token), "probe contains forbidden mutation/control token: \(token)")
        }

        require(!source.localizedCaseInsensitiveContains("/usr/bin/powermetrics"), "probe source must not invoke powermetrics")
        require(!runner.localizedCaseInsensitiveContains("powermetrics"), "probe runner must not invoke powermetrics")
        require(!runner.localizedCaseInsensitiveContains("sudo"), "probe runner must not require sudo")
        require(!source.contains("PrivilegedHelper"), "probe must not use a privileged helper")
        require(source.contains("smcWritesAttempted: false"), "probe safety report must prove no SMC writes were attempted")
        require(source.contains("hidWritesAttempted: false"), "probe safety report must prove no HID writes were attempted")
        require(source.contains("hidSetReportInvoked: false"), "probe safety report must prove no HID report writes were invoked")
        require(source.contains("voltagePowerMutationAttempted: false"), "probe safety report must prove no voltage/power mutation was attempted")
        require(source.contains("authorizationServicesUsed: false"), "probe safety report must prove no Authorization Services were used")
        require(source.contains("workloadGenerated: false"), "probe must prove that it generates no workload")

        print("PASS ThermalHardwareProbe read-only source contract")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
