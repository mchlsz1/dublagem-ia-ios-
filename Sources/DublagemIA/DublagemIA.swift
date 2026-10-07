import SwiftUI
import AVFoundation
import AVFAudio
import Speech

final class SpeechManager: NSObject, ObservableObject {

    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var translatedText = ""

    private let audioEngine = AVAudioEngine()

    private let speechRecognizer =
        SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))

    private var recognitionRequest:
        SFSpeechAudioBufferRecognitionRequest?

    private var recognitionTask:
        SFSpeechRecognitionTask?

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Permissões

    func requestPermissions() {

        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    print("Reconhecimento autorizado")
                } else {
                    print("Reconhecimento não autorizado")
                }
            }
        }

        AVAudioSession.sharedInstance()
            .requestRecordPermission { granted in
                print("Microfone: \(granted)")
            }
    }

    // MARK: - Reconhecimento

    func startListening() {

        guard !isListening else {
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

                self?.recognitionRequest?
                    .append(buffer)
            }

            recognitionTask =
                speechRecognizer?.recognitionTask(
                    with: request
                ) { [weak self] result, error in

                    if let result = result {

                        DispatchQueue.main.async {

                            self?.recognizedText =
                                result.bestTranscription
                                .formattedString
                        }
                    }

                    if error != nil {
                        self?.stopListening()
                    }
                }

            audioEngine.prepare()

            try audioEngine.start()

            DispatchQueue.main.async {
                self.isListening = true
            }

        } catch {

            print("Erro ao iniciar áudio: \(error)")
        }
    }

    // MARK: - Parar

    func stopListening() {

        audioEngine.stop()

        audioEngine.inputNode
            .removeTap(onBus: 0)

        recognitionRequest?.endAudio()

        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        DispatchQueue.main.async {
            self.isListening = false
        }
    }

    // MARK: - Tradução

    func translate() {

        guard !recognizedText.isEmpty else {
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
            forHTTPHeaderField: "Content-Type"
        )

        let body = [
            "text": recognizedText
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
                    "Erro na API: " +
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

                    self?.translatedText =
                        response.translated
                }

            } catch {

                print(
                    "Erro ao interpretar resposta: \(error)"
                )
            }

        }.resume()
    }

    // MARK: - Voz em português

    func speakTranslation() {

        guard !translatedText.isEmpty else {
            return
        }

        synthesizer.stopSpeaking(
            at: .immediate
        )

        let utterance =
            AVSpeechUtterance(
                string: translatedText
            )

        utterance.voice =
            AVSpeechSynthesisVoice(
                language: "pt-BR"
            )

        utterance.rate = 0.5

        synthesizer.speak(utterance)
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

                Button("Autorizar") {

                    speechManager.requestPermissions()
                }
                .buttonStyle(.bordered)

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

                Button("Traduzir") {

                    speechManager.translate()
                }
                .buttonStyle(.bordered)

                Button("🔊 Ouvir tradução") {

                    speechManager.speakTranslation()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
