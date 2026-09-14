import SwiftUI
import NGAKit

/// 版块 (社区): a capsule row of categories and a grid of board glass cards.
/// Tapping a card opens its topics; the star adds it to the home favourites.
struct CommunityView: View {
    let session: SessionStore
    let store: BoardStore
    @Binding var tabBarVisibility: Visibility
    @State private var sections: [BoardSection] = []
    @State private var selected = 0
    @State private var selectedGroup = 0
    @State private var showingOrder = false
    @State private var showingAccount = false
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""
    @State private var requestID = UUID()
    @State private var treeDump = ""
    @State private var rawIndex = ""
    @State private var loadedRevision = -1
    private let columns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]
    private let indexCacheKey = "nga.community.forum-index.v1"

    private var filtered: [BoardSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.compactMap { s in
            let matched = s.boards.filter { $0.name.lowercased().contains(q) }
            return matched.isEmpty ? nil : BoardSection(id: s.id, title: s.title, boards: matched)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            communityRootHeader
            Group {
                if !treeDump.isEmpty {
                    ScrollView {
                        Text(treeDump).font(.system(.caption2, design: .monospaced)).foregroundStyle(AppTheme.inkSoft)
                            .textSelection(.enabled).padding(AppTheme.pad).frame(maxWidth: .infinity, alignment: .leading)
                    }.sceneCanvas()
                } else if loading && sections.isEmpty {
                    ProgressView("正在载入版块…").tint(AppTheme.brand)
                } else if let error, sections.isEmpty {
                    errorView(error)
                } else if sections.isEmpty {
                    ContentUnavailableView("没有版块", systemImage: "square.grid.2x2",
                                           description: Text("下拉刷新，或检查网络连接。"))
                } else {
                    content
                }
            }
        }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .sheet(isPresented: $showingAccount) { AccountView(session: session) }
            .sheet(isPresented: $showingOrder) {
                BoardSectionOrderView(sections: sections) { reordered in
                    let selectedID = sections.indices.contains(selected) ? sections[selected].id : nil
                    sections = reordered
                    selected = selectedID.flatMap { id in reordered.firstIndex(where: { $0.id == id }) } ?? 0
                    selectedGroup = 0
                    UserDefaults.standard.set(reordered.map(\.id), forKey: "nga.community.section-order")
                }
            }
            .task(id: session.revision) {
                if sections.isEmpty,
                   let cached = UserDefaults.standard.string(forKey: indexCacheKey) {
                    applyIndex(cached)
                }
                // Returning to this tab must not re-fetch and re-parse the whole index:
                // the parse runs on the main actor and would compete with the pop
                // transition for frames. Only a session change or an empty state reloads.
                guard sections.isEmpty || loadedRevision != session.revision else { return }
                await load()
            }
            .animation(nil, value: sections)
            .animation(nil, value: selected)
            .onAppear { if ProcessInfo.processInfo.arguments.contains("--dsh-tree") { Task { await dumpTree() } } }
    }

    private var communityRootHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Text("版块").font(.headline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                HStack {
                    Spacer()
                    Button { showingAccount = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(url: session.accountProfile?.avatar,
                                       name: session.accountProfile?.name ?? "账户", size: 32)
                            Circle()
                                .fill(session.isLoggedIn ? AppTheme.online : AppTheme.alert)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(AppTheme.page, lineWidth: 1.5))
                        }
                        .frame(width: 44, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.isLoggedIn ? "账户与连接，已登录" : "账户与连接，未登录")
                }
            }
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.inkSoft)
                TextField("搜索版块名", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .font(.subheadline)
            .padding(.horizontal, 13).frame(height: 38)
            .background(AppTheme.cardSoft.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, AppTheme.pad).padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @MainActor private func dumpTree() async {
        do {
            let client = NGAClient(host: session.host)
            let raw = try await client.forumIndexRaw(cookie: await session.cookieHeader(for: session.host))
            treeDump = ForumIndex.tree(raw)
        } catch { treeDump = "err: \(error)" }
    }

    private var content: some View {
        let list = filtered
        return Group {
            if list.isEmpty {
                ContentUnavailableView("没有匹配的版块", systemImage: "magnifyingglass",
                                       description: Text("换个关键词再试试。")).sceneCanvas()
            } else {
                let idx = clamped(list)
                let grouped = groups(for: list[idx])
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        categoryNavigation(list, selected: idx)
                        if !grouped.isEmpty { subcategoryPills(grouped) }
                    }
                    .padding(.horizontal, AppTheme.pad)
                    .padding(.top, 8).padding(.bottom, 10)
                    .background(.ultraThinMaterial)

                    ScrollView {
                        boardGrid(section: list[idx], grouped: grouped)
                            .padding(.horizontal, AppTheme.pad)
                            .padding(.top, 16)
                            .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                }
                .sceneCanvas()
            }
        }
    }

    private func clamped(_ list: [BoardSection]) -> Int {
        list.isEmpty ? 0 : min(selected, list.count - 1)
    }

    private func categoryNavigation(_ list: [BoardSection], selected: Int) -> some View {
        HStack(spacing: 10) {
            categoryPills(list, selected: selected)
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { showingOrder = true } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.bold)).foregroundStyle(AppTheme.brand)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(AppTheme.glassStroke))
                }
                .buttonStyle(.plain).accessibilityLabel("调整版块分类顺序")
            }
        }
    }

    private func categoryPills(_ list: [BoardSection], selected: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                    Button { self.selected = i; selectedGroup = 0 } label: {
                        Text(s.title)
                            .font(.subheadline.weight(i == selected ? .bold : .medium))
                            .foregroundStyle(i == selected ? .white : AppTheme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(
                                i == selected ? AnyShapeStyle(AppTheme.brand) : AnyShapeStyle(AppTheme.glassFill),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(AppTheme.glassStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func subcategoryPills(_ groups: [BoardSection]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    Button { selectedGroup = index } label: {
                        VStack(spacing: 7) {
                            Text(group.title)
                                .font(.subheadline.weight(index == clampedGroup(groups) ? .bold : .medium))
                                .foregroundStyle(index == clampedGroup(groups) ? AppTheme.forumAccent : AppTheme.inkSoft)
                                .lineLimit(1)
                            Capsule()
                                .fill(index == clampedGroup(groups) ? AppTheme.forumAccent : .clear)
                                .frame(height: 3)
                        }
                        .padding(.horizontal, 12).padding(.top, 5)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func clampedGroup(_ groups: [BoardSection]) -> Int {
        groups.isEmpty ? 0 : min(selectedGroup, groups.count - 1)
    }

    private func boardGrid(section: BoardSection, grouped: [BoardSection]) -> some View {
        let boards = grouped.isEmpty ? section.boards : grouped[clampedGroup(grouped)].boards
        return LazyVGrid(columns: columns, spacing: 11) {
            ForEach(boards) { board in
                boardRow(board)
            }
        }
    }

    private func groups(for section: BoardSection) -> [BoardSection] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard !rawIndex.isEmpty, let hubID = section.id.split(separator: ".").last.map(String.init) else { return [] }
        let result = ForumIndex.hubSections(rawIndex, hubID: hubID)
        return result.count > 1 ? result : []
    }

    private func boardRow(_ board: Board) -> some View {
        CommunityBoardRow(board: board, session: session, store: store, tabBarVisibility: $tabBarVisibility, alreadyAdded: store.contains(board.id)) {
            toggleFavorite(board)
        }
    }

    private func toggleFavorite(_ board: Board) {
        let added = store.toggle(board)
        // Mirror the local bookmark to the official NGA account so the favourite is real.
        Task { try? await session.favoriteBoard(fid: board.id, add: added) }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(AppTheme.inkSoft)
            Text("版块暂时读取失败").font(.headline).foregroundStyle(AppTheme.ink)
            Text(message).font(.footnote).foregroundStyle(AppTheme.inkSoft).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent).tint(AppTheme.brand)
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
            if result.isEmpty { error = "版块目录已获取，但未能识别为分类。" }
            else {
                applyIndex(raw)
                loadedRevision = session.revision
                UserDefaults.standard.set(raw, forKey: indexCacheKey)
            }
        } catch {
            if !Task.isCancelled, token == requestID { self.error = session.network.describe(error) }
        }
    }

    @MainActor private func applyIndex(_ raw: String) {
        let result = ForumIndex.parse(raw)
        guard !result.isEmpty else { return }
        rawIndex = raw
        let saved = UserDefaults.standard.stringArray(forKey: "nga.community.section-order") ?? []
        let positions = Dictionary(uniqueKeysWithValues: saved.enumerated().map { ($0.element, $0.offset) })
        sections = result.enumerated().sorted { lhs, rhs in
            let left = positions[lhs.element.id] ?? (saved.count + lhs.offset)
            let right = positions[rhs.element.id] ?? (saved.count + rhs.offset)
            return left < right
        }.map(\.element)
        store.reconcile(with: result.flatMap(\.boards))
    }
}

private struct BoardSectionOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [BoardSection]
    let onSave: ([BoardSection]) -> Void

    init(sections: [BoardSection], onSave: @escaping ([BoardSection]) -> Void) {
        _draft = State(initialValue: sections)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(draft) { section in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(AppTheme.inkSoft)
                        Text(section.title).foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(section.boards.count)").font(.caption.monospacedDigit()).foregroundStyle(AppTheme.inkSoft)
                    }
                }
                .onMove { draft.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("调整分类顺序").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { onSave(draft); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Compact two-column board card. The star is a real toggle, so favourites can
/// be removed from the same place where they were added.
struct CommunityBoardRow: View {
    let board: Board
    let session: SessionStore
    let store: BoardStore
    let tabBarVisibility: Binding<Visibility>
    let alreadyAdded: Bool
    let onAdd: () -> Void
    var body: some View {
        let artwork = AppTheme.boardArtwork(for: board.name)
        let hasArtwork = artwork != nil
        ZStack(alignment: .topTrailing) {
            NavigationLink { TopicListView(board: board, session: session, store: store, tabBarVisibility: tabBarVisibility) } label: {
                ZStack(alignment: .bottomLeading) {
                    if let artwork {
                        Rectangle().fill(.clear).overlay {
                            Image(uiImage: artwork).resizable().scaledToFill()
                        }.clipped()
                        LinearGradient(colors: [Color.black.opacity(0.03), Color.black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                    } else {
                        LinearGradient(colors: [AppTheme.starWash(for: board.id).opacity(0.82), AppTheme.glassFill],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Circle()
                            .fill(AppTheme.starColor(for: board.id).opacity(0.10))
                            .frame(width: 112, height: 112)
                            .blur(radius: 20)
                            .offset(x: 74, y: 48)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        BoardIcon(board: board, size: 34)
                            .padding(4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Spacer(minLength: 0)
                        Text(board.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(hasArtwork ? Color.white : AppTheme.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity).frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(AppTheme.glassStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: onAdd) {
                Image(systemName: alreadyAdded ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(alreadyAdded ? AppTheme.forumAccent : (hasArtwork ? Color.white : AppTheme.inkSoft.opacity(0.62)))
                    .frame(width: 34, height: 34, alignment: .center)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(5)
            .buttonStyle(.plain)
            .accessibilityLabel(alreadyAdded ? "取消收藏版块" : "收藏版块")
        }
        .shadow(color: .black.opacity(hasArtwork ? 0.12 : 0.045), radius: 10, y: 5)
    }
}

/// Board icon from NGA's CDN, or a coloured orb when it can't be loaded.
struct BoardIcon: View {
    let board: Board
    var size: CGFloat = 44
    var body: some View {
        let color = AppTheme.starColor(for: board.id)
        AsyncImage(url: AppTheme.boardIconURL(for: board.id)) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFit()
            default:
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.16))
                    Text(board.name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "版")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
