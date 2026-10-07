import SwiftUI
import AVFoundation
import Speech

final class SpeechManager: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var recognizedText = ""

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    print("Reconhecimento de fala autorizado")
                } else {
                    print("Reconhecimento de fala não autorizado")
                }
            }
        }
    }

    func startListening() {
        guard !isListening else { return }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers]
            )

            try audioSession.setActive(
                true,
                options: .notifyOthersOnDeactivation
            )

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: recordingFormat
            ) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            recognitionTask = speechRecognizer?.recognitionTask(
                with: request
            ) { [weak self] result, error in

                if let result = result {
                    DispatchQueue.main.async {
                        self?.recognizedText = result.bestTranscription.formattedString
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
            print("Erro ao iniciar reconhecimento: \(error)")
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        DispatchQueue.main.async {
            self.isListening = false
        }
    }
}

@main
struct DublagemIAApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var speechManager = SpeechManager()

    var body: some View {
        VStack(spacing: 20) {

            Text("Dublagem IA")
                .font(.largeTitle)
                .bold()

            Text(
                speechManager.isListening
                ? "Ouvindo japonês..."
                : "Pronto para testar"
            )
            .foregroundStyle(.secondary)

            ScrollView {
                Text(
                    speechManager.recognizedText.isEmpty
                    ? "O texto reconhecido aparecerá aqui."
                    : speechManager.recognizedText
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(maxHeight: 250)

            Button("Autorizar reconhecimento") {
                speechManager.requestPermissions()
            }
            .buttonStyle(.bordered)

            Button(
                speechManager.isListening
                ? "Parar"
                : "Começar reconhecimento"
            ) {
                if speechManager.isListening {
                    speechManager.stopListening()
                } else {
                    speechManager.startListening()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
