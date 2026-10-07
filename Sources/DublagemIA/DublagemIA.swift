import SwiftUI
import AVFoundation
import AVFAudio
import Speech

final class SpeechManager: NSObject, ObservableObject {

    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var translatedText = ""

    @Published var speechRate: Float = 0.50
    @Published var speechVolume: Float = 1.00

    @Published var permissionsReady = false
    @Published var permissionMessage = "Permissões necessárias"

    // MARK: - Status da dublagem

    @Published var dubbingStatus = "Aguardando"

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    private let speechRecognizer =
        SFSpeechRecognizer(
            locale: Locale(identifier: "ja-JP")
        )

    private var recognitionRequest:
        SFSpeechAudioBufferRecognitionRequest?

    private var recognitionTask:
        SFSpeechRecognitionTask?

    // MARK: - Inicialização

    override init() {
        super.init()

        synthesizer.delegate = self
    }

    // MARK: - Permissões

    func requestPermissions() {

        dubbingStatus = "Solicitando permissões..."

        SFSpeechRecognizer.requestAuthorization {
            [weak self] status in

            DispatchQueue.main.async {

                guard let self = self else {
                    return
                }

                switch status {

                case .authorized:

                    self.requestMicrophonePermission()

                case .denied:

                    self.permissionsReady = false
                    self.dubbingStatus = "Permissão negada"
                    self.permissionMessage =
                        "Permissão de reconhecimento negada. Ative em Ajustes."

                case .restricted:

                    self.permissionsReady = false
                    self.dubbingStatus = "Reconhecimento restrito"
                    self.permissionMessage =
                        "Reconhecimento de fala está restrito neste iPhone."

                case .notDetermined:

                    self.permissionsReady = false
                    self.dubbingStatus = "Aguardando permissão"
                    self.permissionMessage =
                        "Aguardando permissão de reconhecimento."

                @unknown default:

                    self.permissionsReady = false
                    self.dubbingStatus = "Erro"
                    self.permissionMessage =
                        "Não foi possível verificar a permissão."
                }
            }
        }
    }

    private func requestMicrophonePermission() {

        AVAudioApplication.requestRecordPermission {
            [weak self] granted in

            DispatchQueue.main.async {

                guard let self = self else {
                    return
                }

                if granted {

                    self.permissionsReady = true
                    self.dubbingStatus = "Pronto"
                    self.permissionMessage =
                        "Tudo pronto para ouvir japonês."

                } else {

                    self.permissionsReady = false
                    self.dubbingStatus = "Microfone negado"
                    self.permissionMessage =
                        "Permissão do microfone negada. Ative em Ajustes."
                }
            }
        }
    }

    // MARK: - Reconhecimento

    func startListening() {

        guard !isListening else {
            return
        }

        guard permissionsReady else {

            dubbingStatus = "Permissões necessárias"

            permissionMessage =
                "Autorize o reconhecimento e o microfone primeiro."

            return
        }

        guard speechRecognizer?.isAvailable == true else {

            dubbingStatus = "Reconhecimento indisponível"

            permissionMessage =
                "O reconhecimento de japonês não está disponível agora."

            return
        }

        recognitionTask?.cancel()

        let request =
            SFSpeechAudioBufferRecognitionRequest()

        request.shouldReportPartialResults = true

        recognitionRequest = request

        let session =
            AVAudioSession.sharedInstance()

        do {

            try session.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers]
            )

            try session.setActive(true)

            let inputNode =
                audioEngine.inputNode

            let format =
                inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: format
            ) { [weak self] buffer, _ in

                self?.recognitionRequest?.append(buffer)
            }

            recognitionTask =
                speechRecognizer?.recognitionTask(
                    with: request
                ) { [weak self] result, error in

                    guard let self = self else {
                        return
                    }

                    if let result = result {

                        let text =
                            result.bestTranscription
                                .formattedString

                        DispatchQueue.main.async {

                            self.recognizedText =
                                text

                            if !text.isEmpty {

                                self.dubbingStatus =
                                    "🎙️ Ouvindo"
                            }

                            // Traduz somente quando
                            // a frase estiver finalizada.
                            if result.isFinal {

                                self.dubbingStatus =
                                    "🌐 Traduzindo"

                                self.translate(text)
                            }
                        }
                    }

                    if error != nil {

                        DispatchQueue.main.async {

                            self.stopListening()
                        }
                    }
                }

            audioEngine.prepare()

            try audioEngine.start()

            DispatchQueue.main.async {

                self.isListening = true

                self.dubbingStatus =
                    "🎙️ Ouvindo"

                self.permissionMessage =
                    "Ouvindo japonês..."
            }

        } catch {

            print(
                "Erro ao iniciar áudio: \(error)"
            )

            permissionMessage =
                "Não foi possível iniciar o microfone."

            dubbingStatus =
                "Erro no áudio"

            stopListening()
        }
    }

    // MARK: - Parar reconhecimento

    func stopListening() {

        audioEngine.stop()

        audioEngine.inputNode.removeTap(
            onBus: 0
        )

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        DispatchQueue.main.async {

            self.isListening = false

            if self.permissionsReady {

                self.dubbingStatus =
                    "Pronto"

                self.permissionMessage =
                    "Pronto."
            }
        }
    }

    // MARK: - Tradução

    private func translate(
        _ text: String
    ) {

        guard !text.isEmpty else {
            return
        }

        DispatchQueue.main.async {

            self.dubbingStatus =
                "🌐 Traduzindo"
        }

        guard let url = URL(
            string:
                "https://dublagem-ia-ios.vercel.app/api/translate"
        ) else {

            DispatchQueue.main.async {

                self.dubbingStatus =
                    "Erro na tradução"
            }

            return
        }

        var request =
            URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )

        let body = [
            "text": text
        ]

        request.httpBody =
            try? JSONSerialization.data(
                withJSONObject: body
            )

        URLSession.shared.dataTask(
            with: request
        ) { [weak self] data, _, error in

            guard let self = self else {
                return
            }

            guard let data = data,
                  error == nil else {

                print(
                    "Erro API: " +
                    (error?.localizedDescription ??
                     "desconhecido")
                )

                DispatchQueue.main.async {

                    self.dubbingStatus =
                        "Erro na tradução"
                }

                return
            }

            do {

                let response =
                    try JSONDecoder().decode(
                        TranslationResponse.self,
                        from: data
                    )

                DispatchQueue.main.async {

                    self.translatedText =
                        response.translated

                    self.dubbingStatus =
                        "🔊 Falando"

                    self.speakTranslation()
                }

            } catch {

                print(
                    "Erro na tradução: \(error)"
                )

                DispatchQueue.main.async {

                    self.dubbingStatus =
                        "Erro na tradução"
                }
            }

        }.resume()
    }

    // MARK: - Falar tradução

    private func speakTranslation() {

        guard !translatedText.isEmpty else {
            return
        }

        speak(text: translatedText)
    }

    // MARK: - Voz

    private func speak(text: String) {

        guard !text.isEmpty else {
            return
        }

        synthesizer.stopSpeaking(
            at: .immediate
        )

        let utterance =
            AVSpeechUtterance(
                string: text
            )

        utterance.voice =
            AVSpeechSynthesisVoice(
                language: "pt-BR"
            )

        utterance.rate =
            speechRate

        utterance.volume =
            speechVolume

        dubbingStatus =
            "🔊 Falando"

        synthesizer.speak(
            utterance
        )
    }

    // MARK: - Parar voz

    func stopVoice() {

        synthesizer.stopSpeaking(
            at: .immediate
        )

        DispatchQueue.main.async {

            self.dubbingStatus =
                self.permissionsReady
                ? "Pronto"
                : "Aguardando"
        }
    }

    // MARK: - Teste de velocidade e volume

    func testVoiceSpeed() {

        let text =
            "Este é um teste da velocidade e do volume da voz."

        recognizedText =
            "これは速度と音量のテストです"

        translatedText =
            text

        dubbingStatus =
            "🔊 Falando"

        speak(text: text)
    }
}

// MARK: - Delegate da voz

extension SpeechManager:
    AVSpeechSynthesizerDelegate {

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {

        DispatchQueue.main.async {

            self.dubbingStatus =
                "🔊 Falando"
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {

        DispatchQueue.main.async {

            self.dubbingStatus =
                "Pronto"
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {

        DispatchQueue.main.async {

            self.dubbingStatus =
                self.permissionsReady
                ? "Pronto"
                : "Aguardando"
        }
    }
}

// MARK: - Resposta da API

struct TranslationResponse: Codable {

    let original: String
    let translated: String
}

// MARK: - Aplicativo

@main
struct DublagemIAApp: App {

    var body: some Scene {

        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Interface

struct ContentView: View {

    @StateObject private var speechManager =
        SpeechManager()

    var body: some View {

        ScrollView {

            VStack(spacing: 18) {

                Text("Dublagem IA")
                    .font(.largeTitle)
                    .bold()

                // MARK: - Status

                VStack(spacing: 8) {

                    Text("Status da dublagem")
                        .font(.headline)

                    Text(
                        speechManager.dubbingStatus
                    )
                    .font(.title3)
                    .bold()

                }
                .frame(
                    maxWidth: .infinity
                )
                .padding()
                .background(
                    .gray.opacity(0.15)
                )
                .cornerRadius(12)

                // MARK: - Japonês

                Text("Japonês")
                    .font(.headline)

                Text(
                    speechManager.recognizedText.isEmpty
                    ? "Nenhum texto reconhecido"
                    : speechManager.recognizedText
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding()
                .background(
                    .gray.opacity(0.15)
                )
                .cornerRadius(12)

                // MARK: - Português

                Text("Português")
                    .font(.headline)

                Text(
                    speechManager.translatedText.isEmpty
                    ? "A tradução aparecerá aqui"
                    : speechManager.translatedText
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding()
                .background(
                    .gray.opacity(0.15)
                )
                .cornerRadius(12)

                // MARK: - Permissões

                VStack(spacing: 8) {

                    Image(
                        systemName:
                            speechManager.permissionsReady
                            ? "checkmark.circle.fill"
                            : "lock.circle"
                    )
                    .font(.title2)

                    Text(
                        speechManager.permissionMessage
                    )
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding()
                .background(
                    .gray.opacity(0.15)
                )
                .cornerRadius(12)

                // MARK: - Velocidade

                VStack(spacing: 8) {

                    HStack {

                        Text("🐢")

                        Text("Velocidade da voz")
                            .font(.headline)

                        Spacer()

                        Text(
                            String(
                                format: "%.2fx",
                                speechManager.speechRate / 0.5
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Slider(
                        value:
                            $speechManager.speechRate,
                        in: 0.30...0.80,
                        step: 0.05
                    )

                    HStack {

                        Text("Lenta")
                            .font(.caption)

                        Spacer()

                        Text("Normal")
                            .font(.caption)

                        Spacer()

                        Text("Rápida")
                            .font(.caption)
                    }
                    .foregroundStyle(
                        .secondary
                    )
                }
                .padding()
                .background(
                    .gray.opacity(0.15)
                )
                .cornerRadius(12)

                // MARK: - Volume

                VStack(spacing: 8) {

                    HStack {

                        Text("🔊")

                        Text("Volume da voz")
                            .font(.headline)

                        Spacer()

                        Text(
                            "\(Int(speechManager.speechVolume * 100))%"
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Slider(
                        value:
                            $speechManager.speechVolume,
                        in: 0.0...1.0,
                        step: 0.05
                    )

                    HStack {

                        Text("0%")
                            .font(.caption)

                        Spacer()

                        Text("50%")
                            .font(.caption)

                        Spacer()

                        Text("100%")
                            .font(.caption)
                    }
                    .foregroundStyle(
                        .secondary
                    )
                }
                .padding()
                .background(
                    .gray.opacity(0.15)
                )
                .cornerRadius(12)

                // MARK: - Autorizar

                Button("Autorizar permissões") {

                    speechManager.requestPermissions()
                }
                .buttonStyle(.bordered)

                // MARK: - Ouvir

                Button(
                    speechManager.isListening
                    ? "Parar"
                    : "Ouvir japonês"
                ) {

                    if speechManager.isListening {

                        speechManager.stopListening()

                    } else {

                        speechManager.startListening()
                    }
                }
                .buttonStyle(
                    .borderedProminent
                )
                .disabled(
                    !speechManager.permissionsReady
                    && !speechManager.isListening
                )

                // MARK: - Teste

                Button("🔊 Testar voz") {

                    speechManager.testVoiceSpeed()
                }
                .buttonStyle(
                    .borderedProminent
                )

                // MARK: - Parar voz

                Button("⏹️ Parar voz") {

                    speechManager.stopVoice()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}
