# Revisión de rendimiento — 20 de octubre de 2026

Alcance: app de barra de macOS, código local de este proyecto. Se aplicó la guía comunitaria [SwiftUI Expert Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) instalada (revisión `204dba7c67256a8b707ee3fbc5759a824191974f`), en particular sus referencias de rendimiento y estado. Sus ejemplos se trataron como orientación; se conservaron AppKit y `ObservableObject`, adecuados para esta app y su destino macOS 14. No se ejecutó ninguna recuperación global. La posterior instalación local está documentada en [DEPLOYMENT.md](DEPLOYMENT.md).

## Entrada y línea base

Lectura local de 3.000 muestras reales consecutivas con el mismo ejecutable arm64 optimizado `swiftc -O`, sin interfaz ni operación de recuperación. Cada muestra comprobó `used + cached + free == physical`. El ejecutable previo a los cambios quedó en `Build/Checks/memory-sampling-baseline`. Se intercalaron tres ejecuciones de cada variante después de compilar la nueva; otros builds en la Mac y el estado de cachés generan ruido. La lectura inicial previa al calentamiento tuvo mediana de 5,333 µs y no se usó para comparar. Son tiempos de la función de lectura, no de la app completa ni de una Mac acelerada.

| Medida | Antes | Después | Evidencia |
| --- | ---: | ---: | --- |
| Mediana de las medianas de tres series de 3.000 lecturas, panel cerrado | 3,375 µs | 1,625 µs | Series antes: 3,375 / 3,792 / 3,000 µs; después: 2,458 / 1,625 / 1,375 µs. |
| Consultas opcionales `sysctlbyname` por lectura, panel cerrado | 2 | 0 | Ramas de `MemoryReader.read(includeDetails:)`: solo se leen swap y presión al pedir detalles. Se mantienen la consulta VM y el porcentaje cada dos segundos. |
| Avisos `objectWillChange` en tres lecturas con panel cerrado | 3 | 0 | Probe con temporizador real durante 4,4 s, mismo monitor; un callback de lectura por muestra. |
| Símbolos SF creados por cada actualización periódica | 1 | 0 | Se guardan los dos símbolos al crear el delegado y solo se intercambian cuando cambia el estado. |
| Lectura completa con detalles visibles, misma batería | 3,375 µs antes | 3,125 µs después | Series después: 4,250 / 3,125 / 2,750 µs; dentro del ruido. Sin degradación demostrada ni mejora atribuible. |

El probe de notificaciones posterior observó 2 lecturas y 2 avisos durante 2,3 s con detalles visibles, incluidas actualización inmediata al abrir y siguiente muestra periódica. No se suprime la actualización del panel abierto. Los checks con muestra sintética fija comprobaron que libre excluye especulativas, caché no se duplica, la suma coincide con RAM física, swap ausente permanece ausente y las entradas inválidas fallan. Seis lecturas reales verificaron los invariantes en el sistema actual. Los checks nunca pidieron recuperar memoria.

## Cambios

`MemoryReader` conserva la lectura completa por defecto para llamadas externas y verificaciones. El monitor pide solo contadores VM cuando no hay detalles abiertos; `NSPopoverDelegate` habilita la lectura completa al abrir y la deshabilita al cerrar. Los datos opcionales se refrescan inmediatamente al mostrar detalles. Los contadores de uso, caché, libre, cableada, comprimida y purgable conservan sus definiciones; presión y swap nunca se muestran como cero inventado.

`MemoryMonitor` guarda la última muestra para la barra sin emitir invalidaciones a SwiftUI cuando el panel está cerrado. Cuando está visible emite una por muestra antes de actualizarla. El botón de barra solo recibe nuevos valores de título, tooltip, accesibilidad o imagen si el contenido correspondiente cambia. El temporizador sigue siendo único y su callback no retiene el monitor. La recuperación y el clic silencioso no se modificaron.

## Validación y límites

- `Tools/build.sh`: Release universal arm64/x86_64 correcto, firma local verificada; log `Build/build-performance.log`.
- `Tests/MemoryMetricsChecks.swift`: pasó, con fixture determinista y seis lecturas reales de solo lectura.
- `Build/Checks/MonitorNotificationProbe.swift`: oculto, 3 lecturas / 0 avisos; visible, 2 lecturas / 2 avisos. La línea base oculta fue 3 / 3.
- `Build/Checks/MemorySamplingProbe.swift`: 3.000 lecturas por serie, tres series intercaladas por variante; invariantes por muestra. El modo ligero verificó swap ausente y presión desconocida mientras esos datos no se consultan.

No se hicieron pruebas UI automatizadas, de batería a largo plazo ni en Intel/macOS anteriores. La prueba de rendimiento usa lecturas rápidas y una ejecución corta, por lo que no demuestra ahorro energético ni cambios perceptibles de velocidad. Se abrió la copia estable una vez después de la revisión, se comprobó el porcentaje mediante lectura pasiva de accesibilidad y se corrigió su entrada de inicio; los detalles están en [DEPLOYMENT.md](DEPLOYMENT.md). Falta comprobar un login real. Este trabajo no indica aprobación de App Store ni altera su modelo de compra única.
