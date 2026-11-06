import SwiftUI
import CloudKit

struct SharingSheet: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
    let title: String
}
struct CloudSharingView: UIViewControllerRepresentable {
    let sheet: SharingSheet
    let onFinish: () -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: sheet.share, container: sheet.container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    @MainActor final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudSharingView
        init(_ parent: CloudSharingView) { self.parent = parent }
        func itemTitle(for csc: UICloudSharingController) -> String? { parent.sheet.title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { parent.onError(error.localizedDescription) }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { parent.onFinish() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { parent.onFinish() }
    }
}
