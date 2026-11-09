import SwiftUI

/// Asks what is still to finish before a tab with an active session closes.
struct CloseSheet: View {
    let record: SessionRecord
    let onSave: (String) -> Void
    let onDiscard: () -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(record: SessionRecord,
         onSave: @escaping (String) -> Void,
         onDiscard: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.record = record
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.onCancel = onCancel
        _text = State(initialValue: WorkbenchStore.autoNote(record))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Still to finish?")
                    .font(.headline)
                Text(record.title.isEmpty ? (record.cwd as NSString).lastPathComponent : record.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(record.cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor))
                )

            HStack {
                Button("Close without saving") { onDiscard() }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Close & save") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
