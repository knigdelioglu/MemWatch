# MemWatch thermal hardware probe

Read-only evidence collected at 2026-09-04T10:11:12Z.

## A. Hardware detected

- Model: Mac16,12
- Chip: Apple M4
- Architecture: arm64
- Apple Silicon: true
- macOS: 27.0 (26A5425a)
- Kernel: 27.0.0
- Effective UID: 501
- Running as root: false
- Sandbox: not determinable from CLI environment (no container marker)

## B. AppleSMC access

AppleSMC unavailable: matching service was found, but IOServiceOpen/#KEY protocol validation failed
- Protocol attempt: IOConnectCallStructMethod selector 2; key-info command 9, read-bytes command 5, read-index command 8; not reached because IOServiceOpen/#KEY validation failed
- Discovery attempts:
  - AppleSMC → AppleSMCKeysEndpoint / AppleSMCKeysEndpoint; IOServiceOpen: 0xE00002E2 (iokit/common) not permitted; protocol: IOServiceOpen failed
  - AppleSMCInterface → AppleSMCInterface / smc-pmu; IOServiceOpen: 0xE00002C7 (iokit/common) unsupported function; protocol: IOServiceOpen failed
  - AppleSMCInterface → AppleSMCInterface / smc-charger-util-1; IOServiceOpen: 0xE00002C7 (iokit/common) unsupported function; protocol: IOServiceOpen failed
  - AppleSMCInterface → AppleSMCInterface / smc-charger-util-0; IOServiceOpen: 0xE00002C7 (iokit/common) unsupported function; protocol: IOServiceOpen failed
  - AppleSMCInterface → AppleSMCInterface / smc-charger-util; IOServiceOpen: 0xE00002C7 (iokit/common) unsupported function; protocol: IOServiceOpen failed
  - AppleSMCPMU → AppleSMCPMU / AppleSMCPMU; IOServiceOpen: 0xE00002C7 (iokit/common) unsupported function; protocol: IOServiceOpen failed
  - AppleSMCClient: no matching service
- Key enumeration: SKIPPED because no read-only SMC connection passed protocol validation

## C. Temperature-capable keys

Temperature-like means only that the dynamically enumerated FourCC begins with `T`; meaning is not asserted from the prefix.

| Key | Type | °C | Candidate meaning | Confidence | Status | Samples min / avg / max / delta |
|---|---|---:|---|---|---|---:|
| — | — | — | No temperature-like SMC keys observed | — | — | — |

- Temperature-like keys: 0
- Keys with a decoder and valid initial sample: 0
- Sanity range: -40.0 ... 125.0 °C; values are rejected, never clamped. This broad range covers ordinary internal and battery diagnostic readings while rejecting sentinels and obvious fixed-point failures.

## D. Battery telemetry

- AppleSmartBattery service: PASS (2 match(es))
- Matched service classes: AppleSmartBattery, AppleSmartBatteryPack
- Property read: PASS
- Selected interpretation: UNVERIFIED

| Property | Path | NSNumber/CF representation | Candidate conversions |
|---|---|---|---|
| Amperage | AppleSmartBattery.Amperage | objCType=i, int64=0, uint64=0, double=0.00 | — |
| InstantAmperage | AppleSmartBattery.InstantAmperage | objCType=i, int64=0, uint64=0, double=0.00 | — |
| Voltage | AppleSmartBattery.Voltage | objCType=i, int64=12630, uint64=12630, double=12630.00 | — |
| Amperage | AppleSmartBatteryPack.BatteryData.Amperage | objCType=i, int64=0, uint64=0, double=0.00 | — |
| InstantAmperage | AppleSmartBatteryPack.BatteryData.InstantAmperage | objCType=i, int64=0, uint64=0, double=0.00 | — |
| AverageTemperature | AppleSmartBatteryPack.BatteryData.LifetimeData.AverageTemperature | objCType=i, int64=225, uint64=225, double=225.00 | Candidate macOS /100 interpretation=2.25 °C [plausible]<br>Candidate Smart Battery 0.1 K interpretation=-250.65 °C [invalid]<br>Candidate tenths-Celsius interpretation=22.50 °C [plausible]<br>Candidate integer-Celsius interpretation=225.00 °C [invalid] |
| MaximumTemperature | AppleSmartBatteryPack.BatteryData.LifetimeData.MaximumTemperature | objCType=i, int64=40, uint64=40, double=40.00 | Candidate macOS /100 interpretation=0.40 °C [plausible]<br>Candidate Smart Battery 0.1 K interpretation=-269.15 °C [invalid]<br>Candidate tenths-Celsius interpretation=4.00 °C [plausible]<br>Candidate integer-Celsius interpretation=40.00 °C [plausible] |
| MinimumTemperature | AppleSmartBatteryPack.BatteryData.LifetimeData.MinimumTemperature | objCType=i, int64=3, uint64=3, double=3.00 | Candidate macOS /100 interpretation=0.03 °C [plausible]<br>Candidate Smart Battery 0.1 K interpretation=-272.85 °C [invalid]<br>Candidate tenths-Celsius interpretation=0.30 °C [plausible]<br>Candidate integer-Celsius interpretation=3.00 °C [plausible] |
| TemperatureSamples | AppleSmartBatteryPack.BatteryData.LifetimeData.TemperatureSamples | objCType=i, int64=221673, uint64=221673, double=221673.00 | Candidate macOS /100 interpretation=2216.73 °C [invalid]<br>Candidate Smart Battery 0.1 K interpretation=21894.15 °C [invalid]<br>Candidate tenths-Celsius interpretation=22167.30 °C [invalid]<br>Candidate integer-Celsius interpretation=221673.00 °C [invalid] |
| Temperature | AppleSmartBatteryPack.BatteryData.Temperature | objCType=i, int64=3329, uint64=3329, double=3329.00 | Candidate macOS /100 interpretation=33.29 °C [plausible]<br>Candidate Smart Battery 0.1 K interpretation=59.75 °C [plausible]<br>Candidate tenths-Celsius interpretation=332.90 °C [invalid]<br>Candidate integer-Celsius interpretation=3329.00 °C [invalid] |
| VirtualTemperature | AppleSmartBatteryPack.BatteryData.VirtualTemperature | objCType=i, int64=3329, uint64=3329, double=3329.00 | Candidate macOS /100 interpretation=33.29 °C [plausible]<br>Candidate Smart Battery 0.1 K interpretation=59.75 °C [plausible]<br>Candidate tenths-Celsius interpretation=332.90 °C [invalid]<br>Candidate integer-Celsius interpretation=3329.00 °C [invalid] |
| Voltage | AppleSmartBatteryPack.BatteryData.Voltage | objCType=q, int64=12630, uint64=12630, double=12630.00 | — |

Temperature-unit selection remains UNVERIFIED. The report preserves /100, Smart Battery 0.1 K, tenths-Celsius and integer-Celsius candidates without selecting or clamping one.

## E. CPU findings

No validated CPU/SoC sensor evidence.

## F. GPU findings

No validated GPU sensor evidence.

## G. Memory findings

No validated memory-related sensor evidence.
Memory Proximity is not treated as RAM junction temperature.

## H. SSD findings

No validated storage-related sensor evidence.
SSD proximity is not treated as NAND temperature.

## I. Unknown sensors

None among temperature-like keys.

## J. Sampling correlation

- Requested: 12 sample(s) × 5.0 seconds
- Status: SKIPPED: AppleSMC connection unavailable
- Completed: 0; workload generated: false

| Key | Min | Avg | Max | Delta | First | Last | Valid / invalid |
|---|---:|---:|---:|---:|---:|---:|---:|
| — | — | — | — | — | — | — | — |

## K. Safety

- Read-only: true
- SMC mutation attempted: false
- Fan manipulation: false
- Power-limit mutation: false
- powermetrics invoked: false
- Privileged helper used: false
- Connection release: NOT APPLICABLE; no SMC connection was opened

## L. Performance

- Total wall time: 724.81 ms
- Process CPU time: 9.90 ms
- SMC enumeration wall time: 0.00 ms
- Initial key reads: 0; sampled temperature reads: 0
- 5-second diagnostic cadence is reasonable; measured probe CPU time is 9.90 ms/sample and does not approach the cadence budget.

## M. Build/tests

- Probe build with `-warnings-as-errors`: PASS.
- Probe codec and sanity self-test: PASS.
- Read-only source contract test: PASS.
- Existing `BackgroundCadenceTests`: PASS.
- Existing `MergeArchitectureContractTests`: PASS.
- Existing `MonitoringConcurrencyTests`: PASS (Xcode 27 SDK emitted an existing `sysctl.h` macro-import warning).
- MemWatch Debug Xcode build: FAIL in the environment (Xcode 27 beta SwiftUI macro plugin server returned a malformed response; exit 65). No production thermal files were changed and the probe is outside the app target.
- Hardware snapshot: PASS; 12 × 5-second sampling: SKIPPED because AppleSMC was unavailable before key enumeration.

## N. Files created

- `thermal_probe_summary.md`
- `thermal_probe_raw.json`

## O. Production recommendations

- Keep thermal monitoring out of MemWatch until exact M4 semantics are validated with controlled manual workloads.
- Treat AppleSMC key prefixes as candidate labels only; do not ship CPU-core, P-core/E-core, GPU, DRAM or NAND names from this snapshot alone.
- AppleSmartBattery values can be surfaced as raw diagnostics first; keep Temperature/VirtualTemperature conversion UNVERIFIED unless an independent unit contract is established.
- If future production use adopts SMC, the observed lifecycle supports cached connection + sleep invalidation + wake reconnect as a design to validate, not as a probe guarantee.

## P. Unresolved questions

- Physical sensor placement and P-core/E-core semantics are not proven by key names or idle sampling.
- Memory junction and SSD/NAND temperatures are not proven unless an external, model-specific source agrees with controlled workload correlation.
- AppleSmartBattery Temperature unit remains UNVERIFIED when multiple physically plausible interpretations exist.

## Q. Verdict

MORE HARDWARE VALIDATION REQUIRED

## References

- Apple IOKit IOServiceOpen documentation: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen
- Apple IOKit IOConnectCallStructMethod documentation: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod
- Linux/Asahi Apple Silicon SMC transport reference: https://github.com/torvalds/linux/blob/master/drivers/mfd/macsmc.c
- Linux/Asahi Apple Silicon SMC hwmon type handling reference: https://github.com/torvalds/linux/blob/master/drivers/hwmon/macsmc-hwmon.c
- Stats Swift SMC user-client structure and read command reference: https://github.com/exelban/stats/blob/master/SMC/smc.swift
- macmon Apple Silicon monitor reference: https://github.com/vladkens/macmon
- iSMC Apple Silicon HID/SMC split reference: https://github.com/dkorunic/iSMC
