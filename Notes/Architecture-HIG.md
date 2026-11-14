# Arquitectura y revisión estática de macOS

Revisión: 18 de octubre de 2026. Alcance: código fuente; sin abrir la app, automatizar permisos ni ejecutar recuperación. Se conserva el porcentaje cada dos segundos y la recuperación silenciosa con clic principal.

## Mapa de módulos

| Archivo | Responsabilidad | Extensión natural |
| --- | --- | --- |
| `FreeRAMMac/MemoryMetrics.swift` | Modelos de lectura, acceso de solo lectura al kernel y conversión/validación de contadores. No contiene vistas ni recuperación. | Añadir contadores y su validación aquí; conservar diagnósticos para datos opcionales. |
| `FreeRAMMac/RecoveryService.swift` | Actor que solicita al kernel descartar memoria purgable. Sin interfaz, shell ni control de otros procesos. | Incorporar operaciones locales explícitas aquí solo si respetan el alcance de memoria descartable. |
| `FreeRAMMac/MemoryMonitor.swift` | Estado observable del panel, lectura periódica y callback directo de la barra, coordinación de recuperación, exclusión de clics repetidos. Incluye el pequeño formateador `MemoryFormat`. | Añadir estados derivados aquí; extraer el formateador si crece, sin crear capas adicionales ahora. |
| `FreeRAMMac/AppDelegate.swift` | Ciclo de vida AppKit, `NSStatusItem`, presentación del porcentaje, distribución de clics y apertura explícita de opciones/detalles. | Modificar acciones nativas aquí; mantener el clic principal sin activación ni ventanas. |
| `FreeRAMMac/MenuBarView.swift` | Vistas SwiftUI opcionales de detalle y ayuda, estilos y textos de presión. | Ampliar únicamente información que el usuario abra explícitamente. |

Flujo de lectura: kernel → `MemoryReader` → `MemorySnapshot` → `MemoryMonitor` → indicador/vistas. Flujo de acción: clic → `AppDelegate` → `MemoryMonitor` → `RecoveryService`; el estado vuelve al indicador. La estructura ya separa modelo, servicios, estado y presentación de forma equivalente a MVVM; no necesita un refactor general. La lectura síncrona de contadores es pequeña; si en el futuro incorpora trabajo lento, sacarlo del hilo principal antes de ampliar el temporizador.

No hay procesamiento ML, SDK de terceros, cuentas, analítica ni comunicaciones de red en estos módulos. Archivos y exportación no forman parte del producto actual; no se añaden servicios vacíos para ellos. Modelo comercial acordado: compra única al descargar desde App Store. Sin StoreKit, compras internas, suscripciones, anuncios ni desbloqueos locales. Esta revisión no cambia distribución, certificados ni cuentas.

## Revisión HIG aplicable

Fuentes oficiales consultadas: [barra de menús](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover), [accesibilidad](https://developer.apple.com/design/human-interface-guidelines/accessibility) y [tipografía](https://developer.apple.com/design/human-interface-guidelines/typography).

- Plataforma: AppKit, `NSStatusItem`, menú contextual `NSMenu` y ventanas nativas; `LSUIElement` y política accessory mantienen el comportamiento de utilidad de barra. No se aplican tamaños táctiles ni navegación de iOS. macOS no admite Dynamic Type como iOS; las vistas usan principalmente estilos de fuente del sistema.
- Indicador: símbolo SF template para adaptación clara/oscura; porcentaje con dígitos monoespaciados y ancho estable. El estado ocupado cambia el símbolo y conserva el porcentaje. Error de lectura muestra `—%`, con diagnóstico textual; no presenta una cifra vieja como actual. No depende solo del color para representar estados.
- Interacción: Apple describe normalmente un menú para los extras de barra. El clic principal directo es una elección expresa del usuario y se conserva; clic secundario/Control-clic abre el menú nativo. Inicio y reapertura no muestran detalles automáticamente.
- Corrección concreta: el nombre accesible del botón permanece como «Free RAM Mac»; lectura y estado se exponen mediante su valor, y las instrucciones mediante ayuda accesible. Evita cambiar la identidad del control cada dos segundos. No se introducen anuncios automáticos continuos.
- Concurrencia: una recuperación activa bloquea otra solicitud; no cierra ni pausa otras apps. La API solo confirma la solicitud y no garantiza una cantidad liberada.

Pendientes de verificación manual futura, sin iniciar pruebas ahora: navegación por teclado y descubrimiento del menú secundario con VoiceOver; lectura real de nombre/valor/ayuda; contraste de textos pequeños coloreados y terciarios en detalles, modos claro/oscuro y Aumentar contraste; legibilidad con ajustes de tamaño de texto y espacio limitado de la barra. Los textos opcionales usan algunos tamaños fijos de 10 pt y el indicador 11 pt; conviene evaluarlos antes de distribución. No se afirma que estas comprobaciones se hayan realizado ni que exista conformidad HIG completa o aprobación App Store.

## Validación de esta revisión

Comprobación de tipos de los cinco archivos Swift con `xcrun swiftc -typecheck -swift-version 6`: correcta. Sin compilación de producto, instalación, relanzamiento, pruebas UI ni solicitudes de recuperación. La corrección queda en el código fuente; el binario abierto no se reemplazó.
