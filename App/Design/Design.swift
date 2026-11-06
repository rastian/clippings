import SwiftUI
import LinkPresentation

enum Design {
    static let accent = Color("AccentColor")
    static let icons = ["folder", "fork.knife", "map", "bag", "book", "play.rectangle", "figure.2.and.child.holdinghands", "heart", "house", "sparkles", "leaf", "gift"]
}
struct CollectionBadge: View {
    let icon: String
    var body: some View {
        Image(systemName: icon.isEmpty ? "folder" : icon)
            .font(.title3).foregroundStyle(Design.accent)
            .frame(width: 44, height: 44).background(Design.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}
struct LinkRow: View {
    let item: Item
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CollectionBadge(icon: "link")
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(3)
                Text(item["domain"]).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(item.date, style: .date).font(.caption).foregroundStyle(.tertiary)
            }
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}
struct NativeLinkPreview: UIViewRepresentable {
    let metadata: LPLinkMetadata
    func makeUIView(context: Context) -> LPLinkView { LPLinkView(metadata: metadata) }
    func updateUIView(_ uiView: LPLinkView, context: Context) { uiView.metadata = metadata }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LPLinkView, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? 300, height: proposal.height ?? 360))
    }
}
