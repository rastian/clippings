import SwiftUI

@main
struct LinkinApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentUnavailableView("linkin", systemImage: "link", description: Text("Your family’s corner of the internet."))
                    .navigationTitle("Library")
            }.tint(.green)
        }
    }
}
