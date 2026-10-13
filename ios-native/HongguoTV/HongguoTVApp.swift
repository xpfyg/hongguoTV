import SwiftUI

@main
struct HongguoTVApp: App {
    @StateObject private var store = LocalStore()

    init() {
        URLProtocol.registerClass(AuthURLProtocol.self)
        Diagnostics.setupCrashCapture()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
