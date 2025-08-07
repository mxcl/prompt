import SwiftUI

@main
struct PromptApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    init() {
        print(Provider().json)
    }
}
