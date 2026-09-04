# ThermalHardwareProbe

MemWatch için izole, manuel çalıştırılan AppleSMC/AppleSmartBattery donanım
kanıtı probe'udur. MemWatch production target'ına bağlı değildir; UI,
`MonitoringCollector`, `MonitoringService` ve polling davranışını değiştirmez.

## Çalıştırma

Repo kökünden:

```sh
Scripts/ThermalHardwareProbe/run.sh
Scripts/ThermalHardwareProbe/run.sh --samples 12 --interval 5
Scripts/ThermalHardwareProbe/run.sh --self-test
```

Varsayılan çıktılar:

- `docs/generated/thermal_probe/thermal_probe_summary.md`
- `docs/generated/thermal_probe/thermal_probe_raw.json`

Probe workload üretmez, `powermetrics` çalıştırmaz, `sudo`/root istemez,
AppleSMC'ye mutation komutu göndermez, fan veya power limit kontrol etmez ve
privileged helper kullanmaz. `AppleSMC` connection kapanışında `IOServiceClose`
çağrılır. Sensor anlamları key prefix'lerinden kesinleştirilmez; raw bytes ve
type metadata JSON'da korunur.
