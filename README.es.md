# Free RAM Mac

App nativa de macOS para recuperar memoria descartable desde la barra de menús. Interfaz en español, sin icono persistente en el Dock, sin contraseña y sin cerrar programas.

Posicionamiento, textos localizados, guion de capturas y pendientes de App Store: [ASO.md](ASO.md).

## Usar

Abre `Build/Products/Release/Free RAM Mac.app`. Al arrancar aparece el icono con el porcentaje de RAM en uso en la barra, sin abrir paneles ni recuperar memoria automáticamente.

- **Clic principal en el chip de la barra:** intenta recuperar memoria purgable silenciosamente, sin abrir panel ni informe. El porcentaje sigue mostrando mediciones del sistema, también durante la recuperación. Otro clic durante una solicitud activa no inicia otra.
- **Clic secundario o Control-clic:** abre las opciones para consultar detalles de memoria, activar o desactivar el inicio de sesión, ver la ayuda y salir.

Por defecto la app no se añade al inicio de sesión. Si lo quieres, activa **Abrir al iniciar sesión** en el menú del clic secundario: usa `SMAppService` de Apple (sin helper ni LaunchAgent). Si macOS pide aprobación, la app te lleva a Ajustes del Sistema → General → Elementos de inicio. Vuelve a pulsarlo para desactivarlo.

Lee los contadores del kernel cada dos segundos, también con el panel cerrado, y al comenzar y terminar la recuperación. Solo hay un temporizador; no ejecuta procesos auxiliares para medir.

Las consultas opcionales de swap y presión se hacen mientras el panel de detalles está abierto; al abrirlo se actualizan de inmediato. Con el panel cerrado, la barra continúa leyendo el porcentaje cada dos segundos.

El porcentaje es **uso estimado / RAM física × 100**, con un decimal y dígitos monoespaciados. Uso estimado excluye la caché de archivos: no significa toda la memoria recuperable ni replica exactamente Monitor de Actividad. Se obtiene de los contadores reales descritos abajo; puede bajar, subir o no cambiar. No se anima un descenso ficticio. Si la lectura falla, la barra muestra `—%` y el motivo queda en su descripción emergente, en lugar de presentar una cifra antigua como actual.

## Alcance real

La acción llama a `mach_vm_purgable_control(mach_task_self_, 0, VM_PURGABLE_PURGE_ALL, &state)`. El kernel descarta objetos **volátiles que sus propietarios ya declararon prescindibles**. La solicitud es global y no se limita a la memoria de esta app. No equivale a recuperar toda la caché de archivos. Una solicitud correcta puede liberar cero bytes.

No cierra, pausa ni reinicia procesos; no elimina archivos, no ejecuta `purge`, no instala helpers ni crea presión artificial. No libera RAM cableada, memoria privada normal de un modelo de IA ni swap. Las apps pueden tener que reconstruir sus cachés descartables; no se promete ausencia de latencia ni una reducción concreta de GB. No se hizo una prueba de carga con un modelo de IA de 16 GB.

La respuesta del kernel solo indica éxito o error; no informa bytes liberados. El clic principal no abre un informe: el porcentaje permanece en la barra y las métricas ampliadas están en el menú secundario. La memoria ocupada no significa memoria desperdiciada: con presión normal, normalmente no hace falta limpiar.

## Métricas

Lecturas locales de `host_statistics64`, `host_page_size`, `ProcessInfo.physicalMemory`, `vm.swapusage` y `kern.memorystatus_vm_pressure_level`.

- Libre: `free_count − speculative_count`.
- Caché estimada: `external_page_count`, que ya incluye páginas especulativas.
- Uso estimado: RAM física menos libre y caché. Las tres categorías suman la RAM física.
- Cableada y compresor físico: detalles del uso. Purgable: contador solapado, no se suma a caché.
- Swap: disco, separado de la RAM. Presión: nivel del kernel; no se calcula a partir de RAM ocupada.

Las cifras no replican exactamente Monitor de Actividad. No toda la caché se puede descartar de inmediato. Las métricas opcionales no disponibles muestran un diagnóstico; una lectura inconsistente conserva la muestra anterior con advertencia.

## Abrir y compilar en Xcode

Abre **Free RAM Mac.xcodeproj**, elige el esquema **Free RAM Mac** y destino **My Mac**, y ejecuta con ⌘R. No requiere paquetes externos ni un equipo de desarrollador: el proyecto usa firma local ad hoc. Destino mínimo macOS 14; ejecución verificada en macOS 27.0.1 con Xcode 27.1. La compilación Release genera un binario universal arm64/x86_64; el runtime Intel y versiones anteriores de macOS no se han probado.

Desde esta carpeta:

```sh
Tools/build.sh
```

Producto: `Build/Products/Release/Free RAM Mac.app`. Datos de compilación y pruebas permanecen en `Build/`, dentro de esta carpeta. El proyecto no configura App Sandbox; solo se ha validado la ejecución local sin sandbox. La firma local no es una firma Developer ID ni una notarización para distribuir en otros equipos.

## Verificación

```sh
Tools/check.sh
```

El script comprueba fórmulas, solapamientos, desbordamientos, lecturas reales y la recuperación efectiva. **El check de recuperación realiza una solicitud global real** como usuario normal, usando una página propia marcada como purgable y una pequeña página privada de control; no crea presión ni solicita privilegios. Se incluye así para verificar que la acción no es una simulación.

Revisión y resultados en [Notes/Validation.md](Notes/Validation.md). Detalles técnicos y documentación primaria de Apple en [Notes/MemoryMetrics.md](Notes/MemoryMetrics.md) y [Notes/Recovery.md](Notes/Recovery.md).

Mediciones y cambios de rendimiento: [PERFORMANCE.md](PERFORMANCE.md).

English version: [README.md](README.md).
