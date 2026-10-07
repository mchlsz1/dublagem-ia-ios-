import SwiftUI
import AVFoundation
import AVFAudio
import Speech

final class SpeechManager: NSObject, ObservableObject {

    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var translatedText = ""

    @Published var speechRate: Float = 0.50

    @Published var permissionsReady = false
    @Published var permissionMessage = "Permissões necessárias"

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

    private var translationWorkItem:
        DispatchWorkItem?

    // MARK: - Permissões

    func requestPermissions() {

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
                    self.permissionMessage =
                        "Permissão de reconhecimento negada. Ative em Ajustes."

                case .restricted:
                    self.permissionsReady = false
                    self.permissionMessage =
                        "Reconhecimento de fala está restrito neste iPhone."

                case .notDetermined:
                    self.permissionsReady = false
                    self.permissionMessage =
                        "Aguardando permissão de reconhecimento."

                @unknown default:
                    self.permissionsReady = false
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
                    self.permissionMessage =
                        "Tudo pronto para ouvir japonês."

                } else {

                    self.permissionsReady = false
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

            permissionMessage =
                "Autorize o reconhecimento e o microfone primeiro."

            return
        }

        guard speechRecognizer?.isAvailable == true else {

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

                            self.recognizedText = text

                            self.scheduleTranslation(text)
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
                self.permissionMessage =
                    "Ouvindo japonês..."
            }

        } catch {

            print(
                "Erro ao iniciar áudio: \(error)"
            )

            permissionMessage =
                "Não foi possível iniciar o microfone."

            stopListening()
        }
    }

    // MARK: - Tradução automática

    private func scheduleTranslation(
        _ text: String
    ) {

        translationWorkItem?.cancel()

        let workItem =
            DispatchWorkItem { [weak self] in
                self?.translate(text)
            }

        translationWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.0,
            execute: workItem
        )
    }

    // MARK: - Parar

    func stopListening() {

        translationWorkItem?.cancel()

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
                self.permissionMessage = "Pronto."
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

        guard let url = URL(
            string:
                "https://dublagem-ia-ios.vercel.app/api/translate"
        ) else {
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

            guard let data = data,
                  error == nil else {

                print(
                    "Erro API: " +
                    (error?.localizedDescription ??
                     "desconhecido")
                )

                return
            }

            do {

                let response =
                    try JSONDecoder().decode(
                        TranslationResponse.self,
                        from: data
                    )

                DispatchQueue.main.async {

                    guard let self = self else {
                        return
                    }

                    self.translatedText =
                        response.translated

                    self.speakTranslation()
                }

            } catch {

                print(
                    "Erro na tradução: \(error)"
                )
            }

        }.resume()
    }

    // MARK: - Voz

    private func speakTranslation() {

        guard !translatedText.isEmpty else {
            return
        }

        speak(text: translatedText)
    }

    // MARK: - Falar texto

    private func speak(text: String) {

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

        synthesizer.speak(
            utterance
        )
    }

    // MARK: - Teste de velocidade

    func testVoiceSpeed() {

        let text =
            "Este é um teste da velocidade da voz."

        recognizedText =
            "これは速度のテストです"

        translatedText =
            text

        speak(text: text)
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
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                .buttonStyle(.borderedProminent)
                .disabled(
                    !speechManager.permissionsReady
                    && !speechManager.isListening
                )

                // MARK: - Testar velocidade

                Button("🔊 Testar velocidade") {

                    speechManager.testVoiceSpeed()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
