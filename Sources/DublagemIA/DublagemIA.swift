import SwiftUI

@main
struct DublagemIAApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Dublagem IA")
                .font(.largeTitle)
                .bold()

            Text("Projeto inicial")
                .foregroundStyle(.secondary)

            Button("Testar") {
                print("Dublagem IA ativada")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
