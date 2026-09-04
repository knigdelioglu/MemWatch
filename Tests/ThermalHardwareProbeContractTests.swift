import Foundation

@main
struct ThermalHardwareProbeContractTests {
    static func main() throws {
        let sourcePath = "Scripts/ThermalHardwareProbe/main.swift"
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
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

        let forbiddenMutationTokens = [
            "writeBytes",
            "SMC_CMD_WRITE",
            "setKey",
            "writeKey",
            "IOConnectCallMethod(",
            "IOConnectCallScalarMethod",
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
