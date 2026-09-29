import SwiftUI

@main
struct MYIEMApp: App {
    @StateObject private var receiver = AudioReceiver()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(receiver) }
    }
}
