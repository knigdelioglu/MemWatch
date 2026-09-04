# MemWatch thermal hardware validation

Read-only diagnostic evidence; generated at 2026-09-04T11:45:37Z.
Run identifier: m4-test-repro

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
- Matching: PrimaryUsagePage 0xFF00; PrimaryUsage 0x0005; call result void API; no return code; status completed
- Provenance: Apple IOHIDFamily/Chromium declares Apple vendor page 0xFF00, temperature usage 0x0005, event type 15, and event field base type << 16. The probe records these constants and resolves private symbols at runtime.
- Compared implementations: Stats, SwiftTempBar, lude-vitals, and redline use this diagnostic path; their repositories are MIT. iSMC is GPL-3.0 and was reference-only; no GPL code was copied.

## C. HID temperature services

| ID | Product | Current °C | Candidate category | Confidence |
|---|---|---:|---|---|
| LocationID=1414674274 | PMU2 tdie7 | 42.45 | gpu | likely |
| LocationID=1414542434 | PMU tdie4 | 45.40 | cpu | likely |
| LocationID=1413951560 | gas gauge battery | 34.00 | battery | validated |
| LocationID=1414553954 | PMU tdie10 | 45.09 | cpu | likely |
| LocationID=1414673764 | PMU2 tdev5 | 43.68 | gpu | likely |
| LocationID=1414674796 | PMU2 tdie9 | 42.61 | gpu | likely |
| LocationID=1414543202 | PMU tdie7 | 46.52 | cpu | likely |
| LocationID=1414541666 | PMU tdie1 | 45.88 | cpu | likely |
| LocationID=1413951810 | gas gauge battery | 33.70 | battery | validated |
| LocationID=1414554732 | PMU tdie13 | 45.56 | cpu | likely |
| LocationID=1414672994 | PMU2 tdie2 | 43.65 | gpu | likely |
| LocationID=1414543714 | PMU tdie9 | 44.93 | cpu | likely |
| LocationID=1414542690 | PMU tdie5 | 45.48 | cpu | likely |
| LocationID=1414672996 | PMU2 tdev2 | 42.92 | gpu | likely |
| LocationID=1414673506 | PMU2 tdie4 | 42.53 | gpu | likely |
| LocationID=1414543204 | PMU tdev7 | 42.31 | cpu | likely |
| LocationID=1414674018 | PMU2 tdie6 | 42.69 | gpu | likely |
| LocationID=1414541922 | PMU tdie2 | 44.93 | cpu | likely |
| LocationID=1414554988 | PMU tdie14 | 45.32 | cpu | likely |
| LocationID=1414410350 | NAND CH0 temp | 42.00 | unknown | unknown |
| LocationID=1413951555 | gas gauge battery | 33.00 | battery | validated |
| LocationID=1414673508 | PMU2 tdev4 | 45.60 | gpu | likely |
| LocationID=0 | als-temp | — | unknown | unknown |
| LocationID=1414674540 | PMU2 tdie8 | 42.53 | gpu | likely |
| LocationID=1414542946 | PMU tdie6 | 47.08 | cpu | likely |
| LocationID=1414541402 | PMU tcal | 51.82 | unknown | unknown |
| LocationID=1413951574 | gas gauge battery | 34.00 | battery | validated |
| LocationID=1414554220 | PMU tdie11 | 45.32 | cpu | likely |
| LocationID=1414542180 | PMU tdev3 | 41.33 | cpu | likely |
| LocationID=1414672738 | PMU2 tdie1 | 43.81 | gpu | likely |
| LocationID=1414542692 | PMU tdev5 | 44.70 | cpu | likely |
| LocationID=1414685036 | PMU2 tdie10 | 42.21 | gpu | likely |
| LocationID=1414542178 | PMU tdie3 | 44.93 | cpu | likely |
| LocationID=1414672740 | PMU2 tdev1 | -22.07 | gpu | likely |
| LocationID=1413952066 | gas gauge battery | 34.00 | battery | validated |
| LocationID=1414542436 | PMU tdev4 | 44.16 | cpu | likely |
| LocationID=1414673250 | PMU2 tdie3 | 42.61 | gpu | likely |
| LocationID=1414542948 | PMU tdev6 | 41.33 | cpu | likely |
| LocationID=1414541668 | PMU tdev1 | -22.10 | cpu | likely |
| LocationID=1414673762 | PMU2 tdie5 | 42.45 | gpu | likely |
| LocationID=1414543460 | PMU tdev8 | 42.71 | cpu | likely |
| LocationID=1414672474 | PMU2 tcal | 51.82 | unknown | unknown |
| LocationID=1414554476 | PMU tdie12 | 45.32 | cpu | likely |
| LocationID=1413951554 | gas gauge battery | 34.00 | battery | validated |
| LocationID=1414543458 | PMU tdie8 | 46.28 | cpu | likely |
| LocationID=1414541924 | PMU tdev2 | 43.99 | cpu | likely |
| LocationID=1414673252 | PMU2 tdev3 | -22.20 | gpu | likely |

- Raw services are retained even when names suggest duplicates, virtual sensors, calibration, battery, memory, or storage.

## D. Raw properties

### PMU2 tdie7

- ID: LocationID=1414674274; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414674274 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie7 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie4

- ID: LocationID=1414542434; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542434 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie4 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### gas gauge battery

- ID: LocationID=1413951560; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1413951560 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | gas gauge battery |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie10

- ID: LocationID=1414553954; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414553954 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie10 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdev5

- ID: LocationID=1414673764; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414673764 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdev5 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie9

- ID: LocationID=1414674796; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414674796 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie9 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie7

- ID: LocationID=1414543202; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414543202 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie7 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie1

- ID: LocationID=1414541666; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414541666 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie1 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### gas gauge battery

- ID: LocationID=1413951810; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1413951810 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | gas gauge battery |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie13

- ID: LocationID=1414554732; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414554732 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie13 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie2

- ID: LocationID=1414672994; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414672994 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie2 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie9

- ID: LocationID=1414543714; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414543714 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie9 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie5

- ID: LocationID=1414542690; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542690 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie5 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdev2

- ID: LocationID=1414672996; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414672996 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdev2 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie4

- ID: LocationID=1414673506; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414673506 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie4 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev7

- ID: LocationID=1414543204; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414543204 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev7 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie6

- ID: LocationID=1414674018; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414674018 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie6 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie2

- ID: LocationID=1414541922; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414541922 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie2 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie14

- ID: LocationID=1414554988; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414554988 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie14 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### NAND CH0 temp

- ID: LocationID=1414410350; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414410350 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | NAND CH0 temp |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### gas gauge battery

- ID: LocationID=1413951555; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1413951555 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | gas gauge battery |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdev4

- ID: LocationID=1414673508; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414673508 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdev4 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### als-temp

- ID: LocationID=0; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| LocationID | NSNumber | 0 |
| Manufacturer | string | Apple |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | als-temp |
| ProductID | NSNumber | 33028 |
| Transport | string | SPU |
| VendorID | NSNumber | 1452 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie8

- ID: LocationID=1414674540; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414674540 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie8 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie6

- ID: LocationID=1414542946; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542946 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie6 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tcal

- ID: LocationID=1414541402; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414541402 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tcal |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### gas gauge battery

- ID: LocationID=1413951574; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1413951574 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | gas gauge battery |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie11

- ID: LocationID=1414554220; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414554220 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie11 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev3

- ID: LocationID=1414542180; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542180 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev3 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie1

- ID: LocationID=1414672738; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414672738 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie1 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev5

- ID: LocationID=1414542692; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542692 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev5 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie10

- ID: LocationID=1414685036; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414685036 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie10 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie3

- ID: LocationID=1414542178; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542178 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie3 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdev1

- ID: LocationID=1414672740; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414672740 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdev1 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### gas gauge battery

- ID: LocationID=1413952066; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1413952066 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | gas gauge battery |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev4

- ID: LocationID=1414542436; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542436 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev4 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie3

- ID: LocationID=1414673250; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414673250 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie3 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev6

- ID: LocationID=1414542948; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414542948 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev6 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev1

- ID: LocationID=1414541668; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414541668 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev1 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdie5

- ID: LocationID=1414673762; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414673762 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdie5 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev8

- ID: LocationID=1414543460; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414543460 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev8 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tcal

- ID: LocationID=1414672474; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414672474 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tcal |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie12

- ID: LocationID=1414554476; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414554476 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie12 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### gas gauge battery

- ID: LocationID=1413951554; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1413951554 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | gas gauge battery |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdie8

- ID: LocationID=1414543458; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414543458 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdie8 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU tdev2

- ID: LocationID=1414541924; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414541924 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU tdev2 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.
### PMU2 tdev3

- ID: LocationID=1414673252; identity source: LocationID
- Property copy errors: none reported

| Property | Kind | Value/summary |
|---|---|---|
| CountryCode | NSNumber | 0 |
| DeviceUsagePairs | array | <array> |
| HIDEventServiceProperties | dictionary | <dictionary> |
| LocationID | NSNumber | 1414673252 |
| PrimaryUsage | NSNumber | 5 |
| PrimaryUsagePage | NSNumber | 65280 |
| Product | string | PMU2 tdev3 |
| ProductID | NSNumber | 0 |
| VendorID | NSNumber | 0 |
| VendorIDSource | NSNumber | 0 |

Full nested/raw values are preserved in the JSON evidence.

## E. 12×5 sampling results

- Requested: 2 sample(s) × 1.00 seconds; completed: 2
- Status: completed; workload generated: false

| Product | Samples | Valid | Min | Avg | Max | Delta | Std dev |
|---|---:|---:|---:|---:|---:|---:|---:|
| PMU2 tdie7 | 2 | 2 | 42.45 | 42.53 | 42.61 | -0.16 | 0.08 |
| PMU tdie4 | 2 | 2 | 44.93 | 45.16 | 45.40 | 0.48 | 0.24 |
| gas gauge battery | 2 | 2 | 34.00 | 34.00 | 34.00 | 0.00 | 0.00 |
| PMU tdie10 | 2 | 2 | 44.37 | 44.73 | 45.09 | 0.72 | 0.36 |
| PMU2 tdev5 | 2 | 2 | 43.68 | 43.77 | 43.86 | -0.17 | 0.09 |
| PMU2 tdie9 | 2 | 2 | 42.45 | 42.53 | 42.61 | 0.16 | 0.08 |
| PMU tdie7 | 2 | 2 | 46.52 | 46.68 | 46.84 | -0.32 | 0.16 |
| PMU tdie1 | 2 | 2 | 45.88 | 46.12 | 46.36 | -0.48 | 0.24 |
| gas gauge battery | 2 | 2 | 33.70 | 33.75 | 33.80 | -0.10 | 0.05 |
| PMU tdie13 | 2 | 2 | 45.56 | 45.76 | 45.96 | -0.40 | 0.20 |
| PMU2 tdie2 | 2 | 2 | 43.49 | 43.57 | 43.65 | 0.16 | 0.08 |
| PMU tdie9 | 2 | 2 | 44.93 | 45.12 | 45.32 | -0.40 | 0.20 |
| PMU tdie5 | 2 | 2 | 45.48 | 45.60 | 45.72 | -0.24 | 0.12 |
| PMU2 tdev2 | 2 | 2 | 42.92 | 42.92 | 42.92 | 0.00 | 0.00 |
| PMU2 tdie4 | 2 | 2 | 42.05 | 42.29 | 42.53 | 0.48 | 0.24 |
| PMU tdev7 | 2 | 2 | 42.12 | 42.22 | 42.31 | 0.18 | 0.09 |
| PMU2 tdie6 | 2 | 2 | 42.29 | 42.49 | 42.69 | 0.40 | 0.20 |
| PMU tdie2 | 2 | 2 | 44.93 | 45.12 | 45.32 | -0.40 | 0.20 |
| PMU tdie14 | 2 | 2 | 45.32 | 45.56 | 45.80 | -0.48 | 0.24 |
| NAND CH0 temp | 2 | 2 | 42.00 | 42.00 | 42.00 | 0.00 | 0.00 |
| gas gauge battery | 2 | 2 | 33.00 | 33.00 | 33.00 | 0.00 | 0.00 |
| PMU2 tdev4 | 2 | 2 | 45.60 | 45.76 | 45.92 | -0.32 | 0.16 |
| als-temp | 2 | 0 | — | — | — | — | — |
| PMU2 tdie8 | 2 | 2 | 42.53 | 42.81 | 43.09 | -0.56 | 0.28 |
| PMU tdie6 | 2 | 2 | 46.60 | 46.84 | 47.08 | 0.48 | 0.24 |
| PMU tcal | 2 | 2 | 51.82 | 51.82 | 51.82 | 0.00 | 0.00 |
| gas gauge battery | 2 | 2 | 34.00 | 34.00 | 34.00 | 0.00 | 0.00 |
| PMU tdie11 | 2 | 2 | 45.32 | 45.44 | 45.56 | -0.24 | 0.12 |
| PMU tdev3 | 2 | 2 | 41.33 | 41.49 | 41.65 | -0.33 | 0.16 |
| PMU2 tdie1 | 2 | 2 | 43.81 | 43.85 | 43.89 | -0.08 | 0.04 |
| PMU tdev5 | 2 | 2 | 44.52 | 44.61 | 44.70 | 0.17 | 0.09 |
| PMU2 tdie10 | 2 | 2 | 42.21 | 42.29 | 42.37 | -0.16 | 0.08 |
| PMU tdie3 | 2 | 2 | 44.93 | 45.08 | 45.24 | -0.32 | 0.16 |
| PMU2 tdev1 | 2 | 2 | -22.21 | -22.14 | -22.07 | 0.13 | 0.07 |
| gas gauge battery | 2 | 2 | 34.00 | 34.00 | 34.00 | 0.00 | 0.00 |
| PMU tdev4 | 2 | 2 | 44.16 | 44.23 | 44.29 | -0.13 | 0.07 |
| PMU2 tdie3 | 2 | 2 | 42.61 | 42.73 | 42.85 | -0.24 | 0.12 |
| PMU tdev6 | 2 | 2 | 41.33 | 41.49 | 41.65 | -0.33 | 0.16 |
| PMU tdev1 | 2 | 2 | -22.10 | -22.09 | -22.07 | -0.03 | 0.01 |
| PMU2 tdie5 | 2 | 2 | 42.45 | 42.49 | 42.53 | -0.08 | 0.04 |
| PMU tdev8 | 2 | 2 | 42.71 | 42.77 | 42.84 | -0.14 | 0.07 |
| PMU2 tcal | 2 | 2 | 51.82 | 51.82 | 51.82 | 0.00 | 0.00 |
| PMU tdie12 | 2 | 2 | 45.32 | 45.52 | 45.72 | -0.40 | 0.20 |
| gas gauge battery | 2 | 2 | 34.00 | 34.00 | 34.00 | 0.00 | 0.00 |
| PMU tdie8 | 2 | 2 | 46.28 | 46.40 | 46.52 | -0.24 | 0.12 |
| PMU tdev2 | 2 | 2 | 43.99 | 44.06 | 44.12 | -0.14 | 0.07 |
| PMU2 tdev3 | 2 | 2 | -22.21 | -22.21 | -22.20 | 0.01 | 0.01 |

- HID events: 94; successful event copies: 92; failed event copies: 2
- Duplicate/derived candidates:
  - PMU2 tdie7 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414673762: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU2 tdie7 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie7 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie4 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained (max absolute difference 0.000 °C)
  - PMU tdie10 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie10 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev5 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie9 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie7 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie1 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414673508: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.045 °C)
  - PMU tdie13 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie13 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie2 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414541922: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.000 °C)
  - PMU tdie9 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414542178: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU tdie9 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie9 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie5 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie4 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev7 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie6 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414543714: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.000 °C)
  - PMU tdie2 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414542178: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU tdie2 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie2 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414554476: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU tdie14 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie14 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained
  - PMU2 tdev4 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414554732: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.045 °C)
  - PMU2 tdev4 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev4 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie8 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie6 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tcal ↔ LocationID=1414672474: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained (max absolute difference 0.000 °C)
  - PMU tdie11 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie11 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414542948: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.000 °C)
  - PMU tdev3 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev3 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie1 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev5 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie10 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414543714: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU tdie3 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414541922: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU tdie3 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie3 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev1 ↔ LocationID=1414673252: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained (max absolute difference 0.000 °C)
  - PMU tdev4 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev4 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie3 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414542180: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.000 °C)
  - PMU tdev6 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev6 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev1 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414674274: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU2 tdie5 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdie5 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev8 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tcal ↔ LocationID=1414541402: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.000 °C)
  - PMU tdie12 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414554988: near-identical valid sample series; duplicate/derived candidate (max absolute difference 0.080 °C)
  - PMU tdie12 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie12 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained (max absolute difference 0.000 °C)
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained (max absolute difference 0.000 °C)
  - PMU tdie8 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdie8 ↔ LocationID=1414541924: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414674274: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414673764: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414543202: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414541666: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1413951810: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414554732: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414543714: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414542690: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414541922: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414554988: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414673508: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414674540: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414554220: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414542180: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414672738: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414685036: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414542178: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414542436: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414673250: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414542948: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414541668: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414673762: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414543460: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414554476: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU tdev2 ↔ LocationID=1414543458: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414542434: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414553954: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414674796: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414672994: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414673506: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414543204: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414674018: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414542946: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414542692: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)
  - PMU2 tdev3 ↔ LocationID=1414672740: highly correlated valid sample series; derived/duplicate candidate (Pearson r 1.0000)

## F. CPU candidates

- HID tiers:
- Likely:
  - PMU tdie4 [LocationID=1414542434]: 45.40 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie10 [LocationID=1414553954]: 45.09 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie7 [LocationID=1414543202]: 46.52 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie1 [LocationID=1414541666]: 45.88 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie13 [LocationID=1414554732]: 45.56 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie9 [LocationID=1414543714]: 44.93 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie5 [LocationID=1414542690]: 45.48 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev7 [LocationID=1414543204]: 42.31 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie2 [LocationID=1414541922]: 44.93 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie14 [LocationID=1414554988]: 45.32 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie6 [LocationID=1414542946]: 47.08 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie11 [LocationID=1414554220]: 45.32 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev3 [LocationID=1414542180]: 41.33 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev5 [LocationID=1414542692]: 44.70 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie3 [LocationID=1414542178]: 44.93 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev4 [LocationID=1414542436]: 44.16 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev6 [LocationID=1414542948]: 41.33 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev1 [LocationID=1414541668]: -22.10 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev8 [LocationID=1414543460]: 42.71 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie12 [LocationID=1414554476]: 45.32 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie8 [LocationID=1414543458]: 46.28 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev2 [LocationID=1414541924]: 43.99 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
- SMC evidence:
- `Te04`: 50.37 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te05`: 57.07 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te06`: 61.59 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te08`: 50.39 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te09`: 57.09 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0A`: 61.06 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0G`: 49.55 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0H`: 56.25 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0I`: 60.17 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0R`: 49.44 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0S`: 56.14 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0T`: 61.05 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0U`: 54.88 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0V`: 61.59 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0W`: 53.93 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0X`: 61.05 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp00`: 51.27 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp01`: 58.37 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp02`: 62.27 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp04`: 51.45 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp05`: 58.55 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp06`: 62.39 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp08`: 51.31 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp09`: 58.41 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0A`: 62.30 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0C`: 50.72 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0D`: 57.82 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0E`: 62.55 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0U`: 51.40 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0V`: 58.50 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0W`: 63.50 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0X`: 51.31 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0Y`: 58.41 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0Z`: 63.47 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0a`: 51.75 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0b`: 58.85 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0c`: 64.06 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0d`: 50.77 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0e`: 57.87 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0f`: 63.27 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1A`: 50.74 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1B`: 59.04 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1C`: 65.61 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1E`: 50.96 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1F`: 59.26 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1G`: 63.42 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1Q`: 50.57 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1R`: 58.87 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1S`: 65.52 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3O`: 55.94 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3P`: 63.50 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3S`: 55.45 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3T`: 65.61 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3W`: 56.24 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3X`: 64.06 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- P-core versus E-core is not inferred.

## G. GPU candidates

- HID tiers:
- Likely:
  - PMU2 tdie7 [LocationID=1414674274]: 42.45 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev5 [LocationID=1414673764]: 43.68 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie9 [LocationID=1414674796]: 42.61 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie2 [LocationID=1414672994]: 43.65 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev2 [LocationID=1414672996]: 42.92 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie4 [LocationID=1414673506]: 42.53 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie6 [LocationID=1414674018]: 42.69 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev4 [LocationID=1414673508]: 45.60 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie8 [LocationID=1414674540]: 42.53 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie1 [LocationID=1414672738]: 43.81 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie10 [LocationID=1414685036]: 42.21 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev1 [LocationID=1414672740]: -22.07 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie3 [LocationID=1414673250]: 42.61 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie5 [LocationID=1414673762]: 42.45 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev3 [LocationID=1414673252]: -22.20 °C; Product explicitly names GPU; no GPU workload correlation was performed.
- SMC evidence:
- `Tg0C`: 48.96 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0D`: 53.56 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0G`: 49.14 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0H`: 53.74 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0K`: 49.50 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0L`: 54.10 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0O`: 48.79 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0P`: 53.39 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0U`: 50.50 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0V`: 55.10 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0X`: 50.26 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0Y`: 54.86 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0d`: 50.21 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0e`: 54.81 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0j`: 50.06 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0k`: 54.66 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0m`: 49.55 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0n`: 54.15 °C; Likely GPU candidate; prefix hint only; confidence LOW.

## H. Memory candidates

- No matching Product string was observed.
- Memory/RAM junction temperature is not asserted from Product text alone; raw classification remains unknown.

## I. Storage candidates

- NAND CH0 temp [LocationID=1414410350]: raw classification unknown/unknown; independent physical placement is unproven.
- NAND/SSD temperature is not asserted from Product text alone; raw classification remains unknown.

## J. Battery comparison

- AppleSmartBattery service: available; matches: 2; properties: read
- Raw Temperature: 3400.00; raw VirtualTemperature: 3400.00
- Candidate unit confidence: HIGH; selected interpretation: macOS /100 candidate

| Field | Raw | /100 candidate °C | 0.1 K candidate °C |
|---|---:|---:|---:|
| AppleSmartBatteryPack.BatteryData.LifetimeData.AverageTemperature | 225.00 | 2.25 | -250.65 |
| AppleSmartBatteryPack.BatteryData.LifetimeData.MaximumTemperature | 40.00 | 0.40 | -269.15 |
| AppleSmartBatteryPack.BatteryData.LifetimeData.MinimumTemperature | 3.00 | 0.03 | -272.85 |
| AppleSmartBatteryPack.BatteryData.Temperature | 3400.00 | 34.00 | 66.85 |
| AppleSmartBatteryPack.BatteryData.VirtualTemperature | 3400.00 | 34.00 | 66.85 |

Temperature raw 3400 gives /100 = 34.00 °C and 0.1 K = 66.85 °C.
The first probe recorded BatteryData.Temperature raw 3329: /100 = 33.29 °C versus 0.1 K = 59.75 °C. The 59.75 °C interpretation is physically plausible as an instantaneous value, but it would not reconcile with LifetimeData.MaximumTemperature raw 40 if that lifetime field is integer °C. Because BatteryData and LifetimeData units are not guaranteed identical, this weighs against treating 0.1 K as established; it is not proof of /100.
- Lifetime metadata raw: AverageTemperature 225.00, MinimumTemperature 3.00, MaximumTemperature 40.00, TemperatureSamples 221673.00
- Assessment: Observed Temperature raw 3400 gives /100 = 34.00 °C and Smart Battery 0.1 K = 66.85 °C; both pass the broad sanity range. LifetimeData.MaximumTemperature raw 40 is not assumed to share the same unit. If it means 40 °C, /100 is internally more consistent (34.00 ≤ 40) while 0.1 K would exceed it (66.85 > 40). If the lifetime field uses another unit, this is only supporting evidence, not a unit contract. HID battery correlation supports /100: gas gauge battery (difference 0.00 °C), gas gauge battery (difference 0.20 °C), gas gauge battery (difference 1.00 °C), gas gauge battery (difference 0.00 °C), gas gauge battery (difference 0.00 °C), gas gauge battery (difference 0.00 °C).
- Same-run AppleSmartBattery sampling: 2/2 points; 4 temperature-field readings; status completed

| Field | Readings | Raw min / avg / max | /100 avg °C | 0.1 K avg °C |
|---|---:|---|---:|---:|
| Temperature | 2 | 3400.00 / 3400.00 / 3400.00 | 34.00 | 66.85 |
| VirtualTemperature | 2 | 3400.00 / 3400.00 / 3400.00 | 34.00 | 66.85 |

- HID battery comparison:
  - gas gauge battery [LocationID=1413951560]: 34.00 °C; n=2, valid=2, min=34.00, avg=34.00, max=34.00; confidence validated.
  - gas gauge battery [LocationID=1413951810]: 33.70 °C; n=2, valid=2, min=33.70, avg=33.75, max=33.80; confidence validated.
  - gas gauge battery [LocationID=1413951555]: 33.00 °C; n=2, valid=2, min=33.00, avg=33.00, max=33.00; confidence validated.
  - gas gauge battery [LocationID=1413951574]: 34.00 °C; n=2, valid=2, min=34.00, avg=34.00, max=34.00; confidence validated.
  - gas gauge battery [LocationID=1413952066]: 34.00 °C; n=2, valid=2, min=34.00, avg=34.00, max=34.00; confidence validated.
  - gas gauge battery [LocationID=1413951554]: 34.00 °C; n=2, valid=2, min=34.00, avg=34.00, max=34.00; confidence validated.

## K. AppleSMC status

- Rootless AppleSMC connection: available; enumerated keys 2265, temperature-like keys 200.

## L. Performance

- Total wall: 2287.04 ms; process CPU: 211.13 ms
- Initial HID discovery: 88.94 ms wall / 40.04 ms CPU
- First HID sample read: 43.70 ms wall / 1.43 ms CPU
- Cached HID reads: 1 samples, 47.68 ms wall total / 1.91 ms CPU total
- HID service count: 47; event read count: 94
- Discovery strategy: discover/cache once; subsequent samples read cached service references; full discovery is not repeated per sample.
- 5-second cadence assessment: 5-second diagnostic cadence is reasonable; measured probe CPU time is 105.56 ms/sample and does not approach the cadence budget.
- Sampling wall: 1150.40 ms; SMC key reads initial/sample: 2222/200

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

- HID cleanup: service array attempted/released true/true; client true/true; dlopen handle true/true.

## N. Build/tests

- Probe build: PASS for this run; runtime private-symbol availability is reported above.
- Codec/self-test and source-contract test: run separately and recorded in the task report.
- MemWatch Debug build result is reported separately; a SwiftUI macro/plugin failure is not interpreted as a thermal regression.

## O. Files changed/created

- Raw JSON: docs/generated/thermal_probe/thermal_probe_m4-test-repro_raw.json
- Markdown summary: docs/generated/thermal_probe/thermal_probe_m4-test-repro_summary.md
- Probe source: Scripts/ThermalHardwareProbe/main.swift and HIDTemperatureReader.swift

## P. Production-ready sensor matrix

| Category | Backend | Available | Confidence | Production recommendation |
|---|---|---|---|---|
| CPU/SoC | IOHID temperature service | yes | likely | diagnostic evidence exists; controlled workload correlation and semantics validation still required; controlled workload still required |
| GPU | IOHID temperature service | yes | likely | diagnostic evidence exists; controlled workload correlation and semantics validation still required; controlled workload still required |
| Battery | AppleSmartBattery + HID | yes | HIGH | raw diagnostic only until unit/correlation contract is established |
| Memory | IOHID/SMC | no proven sensor | unknown | do not label RAM/DRAM junction from this run |
| Storage | IOHID/SMC | no proven sensor | unknown | do not label NAND/SSD from this run |
| AppleSMC | AppleSMC user client | yes | low | rootless enumeration is diagnostic-only |

## Q. Remaining unknowns

- HID Product names do not prove physical placement, calibration, or derived/virtual semantics; raw service identities remain available for later correlation.
- CPU/GPU category evidence, if present, is not a controlled workload validation; P-core/E-core, RAM junction, and NAND semantics remain unknown.
- BatteryData and LifetimeData may use different units; the /100 versus 0.1 K comparison is correlation evidence only.
- Sleep/wake reference survival and the need for post-wake HID rediscovery: UNTESTED (this probe does not implement sleep/wake).

## R. Verdict

READY FOR LIMITED THERMAL ARCHITECTURE

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
