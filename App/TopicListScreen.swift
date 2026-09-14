import SwiftUI
import UIKit
import NGAKit

/// Topic list for a board: filter bar (全部 / 置顶 / 精华 / 热帖), in-board search, pinned
/// topics first and a favourite-board action. Sub-board navigation lives in the
/// board catalogue, before the user enters a topic list.
struct TopicListView: View {
    let board: Board
    let session: SessionStore
    let store: BoardStore
    /// Kept for source compatibility with the tab shell; visibility is owned by
    /// this destination's native toolbar preference.
    var tabBarVisibility: Binding<Visibility> = .constant(.visible)
    @State private var topics: [Topic] = []
    @State private var search: [Topic] = []
    @State private var boardDescription: String?
    @State private var subForums: [Board] = []
    @State private var headerTopicID: Int?
    @State private var discoveredThumbnails: [Int: [URL]] = [:]
    @State private var inspectedThumbnails: Set<Int> = []
    @State private var previewTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var showingAccount = false
    @State private var requestID = UUID()
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var showingSearch = false
    @State private var showingComposer = false
    @State private var showingSubForumFilter = false
    @State private var hiddenSubForumIDs: Set<Int> = []
    @State private var hasLoadedOnce = false
    @State private var refreshing = false
    @FocusState private var searchFocused: Bool

    enum Filter: String, CaseIterable { case all = "全部", digest = "精华", hot = "热帖" }

    init(board: Board, session: SessionStore, store: BoardStore,
         tabBarVisibility: Binding<Visibility> = .constant(.visible)) {
        self.board = board
        self.session = session
        self.store = store
        self.tabBarVisibility = tabBarVisibility
        let cached = UserDefaults.standard.string(forKey: "nga.community.forum-index.v1")
        _boardDescription = State(initialValue: cached.flatMap { ForumIndex.boardDescription($0, fid: board.id) })
    }

    private var visible: [Topic] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let source = q.isEmpty ? topics : search
        guard !hiddenSubForumIDs.isEmpty else { return source }
        return source.filter { topic in
            guard let sourceBoardID = topic.sourceBoardID else { return true }
            return !hiddenSubForumIDs.contains(sourceBoardID)
        }
    }

    private var visualPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--dsh-ui-preview")
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                // Topic previews can gain height after their image is fetched. A
                // LazyVStack may retain the old hit-test geometry even after the
                // visible rows have moved, sending a tap to the row below. A forum
                // page is bounded, so laying out the page eagerly keeps drawing and
                // hit testing in the same coordinate system.
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 0).id("topic-list-top")
                    boardHeader
                    filterChips
                        .zIndex(2)
                    if visible.isEmpty && !loading && error == nil {
                        ContentUnavailableView("没有主题", systemImage: filter == .hot ? "flame" : "text.bubble",
                                               description: Text("换个筛选条件，或调整子版面筛选。")).padding(.top, 40)
                    }
                    ForEach(visible) { topic in
                        NavigationLink {
                            ReaderView(topic: topic, board: board, session: session, tabBarVisibility: tabBarVisibility)
                                .id(topic.id)
                        } label: {
                            TopicCard(topic: topic, thumbnails: topic.thumbnails.isEmpty ? (discoveredThumbnails[topic.id] ?? []) : topic.thumbnails)
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .id(topic.id)
                    }
                    if let error {
                        ConnectionNotice(message: error, retry: { Task { await load() } }, connect: { showingAccount = true })
                    }
                    if loading { ProgressView("正在读取…").frame(maxWidth: .infinity).padding(24).tint(AppTheme.forumAccent) }
                    else if hasMore && query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { Task { await loadMore() } } label: {
                            Text("加载更多").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.forumAccent)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.buttonStyle(.plain)
                    }
                }
                // Keep the complete page at a stable, explicit width. A vertical
                // ScrollView otherwise accepts an over-wide child's ideal size,
                // while containerRelativeFrame can resolve to zero on device during
                // navigation. Reading the viewport once is cheap and also follows
                // rotation and iPad split-view resizing.
                .frame(width: max(0, viewport.size.width - AppTheme.pad * 2), alignment: .leading)
                .padding(.top, 10).padding(.bottom, 30)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if showingSearch {
                        searchField
                            .padding(.horizontal, AppTheme.pad).padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                    }
                }
                .safeAreaInset(edge: .bottom) { floatingActions(proxy) }
            }
        }
        .sceneCanvas()
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppTheme.sceneTop.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle(board.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleSearch) {
                    Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                        .foregroundStyle(AppTheme.quietChrome)
                }.accessibilityLabel(showingSearch ? "关闭搜索" : "搜索本版主题")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("发表主题") { showingComposer = true }
                    Button("账户与连接") { showingAccount = true }
                    Button(store.contains(board.id) ? "取消收藏版块" : "收藏版块", action: favoriteBoard)
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(AppTheme.quietChrome)
                }.accessibilityLabel("更多操作")
            }
        }
        .sheet(isPresented: $showingAccount) { AccountView(session: session) }
        .sheet(isPresented: $showingComposer) {
            NewTopicComposer(board: board, session: session) {
                showingComposer = false
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingSubForumFilter) {
            SubForumFilterSheet(subForums: subForums, hiddenIDs: $hiddenSubForumIDs)
        }
        .task(id: session.revision) {
            if visualPreview { loadVisualPreview(); hasLoadedOnce = true }
            else if hasLoadedOnce { await refreshVisibleState() }
            else {
                await load()
                if !Task.isCancelled { hasLoadedOnce = true }
            }
        }
        .onChange(of: filter) { _, _ in Task { if visualPreview { loadVisualPreview() } else { await load() } } }
        .onChange(of: query) { _, newValue in handleQueryChange(newValue) }
        .refreshable { if visualPreview { loadVisualPreview() } else { await load() } }
        .onAppear { loadSubForumPreference() }
        .onChange(of: hiddenSubForumIDs) { _, _ in persistSubForumPreference() }
        .onDisappear { previewTask?.cancel() }
    }

    private var boardHeader: some View {
        Group {
            if let artwork = AppTheme.boardArtwork(for: board.name) {
                VStack(spacing: 0) {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 118)
                        .clipped()
                        .overlay {
                            LinearGradient(colors: [.clear, Color.black.opacity(0.3)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                    boardHeaderContent
                        .padding(12)
                }
                .background(AppTheme.glassFill)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.glassStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.07), radius: 12, y: 6)
                .transaction { $0.animation = nil }
            } else {
                boardHeaderContent
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .trailing) {
                        ZStack {
                            LinearGradient(colors: [AppTheme.starWash(for: board.id), .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            BoardIcon(board: board, size: 138)
                                .opacity(0.09).blur(radius: 1).offset(x: 28, y: 18)
                        }
                    }
                    .glassSurface(radius: 20, fill: .clear)
            }
        }
    }

    private var boardHeaderContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                BoardIcon(board: board, size: 50)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.forumAccent.opacity(0.5), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(board.name).font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink).lineLimit(2)
                    HStack(spacing: 6) {
                        if let headerTopicID {
                            NavigationLink {
                                ReaderView(topic: Topic(id: headerTopicID, subject: "版头", author: "", replies: 0, date: nil),
                                           board: board, session: session, tabBarVisibility: tabBarVisibility)
                            } label: { boardLinkLabel("版头", icon: "doc.richtext") }
                                .buttonStyle(.plain)
                        }
                        if !subForums.isEmpty {
                            Button { showingSubForumFilter = true } label: {
                                boardLinkLabel(subForumFilterTitle, icon: "line.3.horizontal.decrease.circle")
                            }.buttonStyle(.plain)
                        }
                        if headerTopicID == nil && subForums.isEmpty { Color.clear.frame(width: 1) }
                    }
                    .frame(height: 30, alignment: .leading)
                }
                Spacer(minLength: 8)
                Button(action: favoriteBoard) {
                    Image(systemName: store.contains(board.id) ? "star.fill" : "star")
                        .font(.title3).foregroundStyle(store.contains(board.id) ? AppTheme.forumAccent : AppTheme.quietChrome)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.cardSoft.opacity(0.72), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("收藏版块")
            }
            if let description = boardDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Divider().overlay(AppTheme.line.opacity(0.7))
                Text(description)
                    .font(.subheadline).foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func boardLinkLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.forumAccent)
            .padding(.horizontal, 9).frame(height: 30)
            .background(AppTheme.forumAccentSoft, in: Capsule())
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    private var subForumFilterTitle: String {
        hiddenSubForumIDs.isEmpty ? "子版面筛选" : "已隐藏 \(hiddenSubForumIDs.count) 个"
    }

    private func floatingActions(_ proxy: ScrollViewProxy) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 9) {
                Button {
                    withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo("topic-list-top", anchor: .top) }
                } label: {
                    Image(systemName: "arrow.up").font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.forumAccent).frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("返回顶部")
                Button { showingComposer = true } label: {
                    Image(systemName: "square.and.pencil").font(.headline.weight(.semibold))
                        .foregroundStyle(.white).frame(width: 50, height: 50)
                        .background(AppTheme.forumAccent, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }.buttonStyle(.plain).accessibilityLabel("发表新主题")
            }
        }.padding(.horizontal, AppTheme.pad).padding(.vertical, 6)
    }

    private func toggleSearch() {
        if showingSearch {
            showingSearch = false
            searchFocused = false
            if !query.isEmpty {
                query = ""; search = []
                Task { await load() }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { showingSearch = true }
            Task { @MainActor in
                await Task.yield()
                searchFocused = true
            }
        }
    }

    private var subForumPreferenceKey: String { "nga.hidden-subforums.\(board.id)" }

    /// Live in-board search: run `load()` a short moment after the query changes so
    /// results appear as the user types (matching the official app), instead of relying
    /// only on the return key. Clearing the query restores the normal topic list.
    @MainActor private func handleQueryChange(_ newValue: String) {
        searchTask?.cancel()
        let q = newValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            search = []
            Task { await load() }
        } else {
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private func loadSubForumPreference() {
        hiddenSubForumIDs = Set(UserDefaults.standard.array(forKey: subForumPreferenceKey) as? [Int] ?? [])
    }

    private func persistSubForumPreference() {
        UserDefaults.standard.set(hiddenSubForumIDs.sorted(), forKey: subForumPreferenceKey)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.quietChrome)
            TextField("搜索本版主题", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(AppTheme.ink)
                .submitLabel(.search)
                .focused($searchFocused)
                // The search field lives in a safeAreaInset, so an `.onSubmit` attached
                // to the outer ScrollView is not reliably reached on return. Handle
                // submit here so `load()` actually runs the search.
                .onSubmit(of: .search) { Task { await load() } }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.quietChrome)
                }.buttonStyle(.plain).accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14).frame(height: 46)
        .glassSurface(radius: 15)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var filterChips: some View {
        HStack(spacing: 0) {
            ForEach(Filter.allCases, id: \.self) { f in
                Button { filter = f } label: {
                    Text(f.rawValue).font(.subheadline.weight(filter == f ? .bold : .medium))
                        .foregroundStyle(filter == f ? AppTheme.forumAccent : AppTheme.quietChrome)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(filter == f ? AppTheme.forumAccentSoft : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .bottom) {
                            Capsule().fill(filter == f ? AppTheme.forumAccent : .clear).frame(width: 22, height: 2)
                        }
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassSurface(radius: 16)
    }

    private func favoriteBoard() {
        let added = store.toggle(board)
        Task { try? await session.favoriteBoard(fid: board.id, add: added) }
    }

    @MainActor private func load() async {
        let token = UUID(); requestID = token
        let host = session.host
        loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            let cookie = await session.cookieHeader(for: host)
            let client = NGAClient(host: host)
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                var res = try await client.searchTopics(fid: board.id, key: q, recommend: filter == .digest, cookie: cookie)
                if filter == .hot {
                    // The board search has no hot sort; rank page-one results by replies,
                    // mirroring the normal-list hot fallback.
                    res = TopicPage(topics: res.topics.sorted { $0.replies > $1.replies },
                                    page: res.page, hasMore: false, subForums: res.subForums,
                                    boardDescription: res.boardDescription, headerTopicID: res.headerTopicID)
                }
                #if DEBUG
                let first = res.topics.first.map { "[\($0.id)] \($0.subject.prefix(30))" } ?? "(none)"
                print("[NGAReader][search] filter=\(filter.rawValue) fid=\(board.id) key=\(q) topics=\(res.topics.count) first=\(first)")
                #endif
                guard !Task.isCancelled, token == requestID else { return }
                search = res.topics
            } else {
                async let topicRequest = pageRequest(client: client, page: 1, cookie: cookie)
                async let indexRequest = try? client.forumIndexRaw(cookie: cookie)
                let res = try await topicRequest
                let index = await indexRequest
                guard !Task.isCancelled, token == requestID else { return }
                topics = res.topics; page = res.page; hasMore = res.hasMore
                if boardDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                   let value = res.boardDescription { boardDescription = value }
                if !res.subForums.isEmpty { subForums = res.subForums }
                if let value = res.headerTopicID { headerTopicID = value }
                RemoteImageStore.warm(res.topics.flatMap { Array($0.thumbnails.prefix(3)) }, maxPixel: 600)
                if let index {
                    if boardDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        boardDescription = ForumIndex.boardDescription(index, fid: board.id)
                    }
                }
                previewTask?.cancel()
                previewTask = Task { await enrichThumbnails(for: res.topics, cookie: cookie, host: host) }
            }
        } catch {
            if !Task.isCancelled, token == requestID {
                #if DEBUG
                print("[NGAReader][load] ERROR q=\(query) fid=\(board.id): \(error)")
                #endif
                self.error = session.network.describe(error)
            }
        }
    }

    @MainActor private func loadMore() async {
        if loading || refreshing { return }
        let host = session.host
        let cookie = await session.cookieHeader(for: host)
        let next = page + 1
        loading = true
        defer { loading = false }
        do {
            let res = try await pageRequest(client: NGAClient(host: host), page: next, cookie: cookie)
            guard !Task.isCancelled else { return }
            var seen = Set(topics.map(\.id))
            let added = res.topics.filter { seen.insert($0.id).inserted }
            topics += added
            page = res.page; hasMore = res.hasMore && !added.isEmpty
            RemoteImageStore.warm(added.flatMap { Array($0.thumbnails.prefix(3)) }, maxPixel: 600)
            previewTask?.cancel()
            previewTask = Task { await enrichThumbnails(for: added, cookie: cookie, host: host) }
        } catch let loadError { if self.error == nil { self.error = session.network.describe(loadError) } }
    }

    private func pageRequest(client: NGAClient, page: Int, cookie: String?) async throws -> TopicPage {
        // Prefer `officialTopics` (carries sub-board attribution, closer to the official view), but
        // wrap every filter in a fallback to the reliable thread.php path + local filtering so the
        // filter bar never errors.
        switch filter {
        case .all:
            do { return try await client.officialTopics(fid: board.id, action: "list", page: page, cookie: cookie) }
            catch { return try await client.topics(fid: board.id, page: page, cookie: cookie) }
        case .digest:
            do { return try await client.officialTopics(fid: board.id, action: "list", page: page, recommend: true, cookie: cookie) }
            catch {
                let page0 = try await client.topics(fid: board.id, page: page, cookie: cookie)
                return TopicPage(topics: page0.topics.filter(\.flags.isDigest), page: page0.page, hasMore: false,
                                 subForums: page0.subForums, boardDescription: page0.boardDescription, headerTopicID: page0.headerTopicID)
            }
        case .hot:
            do { return try await client.officialTopics(fid: board.id, action: "hot", page: page, days: 1, cookie: cookie) }
            catch {
                let page0 = try await client.topics(fid: board.id, page: page, cookie: cookie)
                return TopicPage(topics: page0.topics.sorted { $0.replies > $1.replies }, page: page0.page, hasMore: false,
                                 subForums: page0.subForums, boardDescription: page0.boardDescription, headerTopicID: page0.headerTopicID)
            }
        }
    }

    /// Returning from a reader must refresh changing metadata without replacing the
    /// user's loaded pages, row order or scroll identity: page-one data is merged into
    /// the existing rows by id, `page`/`hasMore` stay untouched past page one. Reassigning
    /// page one (or the whole list) here used to discard every row after “加载更多”.
    /// `refreshing` also blocks `loadMore` from mutating the list mid-merge.
    @MainActor private func refreshVisibleState() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.isEmpty, !topics.isEmpty, !loading, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let host = session.host
        let cookie = await session.cookieHeader(for: host)
        guard !Task.isCancelled,
              let refreshed = try? await pageRequest(client: NGAClient(host: host), page: 1, cookie: cookie),
              !Task.isCancelled else { return }
        let updates = Dictionary(refreshed.topics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        topics = topics.map { updates[$0.id] ?? $0 }
        if page == 1 { hasMore = refreshed.hasMore }
        previewTask?.cancel()
        previewTask = Task { await enrichThumbnails(for: topics, cookie: cookie, host: host) }
    }

    /// Topic rows do not always include their cover. Inspect the OP of every topic
    /// once; a row receives a thumbnail only when that post really contains an image.
    /// Confirmed images are warmed immediately so they appear finished, not loading.
    @MainActor private func enrichThumbnails(for candidates: [Topic], cookie: String?, host: NGAHost) async {
        let client = NGAClient(host: host)
        let pending = candidates.filter { $0.thumbnails.isEmpty && !inspectedThumbnails.contains($0.id) }
        await withTaskGroup(of: (Int, [URL]).self) { group in
            var iterator = pending.makeIterator()
            func addNext() {
                guard let topic = iterator.next() else { return }
                group.addTask { (topic.id, await client.topicThumbnails(tid: topic.id, cookie: cookie)) }
            }
            for _ in 0..<min(4, pending.count) { addNext() }
            while let (tid, images) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                inspectedThumbnails.insert(tid)
                if !images.isEmpty {
                    discoveredThumbnails[tid] = images
                    RemoteImageStore.warm(Array(images.prefix(3)), maxPixel: 600)
                }
                addNext()
            }
        }
    }

    /// Local-only data for device screenshots. It is reachable solely through the
    /// `--dsh-ui-preview` debug launch argument and is never fetched or persisted.
    @MainActor private func loadVisualPreview() {
        let now = Date()
        let sticky = TopicStatus(sticky: true)
        let digest = TopicStatus(ifmark: 1)
        topics = [
            Topic(id: 9001, subject: "版块公告与发帖规范", author: "版务组", replies: 36, date: now.addingTimeInterval(-2_400), flags: sticky),
            Topic(id: 9002, subject: "关于移动端阅读体验的建议集中讨论", author: "NGA 用户", replies: 128, date: now.addingTimeInterval(-7_200), flags: digest),
            Topic(id: 9003, subject: "分享一个让长帖更容易读完的小技巧", author: "纸上谈兵", replies: 57, date: now.addingTimeInterval(-14_400)),
            Topic(id: 9004, subject: "回归玩家求助：现在入坑该从哪里开始？", author: "路过的旅人", replies: 21, date: now.addingTimeInterval(-31_200)),
            Topic(id: 9005, subject: "把最近几次更新的要点整理在这里", author: "资料管理员", replies: 84, date: now.addingTimeInterval(-86_400)),
            Topic(id: 9006, subject: "有没有人也在等这个功能？", author: "夜航船", replies: 12, date: now.addingTimeInterval(-180_000))
        ]
        boardDescription = "移动端阅读、版务公告与社区讨论。"
        page = 1; hasMore = true; loading = false; error = nil
    }
}

private struct SubForumFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let subForums: [Board]
    @Binding var hiddenIDs: Set<Int>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(subForums) { forum in
                        Toggle(forum.name, isOn: Binding(
                            get: { !hiddenIDs.contains(forum.id) },
                            set: { visible in
                                if visible { hiddenIDs.remove(forum.id) }
                                else { hiddenIDs.insert(forum.id) }
                            }
                        ))
                        .tint(AppTheme.forumAccent)
                    }
                } header: {
                    Text("列表中显示")
                } footer: {
                    Text("关闭不想看的分区后，它的主题会从当前版面列表中隐藏。")
                }
                if !hiddenIDs.isEmpty {
                    Section { Button("全部显示") { hiddenIDs.removeAll() } }
                }
            }
            .navigationTitle("子版面筛选").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct NewTopicComposer: View {
    @Environment(\.dismiss) private var dismiss
    let board: Board
    let session: SessionStore
    let onSent: () -> Void
    @State private var subject = ""
    @State private var content = ""
    @State private var preview = false
    @State private var showingEmotes = false
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("标题", text: $subject)
                    .font(.headline).padding(13).background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: 14))
                Picker("编辑模式", selection: $preview) {
                    Text("代码编辑").tag(false)
                    Text("预览").tag(true)
                }.pickerStyle(.segmented)
                if preview {
                    ScrollView {
                        NativeContentView(nodes: BBCode.parse(content))
                            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    }.background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    HStack {
                        Button { showingEmotes = true } label: { Label("表情", systemImage: "face.smiling") }
                        Spacer()
                        Text("支持 BBCode").foregroundStyle(AppTheme.inkSoft)
                    }.font(.caption.weight(.semibold))
                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden).padding(8)
                        .background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: 14))
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(16).background(AppTheme.page.ignoresSafeArea())
            .navigationTitle("发表到「\(board.name)」").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(sending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "发送中…" : "发表") { submit() }
                        .disabled(sending || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingEmotes) {
            EmotePicker { group, name in content += "[s:\(group):\(name)]" }
        }
    }

    private func submit() {
        sending = true; error = nil
        Task {
            do {
                try await session.newTopic(board: board, subject: subject, content: content)
                onSent()
            } catch {
                self.error = session.network.describe(error)
                sending = false
            }
        }
    }
}

private struct TopicCard: View {
    let topic: Topic
    let thumbnails: [URL]
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    if topic.flags.isSticky { TopicBadge(text: "置顶", color: AppTheme.forumAccent) }
                    if topic.flags.isDigest { TopicBadge(text: "精华", color: AppTheme.online) }
                    Text(topic.subject).font(.headline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text(topic.author.isEmpty ? "NGA 用户" : topic.author)
                        .lineLimit(1).truncationMode(.tail)
                    if let date = topic.date { Text("·").opacity(0.6); Text(AppTheme.timeAgo(date)) }
                    if let forumName = topic.sourceBoardName {
                        Text("·").opacity(0.6)
                        Text(forumName).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    Label("\(topic.replies)", systemImage: "bubble.right")
                        .font(.caption.monospacedDigit())
                        .fixedSize(horizontal: true, vertical: false)
                }.font(.caption).foregroundStyle(AppTheme.inkSoft)
            }
            if !thumbnails.isEmpty {
                TopicThumbnails(urls: Array(thumbnails.prefix(3)))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Failed or still-loading images occupy no space. This keeps the card in its
/// text-only layout until a real OP image has been decoded successfully.
/// Rendering goes through the downsampled store so each thumbnail is decoded
/// once, off the main thread, and warmed ahead of the scroll.
private struct TopicThumbnails: View {
    let urls: [URL]

    var body: some View {
        let previewHeight: CGFloat = urls.count == 1 ? 132 : 92
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let itemWidth = max(
                0,
                (proxy.size.width - spacing * CGFloat(max(0, urls.count - 1))) / CGFloat(max(1, urls.count))
            )
            HStack(spacing: spacing) {
                ForEach(urls, id: \.self) { url in
                    DownsampledImageView(url: url, maxPixel: urls.count == 1 ? 640 : 360)
                        .frame(width: itemWidth, height: previewHeight)
                        .clipped()
                }
            }
        }
        .frame(height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// A small tinted status chip, e.g. 置顶 / 精华.
struct TopicBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(color.opacity(0.52), lineWidth: 1))
    }
}
