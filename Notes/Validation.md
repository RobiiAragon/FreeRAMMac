# Verificación de la primera versión

## Actualización: porcentaje permanente en la barra

Se conserva el clic silencioso. El chip incorpora un porcentaje con un decimal, dígitos monoespaciados y ancho fijo. La lectura se actualiza cada dos segundos (temporizador en los modos comunes del run loop) y al iniciar/finalizar la recuperación. El estado ocupado cambia el chip sin ocultar ni atenuar el porcentaje; los clics repetidos no duplican la recuperación. Una lectura fallida muestra `—%`, con el error en el tooltip.

La métrica es `usedBytes / physicalBytes × 100`: uso residual estimado de los contadores Mach, excluyendo caché de archivos y páginas libres. Es una lectura real con una definición aproximada de uso, no la proporción recuperable ni una réplica exacta de Monitor de Actividad. No se suman purgable, compresor ni swap al total. No se suaviza ni se simula una bajada. El mecanismo de recuperación permanece sin cambios.

Verificación: Release universal **BUILD SUCCEEDED** y firma local válida (`Build/build-percentage.log`). Una comprobación CLI del monitor real produjo tres lecturas distintas en aproximadamente cuatro segundos: 61,4 %, 60,0 % y 59,8 %. Se comprobó la lectura inicial y el temporizador periódico sin abrir ventanas ni invocar recuperación (`Build/status-reading-probe.log`). Esos cambios reflejan actividad del sistema; no son ahorro atribuido a una limpieza. La app se sustituyó una sola vez para aplicar la actualización. No se repitió automatización de interfaz ni se pidió autorización.

## Historial anterior: versión sin porcentaje

Actualización del flujo silencioso: `Tools/build.sh` terminó con **BUILD SUCCEEDED** en Release universal y firma local verificada. Log: `Build/build-silent.log`. El clic principal ya no abre ni activa ventanas, no toma medidas antes/después y no tiene la espera artificial de un segundo. Inicio y reapertura permanecen en la barra. Se retiraron el target y esquema de pruebas UI; no se ejecutaron nuevas pruebas automáticas ni solicitudes de autorización para este cambio.

Fecha: 18 de octubre de 2026. Mac arm64, macOS 27.0.1, Xcode 27.1 (27A9275), Swift 6.4. Proyecto y productos dentro de la carpeta del proyecto.

## Actualización: interacción silenciosa

Se simplificó el flujo: el arranque solo añade el icono a la barra; el clic principal solicita recuperar memoria sin abrir panel ni mostrar cantidades; los detalles quedan en el menú secundario. No hay recuperación automática al arrancar.

Esta actualización no incluye una prueba física del clic ni nuevas pruebas de interfaz, permisos o recuperación. Las comprobaciones visuales descritas a continuación corresponden al flujo anterior con panel y se conservan como historial; no validan la interacción silenciosa actual.

## Compilación y revisión

- `Tools/build.sh`: **BUILD SUCCEEDED**, configuración Release, arquitecturas arm64 y x86_64, destino mínimo macOS 14.
- Configuración Debug (arm64, destino My Mac), usada por Ejecutar en Xcode: **BUILD SUCCEEDED**. Log: `Build/build-debug.log`.
- `codesign --verify --strict`: válido. Firma local ad hoc para este Mac; sin Developer ID ni notarización.
- Info.plist y project.pbxproj: `plutil -lint` correcto. `LSUIElement = true`; política `.accessory` para no tener icono persistente en Dock.
- Sin dependencias de terceros, shell en la app, helper privilegiado, cierre de procesos ajenos o asignación de memoria para provocar presión.
- Swift 6 con comprobación completa de concurrencia, sin errores de compilación Swift. Iconos verificados a las dimensiones de cada escala.
- Revisión independiente encontró el posible inicio del timer antes de que apareciera el panel: corregido. El sondeo arranca en `popoverDidShow` y se detiene en `popoverDidClose`.
- La comprobación visual detectó que el arranque AppKit sin nib no instanciaba el delegado: corregido con punto de entrada explícito, asignación y conservación del delegado durante `NSApplication.run()`. La nueva versión muestra el panel y responde a reapertura.

El entorno Xcode emite un aviso por CoreSimulator desactualizado y otro por no tener AppIntents. La compilación de macOS nativo termina correctamente; el proyecto no utiliza simuladores ni AppIntents. Log: `Build/build-release.log`.

## Comprobaciones ejecutadas

`Tools/check.sh` terminó con código 0; salida conservada en `Build/checks.log`.

- Solapamiento de páginas especulativas: se cuentan una vez, no dos.
- Categorías libre + caché + uso = RAM física; purgable no se añade al total.
- Rechazo de contadores imposibles, páginas con tamaño cero y multiplicaciones con desbordamiento.
- Presión del kernel: flags 1/2/4; estados desconocidos no se convierten en normal.
- Seis lecturas reales con swap y presión, sin datos inventados.
- Recuperación como usuario ordinario, comprobando `geteuid() != 0`.
- Una página VM purgable propia de 16 384 bytes pasó de VOLATILE a EMPTY tras la llamada real al kernel.
- Al restaurar NONVOLATILE, su contenido era demand-zero.
- Una segunda página VM normal, sin PURGABLE, conservó **todos** sus bytes tras la misma solicitud.
- Ambas páginas se desasignan. No se creó presión artificial ni se ejecutó `purge` de caché de archivos.

La prueba de recuperación tiene alcance global sobre objetos que ya fueron declarados descartables por sus propietarios. El resultado no equivale a una cantidad de GB liberada por el botón. No se ejecutó una carga de IA de 16 GB como prueba; la conservación de memoria privada se comprobó con una página real y se fundamenta en el alcance de la API.

## Verificación visual

La app Release se abrió y comprobó mediante interfaz nativa y accesibilidad de macOS. El panel de memoria carga cifras reales, está en español y se revisó sin texto cortado. El botón Recuperar ejecutó la acción real y mostró “Solicitud completada” y las observaciones antes/después, sin contraseña ni cierre de programas. La ayuda se abrió en ventana nativa, se recorrió hasta las fuentes y se cerró correctamente. Se comprobó el tema oscuro.

Con panel y ayuda cerrados, dos muestras separadas por 15 segundos registraron CPU acumulada idéntica (1,84 s), CPU instantánea 0,0 % y memoria residente aproximada de 92 MiB al final. Es una observación local breve, no un benchmark ni una garantía para otros equipos. Log: `Build/runtime-idle.log`. El paquete Release ocupa aproximadamente 1,3 MB en este Mac.

La herramienta de automatización captura ventanas, pero no expone la barra de menús global de este entorno. Por ello no se declara una prueba visual del icono ni del clic secundario de la barra. El elemento está implementado con `NSStatusBar.system.statusItem`; los clics principal y secundario tienen rutas separadas y el botón del panel llama exactamente a la misma recuperación que el principal.

Se revisó específicamente el clic principal: `NSStatusBarButton` envía la acción al recibir `leftMouseUp`; el controlador llama a `recoverFromUserClick()`, que muestra el resultado e inicia `monitor.reclaimPurgeableMemory()` sin exigir un segundo botón. El clic secundario y Control-clic abren el menú. Se intentó acceder a la barra por accesibilidad y navegación de teclado, sin obtener un objetivo de clic expuesto por la herramienta. **El clic físico del icono no se pudo verificar en este entorno; no se presenta la prueba del botón del panel como sustituto de esa comprobación física.**

Se intentó abrir `Free RAM Mac.xcodeproj` en Xcode. Su interfaz presenta “Install Required — System-wide components must be installed to use Xcode”. No se activó la instalación del sistema. La interfaz de Xcode queda bloqueada por ese paso inicial; esto no impidió compilar y verificar ambas configuraciones por `xcodebuild`. No se afirma haber ejecutado ⌘R desde esa interfaz.

## Límites

Ejecución real validada en este Mac arm64. La arquitectura Intel compila, pero no se ejecutó en hardware Intel. No se probó en otras versiones de macOS ni con App Sandbox habilitado. Los contadores y la recuperación dependen del kernel; si devuelve un error, la app lo muestra en lugar de simular éxito.
