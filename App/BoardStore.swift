import Foundation
import Observation
import NGAKit

/// The user's locally saved board entries. Observable so the board list and the catalogue stay
/// in sync when a board is added or removed.
@MainActor @Observable final class BoardStore {
    var boards: [Board]
    private let key = "nga.boards"

    init() {
        if let data = UserDefaults.standard.data(forKey: "nga.boards"),
           let saved = try? JSONDecoder().decode([Board].self, from: data) {
            // Earlier prototypes allowed arbitrary numeric entries. Remove known
            // directory headings that cannot serve a topic list.
            let directoryOnlyNames: Set<String> = [
                "魔兽世界", "职业讨论区", "冒险心得", "历史背景 资料整理"
            ]
            boards = saved.filter { !directoryOnlyNames.contains($0.name) }
        } else {
            boards = []
        }
        // The first prototype silently seeded these two boards. They are not
        // user favourites, so remove them once from existing installations.
        let legacySeedMigration = "nga.migration.remove-legacy-seed-boards.v1"
        if !UserDefaults.standard.bool(forKey: legacySeedMigration) {
            boards.removeAll { [414, -547859].contains($0.id) }
            UserDefaults.standard.set(true, forKey: legacySeedMigration)
        }
        persist()
    }

    func contains(_ id: Int) -> Bool { boards.contains { $0.id == id } }
    func add(_ board: Board) -> Bool {
        guard !contains(board.id), board.id != 0 else { return false }
        boards.append(board); persist(); return true
    }
    @discardableResult func remove(id: Int) -> Bool {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return false }
        boards.remove(at: index); persist(); return true
    }
    /// Returns the new favourite state.
    @discardableResult func toggle(_ board: Board) -> Bool {
        if contains(board.id) { remove(id: board.id); return false }
        return add(board)
    }
    func remove(at offsets: IndexSet) { boards.remove(atOffsets: offsets); persist() }

    func replace(with remoteBoards: [Board]) {
        var seen = Set<Int>()
        let revised = remoteBoards.filter { $0.id != 0 && seen.insert($0.id).inserted }
        guard revised != boards else { return }
        boards = revised
        persist()
    }

    /// Drop entries created by the old manual-number flow and refresh saved
    /// names from the real catalogue. A valid favourite must correspond to a
    /// concrete leaf board returned by NGA.
    /// Refresh saved names from the real catalogue, but never drop a user's favourite just
    /// because it is missing from the (incomplete) static index or its name differs slightly.
    func reconcile(with catalogue: [Board]) {
        let canonical = Dictionary(catalogue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let revised = boards.map { saved -> Board in
            canonical[saved.id] ?? saved
        }
        guard revised != boards else { return }
        boards = revised
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(boards) { UserDefaults.standard.set(data, forKey: key) }
    }
}
