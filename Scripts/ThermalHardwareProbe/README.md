# ThermalHardwareProbe

MemWatch için izole, manuel çalıştırılan AppleSMC/IOHID/AppleSmartBattery
donanım kanıtı probe'udur. MemWatch production target'ına bağlı değildir; UI,
`MonitoringCollector`, `MonitoringService` ve polling davranışını değiştirmez.

## Çalıştırma

Repo kökünden:

```sh
Scripts/ThermalHardwareProbe/run.sh
Scripts/ThermalHardwareProbe/run.sh --backend all --samples 12 --interval 5 --run-id m4-12x5
Scripts/ThermalHardwareProbe/run.sh --backend hid --samples 24 --interval 5 --run-id manual-workload
Scripts/ThermalHardwareProbe/run.sh --backend battery --samples 1
Scripts/ThermalHardwareProbe/run.sh --self-test
```

`--backend` seçenekleri `smc`, `hid`, `battery` ve `all` değerleridir; varsayılan
`all`'dır. HID discovery bir kez yapılır, sonraki örneklerde cache'lenmiş
service referanslarından event okunur. `--run-id` verildiğinde her çalıştırma
ayrı JSON ve Markdown dosyası üretir; verilmezse UTC timestamp kullanılır.

Çıktı dosyaları:

- `docs/generated/thermal_probe/thermal_probe_<run-id>_summary.md`
- `docs/generated/thermal_probe/thermal_probe_<run-id>_raw.json`

HID backend, `IOHIDEventSystemClient*`, `IOHIDServiceClient*` ve
`IOHIDEventGetFloatValue` private sembollerini `dlopen`/`dlsym` ile runtime'da
çözer. Matching değerleri ve temperature event field değeri kaynak referansları
JSON/Markdown raporunda belirtilir; sembol eksikliği crash yerine
`unavailable` sonucudur. `IOHIDEventSystemClientSetMatching` void ABI'si
nedeniyle raporlanan matching sonucu numeric return code değil, çağrının
yapıldığını belirten metadata'dır.

Probe workload üretmez, `powermetrics` çalıştırmaz, `sudo`/root istemez,
AppleSMC'ye mutation komutu göndermez, fan veya power limit kontrol etmez ve
privileged helper kullanmaz. HID tarafında yalnızca service enumeration,
property copy ve temperature event copy yapılır. `AppleSMC` connection ve HID
CF/IOKit referansları kapanışta bırakılır. Sensor anlamları Product/key
prefix'lerinden kesinleştirilmez; raw properties, event status ve type metadata
JSON'da korunur.
