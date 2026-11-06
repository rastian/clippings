import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = "Our family"
    @State private var creating = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "link.circle.fill").font(.system(size: 72)).foregroundStyle(Design.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Good finds.\nBetter together.").font(.largeTitle.bold())
                        Text("Your family’s corner of the internet.").font(.title3).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        Label("Keep recipes, places, and little discoveries in one place.", systemImage: "bookmark")
                        Label("Share privately with the people you choose, through iCloud.", systemImage: "person.2")
                        Label("No new account. No ads. Just your family.", systemImage: "lock.shield")
                    }.font(.body)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NAME YOUR LIBRARY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("Family library name", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("libraryName")
                        Button {
                            creating = true
                            Task { _ = await model.createLibrary(name); creating = false }
                        } label: { Text(creating ? "Creating…" : "Create a library").frame(maxWidth: .infinity).padding(.vertical, 7) }
                        .buttonStyle(.borderedProminent).disabled(creating || name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("createLibrary")
                        Text(model.cloud == nil ? "Start saving on this device. iCloud sharing is unavailable in this build." : model.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Have an invitation?").font(.headline)
                        Text("Open the iCloud invitation from your family in Messages or Mail. Clippings will help you join.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: 520).padding(28).frame(maxWidth: .infinity)
            }.navigationTitle("Clippings").navigationBarTitleDisplayMode(.inline)
        }
    }
}
