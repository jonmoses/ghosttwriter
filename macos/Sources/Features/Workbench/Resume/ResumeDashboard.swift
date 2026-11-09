import AppKit
import Combine
import SwiftUI

/// Closed records for the resume dashboard, filtered by a search query.
@MainActor
final class ResumeDashboardModel: ObservableObject {
    let store: WorkbenchStore
    @Published var query: String = ""
    private var storeChanges: AnyCancellable?

    init(store: WorkbenchStore) {
        self.store = store
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var rows: [SessionRecord] { store.closedRecords(matching: query) }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// "<repo or cwd basename> · d/t goals · <relative close time>", without goals when there are none.
    static func subtitle(_ r: SessionRecord, now: Date) -> String {
        var parts = [basename(r.repoRoot ?? r.cwd)]
        if !r.goals.isEmpty {
            parts.append("\(r.goals.filter(\.done).count)/\(r.goals.count) goals")
        }
        parts.append(relative.localizedString(for: r.closedAt ?? r.updatedAt, relativeTo: now))
        return parts.joined(separator: " · ")
    }

    static func title(_ r: SessionRecord) -> String {
        r.title.isEmpty ? basename(r.cwd) : r.title
    }

    static func notePreview(_ r: SessionRecord) -> String {
        r.note.split(separator: "\n", omittingEmptySubsequences: true).prefix(2).joined(separator: "\n")
    }

    private static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

/// The ⌘⌥R window listing closed sessions to resume.
@MainActor
final class ResumeDashboard: NSWindowController {
    private static var current: ResumeDashboard?

    private let model: ResumeDashboardModel
    private var resume: (SessionRecord) -> Void

    private init(store: WorkbenchStore, resume: @escaping (SessionRecord) -> Void) {
        model = ResumeDashboardModel(store: store)
        self.resume = resume
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Resume"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: ResumeDashboardView(
            model: model,
            onResume: { [weak self] r in self?.open(r) },
            onDelete: { [weak self] r in self?.delete(r) }))
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the single dashboard window, creating it on first use.
    static func show(store: WorkbenchStore, resume: @escaping (SessionRecord) -> Void) {
        let dashboard: ResumeDashboard
        if let current, current.model.store === store {
            dashboard = current
            dashboard.resume = resume
        } else {
            current?.close()
            dashboard = ResumeDashboard(store: store, resume: resume)
            current = dashboard
        }
        dashboard.showWindow(nil)
        dashboard.window?.makeKeyAndOrderFront(nil)
    }

    private func open(_ record: SessionRecord) {
        close()
        resume(record)
    }

    private func delete(_ record: SessionRecord) {
        do {
            try model.store.deleteRecord(record.id)
        } catch {
            NSSound.beep()
        }
    }
}

private struct ResumeDashboardView: View {
    @ObservedObject var model: ResumeDashboardModel
    let onResume: (SessionRecord) -> Void
    let onDelete: (SessionRecord) -> Void

    @State private var selection: UUID?

    var body: some View {
        let rows = model.rows
        VStack(spacing: 0) {
            TextField("Search title, folder, note or goals", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .onSubmit {
                    if let r = rows.first(where: { $0.id == selection }) ?? rows.first { onResume(r) }
                }

            if rows.isEmpty {
                Spacer()
                Text(model.query.isEmpty ? "No closed sessions" : "No matches")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                TimelineView(.everyMinute) { context in
                    List(rows, selection: $selection) { r in
                        ResumeRow(record: r, now: context.date)
                            .tag(r.id)
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        Button("Resume") { resume(ids) }
                        Button("Delete") { delete(ids) }
                    } primaryAction: { ids in
                        resume(ids)
                    }
                    .onDeleteCommand {
                        if let id = selection { delete([id]) }
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func resume(_ ids: Set<UUID>) {
        guard let id = ids.first, let r = model.rows.first(where: { $0.id == id }) else { return }
        onResume(r)
    }

    private func delete(_ ids: Set<UUID>) {
        for r in model.rows where ids.contains(r.id) { onDelete(r) }
        if let id = selection, ids.contains(id) { selection = nil }
    }
}

private struct ResumeRow: View {
    let record: SessionRecord
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(nsColor: ColorAllocator.nsColor(record.color)))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ResumeDashboardModel.title(record))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(ResumeDashboardModel.subtitle(record, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                let note = ResumeDashboardModel.notePreview(record)
                if !note.isEmpty {
                    Text(note)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
