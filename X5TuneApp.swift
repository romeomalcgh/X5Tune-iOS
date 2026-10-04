import SwiftUI

@main
struct X5TuneApp: App {
    @StateObject private var ble = BLEManager()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(ble).preferredColorScheme(.dark) }
    }
}
