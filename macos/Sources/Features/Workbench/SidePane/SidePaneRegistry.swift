import Foundation

/// Finds the side pane model of the tab that owns a given surface.
@MainActor
final class SidePaneRegistry {
    static let shared = SidePaneRegistry()

    private struct Entry {
        weak var model: SidePaneModel?
        let owns: @MainActor (UUID) -> Bool
    }

    private var entries: [Entry] = []

    /// Registers `model`; `owns` answers whether a surface id belongs to its tab.
    /// Registering the same model again replaces its `owns` closure.
    func register(_ model: SidePaneModel, owns: @escaping @MainActor (UUID) -> Bool) {
        unregister(model)
        entries.append(Entry(model: model, owns: owns))
    }

    func unregister(_ model: SidePaneModel) {
        entries.removeAll { $0.model == nil || $0.model === model }
    }

    func model(for surface: UUID) -> SidePaneModel? {
        for entry in entries {
            if let model = entry.model, entry.owns(surface) { return model }
        }
        return nil
    }
}
