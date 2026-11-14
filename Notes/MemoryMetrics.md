# Métricas de memoria

El lector usa `host_statistics64(HOST_VM_INFO64)`, el tamaño de página de `host_page_size`, `ProcessInfo.physicalMemory`, `vm.swapusage` y la consulta de solo lectura `kern.memorystatus_vm_pressure_level`. Libera el derecho Mach adquirido con `mach_host_self` al terminar cada lectura. La estructura recibida debe contener al menos la revisión 1; no depende de los campos añadidos por el SDK macOS 27.

El trabajo por lectura es constante: consultas de contadores y estructuras pequeñas. No crea un temporizador, una suscripción a presión, un proceso auxiliar ni un bloque grande de memoria. Ambas consultas sysctl pasan `newp = nil` y `newlen = 0`, de modo que no cambian valores del kernel. El llamador decide cuándo actualizar; para una app de barra de menús basta hacerlo al abrir el menú y al pulsar Actualizar. macOS puede devolver estadísticas cacheadas si se consulta repetidamente en menos de un segundo.

Las tres categorías del gráfico son:

- **Libre:** `(free_count − speculative_count) × tamaño de página`.
- **Archivos en RAM (estimación de caché):** `external_page_count × tamaño de página`.
- **En uso:** memoria física menos las dos categorías anteriores. Incluye sistema, aplicaciones, compresor y otros gastos; no es una copia exacta de «Memoria usada» del Monitor de Actividad.

Las páginas especulativas están incluidas tanto en `free_count` como en `external_page_count`. XNU `vm_page_speculate()` incrementa el contador especulativo y el de páginas externas. No hay que volver a sumarlas a la caché.

La memoria cableada, anónima, comprimida y purgable se muestran como detalles superpuestos: no se añaden al gráfico. La memoria comprimida es el espacio físico del compresor, no el tamaño lógico antes de comprimir. «Libre + archivos en RAM» es una estimación y no promete que toda la caché se pueda descartar inmediatamente; puede incluir archivos modificados o en uso. La memoria purgable tampoco se suma a esa estimación. Swap mide espacio en disco.

La presión es el nivel informado por macOS, no un umbral inventado del porcentaje de RAM ocupada. El sysctl exporta las constantes Dispatch `1 = normal`, `2 = aviso`, `4 = crítica`, aunque la enumeración interna del kernel usa valores distintos. Es una consulta sin contrato público de estabilidad: si deja de estar disponible, la interfaz debe mostrar «No disponible» y el diagnóstico, no asumir presión normal. Swap tiene el mismo tratamiento opcional. Fallos en las métricas necesarias o muestras físicamente imposibles producen un error; no se corrigen con valores ficticios.

## Fuentes primarias verificadas

- [Apple: vm_statistics64_data_t](https://developer.apple.com/documentation/kernel/vm_statistics64_data_t).
- Headers locales del SDK de Xcode 27.1: `mach/vm_statistics.h`, `mach/host_info.h`, `sys/sysctl.h` y `dispatch/source.h`.
- [Apple XNU: host.c](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/host.c), `vm_stats()` y `host_statistics64()`.
- [Apple XNU: vm_resident.c](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_resident.c), `vm_page_speculate()`.
- [Apple XNU: kern_memorystatus_notify.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c), `sysctl_memorystatus_vm_pressure_level` y la conversión a constantes Dispatch.
- [Apple: MemoryPressureEvent.warning](https://developer.apple.com/documentation/dispatch/dispatchsource/memorypressureevent/warning).
- [Apple: uso de memoria en Monitor de Actividad](https://support.apple.com/es-es/guide/activity-monitor/actmntr1004/mac).
- [Apple: comprobar si el Mac necesita más RAM](https://support.apple.com/es-es/guide/activity-monitor/actmntr34865/mac).

## Verificación reproducible

Desde la raíz del proyecto:

```sh
mkdir -p Build/Checks
xcrun swiftc -swift-version 6 -strict-concurrency=complete FreeRAMMac/MemoryMetrics.swift Tests/MemoryMetricsChecks.swift -o Build/Checks/MemoryMetricsChecks
Build/Checks/MemoryMetricsChecks
```

Las comprobaciones incluyen una muestra sintética que fallaría al contar dos veces las páginas especulativas, separación entre tamaño físico del compresor y tamaño lógico, tratamiento de contadores imposibles/desbordamiento, traducción de niveles Dispatch y lecturas reales repetidas sin provocación de presión.
