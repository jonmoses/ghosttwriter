import SwiftUI
import WorkbenchProtocol

/// Asks the goals panel's add field to take focus (⌘⌥G).
@MainActor
final class WorkbenchFocus: ObservableObject {
    static let shared = WorkbenchFocus()
    @Published var goalFieldRequested: Int = 0
}

/// The focused surface's goal checklist, note and goal log.
struct GoalsPanel: View {
    @ObservedObject private var store: WorkbenchStore
    @ObservedObject private var focus = WorkbenchFocus.shared
    private let surface: UUID?

    @State private var newGoal = ""
    @State private var noteDraft = ""
    @State private var logExpanded = false
    @FocusState private var addFieldFocused: Bool
    @FocusState private var noteFocused: Bool

    init(store: WorkbenchStore, surface: UUID?) {
        self.store = store
        self.surface = surface
    }

    private var record: SessionRecord? {
        surface.flatMap { store.surfaceRecord[$0] }.flatMap { store.records[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goals").font(.headline)
            if let surface {
                checklist(surface)
                TextField("Add goal", text: $newGoal)
                    .textFieldStyle(.roundedBorder)
                    .focused($addFieldFocused)
                    .onSubmit { addGoal(surface) }
                TextField("Note", text: $noteDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($noteFocused)
                    .onSubmit { saveNote(surface) }
                    .onChange(of: noteFocused) { _, focused in if !focused { saveNote(surface) } }
                DisclosureGroup("Log", isExpanded: $logExpanded) {
                    if logExpanded { log }
                }
                .font(.caption)
            } else {
                Text("No tab selected").foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(8)
        .onAppear(perform: loadNote)
        .onChange(of: surface) { old, _ in
            if let old { saveNote(old) }
            loadNote()
        }
        .onChange(of: record?.note) { _, _ in if !noteFocused { loadNote() } }
        .onChange(of: focus.goalFieldRequested) { _, _ in addFieldFocused = true }
    }

    @ViewBuilder
    private func checklist(_ surface: UUID) -> some View {
        let goals = record?.goals ?? []
        ForEach(Array(goals.enumerated()), id: \.element.id) { offset, goal in
            HStack(spacing: 4) {
                Toggle(isOn: Binding(
                    get: { goal.done },
                    set: { done in
                        try? store.setGoal(surface: surface, index: offset + 1, done: done, author: .user)
                    }
                )) {
                    Text(goal.text).strikethrough(goal.done).lineLimit(2)
                }
                .toggleStyle(.checkbox)
                Spacer(minLength: 0)
                if goal.author == .claude {
                    Text("C")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .help("Added by Claude")
                }
            }
            .contextMenu {
                Button("Remove Goal", role: .destructive) {
                    try? store.removeGoal(surface: surface, index: offset + 1, author: .user)
                }
            }
            .swipeActions {
                Button("Remove", role: .destructive) {
                    try? store.removeGoal(surface: surface, index: offset + 1, author: .user)
                }
            }
        }
    }

    @ViewBuilder
    private var log: some View {
        let events = record.flatMap { try? store.events(record: $0.id) } ?? []
        if events.isEmpty {
            Text("No entries").foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(events.reversed()) { e in
                        Text("\(Self.time.string(from: e.at)) \(e.kind.rawValue) \(e.text) (\(e.author.rawValue))")
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func addGoal(_ surface: UUID) {
        let text = newGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if (try? store.addGoal(surface: surface, text: text, author: .user)) != nil { newGoal = "" }
    }

    private func loadNote() {
        noteDraft = record?.note ?? ""
    }

    private func saveNote(_ surface: UUID) {
        guard store.liveSurfaces[surface] != nil else { return }
        let stored = store.surfaceRecord[surface].flatMap { store.records[$0] }?.note ?? ""
        guard noteDraft != stored else { return }
        try? store.setNote(surface: surface, text: noteDraft)
    }
}
