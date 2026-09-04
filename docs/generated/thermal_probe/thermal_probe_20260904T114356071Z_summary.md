# MemWatch thermal hardware validation

Read-only diagnostic evidence; generated at 2026-09-04T11:43:57Z.
Run identifier: 20260904T114356071Z

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
| LocationID=1414674274 | PMU2 tdie7 | 41.33 | gpu | likely |
| LocationID=1414542434 | PMU tdie4 | 45.16 | cpu | likely |
| LocationID=1413951560 | gas gauge battery | 33.00 | battery | validated |
| LocationID=1414553954 | PMU tdie10 | 44.45 | cpu | likely |
| LocationID=1414673764 | PMU2 tdev5 | 43.24 | gpu | likely |
| LocationID=1414674796 | PMU2 tdie9 | 42.05 | gpu | likely |
| LocationID=1414543202 | PMU tdie7 | 46.28 | cpu | likely |
| LocationID=1414541666 | PMU tdie1 | 46.60 | cpu | likely |
| LocationID=1413951810 | gas gauge battery | 33.70 | battery | validated |
| LocationID=1414554732 | PMU tdie13 | 45.32 | cpu | likely |
| LocationID=1414672994 | PMU2 tdie2 | 42.77 | gpu | likely |
| LocationID=1414543714 | PMU tdie9 | 44.77 | cpu | likely |
| LocationID=1414542690 | PMU tdie5 | 45.72 | cpu | likely |
| LocationID=1414672996 | PMU2 tdev2 | 42.08 | gpu | likely |
| LocationID=1414673506 | PMU2 tdie4 | 42.13 | gpu | likely |
| LocationID=1414543204 | PMU tdev7 | 41.91 | cpu | likely |
| LocationID=1414674018 | PMU2 tdie6 | 41.57 | gpu | likely |
| LocationID=1414541922 | PMU tdie2 | 45.09 | cpu | likely |
| LocationID=1414554988 | PMU tdie14 | 45.32 | cpu | likely |
| LocationID=1414410350 | NAND CH0 temp | 41.00 | unknown | unknown |
| LocationID=1413951555 | gas gauge battery | 33.00 | battery | validated |
| LocationID=1414673508 | PMU2 tdev4 | 44.62 | gpu | likely |
| LocationID=0 | als-temp | — | unknown | unknown |
| LocationID=1414674540 | PMU2 tdie8 | 42.45 | gpu | likely |
| LocationID=1414542946 | PMU tdie6 | 47.96 | cpu | likely |
| LocationID=1414541402 | PMU tcal | 51.82 | unknown | unknown |
| LocationID=1413951574 | gas gauge battery | 33.90 | battery | validated |
| LocationID=1414554220 | PMU tdie11 | 45.32 | cpu | likely |
| LocationID=1414542180 | PMU tdev3 | 41.01 | cpu | likely |
| LocationID=1414672738 | PMU2 tdie1 | 43.49 | gpu | likely |
| LocationID=1414542692 | PMU tdev5 | 44.16 | cpu | likely |
| LocationID=1414685036 | PMU2 tdie10 | 41.73 | gpu | likely |
| LocationID=1414542178 | PMU tdie3 | 44.69 | cpu | likely |
| LocationID=1414672740 | PMU2 tdev1 | -22.09 | gpu | likely |
| LocationID=1413952066 | gas gauge battery | 33.90 | battery | validated |
| LocationID=1414542436 | PMU tdev4 | 43.59 | cpu | likely |
| LocationID=1414673250 | PMU2 tdie3 | 42.29 | gpu | likely |
| LocationID=1414542948 | PMU tdev6 | 41.25 | cpu | likely |
| LocationID=1414541668 | PMU tdev1 | -22.02 | cpu | likely |
| LocationID=1414673762 | PMU2 tdie5 | 41.57 | gpu | likely |
| LocationID=1414543460 | PMU tdev8 | 42.12 | cpu | likely |
| LocationID=1414672474 | PMU2 tcal | 51.82 | unknown | unknown |
| LocationID=1414554476 | PMU tdie12 | 45.32 | cpu | likely |
| LocationID=1413951554 | gas gauge battery | 33.90 | battery | validated |
| LocationID=1414543458 | PMU tdie8 | 46.52 | cpu | likely |
| LocationID=1414541924 | PMU tdev2 | 43.64 | cpu | likely |
| LocationID=1414673252 | PMU2 tdev3 | -22.22 | gpu | likely |

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

- Requested: 1 sample(s) × 5.00 seconds; completed: 1
- Status: completed; workload generated: false

| Product | Samples | Valid | Min | Avg | Max | Delta | Std dev |
|---|---:|---:|---:|---:|---:|---:|---:|
| PMU2 tdie7 | 1 | 1 | 41.33 | 41.33 | 41.33 | 0.00 | 0.00 |
| PMU tdie4 | 1 | 1 | 45.16 | 45.16 | 45.16 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.00 | 33.00 | 33.00 | 0.00 | 0.00 |
| PMU tdie10 | 1 | 1 | 44.45 | 44.45 | 44.45 | 0.00 | 0.00 |
| PMU2 tdev5 | 1 | 1 | 43.24 | 43.24 | 43.24 | 0.00 | 0.00 |
| PMU2 tdie9 | 1 | 1 | 42.05 | 42.05 | 42.05 | 0.00 | 0.00 |
| PMU tdie7 | 1 | 1 | 46.28 | 46.28 | 46.28 | 0.00 | 0.00 |
| PMU tdie1 | 1 | 1 | 46.60 | 46.60 | 46.60 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.70 | 33.70 | 33.70 | 0.00 | 0.00 |
| PMU tdie13 | 1 | 1 | 45.32 | 45.32 | 45.32 | 0.00 | 0.00 |
| PMU2 tdie2 | 1 | 1 | 42.77 | 42.77 | 42.77 | 0.00 | 0.00 |
| PMU tdie9 | 1 | 1 | 44.77 | 44.77 | 44.77 | 0.00 | 0.00 |
| PMU tdie5 | 1 | 1 | 45.72 | 45.72 | 45.72 | 0.00 | 0.00 |
| PMU2 tdev2 | 1 | 1 | 42.08 | 42.08 | 42.08 | 0.00 | 0.00 |
| PMU2 tdie4 | 1 | 1 | 42.13 | 42.13 | 42.13 | 0.00 | 0.00 |
| PMU tdev7 | 1 | 1 | 41.91 | 41.91 | 41.91 | 0.00 | 0.00 |
| PMU2 tdie6 | 1 | 1 | 41.57 | 41.57 | 41.57 | 0.00 | 0.00 |
| PMU tdie2 | 1 | 1 | 45.09 | 45.09 | 45.09 | 0.00 | 0.00 |
| PMU tdie14 | 1 | 1 | 45.32 | 45.32 | 45.32 | 0.00 | 0.00 |
| NAND CH0 temp | 1 | 1 | 41.00 | 41.00 | 41.00 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.00 | 33.00 | 33.00 | 0.00 | 0.00 |
| PMU2 tdev4 | 1 | 1 | 44.62 | 44.62 | 44.62 | 0.00 | 0.00 |
| als-temp | 1 | 0 | — | — | — | — | — |
| PMU2 tdie8 | 1 | 1 | 42.45 | 42.45 | 42.45 | 0.00 | 0.00 |
| PMU tdie6 | 1 | 1 | 47.96 | 47.96 | 47.96 | 0.00 | 0.00 |
| PMU tcal | 1 | 1 | 51.82 | 51.82 | 51.82 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.90 | 33.90 | 33.90 | 0.00 | 0.00 |
| PMU tdie11 | 1 | 1 | 45.32 | 45.32 | 45.32 | 0.00 | 0.00 |
| PMU tdev3 | 1 | 1 | 41.01 | 41.01 | 41.01 | 0.00 | 0.00 |
| PMU2 tdie1 | 1 | 1 | 43.49 | 43.49 | 43.49 | 0.00 | 0.00 |
| PMU tdev5 | 1 | 1 | 44.16 | 44.16 | 44.16 | 0.00 | 0.00 |
| PMU2 tdie10 | 1 | 1 | 41.73 | 41.73 | 41.73 | 0.00 | 0.00 |
| PMU tdie3 | 1 | 1 | 44.69 | 44.69 | 44.69 | 0.00 | 0.00 |
| PMU2 tdev1 | 1 | 1 | -22.09 | -22.09 | -22.09 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.90 | 33.90 | 33.90 | 0.00 | 0.00 |
| PMU tdev4 | 1 | 1 | 43.59 | 43.59 | 43.59 | 0.00 | 0.00 |
| PMU2 tdie3 | 1 | 1 | 42.29 | 42.29 | 42.29 | 0.00 | 0.00 |
| PMU tdev6 | 1 | 1 | 41.25 | 41.25 | 41.25 | 0.00 | 0.00 |
| PMU tdev1 | 1 | 1 | -22.02 | -22.02 | -22.02 | 0.00 | 0.00 |
| PMU2 tdie5 | 1 | 1 | 41.57 | 41.57 | 41.57 | 0.00 | 0.00 |
| PMU tdev8 | 1 | 1 | 42.12 | 42.12 | 42.12 | 0.00 | 0.00 |
| PMU2 tcal | 1 | 1 | 51.82 | 51.82 | 51.82 | 0.00 | 0.00 |
| PMU tdie12 | 1 | 1 | 45.32 | 45.32 | 45.32 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.90 | 33.90 | 33.90 | 0.00 | 0.00 |
| PMU tdie8 | 1 | 1 | 46.52 | 46.52 | 46.52 | 0.00 | 0.00 |
| PMU tdev2 | 1 | 1 | 43.64 | 43.64 | 43.64 | 0.00 | 0.00 |
| PMU2 tdev3 | 1 | 1 | -22.22 | -22.22 | -22.22 | 0.00 | 0.00 |

- HID events: 47; successful event copies: 46; failed event copies: 1
- Duplicate/derived candidates:
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951554: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951560: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951810: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951555: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413951574: same Product string; raw services retained
  - gas gauge battery ↔ LocationID=1413952066: same Product string; raw services retained

## F. CPU candidates

- HID tiers:
- Likely:
  - PMU tdie4 [LocationID=1414542434]: 45.16 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie10 [LocationID=1414553954]: 44.45 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie7 [LocationID=1414543202]: 46.28 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie1 [LocationID=1414541666]: 46.60 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie13 [LocationID=1414554732]: 45.32 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie9 [LocationID=1414543714]: 44.77 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie5 [LocationID=1414542690]: 45.72 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev7 [LocationID=1414543204]: 41.91 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie2 [LocationID=1414541922]: 45.09 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie14 [LocationID=1414554988]: 45.32 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie6 [LocationID=1414542946]: 47.96 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie11 [LocationID=1414554220]: 45.32 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev3 [LocationID=1414542180]: 41.01 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev5 [LocationID=1414542692]: 44.16 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie3 [LocationID=1414542178]: 44.69 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev4 [LocationID=1414542436]: 43.59 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev6 [LocationID=1414542948]: 41.25 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev1 [LocationID=1414541668]: -22.02 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev8 [LocationID=1414543460]: 42.12 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie12 [LocationID=1414554476]: 45.32 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie8 [LocationID=1414543458]: 46.52 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev2 [LocationID=1414541924]: 43.64 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
- SMC evidence:
- `Te04`: 49.85 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te05`: 56.55 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te06`: 61.11 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te08`: 49.67 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te09`: 56.37 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0A`: 61.30 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0G`: 49.09 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0H`: 55.79 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0I`: 60.17 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0R`: 48.85 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0S`: 55.55 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0T`: 60.56 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0U`: 54.34 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0V`: 61.30 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0W`: 53.34 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Te0X`: 60.56 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp00`: 50.90 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp01`: 58.00 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp02`: 62.59 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp04`: 50.84 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp05`: 57.94 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp06`: 61.67 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp08`: 50.90 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp09`: 58.00 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0A`: 62.64 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0C`: 50.23 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0D`: 57.33 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0E`: 62.06 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0U`: 51.12 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0V`: 58.22 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0W`: 63.36 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0X`: 50.72 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0Y`: 57.82 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0Z`: 63.23 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0a`: 51.35 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0b`: 58.45 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0c`: 64.06 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0d`: 50.21 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0e`: 57.31 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp0f`: 63.27 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1A`: 50.47 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1B`: 58.77 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1C`: 65.38 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1E`: 50.56 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1F`: 58.86 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1G`: 63.19 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1Q`: 50.07 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1R`: 58.37 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp1S`: 65.05 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3O`: 55.60 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3P`: 63.36 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3S`: 55.05 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3T`: 65.38 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3W`: 55.83 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- `Tp3X`: 63.58 °C; Likely CPU/SoC candidate; prefix hint only; confidence LOW.
- P-core versus E-core is not inferred.

## G. GPU candidates

- HID tiers:
- Likely:
  - PMU2 tdie7 [LocationID=1414674274]: 41.33 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev5 [LocationID=1414673764]: 43.24 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie9 [LocationID=1414674796]: 42.05 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie2 [LocationID=1414672994]: 42.77 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev2 [LocationID=1414672996]: 42.08 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie4 [LocationID=1414673506]: 42.13 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie6 [LocationID=1414674018]: 41.57 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev4 [LocationID=1414673508]: 44.62 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie8 [LocationID=1414674540]: 42.45 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie1 [LocationID=1414672738]: 43.49 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie10 [LocationID=1414685036]: 41.73 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev1 [LocationID=1414672740]: -22.09 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie3 [LocationID=1414673250]: 42.29 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie5 [LocationID=1414673762]: 41.57 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev3 [LocationID=1414673252]: -22.22 °C; Product explicitly names GPU; no GPU workload correlation was performed.
- SMC evidence:
- `Tg0C`: 48.73 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0D`: 53.33 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0G`: 48.87 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0H`: 53.47 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0K`: 49.39 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0L`: 53.99 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0O`: 48.58 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0P`: 53.18 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0U`: 50.26 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0V`: 54.86 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0X`: 50.05 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0Y`: 54.65 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0d`: 50.04 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0e`: 54.64 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0j`: 49.89 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0k`: 54.49 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0m`: 49.41 °C; Likely GPU candidate; prefix hint only; confidence LOW.
- `Tg0n`: 54.01 °C; Likely GPU candidate; prefix hint only; confidence LOW.

## H. Memory candidates

- No matching Product string was observed.
- Memory/RAM junction temperature is not asserted from Product text alone; raw classification remains unknown.

## I. Storage candidates

- NAND CH0 temp [LocationID=1414410350]: raw classification unknown/unknown; independent physical placement is unproven.
- NAND/SSD temperature is not asserted from Product text alone; raw classification remains unknown.

## J. Battery comparison

- AppleSmartBattery service: available; matches: 2; properties: read
- Raw Temperature: 3389.00; raw VirtualTemperature: 3389.00
- Candidate unit confidence: HIGH; selected interpretation: macOS /100 candidate

| Field | Raw | /100 candidate °C | 0.1 K candidate °C |
|---|---:|---:|---:|
| AppleSmartBatteryPack.BatteryData.LifetimeData.AverageTemperature | 225.00 | 2.25 | -250.65 |
| AppleSmartBatteryPack.BatteryData.LifetimeData.MaximumTemperature | 40.00 | 0.40 | -269.15 |
| AppleSmartBatteryPack.BatteryData.LifetimeData.MinimumTemperature | 3.00 | 0.03 | -272.85 |
| AppleSmartBatteryPack.BatteryData.Temperature | 3389.00 | 33.89 | 65.75 |
| AppleSmartBatteryPack.BatteryData.VirtualTemperature | 3389.00 | 33.89 | 65.75 |

Temperature raw 3389 gives /100 = 33.89 °C and 0.1 K = 65.75 °C.
The first probe recorded BatteryData.Temperature raw 3329: /100 = 33.29 °C versus 0.1 K = 59.75 °C. The 59.75 °C interpretation is physically plausible as an instantaneous value, but it would not reconcile with LifetimeData.MaximumTemperature raw 40 if that lifetime field is integer °C. Because BatteryData and LifetimeData units are not guaranteed identical, this weighs against treating 0.1 K as established; it is not proof of /100.
- Lifetime metadata raw: AverageTemperature 225.00, MinimumTemperature 3.00, MaximumTemperature 40.00, TemperatureSamples 221673.00
- Assessment: Observed Temperature raw 3389 gives /100 = 33.89 °C and Smart Battery 0.1 K = 65.75 °C; both pass the broad sanity range. LifetimeData.MaximumTemperature raw 40 is not assumed to share the same unit. If it means 40 °C, /100 is internally more consistent (33.89 ≤ 40) while 0.1 K would exceed it (65.75 > 40). If the lifetime field uses another unit, this is only supporting evidence, not a unit contract. HID battery correlation supports /100: gas gauge battery (difference 0.89 °C), gas gauge battery (difference 0.19 °C), gas gauge battery (difference 0.89 °C), gas gauge battery (difference 0.01 °C), gas gauge battery (difference 0.01 °C), gas gauge battery (difference 0.01 °C).
- Same-run AppleSmartBattery sampling: 1/1 points; 2 temperature-field readings; status completed

| Field | Readings | Raw min / avg / max | /100 avg °C | 0.1 K avg °C |
|---|---:|---|---:|---:|
| Temperature | 1 | 3389.00 / 3389.00 / 3389.00 | 33.89 | 65.75 |
| VirtualTemperature | 1 | 3389.00 / 3389.00 / 3389.00 | 33.89 | 65.75 |

- HID battery comparison:
  - gas gauge battery [LocationID=1413951560]: 33.00 °C; n=1, valid=1, min=33.00, avg=33.00, max=33.00; confidence validated.
  - gas gauge battery [LocationID=1413951810]: 33.70 °C; n=1, valid=1, min=33.70, avg=33.70, max=33.70; confidence validated.
  - gas gauge battery [LocationID=1413951555]: 33.00 °C; n=1, valid=1, min=33.00, avg=33.00, max=33.00; confidence validated.
  - gas gauge battery [LocationID=1413951574]: 33.90 °C; n=1, valid=1, min=33.90, avg=33.90, max=33.90; confidence validated.
  - gas gauge battery [LocationID=1413952066]: 33.90 °C; n=1, valid=1, min=33.90, avg=33.90, max=33.90; confidence validated.
  - gas gauge battery [LocationID=1413951554]: 33.90 °C; n=1, valid=1, min=33.90, avg=33.90, max=33.90; confidence validated.

## K. AppleSMC status

- Rootless AppleSMC connection: available; enumerated keys 2265, temperature-like keys 200.

## L. Performance

- Total wall: 1377.55 ms; process CPU: 227.52 ms
- Initial HID discovery: 90.19 ms wall / 40.80 ms CPU
- First HID sample read: 44.77 ms wall / 1.51 ms CPU
- Cached HID reads: 0 samples, 0.00 ms wall total / — ms CPU total
- HID service count: 47; event read count: 47
- Discovery strategy: discover/cache once; subsequent samples read cached service references; full discovery is not repeated per sample.
- 5-second cadence assessment: 5-second diagnostic cadence is reasonable; measured probe CPU time is 227.52 ms/sample and does not approach the cadence budget.
- Sampling wall: 45.95 ms; SMC key reads initial/sample: 2222/0

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

- Raw JSON: docs/generated/thermal_probe/thermal_probe_20260904T114356071Z_raw.json
- Markdown summary: docs/generated/thermal_probe/thermal_probe_20260904T114356071Z_summary.md
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
