# Recuperación real sin privilegios

`RecoveryService.reclaimPurgeableMemory()` solicita `mach_vm_purgable_control(mach_task_self_, 0, VM_PURGABLE_PURGE_ALL, &state)` con `state = 0`. Es una API pública Mach incluida en el SDK de macOS. No usa contraseña, helper, shell, `purge`, cambios de configuración ni asignaciones masivas. [Referencia Mach VM de Apple](https://developer.apple.com/documentation/kernel/mach/mach_vm).

## Alcance comprobado en código de Apple

La biblioteca de sistema dirige la llamada al trap Mach y conserva una alternativa RPC. [libsyscall/mach/mach_vm.c](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/mach/mach_vm.c).

El punto de entrada permite el control `VM_PURGABLE_PURGE_ALL` desde espacio de usuario. La app usa únicamente su propio puerto de tarea; no obtiene puertos de otras apps. [osfmk/vm/vm_user.c](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/vm/vm_user.c).

Para ese control, el kernel llama a la recuperación global y devuelve su estado antes de examinar dirección y estado del objeto individual. Esta rama no exige root en el código publicado. [osfmk/vm/vm_map.c](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/vm/vm_map.c).

La recuperación recorre las colas globales de objetos purgables volátiles; por eso no se limita a las asignaciones de esta app. Sólo afecta objetos cuyos propietarios ya declararon descartables. No vacía toda la caché de archivos ni la memoria privada normal, cableada o los archivos de swap. El propietario debe regenerar los datos que vuelva a necesitar; no es posible prometer cero coste de recomputación. [osfmk/vm/vm_purgeable.c](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/vm/vm_purgeable.c). Apple describe el contrato de contenido descartable y el acceso protegido en [Caching and Purgeable Memory](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/CachingandPurgeableMemory.html).

La llamada se ejecuta fuera del hilo de interfaz, nunca automáticamente, sólo por clic deliberado. No termina, pausa ni reinicia procesos o modelos de IA. Una cancelación previa evita iniciarla; una vez dentro del kernel, la app espera el resultado y no afirma revertirla. No se aplica un timeout falso a una operación kernel no cancelable.

`KERN_SUCCESS` confirma que macOS aceptó y completó la solicitud, no que se haya liberado una cantidad concreta. Puede no haber objetos volátiles o el ahorro ser cero. Las diferencias de RAM antes/después son cambios observados de todo el sistema, no un ahorro exclusivamente atribuible al clic. Se informa cualquier error Mach sin simular éxito. La disponibilidad estática corresponde a las versiones del deployment target; una restricción en ejecución queda visible como error.

## Verificación real con dos páginas

El check verifica que no se ejecuta como root y reserva una página VM con `VM_FLAGS_PURGABLE`; escribe su contenido, la marca `VM_PURGABLE_VOLATILE`, llama al servicio real y verifica que pasa a `VM_PURGABLE_EMPTY`. Antes de leer de nuevo restaura `NONVOLATILE` y comprueba el contenido demand-zero. Una segunda página VM asignada sin `PURGABLE` conserva todos sus bytes tras la misma recuperación, comprobados leyendo la memoria real incluso en builds optimizadas. Las dos páginas (32 KB en este Mac) se desasignan al terminar. Esta prueba realiza una única recuperación global de objetos ya descartables, sin presión artificial, acceso administrativo, cambios de procesos ni `vfs_purge`.

`Tests/CrossProcessRecoveryChecks.swift` comprueba también el alcance entre procesos: el padre conserva las dos páginas y un hijo CLI propio, recién iniciado, llama al servicio de producción una vez. En la comprobación real, ambos con UID 501 y PID distintos (15502 y 15508), la página del padre pasó de `VOLATILE=1` a `EMPTY=2`; todos los bytes de la página privada normal permanecieron intactos. Terminó con código 0 en 0,14 s, sin root. Se coordinó una ventana sin fixtures de UI activos para no invalidar su evidencia. Este check no opera ninguna app ajena; el hijo termina normalmente.
