import AppKit
import SwiftUI

/// The tab's stack of inline snapshot cards, bottom-aligned over the terminal.
struct SnapshotCardView: View {
    @ObservedObject var model: SidePaneModel

    init(model: SidePaneModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer(minLength: 0)
            ForEach(model.cards.reversed()) { card in
                SnapshotCard(card: card, model: model)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

private struct SnapshotCard: View {
    let card: SnapshotCardItem
    @ObservedObject var model: SidePaneModel
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = NSImage(contentsOf: card.png) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text(card.source.lastPathComponent)
                        .padding(12)
                }
            }
            .frame(maxHeight: 600)
            .contentShape(Rectangle())
            .onTapGesture { model.open(card.source) }

            Button {
                model.dismissCard(card.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("Dismiss")
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .shadow(radius: 4)
        .focusable()
        .focused($focused)
        .onKeyPress(.escape) {
            model.dismissCard(card.id)
            return .handled
        }
    }
}
