import AppKit
import ApplicationServices
import CoreAudio
import CoreMediaIO
import IOKit.ps
import Observation

/// A bateria interna, como o IOKit conta.
struct Bateria: Equatable, Sendable {
    var porcento: Int
    var carregando: Bool
    var ligadaNaTomada: Bool

    enum Aviso: Equatable, Sendable {
        case fraca(Int)
        case carregando
        case completa
    }

    /// O que já foi avisado. `tomada` nil: ainda não houve leitura.
    struct Memoria: Equatable, Sendable {
        var tomada: Bool?
        var avisou20 = false
        var avisou10 = false
        var avisouCompleta = false
    }

    /// Acima disso os avisos de bateria fraca valem de novo: a bateria só sobe carregando, e a margem de 5 pontos
    /// evita repetir o aviso de 20% quando a carga oscila em volta dele.
    static let rearme = 25

    /// O aviso desta leitura, um no máximo (todos usam o id `mac-bateria`), e a memória nova.
    static func decidir(_ bateria: Bateria?, _ memoria: Memoria) -> (aviso: Aviso?, memoria: Memoria) {
        guard let bateria else { return (nil, memoria) }
        let primeira = memoria.tomada == nil
        let plugou = memoria.tomada == false && bateria.ligadaNaTomada
        let descarregando = !bateria.ligadaNaTomada
        var nova = memoria
        nova.tomada = bateria.ligadaNaTomada
        if bateria.porcento > rearme { nova.avisou20 = false; nova.avisou10 = false }
        if descarregando { nova.avisouCompleta = false }

        if bateria.ligadaNaTomada && bateria.porcento >= 100 && !nova.avisouCompleta {
            nova.avisouCompleta = true
            return (primeira ? nil : .completa, nova)  // abrir o Kizami já cheio na tomada não é novidade
        }
        if plugou { return (.carregando, nova) }
        if descarregando && bateria.porcento <= 10 && !nova.avisou10 {
            nova.avisou10 = true
            nova.avisou20 = true  // quem pula de 21% para 9% (Mac dormindo) recebe um aviso só
            return (.fraca(bateria.porcento), nova)
        }
        if descarregando && bateria.porcento <= 20 && !nova.avisou20 {
            nova.avisou20 = true
            return (.fraca(bateria.porcento), nova)
        }
        return (nil, nova)
    }
}

extension Bateria.Aviso {
    func atividade(porcento: Int) -> Atividade {
        let detalhe = "\(porcento)%"  // fora da chave da tradução: um % solto viraria formato
        return switch self {
        case .fraca(let p):
            Atividade(id: "mac-bateria", titulo: String(localized: "Bateria fraca"), detalhe: detalhe,
                      simbolo: p <= 10 ? "battery.0percent" : "battery.25percent", cor: p <= 10 ? "vermelho" : "laranja",
                      expira: 30, prioridade: p <= 10 ? "alta" : "normal")
        case .carregando:
            Atividade(id: "mac-bateria", titulo: String(localized: "Carregando"), detalhe: detalhe,
                      simbolo: "battery.100percent.bolt", cor: "verde", expira: 4)
        case .completa:
            // Baixa: entra nas asas sem descer, é bom saber mas não pede nada.
            Atividade(id: "mac-bateria", titulo: String(localized: "Carga completa"), simbolo: "battery.100percent",
                      cor: "verde", expira: 8, prioridade: "baixa")
        }
    }
}

/// O emblema de um app no Dock ("3", "•"). Rótulo e nome são conteúdo: nunca no log.
struct Emblema: Equatable, Identifiable, Sendable {
    var bundle: String
    var nome: String
    var rotulo: String
    var id: String { bundle }

    /// Os dígitos do começo: "99+" conta como 99; "•" não é número.
    var numero: Int? { Int(rotulo.prefix { ("0"..."9").contains($0) }) }

    /// Quem ganhou mensagens desde a leitura anterior. O emblema some no zero, então um app que aparece
    /// com número é o caso mais comum (0 → 1). Diminuir ou ficar igual não avisa.
    static func novidades(antes: [Emblema], depois: [Emblema]) -> [Emblema] {
        let anteriores = Dictionary(antes.map { ($0.bundle, $0.numero ?? 0) }, uniquingKeysWith: max)
        return depois.filter { emblema in emblema.numero.map { $0 > (anteriores[emblema.bundle] ?? 0) } ?? false }
    }
}

/// O que o Mac está fazendo: microfone e câmera em uso, bateria e, se a pessoa ligar, os emblemas do Dock.
/// Só lê: nunca muda dispositivo, volume nem abre áudio ou vídeo.
@MainActor @Observable
final class Mac {
    static let chaveEmblemas = "mac.emblemas"

    /// Bundle ids dos apps com o microfone aberto, na ordem em que começaram.
    private(set) var microfone: [String] = []
    /// Alguma câmera ligada. O CoreMediaIO diz que está, não para quem.
    private(set) var camera = false
    /// nil num Mac sem bateria.
    private(set) var bateria: Bateria?
    private(set) var emblemas: [Emblema] = []
    private(set) var emblemasLigados = UserDefaults.standard.bool(forKey: Mac.chaveEmblemas)
    private(set) var acessibilidade = AXIsProcessTrusted()

    @ObservationIgnored private let mural: Mural
    @ObservationIgnored private var memoria = Bateria.Memoria()
    @ObservationIgnored private var sensores: Task<Void, Never>?
    @ObservationIgnored private var leitorDoDock: Task<Void, Never>?
    @ObservationIgnored private var fonteDeEnergia: CFRunLoopSource?
    /// A primeira leitura do Dock é a base: ligar os emblemas não despeja na ilha tudo o que já estava lá.
    @ObservationIgnored private var dockLido = false

    init(mural: Mural) {
        self.mural = mural
    }

    func iniciar() {
        guard sensores == nil else { return }
        // ponytail: consulta microfone e câmera a cada 2 s; o ponto aparece até 2 s depois do sistema.
        // Trocar por AudioObjectAddPropertyListenerBlock (lista + IsRunningInput por processo) e
        // CMIOObjectAddPropertyListenerBlock se o atraso incomodar.
        sensores = Task { [weak self] in
            while !Task.isCancelled {
                // Fora da thread principal: o coreaudiod pode demorar a responder quando um dispositivo muda.
                let (apps, camera) = await Task.detached { (Mac.appsNoMicrofone(), Mac.cameraLigada()) }.value
                guard let self else { return }
                self.conferir(apps: apps, camera: camera)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        observarBateria()
        if emblemasLigados { lerDock() }
    }

    // MARK: Emblemas do Dock

    func ligarEmblemas(_ ligar: Bool) {
        emblemasLigados = ligar
        UserDefaults.standard.set(ligar, forKey: Self.chaveEmblemas)
        guard ligar else { return pararDock() }
        // O texto é a chave do CFDictionary (kAXTrustedCheckOptionPrompt): a global do C não é segura no Swift 6.
        acessibilidade = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        lerDock()
    }

    /// Ao abrir os Ajustes: liberado nos Ajustes do Sistema depois, já vale sem reabrir o app.
    func conferirAcesso() {
        let confiavel = AXIsProcessTrusted()
        if confiavel != acessibilidade { acessibilidade = confiavel }
    }

    /// Traz o app para frente. É o clique da pessoa que pede; o Kizami continua sem foco.
    static func ativar(_ bundle: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return }
        // Como em `Claude.focar`: a ativação cooperativa pode recusar um app inativo; o Launch Services não.
        if !app.activate(), let url = app.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    // ponytail: lê o Dock a cada 10 s; um emblema novo chega à ilha até 10 s depois.
    // Trocar por um AXObserver de kAXValueChangedNotification nos itens do Dock se o atraso incomodar.
    private func lerDock() {
        guard leitorDoDock == nil else { return }
        leitorDoDock = Task { [weak self] in
            while !Task.isCancelled {
                let confiavel = AXIsProcessTrusted()
                let lidos = confiavel ? await Task.detached { Mac.lerEmblemas() }.value : nil
                guard let self, !Task.isCancelled else { return }
                if confiavel != self.acessibilidade { self.acessibilidade = confiavel }
                if !confiavel { self.esquecerDock() }
                if let lidos { self.receber(lidos) }  // nil: o Dock não respondeu; a próxima leitura tenta de novo
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func pararDock() {
        leitorDoDock?.cancel()
        leitorDoDock = nil
        esquecerDock()
    }

    private func esquecerDock() {
        dockLido = false
        if !emblemas.isEmpty { emblemas = [] }
    }

    private func receber(_ lidos: [Emblema]) {
        let novidades = dockLido ? Emblema.novidades(antes: emblemas, depois: lidos) : []
        dockLido = true
        if lidos != emblemas { emblemas = lidos }
        for emblema in novidades {
            let detalhe = emblema.numero == 1 ? String(localized: "1 não lida") : String(localized: "\(emblema.numero ?? 0) não lidas")
            mural.receber(Atividade(id: "mac-emblema-\(emblema.bundle)", titulo: emblema.nome, detalhe: detalhe,
                                    simbolo: "app.badge.fill", expira: 8))
        }
        if !novidades.isEmpty { registro.info("mac: \(novidades.count) emblemas subiram (\(lidos.count) no Dock)") }
    }

    /// Os itens do Dock com emblema. nil quando o Dock não responde: não confundir com "sem emblemas",
    /// senão a próxima leitura anunciaria tudo de novo.
    nonisolated private static func lerEmblemas() -> [Emblema]? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)  // um Dock travado não segura a leitura
        guard let filhos = atributo(app, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        let itens = filhos.filter { atributo($0, kAXRoleAttribute) as? String == kAXListRole }
            .flatMap { atributo($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
        return itens.compactMap { item -> Emblema? in
            guard let rotulo = (atributo(item, "AXStatusLabel") as? String).map({ Atividade.limpo($0, ate: 4) }), !rotulo.isEmpty,
                  let url = atributo(item, kAXURLAttribute) as? URL,
                  let bundle = Bundle(url: url)?.bundleIdentifier else { return nil }
            let nome = Atividade.limpo(atributo(item, kAXTitleAttribute) as? String ?? "", ate: 60)
            return Emblema(bundle: bundle, nome: nome.isEmpty ? url.deletingPathExtension().lastPathComponent : nome, rotulo: rotulo)
        }
    }

    nonisolated private static func atributo(_ elemento: AXUIElement, _ nome: String) -> CFTypeRef? {
        var valor: CFTypeRef?
        return AXUIElementCopyAttributeValue(elemento, nome as CFString, &valor) == .success ? valor : nil
    }

    // MARK: Microfone e câmera

    private func conferir(apps: [String], camera: Bool) {
        let novos = Self.microfone(apps, antes: microfone, proprio: Bundle.main.bundleIdentifier)
        if novos != microfone {
            registro.info("mac: microfone com \(novos.count) apps")
            microfone = novos
        }
        if camera != self.camera {
            registro.info("mac: câmera \(camera ? "ligada" : "desligada", privacy: .public)")
            self.camera = camera
        }
    }

    /// Ordem estável: quem já estava fica no lugar, quem chegou vai para o fim. Sem o próprio Kizami e sem repetir.
    nonisolated static func microfone(_ atuais: [String], antes: [String], proprio: String?) -> [String] {
        let validos = atuais.filter { $0 != proprio }
        let ficam = antes.filter(validos.contains)
        var novos: [String] = []
        for app in validos where !ficam.contains(app) && !novos.contains(app) { novos.append(app) }
        return ficam + novos
    }

    /// Apps cujos processos estão com a entrada de áudio aberta.
    /// Só processos dentro de um .app (ou o WebKit do Safari): o com.apple.CoreSpeech (o "E aí, Siri") mantém
    /// a entrada aberta o tempo todo e o sistema não acende o ponto laranja por ele (visto na sonda).
    // ponytail: ferramenta de linha de comando gravando (sox, ffmpeg) não acende o ponto; o indicador do sistema sim.
    nonisolated private static func appsNoMicrofone() -> [String] {
        let sistema = AudioObjectID(kAudioObjectSystemObject)
        var endereco = endereco(kAudioHardwarePropertyProcessObjectList)
        var tamanho: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sistema, &endereco, 0, nil, &tamanho) == noErr, tamanho > 0 else { return [] }
        var processos = [AudioObjectID](repeating: 0, count: Int(tamanho) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sistema, &endereco, 0, nil, &tamanho, &processos) == noErr else { return [] }
        return processos
            .filter { ler($0, kAudioProcessPropertyIsRunningInput, UInt32(0)) != 0 }
            .compactMap { appDoProcesso($0, pid: ler($0, kAudioProcessPropertyPID, pid_t(-1))) }
    }

    nonisolated private static func appDoProcesso(_ processo: AudioObjectID, pid: pid_t) -> String? {
        var caminho = [CChar](repeating: 0, count: 4096)
        if pid > 0, proc_pidpath(pid, &caminho, UInt32(caminho.count)) > 0,
           let app = Som.caminhoDoApp(String(decoding: caminho.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)),
           let bundle = Bundle(path: app)?.bundleIdentifier {
            return bundle
        }
        var endereco = endereco(kAudioProcessPropertyBundleID)
        var valor: Unmanaged<CFString>?
        var tamanho = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(processo, &endereco, 0, nil, &tamanho, &valor) == noErr,
              let bundle = valor?.takeRetainedValue() as String? else { return nil }
        return Som.appPorBundle(bundle)
    }

    nonisolated private static func ler<T: BitwiseCopyable>(_ objeto: AudioObjectID, _ seletor: AudioObjectPropertySelector, _ padrao: T) -> T {
        var endereco = endereco(seletor)
        var valor = padrao
        var tamanho = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(objeto, &endereco, 0, nil, &tamanho, &valor) == noErr ? valor : padrao
    }

    nonisolated private static func endereco(_ seletor: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: seletor, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated private static func cameraLigada() -> Bool {
        func endereco(_ seletor: Int) -> CMIOObjectPropertyAddress {
            CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(seletor),
                                      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        }
        let sistema = CMIOObjectID(kCMIOObjectSystemObject)
        var lista = endereco(kCMIOHardwarePropertyDevices)
        var tamanho: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(sistema, &lista, 0, nil, &tamanho) == noErr, tamanho > 0 else { return false }
        var dispositivos = [CMIOObjectID](repeating: 0, count: Int(tamanho) / MemoryLayout<CMIOObjectID>.size)
        var usado: UInt32 = 0
        guard CMIOObjectGetPropertyData(sistema, &lista, 0, nil, tamanho, &usado, &dispositivos) == noErr else { return false }
        return dispositivos.contains { dispositivo in
            var rodando = endereco(kCMIODevicePropertyDeviceIsRunningSomewhere)
            var valor: UInt32 = 0
            return CMIOObjectGetPropertyData(dispositivo, &rodando, 0, nil, 4, &usado, &valor) == noErr && valor != 0
        }
    }

    // MARK: Bateria

    private func observarBateria() {
        atualizarBateria()
        // Sem captura: o callback é um ponteiro de função do C. O Mac vive enquanto o app vive, por isso não retém.
        let contexto = Unmanaged.passUnretained(self).toOpaque()
        guard let fonte = IOPSNotificationCreateRunLoopSource({ contexto in
            guard let contexto else { return }
            let mac = Unmanaged<Mac>.fromOpaque(contexto).takeUnretainedValue()
            // A fonte está no run loop principal: o aviso chega na thread principal.
            MainActor.assumeIsolated { mac.atualizarBateria() }
        }, contexto)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), fonte, .commonModes)
        fonteDeEnergia = fonte
    }

    private func atualizarBateria() {
        let lida = Self.lerBateria()
        if lida != bateria { bateria = lida }
        let (aviso, memoria) = Bateria.decidir(lida, self.memoria)
        self.memoria = memoria
        if let aviso, let lida {
            mural.receber(aviso.atividade(porcento: lida.porcento))
            registro.info("mac: aviso de bateria")
        }
    }

    nonisolated private static func lerBateria() -> Bateria? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let fontes = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for fonte in fontes {
            guard let descricao = IOPSGetPowerSourceDescription(info, fonte)?.takeUnretainedValue() as? [String: Any],
                  descricao[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let atual = descricao[kIOPSCurrentCapacityKey] as? Int,
                  let maxima = descricao[kIOPSMaxCapacityKey] as? Int, maxima > 0 else { continue }
            return Bateria(porcento: min(max(atual * 100 / maxima, 0), 100),
                           carregando: descricao[kIOPSIsChargingKey] as? Bool ?? false,
                           ligadaNaTomada: descricao[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil  // Mac de mesa, ou só um nobreak (UPS) ligado
    }
}
