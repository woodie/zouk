import SwiftUI
import ZoukKit

@main
struct ZoukApp: App {
    var body: some Scene {
        WindowGroup("zouk") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
