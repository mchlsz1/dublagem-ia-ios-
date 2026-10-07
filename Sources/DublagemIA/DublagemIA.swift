import SwiftUI
import AVFoundation

final class AudioManager: ObservableObject {
    @Published var isRecording = false

    private let audioEngine = AVAudioEngine()

    func requestPermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Permissão de microfone concedida")
                } else {
                    print("Permissão de microfone negada")
                }
            }
        }
    }

    func startAudioCapture() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format
        ) { buffer, _ in
            print("Áudio recebido: \(buffer.frameLength) frames")
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .record,
                mode: .measurement,
                options: []
            )

            try AVAudioSession.sharedInstance().setActive(true)

            try audioEngine.start()

            DispatchQueue.main.async {
                self.isRecording = true
            }

            print("Captura de áudio iniciada")
        } catch {
            print("Erro ao iniciar áudio: \(error)")
        }
    }

    func stopAudioCapture() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Erro ao desativar áudio: \(error)")
        }

        DispatchQueue.main.async {
            self.isRecording = false
        }

        print("Captura de áudio parada")
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
    @StateObject private var audioManager = AudioManager()

    var body: some View {
        VStack(spacing: 24) {
            Text("Dublagem IA")
                .font(.largeTitle)
                .bold()

            Text(
                audioManager.isRecording
                ? "Capturando áudio..."
                : "Pronto para testar"
            )
            .foregroundStyle(.secondary)

            Button("Permitir microfone") {
                audioManager.requestPermission()
            }
            .buttonStyle(.bordered)

            Button(
                audioManager.isRecording
                ? "Parar captura"
                : "Testar captura"
            ) {
                if audioManager.isRecording {
                    audioManager.stopAudioCapture()
                } else {
                    audioManager.startAudioCapture()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
