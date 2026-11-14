import SwiftUI

private enum Palette {
    static let mint = Color(red: 0.08, green: 0.60, blue: 0.45)
    static let blue = Color(red: 0.25, green: 0.47, blue: 0.88)
}

struct MenuBarView: View {
    @ObservedObject var monitor: MemoryMonitor
    let recover: () -> Void
    let showHelp: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 10) {
                    Image(systemName: "memorychip.fill").font(.title2).foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free RAM Mac").font(.headline)
                        Text("Un clic, sin cerrar tus apps").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Actualizar métricas")
                }
                actionResult
                if let error = monitor.readError {
                    Label(error + " Las cifras previas pueden estar desactualizadas.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let snapshot = monitor.snapshot {
                    memoryDetails(snapshot)
                } else {
                    Text("Métricas no disponibles. Vuelve a actualizar.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                Text("Solo descarta memoria que las apps marcaron como prescindible. No recupera toda la caché ni la RAM privada de un modelo de IA. Las apps pueden reconstruir sus cachés.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cómo funciona", action: showHelp).buttonStyle(.link)
                    Spacer()
                    Button("Recuperar ahora", action: recover)
                        .disabled(monitor.isRecovering)
                }
                Text("Clic en la barra: recuperar · clic secundario: opciones")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(22)
        }.frame(width: 420, height: 590)
    }

    private var actionResult: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if monitor.isRecovering { ProgressView().controlSize(.small).padding(.top, 2) }
                else {
                    Image(systemName: monitor.actionIsError ? "exclamationmark.circle" : "leaf.circle")
                        .font(.title3).foregroundStyle(monitor.actionIsError ? Color.orange : Palette.mint)
                }
                Text(monitor.actionMessage).font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if monitor.isRecovering {
                Text("Otro clic no inicia una segunda solicitud.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !monitor.actionIsError {
                Text("Sin contraseña. macOS ya recupera memoria cuando hace falta; no hay una cantidad garantizada.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func memoryDetails(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Presión \(snapshot.pressure.title.lowercased())", systemImage: snapshot.pressure == .normal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(snapshot.pressure.tint)
                Spacer()
                Text(MemoryFormat.bytes(snapshot.physicalBytes)).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.blue)
                        .frame(width: geometry.size.width * Double(snapshot.usedBytes) / Double(snapshot.physicalBytes))
                    Rectangle().fill(Palette.mint.opacity(0.7))
                        .frame(width: geometry.size.width * Double(snapshot.cachedBytes) / Double(snapshot.physicalBytes))
                    Rectangle().fill(Palette.mint.opacity(0.15))
                }.clipShape(RoundedRectangle(cornerRadius: 4))
            }.frame(height: 12)
                .accessibilityLabel("RAM: en uso \(MemoryFormat.bytes(snapshot.usedBytes)), caché \(MemoryFormat.bytes(snapshot.cachedBytes)), libre \(MemoryFormat.bytes(snapshot.freeBytes))")
            HStack {
                metric("En uso · estim.", snapshot.usedBytes, color: Palette.blue)
                metric("Caché · estim.", snapshot.cachedBytes, color: Palette.mint)
                metric("Libre", snapshot.freeBytes, color: .secondary)
            }
            Divider()
            row("Cableada", MemoryFormat.bytes(snapshot.wiredBytes))
            row("Comprimida en RAM", MemoryFormat.bytes(snapshot.compressedBytes))
            row("Purgable¹", MemoryFormat.bytes(snapshot.purgeableBytes))
            row("Swap en disco", snapshot.swapUsedBytes.map(MemoryFormat.bytes) ?? "No disponible")
            Text("¹ Se solapa con otras categorías; no se suma a la caché. No toda la caché es purgable. Swap es disco, no RAM.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(snapshot.diagnostics, id: \.self) { diagnostic in
                Text(diagnostic).font(.caption).foregroundStyle(.orange)
            }
            Text("\(snapshot.timestamp.formatted(date: .omitted, time: .standard)) · actualización cada 2 s")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func metric(_ title: String, _ bytes: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(MemoryFormat.bytes(bytes)).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.caption)
    }
}

extension MemoryPressure {
    var title: String {
        switch self { case .normal: "Normal"; case .warning: "Alta"; case .critical: "Crítica"; case .unknown: "No disponible" }
    }
    var tint: Color {
        switch self { case .normal: Palette.mint; case .warning: .orange; case .critical: .red; case .unknown: .gray }
    }
}

struct MemoryHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Free RAM Mac", systemImage: "memorychip.fill").font(.title2.weight(.semibold))
                explanation("Un clic desde la barra de menús", "El clic principal intenta recuperar memoria purgable en segundo plano, sin abrir ventanas ni pedir contraseña. El clic secundario permite consultar detalles. Mientras hay una solicitud activa no se inicia otra. La app no se ejecuta al iniciar sesión.")
                explanation("El porcentaje de la barra", "Es la RAM en uso estimada dividida por la RAM física total, con un decimal. Se mide cada dos segundos y al comenzar y terminar la recuperación, también con el panel cerrado. Excluye la caché de archivos de la categoría en uso; no es el porcentaje de memoria que se puede liberar ni una réplica exacta de Monitor de Actividad. Puede subir, bajar o quedarse igual. Si la lectura falla, aparece —% en lugar de mostrar una cifra anterior como actual.")
                explanation("Qué se recupera de verdad", "Usamos mach_vm_purgable_control con VM_PURGABLE_PURGE_ALL. macOS descarta objetos volátiles que sus propias apps declararon prescindibles. El alcance es global, no solo esta app. No equivale a toda la caché de archivos; algunas apps pueden reconstruir cachés y hacer trabajo adicional después.")
                explanation("Tus programas siguen abiertos", "No se cierran ni pausan procesos, no se borran archivos ni se crean asignaciones grandes para forzar presión. La memoria privada normal de un modelo de IA permanece en uso. La app no vacía swap ni libera memoria cableada. No se puede garantizar ausencia de latencia al reconstruir cachés.")
                explanation("Solicitud completada no significa GB liberados", "La API informa éxito o error, no una cantidad recuperada. Puede no haber objetos descartables. El clic no muestra un informe de memoria liberada.")
                explanation("La presión importa más que la RAM libre", "macOS usa RAM para acelerar la lectura de archivos. 15 GB ocupados no implican 6 GB desperdiciados. El nivel de presión lo comunica el kernel; no se calcula a partir del porcentaje ocupado. Con presión normal, limpiar suele ser innecesario.")
                explanation("Cómo se calculan las cifras", "Leemos host_statistics64 con el tamaño real de página. Libre = free_count − speculative_count. Caché estimada = external_page_count, que ya incluye páginas especulativas. En uso estimado = RAM física − libre − caché. Son categorías sin doble conteo, pero no una réplica exacta de Monitor de Actividad: no toda la caché se puede descartar inmediatamente.")
                explanation("Detalles que no se suman", "Cableada y comprimida son detalles del uso. Comprimida es el espacio físico del compresor, no el tamaño original de sus datos. Purgable se solapa con otras categorías; no se suma a la caché. Swap es disco. Unidades decimales: 1 GB = 1 000 000 000 bytes.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fuentes de Apple").font(.headline)
                    Link("Memoria en Monitor de Actividad", destination: URL(string: "https://support.apple.com/es-mx/guide/activity-monitor/actmntr1004/mac")!)
                    Link("API Mach de memoria virtual", destination: URL(string: "https://developer.apple.com/documentation/kernel/mach/mach_vm")!)
                    Link("Implementación de memoria purgable (XNU)", destination: URL(string: "https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_purgeable.c")!)
                    Link("Definiciones de los contadores (XNU)", destination: URL(string: "https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h")!)
                }.font(.callout)
                Text("Las lecturas se procesan localmente. Free RAM Mac no envía métricas a servidores ni instala servicios privilegiados.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.frame(width: 590, height: 650)
    }

    private func explanation(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
