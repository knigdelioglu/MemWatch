# MemWatch thermal hardware validation

Read-only diagnostic evidence; generated at 2026-09-04T11:27:45Z.
Run identifier: m4-mac16-12-12x5-20260904-final2

## A. Hardware

- Model: Mac16,12
- Chip: Apple M4
- Architecture: arm64; Apple Silicon: true
- macOS: 27.0 (26A5425a)
- Kernel: 27.0.0
- Effective UID: 501; root: false
- Sandbox marker: not determinable from CLI environment (no container marker)

## B. HID private symbol availability

| Symbol | Found |
|---|---|
| IOHIDEventGetFloatValue | FOUND |
| IOHIDEventSystemClientCopyServices | FOUND |
| IOHIDEventSystemClientCreate | FOUND |
| IOHIDEventSystemClientSetMatching | FOUND |
| IOHIDServiceClientCopyEvent | FOUND |
| IOHIDServiceClientCopyProperty | FOUND |

- Library loaded: true; all required symbols: true
- Matching: PrimaryUsagePage 0xFF00; PrimaryUsage 0x0005; call result void API; no return code; status noServices
- Discovery error: IOHIDEventSystemClientCopyServices returned nil
- Provenance: Apple IOHIDFamily/Chromium declares Apple vendor page 0xFF00, temperature usage 0x0005, event type 15, and event field base type << 16. The probe records these constants and resolves private symbols at runtime.
- Compared implementations: Stats, SwiftTempBar, lude-vitals, and redline use this diagnostic path; their repositories are MIT. iSMC is GPL-3.0 and was reference-only; no GPL code was copied.

## C. HID temperature services

| ID | Product | Current °C | Candidate category | Confidence |
|---|---|---:|---|---|
| — | — | — | unknown | unknown |

- Raw services are retained even when names suggest duplicates, virtual sensors, calibration, battery, memory, or storage.

## D. Raw properties

No matching HID temperature service exposed properties.

## E. 12×5 sampling results

- Requested: 12 sample(s) × 5.00 seconds; completed: 12
- Status: completed; AppleSMC unavailable; HID returned no temperature services; workload generated: false

| Product | Samples | Valid | Min | Avg | Max | Delta | Std dev |
|---|---:|---:|---:|---:|---:|---:|---:|
| — | 0 | 0 | — | — | — | — | — |

- HID events: 0; successful event copies: 0; failed event copies: 0
- Duplicate/derived candidates: none observed under the conservative same-Product/series-correlation rules.

## F. CPU candidates

- HID tiers:
- None.
- SMC evidence:
No validated CPU/SoC sensor evidence.
- P-core versus E-core is not inferred.

## G. GPU candidates

- HID tiers:
- None.
- SMC evidence:
No validated GPU sensor evidence.

## H. Memory candidates

- No matching Product string was observed.
- Memory/RAM junction temperature is not asserted from Product text alone; raw classification remains unknown.

## I. Storage candidates

- No matching Product string was observed.
- NAND/SSD temperature is not asserted from Product text alone; raw classification remains unknown.

## J. Battery comparison

- AppleSmartBattery service: available; matches: 2; properties: read
- Raw Temperature: 3300.00; raw VirtualTemperature: 3300.00
- Candidate unit confidence: LOW; selected interpretation: UNVERIFIED

| Field | Raw | /100 candidate °C | 0.1 K candidate °C |
|---|---:|---:|---:|
| AppleSmartBatteryPack.BatteryData.LifetimeData.AverageTemperature | 225.00 | 2.25 | -250.65 |
| AppleSmartBatteryPack.BatteryData.LifetimeData.MaximumTemperature | 40.00 | 0.40 | -269.15 |
| AppleSmartBatteryPack.BatteryData.LifetimeData.MinimumTemperature | 3.00 | 0.03 | -272.85 |
| AppleSmartBatteryPack.BatteryData.Temperature | 3300.00 | 33.00 | 56.85 |
| AppleSmartBatteryPack.BatteryData.VirtualTemperature | 3300.00 | 33.00 | 56.85 |

Temperature raw 3300 gives /100 = 33.00 °C and 0.1 K = 56.85 °C.
The first probe recorded BatteryData.Temperature raw 3329: /100 = 33.29 °C versus 0.1 K = 59.75 °C. The 59.75 °C interpretation is physically plausible as an instantaneous value, but it would not reconcile with LifetimeData.MaximumTemperature raw 40 if that lifetime field is integer °C. Because BatteryData and LifetimeData units are not guaranteed identical, this weighs against treating 0.1 K as established; it is not proof of /100.
- Lifetime metadata raw: AverageTemperature 225.00, MinimumTemperature 3.00, MaximumTemperature 40.00, TemperatureSamples 221673.00
- Assessment: Observed Temperature raw 3300 gives /100 = 33.00 °C and Smart Battery 0.1 K = 56.85 °C; both pass the broad sanity range. LifetimeData.MaximumTemperature raw 40 is not assumed to share the same unit. If it means 40 °C, /100 is internally more consistent (33.00 ≤ 40) while 0.1 K would exceed it (56.85 > 40). If the lifetime field uses another unit, this is only supporting evidence, not a unit contract.
- Same-run AppleSmartBattery sampling: 12/12 points; 24 temperature-field readings; status completed

| Field | Readings | Raw min / avg / max | /100 avg °C | 0.1 K avg °C |
|---|---:|---|---:|---:|
| Temperature | 12 | 3300.00 / 3300.00 / 3300.00 | 33.00 | 56.85 |
| VirtualTemperature | 12 | 3300.00 / 3300.00 / 3300.00 | 33.00 | 56.85 |

- HID battery comparison: no Product-backed battery service was identified; no cross-backend match asserted.

## K. AppleSMC status

- Rootless AppleSMC: unavailable; matching service was found, but IOServiceOpen/#KEY protocol validation failed
  - AppleSMC: IOServiceOpen 0xE00002E2 (iokit/common) not permitted; IOServiceOpen failed
  - AppleSMCInterface: IOServiceOpen 0xE00002C7 (iokit/common) unsupported function; IOServiceOpen failed
  - AppleSMCInterface: IOServiceOpen 0xE00002C7 (iokit/common) unsupported function; IOServiceOpen failed
  - AppleSMCInterface: IOServiceOpen 0xE00002C7 (iokit/common) unsupported function; IOServiceOpen failed
  - AppleSMCInterface: IOServiceOpen 0xE00002C7 (iokit/common) unsupported function; IOServiceOpen failed
  - AppleSMCPMU: IOServiceOpen 0xE00002C7 (iokit/common) unsupported function; IOServiceOpen failed
- This preserves the first probe conclusion: rootless SMC enumeration is unavailable unless new evidence says otherwise.

## L. Performance

- Total wall: 55507.16 ms; process CPU: 73.76 ms
- Initial HID discovery: 3.24 ms wall / 2.66 ms CPU
- First HID sample read: 0.01 ms wall / 0.01 ms CPU
- Cached HID reads: 11 samples, 0.26 ms wall total / 0.18 ms CPU total
- HID service count: 0; event read count: 0
- Discovery strategy: discover/cache once; subsequent samples read cached service references; full discovery is not repeated per sample.
- 5-second cadence assessment: 5-second diagnostic cadence is reasonable; measured probe CPU time is 6.15 ms/sample and does not approach the cadence budget.
- Sampling wall: 55096.45 ms; SMC key reads initial/sample: 0/0

## M. Safety/read-only verification

| Check | Result |
|---|---|
| Read-only contract | PASS |
| SMC writes attempted | PASS |
| HID writes attempted | PASS |
| HID report mutation invoked | PASS |
| Voltage/power mutation attempted | PASS |
| Authorization Services used | PASS |
| Fan/power-limit controls | PASS |
| powermetrics | PASS |
| Privileged helper | PASS |
| Workload generated | PASS |
| Root required | PASS (actual root: false) |
| Sleep/wake integration | NOT IMPLEMENTED; lifecycle test UNTESTED |

- HID cleanup: service array attempted/released false/false; client true/true; dlopen handle true/true.

## N. Build/tests

- Probe build: PASS for this run; runtime private-symbol availability is reported above.
- Codec/self-test and source-contract test: run separately and recorded in the task report.
- MemWatch Debug build result is reported separately; a SwiftUI macro/plugin failure is not interpreted as a thermal regression.

## O. Files changed/created

- Raw JSON: docs/generated/thermal_probe/thermal_probe_m4-mac16-12-12x5-20260904-final2_raw.json
- Markdown summary: docs/generated/thermal_probe/thermal_probe_m4-mac16-12-12x5-20260904-final2_summary.md
- Probe source: Scripts/ThermalHardwareProbe/main.swift and HIDTemperatureReader.swift

## P. Production-ready sensor matrix

| Category | Backend | Available | Confidence | Production recommendation |
|---|---|---|---|---|
| CPU/SoC | IOHID temperature service | no | unknown | no evidence in this run; controlled workload still required |
| GPU | IOHID temperature service | no | unknown | no evidence in this run; controlled workload still required |
| Battery | AppleSmartBattery | yes | LOW | raw diagnostic only until unit/correlation contract is established |
| Memory | IOHID/SMC | no proven sensor | unknown | do not label RAM/DRAM junction from this run |
| Storage | IOHID/SMC | no proven sensor | unknown | do not label NAND/SSD from this run |
| AppleSMC | AppleSMC user client | no | unavailable | rootless enumeration is unavailable |

## Q. Remaining unknowns

- HID Product names do not prove physical placement, calibration, or derived/virtual semantics; raw service identities remain available for later correlation.
- CPU/GPU category evidence, if present, is not a controlled workload validation; P-core/E-core, RAM junction, and NAND semantics remain unknown.
- BatteryData and LifetimeData may use different units; the /100 versus 0.1 K comparison is correlation evidence only.
- Sleep/wake reference survival and the need for post-wake HID rediscovery: UNTESTED (this probe does not implement sleep/wake).

## R. Verdict

MORE HARDWARE VALIDATION REQUIRED

This diagnostic does not modify MemWatch production behavior.

External evidence and licenses:
- Apple IOKit IOServiceOpen documentation: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen
- Apple IOKit IOConnectCallStructMethod documentation: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod
- Apple IOKit IOHIDEventSystemClientCopyServices documentation: https://developer.apple.com/documentation/iokit/2269511-iohideventsystemclientcopyservic
- Apple IOKit IOHIDServiceClientCopyProperty documentation: https://developer.apple.com/documentation/iokit/2269430-iohidserviceclientcopyproperty
- Linux/Asahi Apple Silicon SMC transport reference: https://github.com/torvalds/linux/blob/master/drivers/mfd/macsmc.c
- Linux/Asahi Apple Silicon SMC hwmon type handling reference: https://github.com/torvalds/linux/blob/master/drivers/hwmon/macsmc-hwmon.c
- Stats Swift SMC user-client structure and read command reference: https://github.com/exelban/stats/blob/master/SMC/smc.swift
- Stats IOHID temperature reader reference (MIT): https://github.com/exelban/stats/blob/master/Modules/Sensors/reader.m
- SwiftTempBar IOHID temperature matching and event reference (MIT): https://github.com/WHYBBE/SwiftTempBar
- SwiftTempBar source declaration of the void SetMatching ABI (MIT): https://github.com/WHYBBE/SwiftTempBar/blob/main/Sources/TemperatureReader.swift
- lude-vitals IOHID private-symbol sampler reference (MIT): https://github.com/iamdemetris/lude-vitals
- redline IOHID temperature enumeration and conservative filtering reference (MIT): https://github.com/apeabody007/redline
- IOHID temperature usage/event declarations: https://github.com/freedomtan/sensors_cmdline/blob/main/sensors.m
- Chromium Apple Silicon sensor declarations: https://chromium.googlesource.com/chromium/src/+/c21e9f71d1f2e/components/power_metrics/m1_sensors_internal_types_mac.h
- Netdata macOS IOHID declaration comparison: https://github.com/netdata/netdata/blob/master/src/collectors/macos.plugin/macos_iohid.c
- macmon/mactop Apple Silicon monitor reference (MIT; optional fan-control writes are outside this probe): https://github.com/metaspartan/mactop
- iSMC Apple Silicon HID/SMC reference (GPL-3.0; reference only, no code copied): https://github.com/dkorunic/iSMC
