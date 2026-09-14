import SwiftUI
import UIKit
import NGAKit

/// Browse every NGA board by category and add one by tapping — no need to know the fid.
/// The full catalogue comes from NGA's static board index; the search box filters by name.
struct BoardCatalogView: View {
    let session: SessionStore
    let store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var sections: [BoardSection] = []
    @State private var loading = false
    @State private var error: String?
    @State private var rawSnippet = ""
    @State private var query = ""
    @State private var requestID = UUID()

    private var filtered: [BoardSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.compactMap { section in
            let matched = section.boards.filter { $0.name.lowercased().contains(q) }
            return matched.isEmpty ? nil : BoardSection(id: section.id, title: section.title, boards: matched)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && sections.isEmpty {
                    ProgressView("正在读取版块目录…").tint(AppTheme.brand)
                } else if let error, sections.isEmpty {
                    errorView(error)
                } else if sections.isEmpty {
                    ContentUnavailableView("没有版块", systemImage: "square.grid.2x2",
                                           description: Text("下拉刷新，或检查网络连接。"))
                } else {
                    catalogueList
                }
            }
            .navigationTitle("版块目录").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索版块名，如 艾泽拉斯")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .refreshable { await load() }
        }
        .presentationDetents([.large])
        .task { await load() }
    }

    private var catalogueList: some View {
        List {
            ForEach(filtered) { section in
                Section {
                    ForEach(section.boards) { board in
                        BoardCatalogRow(board: board, alreadyAdded: store.contains(board.id)) {
                            Task { @MainActor in _ = store.toggle(board) }
                        }
                    }
                } header: {
                    Text(section.title).textCase(nil).foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sceneCanvas()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(AppTheme.inkSoft)
            Text("版块目录暂时读取失败").font(.headline).foregroundStyle(AppTheme.ink)
            Text(message).font(.footnote).foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent).tint(AppTheme.brand)
            Text("可以先使用已经收藏的版面，稍后再刷新目录。")
                .font(.footnote).foregroundStyle(AppTheme.inkSoft).multilineTextAlignment(.center).padding(.horizontal, 32)
            if !rawSnippet.isEmpty {
                ScrollView {
                    Text(rawSnippet)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(AppTheme.inkSoft)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: 300)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
        }
    }

    @MainActor private func load() async {
        let token = UUID(); requestID = token
        loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            let host = session.host
            let cookie = await session.cookieHeader(for: host)
            let client = NGAClient(host: host)
            let raw = try await client.forumIndexRaw(cookie: cookie)
            let result = ForumIndex.parse(raw)
            guard !Task.isCancelled, token == requestID else { return }
            if result.isEmpty {
                rawSnippet = ForumIndex.summary(raw)
                error = "版块目录已获取，但未能识别为分类。"
            } else {
                sections = result
            }
        } catch {
            if !Task.isCancelled, token == requestID { self.error = session.network.describe(error) }
        }
    }
}

private struct BoardCatalogRow: View {
    let board: Board
    let alreadyAdded: Bool
    let onAdd: () -> Void
    var body: some View {
        Button(action: onAdd) {
            let color = AppTheme.starColor(for: board.id)
            let initial = board.name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "版"
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.16)).frame(width: 36, height: 36)
                    Text(initial).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(board.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink).lineLimit(1)
                }
                Spacer()
                Image(systemName: alreadyAdded ? "star.fill" : "star")
                    .font(.title2).foregroundStyle(alreadyAdded ? AppTheme.online : AppTheme.brand)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alreadyAdded ? "取消收藏版块" : "收藏版块")
        .listRowBackground(AppTheme.card)
    }
}
