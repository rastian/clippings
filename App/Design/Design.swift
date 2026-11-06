import SwiftUI
import LinkPresentation

enum Design {
    static let accent = Color("AccentColor")
    static let paper = adaptive(light: 0xF5F0E5, dark: 0x191D19)
    static let card = adaptive(light: 0xFFFCF5, dark: 0x232923)
    static let ink = adaptive(light: 0x262D25, dark: 0xEDE8DC)
    static let secondaryInk = adaptive(light: 0x63685F, dark: 0xBAC1B3)
    static let rule = adaptive(light: 0xD7D7C8, dark: 0x444D41)
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let iconNames = ["folder": "Folder", "fork.knife": "Food", "map": "Places", "bag": "Shopping", "book": "Reading", "play.rectangle": "Videos", "figure.2.and.child.holdinghands": "Family activities", "heart": "Favourites", "house": "Home", "sparkles": "Ideas", "leaf": "Nature", "gift": "Gifts"]
    static let icons = ["folder", "fork.knife", "map", "bag", "book", "play.rectangle", "figure.2.and.child.holdinghands", "heart", "house", "sparkles", "leaf", "gift"]
}

struct NewspaperMasthead: View {
    var body: some View {
        VStack(spacing: 9) {
            Text("THE FAMILY EDITION").font(.caption2).tracking(2).foregroundStyle(Design.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Clippings").font(.system(.largeTitle, design: .serif, weight: .bold))
                Image(systemName: "asterisk").font(.title3.weight(.bold)).foregroundStyle(Design.accent).accessibilityHidden(true)
            }.foregroundStyle(Design.ink).accessibilityAddTraits(.isHeader)
            VStack(spacing: 2) { Rectangle().frame(height: 1); Rectangle().frame(height: 1) }.foregroundStyle(Design.ink)
            ViewThatFits(in: .horizontal) {
                HStack { editionDate; Spacer(minLength: 12); Text("GOOD FINDS, KEPT.") }
                editionDate
            }.font(.caption2).foregroundStyle(Design.secondaryInk)
            Rectangle().fill(Design.rule).frame(height: 1)
        }.padding(.top, 4).padding(.bottom, 10)
    }
    private var editionDate: some View { Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()) }
}

struct ClippingCard: View {
    @Environment(AppModel.self) private var model
    let item: Item
    var featured = true
    @State private var preview: ClippingPreview?
    private var headline: String { item.title == item["domain"] ? (preview?.title ?? item.title) : item.title }
    private var excerpt: String? { ArticleExcerpt.preview(item["summary"]) ?? preview?.excerpt }
    private var author: String {
        item["author"] == model.userID ? "You" : model.snapshot.zones[item.zone.key]?.libraryMembers.first { $0.id == item["author"] }?.name ?? "Family member"
    }
    private var collection: String? { model.snapshot.visible(.collection, zone: item.zone).first { $0.id == item["collection"] }?.title }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if featured, let image = preview?.image {
                GeometryReader { geometry in
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: 178).clipped()
                }.frame(height: 178).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { source; Spacer(minLength: 8); savedDate }
                    VStack(alignment: .leading, spacing: 4) { source; savedDate }
                }
                Text(headline).font(.system(featured ? .title2 : .headline, design: .serif, weight: .medium)).foregroundStyle(Design.ink).fixedSize(horizontal: false, vertical: true)
                if featured, let excerpt {
                    Text(excerpt).font(.system(.body, design: .serif)).foregroundStyle(Design.secondaryInk).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("clippingExcerpt")
                }
                Rectangle().fill(Design.rule).frame(height: 1)
                ViewThatFits(in: .horizontal) {
                    HStack { byline; Spacer(minLength: 8); collectionLabel }
                    VStack(alignment: .leading, spacing: 6) { byline; collectionLabel }
                }
            }.padding(16)
        }.background(Design.card, in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Design.rule, lineWidth: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .task(id: featured ? item["url"] : "") {
                preview = nil
                guard featured, !Configuration.isUITesting, let url = try? LinkRules.validatedURL(item["url"]) else { return }
                let result = await ClippingPreviewService.shared.preview(for: url)
                guard !Task.isCancelled else { return }
                preview = result
            }
    }
    private var source: some View { Text(item["domain"].uppercased()).font(.caption2.weight(.semibold)).tracking(0.7).foregroundStyle(Design.accent) }
    private var savedDate: some View { Text(item.date, style: .date).font(.caption2).foregroundStyle(Design.secondaryInk) }
    private var byline: some View { Label("Clipped by \(author)", systemImage: "person.crop.circle").font(.caption).foregroundStyle(Design.secondaryInk) }
    @ViewBuilder private var collectionLabel: some View {
        if let collection { Text(collection).font(.caption).foregroundStyle(Design.accent).padding(.horizontal, 7).padding(.vertical, 3).background(Design.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 3)) }
    }
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

struct ScrollableEmptyState<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content().frame(maxWidth: .infinity).frame(minHeight: max(0, geometry.size.height - 32))
                    .padding(.bottom, 32)
            }
        }
    }
}
