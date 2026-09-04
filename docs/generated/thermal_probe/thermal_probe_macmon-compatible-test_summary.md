# MemWatch thermal hardware validation

Read-only diagnostic evidence; generated at 2026-09-04T11:50:11Z.
Run identifier: macmon-compatible-test

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
- Matching: PrimaryUsagePage 0xFF00; PrimaryUsage 0x0005; call result macmon-compatible Int32 API; returned 56030784; status completed
- Provenance: Apple IOHIDFamily/Chromium declares Apple vendor page 0xFF00, temperature usage 0x0005, event type 15, and event field base type << 16. The probe records these constants and resolves private symbols at runtime.
- Compared implementations: Stats, SwiftTempBar, lude-vitals, and redline use this diagnostic path; their repositories are MIT. iSMC is GPL-3.0 and was reference-only; no GPL code was copied.

## C. HID temperature services

| ID | Product | Current °C | Candidate category | Confidence |
|---|---|---:|---|---|
| LocationID=1414674274 | PMU2 tdie7 | 42.13 | gpu | likely |
| LocationID=1414542434 | PMU tdie4 | 45.48 | cpu | likely |
| LocationID=1413951560 | gas gauge battery | 34.00 | battery | likely |
| LocationID=1414553954 | PMU tdie10 | 45.56 | cpu | likely |
| LocationID=1414673764 | PMU2 tdev5 | 44.16 | gpu | likely |
| LocationID=1414674796 | PMU2 tdie9 | 42.37 | gpu | likely |
| LocationID=1414543202 | PMU tdie7 | 46.92 | cpu | likely |
| LocationID=1414541666 | PMU tdie1 | 46.68 | cpu | likely |
| LocationID=1413951810 | gas gauge battery | 33.90 | battery | likely |
| LocationID=1414554732 | PMU tdie13 | 45.80 | cpu | likely |
| LocationID=1414672994 | PMU2 tdie2 | 43.41 | gpu | likely |
| LocationID=1414543714 | PMU tdie9 | 45.48 | cpu | likely |
| LocationID=1414542690 | PMU tdie5 | 46.44 | cpu | likely |
| LocationID=1414672996 | PMU2 tdev2 | 43.06 | gpu | likely |
| LocationID=1414673506 | PMU2 tdie4 | 42.77 | gpu | likely |
| LocationID=1414543204 | PMU tdev7 | 42.39 | cpu | likely |
| LocationID=1414674018 | PMU2 tdie6 | 42.69 | gpu | likely |
| LocationID=1414541922 | PMU tdie2 | 46.20 | cpu | likely |
| LocationID=1414554988 | PMU tdie14 | 46.04 | cpu | likely |
| LocationID=1414410350 | NAND CH0 temp | 42.00 | unknown | unknown |
| LocationID=1413951555 | gas gauge battery | 33.00 | battery | likely |
| LocationID=1414673508 | PMU2 tdev4 | 45.89 | gpu | likely |
| LocationID=0 | als-temp | — | unknown | unknown |
| LocationID=1414674540 | PMU2 tdie8 | 43.41 | gpu | likely |
| LocationID=1414542946 | PMU tdie6 | 48.20 | cpu | likely |
| LocationID=1414541402 | PMU tcal | 51.82 | unknown | unknown |
| LocationID=1413951574 | gas gauge battery | 34.10 | battery | likely |
| LocationID=1414554220 | PMU tdie11 | 45.72 | cpu | likely |
| LocationID=1414542180 | PMU tdev3 | 41.33 | cpu | likely |
| LocationID=1414672738 | PMU2 tdie1 | 44.45 | gpu | likely |
| LocationID=1414542692 | PMU tdev5 | 44.66 | cpu | likely |
| LocationID=1414685036 | PMU2 tdie10 | 42.53 | gpu | likely |
| LocationID=1414542178 | PMU tdie3 | 46.04 | cpu | likely |
| LocationID=1414672740 | PMU2 tdev1 | -21.97 | gpu | likely |
| LocationID=1413952066 | gas gauge battery | 34.10 | battery | likely |
| LocationID=1414542436 | PMU tdev4 | 44.03 | cpu | likely |
| LocationID=1414673250 | PMU2 tdie3 | 43.41 | gpu | likely |
| LocationID=1414542948 | PMU tdev6 | 41.46 | cpu | likely |
| LocationID=1414541668 | PMU tdev1 | -22.24 | cpu | likely |
| LocationID=1414673762 | PMU2 tdie5 | 42.21 | gpu | likely |
| LocationID=1414543460 | PMU tdev8 | 42.66 | cpu | likely |
| LocationID=1414672474 | PMU2 tcal | 51.82 | unknown | unknown |
| LocationID=1414554476 | PMU tdie12 | 45.56 | cpu | likely |
| LocationID=1413951554 | gas gauge battery | 34.10 | battery | likely |
| LocationID=1414543458 | PMU tdie8 | 48.52 | cpu | likely |
| LocationID=1414541924 | PMU tdev2 | 44.03 | cpu | likely |
| LocationID=1414673252 | PMU2 tdev3 | -22.21 | gpu | likely |

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
| PMU2 tdie7 | 1 | 1 | 42.13 | 42.13 | 42.13 | 0.00 | 0.00 |
| PMU tdie4 | 1 | 1 | 45.48 | 45.48 | 45.48 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 34.00 | 34.00 | 34.00 | 0.00 | 0.00 |
| PMU tdie10 | 1 | 1 | 45.56 | 45.56 | 45.56 | 0.00 | 0.00 |
| PMU2 tdev5 | 1 | 1 | 44.16 | 44.16 | 44.16 | 0.00 | 0.00 |
| PMU2 tdie9 | 1 | 1 | 42.37 | 42.37 | 42.37 | 0.00 | 0.00 |
| PMU tdie7 | 1 | 1 | 46.92 | 46.92 | 46.92 | 0.00 | 0.00 |
| PMU tdie1 | 1 | 1 | 46.68 | 46.68 | 46.68 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.90 | 33.90 | 33.90 | 0.00 | 0.00 |
| PMU tdie13 | 1 | 1 | 45.80 | 45.80 | 45.80 | 0.00 | 0.00 |
| PMU2 tdie2 | 1 | 1 | 43.41 | 43.41 | 43.41 | 0.00 | 0.00 |
| PMU tdie9 | 1 | 1 | 45.48 | 45.48 | 45.48 | 0.00 | 0.00 |
| PMU tdie5 | 1 | 1 | 46.44 | 46.44 | 46.44 | 0.00 | 0.00 |
| PMU2 tdev2 | 1 | 1 | 43.06 | 43.06 | 43.06 | 0.00 | 0.00 |
| PMU2 tdie4 | 1 | 1 | 42.77 | 42.77 | 42.77 | 0.00 | 0.00 |
| PMU tdev7 | 1 | 1 | 42.39 | 42.39 | 42.39 | 0.00 | 0.00 |
| PMU2 tdie6 | 1 | 1 | 42.69 | 42.69 | 42.69 | 0.00 | 0.00 |
| PMU tdie2 | 1 | 1 | 46.20 | 46.20 | 46.20 | 0.00 | 0.00 |
| PMU tdie14 | 1 | 1 | 46.04 | 46.04 | 46.04 | 0.00 | 0.00 |
| NAND CH0 temp | 1 | 1 | 42.00 | 42.00 | 42.00 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 33.00 | 33.00 | 33.00 | 0.00 | 0.00 |
| PMU2 tdev4 | 1 | 1 | 45.89 | 45.89 | 45.89 | 0.00 | 0.00 |
| als-temp | 1 | 0 | — | — | — | — | — |
| PMU2 tdie8 | 1 | 1 | 43.41 | 43.41 | 43.41 | 0.00 | 0.00 |
| PMU tdie6 | 1 | 1 | 48.20 | 48.20 | 48.20 | 0.00 | 0.00 |
| PMU tcal | 1 | 1 | 51.82 | 51.82 | 51.82 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 34.10 | 34.10 | 34.10 | 0.00 | 0.00 |
| PMU tdie11 | 1 | 1 | 45.72 | 45.72 | 45.72 | 0.00 | 0.00 |
| PMU tdev3 | 1 | 1 | 41.33 | 41.33 | 41.33 | 0.00 | 0.00 |
| PMU2 tdie1 | 1 | 1 | 44.45 | 44.45 | 44.45 | 0.00 | 0.00 |
| PMU tdev5 | 1 | 1 | 44.66 | 44.66 | 44.66 | 0.00 | 0.00 |
| PMU2 tdie10 | 1 | 1 | 42.53 | 42.53 | 42.53 | 0.00 | 0.00 |
| PMU tdie3 | 1 | 1 | 46.04 | 46.04 | 46.04 | 0.00 | 0.00 |
| PMU2 tdev1 | 1 | 1 | -21.97 | -21.97 | -21.97 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 34.10 | 34.10 | 34.10 | 0.00 | 0.00 |
| PMU tdev4 | 1 | 1 | 44.03 | 44.03 | 44.03 | 0.00 | 0.00 |
| PMU2 tdie3 | 1 | 1 | 43.41 | 43.41 | 43.41 | 0.00 | 0.00 |
| PMU tdev6 | 1 | 1 | 41.46 | 41.46 | 41.46 | 0.00 | 0.00 |
| PMU tdev1 | 1 | 1 | -22.24 | -22.24 | -22.24 | 0.00 | 0.00 |
| PMU2 tdie5 | 1 | 1 | 42.21 | 42.21 | 42.21 | 0.00 | 0.00 |
| PMU tdev8 | 1 | 1 | 42.66 | 42.66 | 42.66 | 0.00 | 0.00 |
| PMU2 tcal | 1 | 1 | 51.82 | 51.82 | 51.82 | 0.00 | 0.00 |
| PMU tdie12 | 1 | 1 | 45.56 | 45.56 | 45.56 | 0.00 | 0.00 |
| gas gauge battery | 1 | 1 | 34.10 | 34.10 | 34.10 | 0.00 | 0.00 |
| PMU tdie8 | 1 | 1 | 48.52 | 48.52 | 48.52 | 0.00 | 0.00 |
| PMU tdev2 | 1 | 1 | 44.03 | 44.03 | 44.03 | 0.00 | 0.00 |
| PMU2 tdev3 | 1 | 1 | -22.21 | -22.21 | -22.21 | 0.00 | 0.00 |

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
  - PMU tdie4 [LocationID=1414542434]: 45.48 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie10 [LocationID=1414553954]: 45.56 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie7 [LocationID=1414543202]: 46.92 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie1 [LocationID=1414541666]: 46.68 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie13 [LocationID=1414554732]: 45.80 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie9 [LocationID=1414543714]: 45.48 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie5 [LocationID=1414542690]: 46.44 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev7 [LocationID=1414543204]: 42.39 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie2 [LocationID=1414541922]: 46.20 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie14 [LocationID=1414554988]: 46.04 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie6 [LocationID=1414542946]: 48.20 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie11 [LocationID=1414554220]: 45.72 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev3 [LocationID=1414542180]: 41.33 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev5 [LocationID=1414542692]: 44.66 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie3 [LocationID=1414542178]: 46.04 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev4 [LocationID=1414542436]: 44.03 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev6 [LocationID=1414542948]: 41.46 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev1 [LocationID=1414541668]: -22.24 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev8 [LocationID=1414543460]: 42.66 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie12 [LocationID=1414554476]: 45.56 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdie8 [LocationID=1414543458]: 48.52 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
  - PMU tdev2 [LocationID=1414541924]: 44.03 °C; Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted.
- SMC evidence:
No validated CPU/SoC sensor evidence.
- P-core versus E-core is not inferred.

## G. GPU candidates

- HID tiers:
- Likely:
  - PMU2 tdie7 [LocationID=1414674274]: 42.13 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev5 [LocationID=1414673764]: 44.16 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie9 [LocationID=1414674796]: 42.37 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie2 [LocationID=1414672994]: 43.41 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev2 [LocationID=1414672996]: 43.06 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie4 [LocationID=1414673506]: 42.77 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie6 [LocationID=1414674018]: 42.69 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev4 [LocationID=1414673508]: 45.89 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie8 [LocationID=1414674540]: 43.41 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie1 [LocationID=1414672738]: 44.45 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie10 [LocationID=1414685036]: 42.53 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev1 [LocationID=1414672740]: -21.97 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie3 [LocationID=1414673250]: 43.41 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdie5 [LocationID=1414673762]: 42.21 °C; Product explicitly names GPU; no GPU workload correlation was performed.
  - PMU2 tdev3 [LocationID=1414673252]: -22.21 °C; Product explicitly names GPU; no GPU workload correlation was performed.
- SMC evidence:
No validated GPU sensor evidence.

## H. Memory candidates

- No matching Product string was observed.
- Memory/RAM junction temperature is not asserted from Product text alone; raw classification remains unknown.

## I. Storage candidates

- NAND CH0 temp [LocationID=1414410350]: raw classification unknown/unknown; independent physical placement is unproven.
- NAND/SSD temperature is not asserted from Product text alone; raw classification remains unknown.

## J. Battery comparison

- AppleSmartBattery service: unavailable; matches: 0; properties: read failed
- Raw Temperature: —; raw VirtualTemperature: —
- Candidate unit confidence: LOW; selected interpretation: UNVERIFIED

| Field | Raw | /100 candidate °C | 0.1 K candidate °C |
|---|---:|---:|---:|
| — | — | — | — |

The first probe recorded BatteryData.Temperature raw 3329: /100 = 33.29 °C versus 0.1 K = 59.75 °C. The 59.75 °C interpretation is physically plausible as an instantaneous value, but it would not reconcile with LifetimeData.MaximumTemperature raw 40 if that lifetime field is integer °C. Because BatteryData and LifetimeData units are not guaranteed identical, this weighs against treating 0.1 K as established; it is not proof of /100.
- Lifetime metadata raw: AverageTemperature —, MinimumTemperature —, MaximumTemperature —, TemperatureSamples —
- Assessment: No AppleSmartBattery temperature metadata was available.
- HID battery comparison:
  - gas gauge battery [LocationID=1413951560]: 34.00 °C; n=1, valid=1, min=34.00, avg=34.00, max=34.00; confidence likely.
  - gas gauge battery [LocationID=1413951810]: 33.90 °C; n=1, valid=1, min=33.90, avg=33.90, max=33.90; confidence likely.
  - gas gauge battery [LocationID=1413951555]: 33.00 °C; n=1, valid=1, min=33.00, avg=33.00, max=33.00; confidence likely.
  - gas gauge battery [LocationID=1413951574]: 34.10 °C; n=1, valid=1, min=34.10, avg=34.10, max=34.10; confidence likely.
  - gas gauge battery [LocationID=1413952066]: 34.10 °C; n=1, valid=1, min=34.10, avg=34.10, max=34.10; confidence likely.
  - gas gauge battery [LocationID=1413951554]: 34.10 °C; n=1, valid=1, min=34.10, avg=34.10, max=34.10; confidence likely.

## K. AppleSMC status

- Rootless AppleSMC: unavailable; AppleSMC not requested by selected backend
- This preserves the first probe conclusion: rootless SMC enumeration is unavailable unless new evidence says otherwise.

## L. Performance

- Total wall: 828.49 ms; process CPU: 66.12 ms
- Initial HID discovery: 106.76 ms wall / 50.16 ms CPU
- First HID sample read: 45.19 ms wall / 3.43 ms CPU
- Cached HID reads: 0 samples, 0.00 ms wall total / — ms CPU total
- HID service count: 47; event read count: 47
- Discovery strategy: macmon-compatible: exact CFDictionaryCreate and Int32 SetMatching declaration; full discovery is not repeated per sample.
- 5-second cadence assessment: 5-second diagnostic cadence is reasonable; measured probe CPU time is 66.12 ms/sample and does not approach the cadence budget.
- Sampling wall: 45.25 ms; SMC key reads initial/sample: 0/0

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

- Raw JSON: docs/generated/thermal_probe/thermal_probe_macmon-compatible-test_raw.json
- Markdown summary: docs/generated/thermal_probe/thermal_probe_macmon-compatible-test_summary.md
- Probe source: Scripts/ThermalHardwareProbe/main.swift and HIDTemperatureReader.swift

## P. Production-ready sensor matrix

| Category | Backend | Available | Confidence | Production recommendation |
|---|---|---|---|---|
| CPU/SoC | IOHID temperature service | yes | likely | diagnostic evidence exists; controlled workload correlation and semantics validation still required; controlled workload still required |
| GPU | IOHID temperature service | yes | likely | diagnostic evidence exists; controlled workload correlation and semantics validation still required; controlled workload still required |
| Battery | AppleSmartBattery + HID | no | LOW | raw diagnostic only until unit/correlation contract is established |
| Memory | IOHID/SMC | no proven sensor | unknown | do not label RAM/DRAM junction from this run |
| Storage | IOHID/SMC | no proven sensor | unknown | do not label NAND/SSD from this run |
| AppleSMC | AppleSMC user client | no | unavailable | rootless enumeration is unavailable |

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
