import SwiftUI
import UIKit
import NGAKit

/// Editorial reader: the topic header establishes context, then each floor is a clear reading
/// card. The layout deliberately prioritises actual content over chat-like decoration.
struct ReaderView: View {
    let topic: Topic
    var board: Board? = nil
    let session: SessionStore
    /// Kept for source compatibility with the tab shell; visibility is owned by
    /// this destination's native toolbar preference.
    var tabBarVisibility: Binding<Visibility> = .constant(.visible)
    @State private var posts: [Post] = []
    @State private var title = ""
    @State private var page = 1
    @State private var hasMore = false
    @State private var totalPages: Int?
    @State private var showingPagePicker = false
    @State private var loading = false
    @State private var error: String?
    @State private var showingAccount = false
    @State private var requestID = UUID()
    @State private var composerOpen = false
    @State private var draft = ""
    @State private var replyTarget: Post?
    @State private var composerSelection = NSRange(location: 0, length: 0)
    @State private var composerMode: ComposerMode = .source
    @State private var topicFavorited = false
    @State private var showingEmotes = false
    @State private var referencedPosts: [Int: Post] = [:]
    @State private var selectedUser: NGAUser?
    @State private var authorOnly: AuthorOnlyFilter?
    @State private var voteSelections: [Int: PostVote] = [:]
    @State private var voteDeltas: [Int: Int] = [:]
    @State private var votingPIDs: Set<Int> = []
    @State private var voteErrors: [Int: String] = [:]
    @State private var previewImageURL: URL?

    private struct AuthorOnlyFilter: Equatable {
        let uid: String?
        let anonymousPID: Int?
        let name: String
    }

    private enum ComposerMode: String, CaseIterable, Identifiable {
        case source = "源码"
        case preview = "预览"
        var id: String { rawValue }
    }

    private var visualPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--dsh-ui-preview")
    }

    /// A reader can be reused by SwiftUI when two links share the same destination
    /// type. Include the topic itself so a second topic never inherits the first
    /// topic's state or skips its network request.
    private var loadIdentity: String {
        "\(session.host.rawValue):\(session.revision):\(topic.id)"
    }

    var body: some View {
        ZStack {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        topicHeader
                            .id("top")

                        ForEach(posts) { post in
                            ReaderPostCard(
                                post: post,
                                displayContent: displayContent(for: post),
                                shareURL: postURL(post),
                                voteSelection: voteSelections[post.pid],
                                scoreDelta: voteDeltas[post.pid] ?? 0,
                                isVoting: votingPIDs.contains(post.pid),
                                voteError: voteErrors[post.pid],
                                isOnlyAuthor: authorOnly.map { filter in
                                    if let uid = filter.uid { return uid == post.user?.uid }
                                    return filter.anonymousPID == post.pid
                                } ?? false,
                                onUser: { if let user = post.user, !user.isAnonymous { selectedUser = user } },
                                onImage: { previewImageURL = $0 },
                                onQuote: { replyTarget = post; draft = BBCode.quoteText(author: post.author, content: post.content); composerOpen = true },
                                onFavorite: { Task { try? await session.favoritePost(topic: topic, post: post) } },
                                onOnlyAuthor: { toggleAuthorOnly(post) },
                                onVote: { direction in Task { await vote(post, direction: direction) } }
                            )
                        }

                        if loading { ProgressView("正在读取…").frame(maxWidth: .infinity).padding(24).tint(AppTheme.forumAccent) }
                        if let error {
                            ConnectionNotice(message: error, retry: { Task { await load(page) } }, connect: { showingAccount = true })
                                .padding(AppTheme.pad)
                        }
                        Color.clear.frame(height: 8)
                    }
                    .padding(.horizontal, AppTheme.pad)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
                .refreshable { await load(page) }
                .overlay(alignment: .bottom) { bottomBar(proxy: proxy) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo("top", anchor: .top) }
                    } label: {
                            Image(systemName: "arrow.up.to.line")
                    }
                        .tint(AppTheme.forumAccent)
                    .accessibilityLabel("返回顶部")
                    }
                }
            }
            .sceneCanvas()
            .toolbar(previewImageURL == nil ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingPagePicker) {
                PageJumpSheet(currentPage: page, totalPages: totalPages) { target in
                    Task {
                        await load(target)
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
            .fullScreenCover(item: $selectedUser) { user in
                NavigationStack {
                    NGAUserView(user: user, posts: posts.filter { candidate in
                        if !user.uid.isEmpty { return candidate.user?.uid == user.uid }
                        return candidate.author == user.name
                    }, session: session)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { selectedUser = nil } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("关闭用户资料")
                        }
                    }
                }
            }
        }
        if let previewImageURL {
            PostImagePreviewView(url: previewImageURL) {
                withAnimation(.easeOut(duration: 0.18)) { self.previewImageURL = nil }
            }
            .transition(.opacity)
            .zIndex(100)
        }
        }
        .animation(.easeInOut(duration: 0.18), value: previewImageURL)
        .statusBarHidden(previewImageURL != nil)
        .navigationTitle("帖子详情").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        do { try await session.favoriteTopic(topic); topicFavorited = true }
                        catch { self.error = session.network.describe(error) }
                    }
                } label: {
                    Image(systemName: topicFavorited ? "star.fill" : "star")
                }
                .tint(AppTheme.forumAccent)
                .accessibilityLabel(topicFavorited ? "已收藏主题" : "收藏主题")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: "/read.php?tid=\(topic.id)", relativeTo: session.host.url)!.absoluteURL)
                    .tint(AppTheme.forumAccent)
            }
        }
        .sheet(isPresented: $composerOpen) { composer }
        .sheet(isPresented: $showingAccount) { AccountView(session: session) }
        .task(id: loadIdentity) {
            resetForNewTopic()
            ReadingHistoryStore.shared.record(topic, board: board)
            if visualPreview { loadVisualPreview() } else { await load(1) }
        }
    }

    private func displayContent(for post: Post) -> String {
        guard let targetPID = BBCode.looseReplyTargetPID(in: post.content),
              let target = posts.first(where: { $0.pid == targetPID }) ?? referencedPosts[targetPID] else { return post.content }
        return BBCode.restoringLooseReply(post.content, referencedContent: target.content)
    }

    private var topicHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let board {
                HStack(spacing: 8) {
                    BoardIcon(board: board, size: 24)
                    Text(board.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.quietChrome)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.quietChrome.opacity(0.7))
                    Text("主题详情").font(.subheadline).foregroundStyle(AppTheme.inkSoft)
                }
            }
            Text(title.isEmpty ? topic.subject : title)
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
            HStack(spacing: 18) {
                Label("\(topic.replies)", systemImage: "bubble.left.and.bubble.right")
                Label(totalPages.map { "第 \(page)/\($0) 页" } ?? "第 \(page) 页", systemImage: "doc.plaintext")
                if let date = posts.first?.date { Text(AppTheme.timeAgo(date)) }
            }
            .font(.caption).foregroundStyle(AppTheme.quietChrome)
            if let authorOnly {
                Button {
                    self.authorOnly = nil
                    Task { await load(1) }
                } label: {
                    Label("只看 \(authorOnly.name)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.forumAccent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(AppTheme.forumAccentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("点按恢复查看全部回复")
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: 23, fill: AppTheme.forumAccent.opacity(0.045))
    }

    private func bottomBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Button { replyTarget = nil; composerOpen = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil").foregroundStyle(AppTheme.forumAccent)
                    Text("发表回复…").font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .glassSurface(radius: 20)
            }.buttonStyle(.plain)
            pagerButtons(proxy: proxy)
        }
        .padding(.horizontal, AppTheme.pad)
        .padding(.top, 2)
        .padding(.bottom, 0)
    }

    private func pagerButtons(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 1) {
            pagerIconButton("首页", systemImage: "backward.end", disabled: page <= 1 || loading) {
                Task { await load(1); proxy.scrollTo("top", anchor: .top) }
            }
            pagerIconButton("上一页", systemImage: "chevron.left", disabled: page <= 1 || loading) {
                Task { await load(page - 1); proxy.scrollTo("top", anchor: .top) }
            }
            Button { showingPagePicker = true } label: {
                Text(totalPages.map { "\(page)/\($0)" } ?? "\(page)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .frame(minWidth: 38, minHeight: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择页码，当前第 \(page) 页")
            pagerIconButton("下一页", systemImage: "chevron.right", disabled: !hasMore || loading) {
                Task { await load(page + 1); proxy.scrollTo("top", anchor: .top) }
            }
            pagerIconButton("尾页", systemImage: "forward.end",
                            disabled: totalPages == nil || page >= (totalPages ?? page) || loading) {
                guard let totalPages else { return }
                Task { await load(totalPages); proxy.scrollTo("top", anchor: .top) }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 7)
        .glassSurface(radius: 20)
    }

    private func pagerIconButton(_ text: String, systemImage: String, disabled: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 27, height: 30)
            .foregroundStyle(disabled ? AppTheme.inkSoft.opacity(0.5) : AppTheme.forumAccent)
        }
        .buttonStyle(.plain).disabled(disabled).accessibilityLabel(text)
    }

    private var composer: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let target = replyTarget {
                    Text("引用 \(target.author)").font(.footnote).foregroundStyle(AppTheme.inkSoft).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 8)
                }
                Picker("编辑模式", selection: $composerMode) {
                    ForEach(ComposerMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10)
                if composerMode == .source {
                    composerToolbar
                    BBCodeComposerTextView(text: $draft, selection: $composerSelection)
                        .padding(10)
                        .background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16).padding(.bottom, 16)
                        .frame(minHeight: 190)
                } else {
                    ScrollView {
                        NativeContentView(nodes: BBCode.parse(draft))
                            .foregroundStyle(AppTheme.ink)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: 16))
                    .padding(16).frame(minHeight: 230)
                    .overlay(alignment: .bottomTrailing) {
                        Text("发送前预览").font(.caption2).foregroundStyle(AppTheme.inkSoft).padding(24)
                    }
                }
                Spacer()
            }
            .background(AppTheme.page.ignoresSafeArea())
            .navigationTitle("回复").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { composerOpen = false; draft = ""; composerMode = .source } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { submit() }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingEmotes) {
            EmotePicker { group, name in insertEmote(group: group, name: name) }
        }
        .presentationDetents([.medium])
    }

    private var composerToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showingEmotes = true } label: {
                    Label("表情", systemImage: "face.smiling")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.forumAccent)
                        .padding(.horizontal, 10).frame(height: 36)
                        .background(AppTheme.forumAccentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                ForEach(ComposerFormat.all) { format in
                    Button { apply(format) } label: {
                        Label(format.title, systemImage: format.symbol)
                            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 10).frame(height: 36)
                            .background(AppTheme.cardSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func insertEmote(group: String, name: String) {
        let source = draft as NSString
        let safeLocation = min(max(composerSelection.location, 0), source.length)
        let safeLength = min(max(composerSelection.length, 0), source.length - safeLocation)
        let range = NSRange(location: safeLocation, length: safeLength)
        let token = "[s:\(group):\(name)]"
        draft = source.replacingCharacters(in: range, with: token)
        composerSelection = NSRange(location: safeLocation + (token as NSString).length, length: 0)
    }

    private func apply(_ format: ComposerFormat) {
        let source = draft as NSString
        let safeLocation = min(max(composerSelection.location, 0), source.length)
        let safeLength = min(max(composerSelection.length, 0), source.length - safeLocation)
        let range = NSRange(location: safeLocation, length: safeLength)
        let selected = safeLength > 0 ? source.substring(with: range) : format.placeholder
        let replacement = format.open + selected + format.close
        draft = source.replacingCharacters(in: range, with: replacement)
        composerSelection = NSRange(location: safeLocation + (format.open as NSString).length,
                                    length: (selected as NSString).length)
    }

    private func submit() {
        let content = draft
        Task {
            do {
                try await session.reply(topic: topic, pid: replyTarget?.pid, content: content)
                composerOpen = false; draft = ""; replyTarget = nil; composerMode = .source
                await load(page)
            } catch {
                composerOpen = false; draft = ""; replyTarget = nil; composerMode = .source
                self.error = session.network.describe(error)
            }
        }
    }

    @MainActor private func load(_ requestedPage: Int) async {
        let token = UUID(); requestID = token
        let host = session.host
        loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            let cookie = await session.cookieHeader(for: host)
            let result = try await NGAClient(host: host).posts(
                tid: topic.id, page: requestedPage, authorID: authorOnly?.uid,
                anonymousAuthorPID: authorOnly?.anonymousPID, cookie: cookie
            )
            guard !Task.isCancelled, token == requestID, host == session.host else { return }
            posts = result.posts; referencedPosts = [:]
            for post in result.posts {
                if let vote = savedVote(for: post) ?? post.vote { voteSelections[post.pid] = vote }
                else { voteSelections.removeValue(forKey: post.pid) }
            }
            title = result.title; page = result.page; hasMore = result.hasMore; totalPages = result.totalPages
            await loadReferencedPosts(for: result.posts, currentPage: result.page, host: host, cookie: cookie, token: token)
        } catch let error as NGAError {
            guard !Task.isCancelled, token == requestID else { return }
            self.error = session.network.describe(error)
        } catch {
            if !Task.isCancelled, token == requestID { self.error = session.network.describe(error) }
        }
    }

    @MainActor private func resetForNewTopic() {
        requestID = UUID()
        posts = []
        referencedPosts = [:]
        title = ""
        page = 1
        hasMore = false
        totalPages = nil
        error = nil
        authorOnly = nil
        voteSelections = [:]
        voteDeltas = [:]
        votingPIDs = []
        voteErrors = [:]
    }

    private func postURL(_ post: Post) -> URL {
        var components = URLComponents(url: session.host.url.appendingPathComponent("read.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "tid", value: String(topic.id)),
                                 URLQueryItem(name: "pid", value: String(post.pid))]
        return components.url!
    }

    private func toggleAuthorOnly(_ post: Post) {
        guard let user = post.user, !user.uid.isEmpty else { return }
        let proposed = user.isAnonymous
            ? AuthorOnlyFilter(uid: nil, anonymousPID: post.pid, name: post.author)
            : AuthorOnlyFilter(uid: user.uid, anonymousPID: nil, name: post.author)
        authorOnly = authorOnly == proposed ? nil : proposed
        Task { await load(1) }
    }

    @MainActor private func vote(_ post: Post, direction: PostVote) async {
        guard !votingPIDs.contains(post.pid) else { return }
        let previousSelection = voteSelections[post.pid]
        let proposedSelection: PostVote? = previousSelection == direction ? nil : direction
        voteSelections[post.pid] = proposedSelection
        voteErrors.removeValue(forKey: post.pid)
        votingPIDs.insert(post.pid)
        defer { votingPIDs.remove(post.pid) }
        do {
            let result = try await session.vote(topic: topic, post: post, direction: direction)
            voteDeltas[post.pid, default: 0] += result.delta
            if let selection = result.selection {
                voteSelections[post.pid] = selection
                UserDefaults.standard.set(selection.rawValue, forKey: voteReceiptKey(post))
            } else {
                voteSelections.removeValue(forKey: post.pid)
                UserDefaults.standard.removeObject(forKey: voteReceiptKey(post))
            }
        } catch {
            voteSelections[post.pid] = previousSelection
            voteErrors[post.pid] = session.network.describe(error)
        }
    }

    private func voteReceiptKey(_ post: Post) -> String {
        "nga.vote.\(session.host.rawValue).\(topic.id).\(post.pid)"
    }

    private func savedVote(for post: Post) -> PostVote? {
        PostVote(rawValue: UserDefaults.standard.integer(forKey: voteReceiptKey(post)))
    }

    @MainActor private func loadReferencedPosts(for source: [Post], currentPage: Int, host: NGAHost,
                                                cookie: String?, token: UUID) async {
        let loadedPIDs = Set(source.map(\.pid))
        let pages = Set(source.compactMap { post -> Int? in
            guard let pid = BBCode.looseReplyTargetPID(in: post.content), !loadedPIDs.contains(pid),
                  let targetPage = BBCode.looseReplyTargetPage(in: post.content), targetPage > 0,
                  targetPage != currentPage else { return nil }
            return targetPage
        }).prefix(3)
        for targetPage in pages {
            guard !Task.isCancelled, token == requestID else { return }
            if let result = try? await NGAClient(host: host).posts(tid: topic.id, page: targetPage, cookie: cookie) {
                for post in result.posts { referencedPosts[post.pid] = post }
            }
        }
    }

    /// Local-only content for layout review on a physical device. This is enabled
    /// only with `--dsh-ui-preview`; production always loads NGA responses.
    @MainActor private func loadVisualPreview() {
        let now = Date()
        title = topic.subject.isEmpty ? "移动端阅读体验的版式预览" : topic.subject
        posts = [
            Post(id: "preview-1", pid: 1, floor: 0, author: "版务观察员", content: "这是一段用于检查原生阅读排版的本地样例。正文应当优先于装饰：行宽舒适、层级清晰，也能自然承载 NGA 的 BBCode 内容。\n\n[quote]引用内容会保持独立的阅读边界，避免和正文混在一起。[/quote]\n\n欢迎把你最常阅读的长帖、攻略帖和讨论帖带来测试，我们会继续根据真实内容调整间距和字号。", date: now.addingTimeInterval(-4_200)),
            Post(id: "preview-2", pid: 2, floor: 1, author: "阅读爱好者", content: "列表里的标题层级和帖子里的正文密度看起来都比较稳。希望长引用、图片和代码块也能保持这个节奏。", date: now.addingTimeInterval(-2_400)),
            Post(id: "preview-3", pid: 3, floor: 2, author: "路过的用户", content: "底部回复入口固定在安全区上方，翻页和收藏仍然能随手操作。", date: now.addingTimeInterval(-900))
        ]
        page = 1; hasMore = true; totalPages = 8; loading = false; error = nil
    }
}

private struct PageJumpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentPage: Int
    let totalPages: Int?
    let onJump: (Int) -> Void
    @State private var targetText: String

    init(currentPage: Int, totalPages: Int?, onJump: @escaping (Int) -> Void) {
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.onJump = onJump
        _targetText = State(initialValue: String(currentPage))
    }

    private var target: Int? {
        guard let value = Int(targetText), value > 0 else { return nil }
        if let totalPages, value > totalPages { return nil }
        return value
    }

    private var quickPages: [Int] {
        let upper = totalPages ?? max(currentPage + 2, 3)
        return Array(Set([1, max(1, currentPage - 2), max(1, currentPage - 1), currentPage,
                          min(upper, currentPage + 1), min(upper, currentPage + 2), upper])).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    TextField("页码", text: $targetText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("跳转") { jump(to: target) }
                        .buttonStyle(.borderedProminent).tint(AppTheme.forumAccent)
                        .disabled(target == nil)
                }
                Text(totalPages.map { "共 \($0) 页，当前第 \(currentPage) 页" } ?? "当前第 \(currentPage) 页")
                    .font(.footnote).foregroundStyle(AppTheme.inkSoft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPages, id: \.self) { value in
                            Button(value == 1 ? "首页" : (value == totalPages ? "尾页" : "第 \(value) 页")) {
                                jump(to: value)
                            }
                            .font(.caption.weight(value == currentPage ? .bold : .medium))
                            .foregroundStyle(value == currentPage ? Color.white : AppTheme.ink)
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(value == currentPage ? AnyShapeStyle(AppTheme.forumAccent) : AnyShapeStyle(AppTheme.cardSoft),
                                        in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(AppTheme.page.ignoresSafeArea())
            .navigationTitle("选择页码").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .presentationDetents([.height(250)])
    }

    private func jump(to page: Int?) {
        guard let page else { return }
        dismiss()
        onJump(page)
    }
}

struct EmotePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var group = "a2"
    let onSelect: (String, String) -> Void
    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BBCode.emoteGroups, id: \.self) { item in
                            Button(item.uppercased()) { group = item }
                                .font(.caption.weight(group == item ? .bold : .medium))
                                .foregroundStyle(group == item ? .white : AppTheme.ink)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(group == item ? AnyShapeStyle(AppTheme.brand) : AnyShapeStyle(AppTheme.cardSoft), in: Capsule())
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 10)
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(BBCode.emoteNames(in: group), id: \.self) { name in
                            Button {
                                onSelect(group, name)
                                dismiss()
                            } label: {
                                VStack(spacing: 5) {
                                    AsyncImage(url: BBCode.emoteURL(group: group, name: name)) { phase in
                                        if case .success(let image) = phase { image.resizable().scaledToFit() }
                                        else { ProgressView().tint(AppTheme.brand) }
                                    }
                                    .frame(width: 48, height: 48)
                                    Text(name).font(.caption2).foregroundStyle(AppTheme.ink).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
            }
            .background(AppTheme.page.ignoresSafeArea())
            .navigationTitle("选择表情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ComposerFormat: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let open: String
    let close: String
    let placeholder: String

    static let all: [ComposerFormat] = [
        .init(id: "bold", title: "粗体", symbol: "bold", open: "[b]", close: "[/b]", placeholder: "文字"),
        .init(id: "color", title: "颜色", symbol: "paintpalette", open: "[color=royalblue]", close: "[/color]", placeholder: "文字"),
        .init(id: "quote", title: "引用", symbol: "quote.opening", open: "[quote]", close: "[/quote]", placeholder: "引用内容"),
        .init(id: "list", title: "列表", symbol: "list.bullet", open: "[list]\n[*]", close: "\n[/list]", placeholder: "项目"),
        .init(id: "link", title: "链接", symbol: "link", open: "[url=https://]", close: "[/url]", placeholder: "链接文字"),
        .init(id: "image", title: "图片", symbol: "photo", open: "[img]", close: "[/img]", placeholder: "https://"),
        .init(id: "collapse", title: "折叠", symbol: "chevron.down.square", open: "[collapse=展开查看]", close: "[/collapse]", placeholder: "折叠内容"),
        .init(id: "code", title: "代码", symbol: "chevron.left.forwardslash.chevron.right", open: "[code]", close: "[/code]", placeholder: "代码")
    ]
}

/// UITextView bridge used so toolbar actions can wrap the user's current
/// selection. SwiftUI's iOS 17 TextEditor does not expose its selected range.
private struct BBCodeComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.keyboardDismissMode = .interactive
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        let length = (view.text as NSString).length
        let location = min(max(selection.location, 0), length)
        let range = NSRange(location: location, length: min(max(selection.length, 0), length - location))
        if view.selectedRange != range { view.selectedRange = range }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BBCodeComposerTextView
        init(parent: BBCodeComposerTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) { parent.selection = textView.selectedRange }
    }
}

private struct ReaderPostCard: View {
    let post: Post
    let displayContent: String
    let shareURL: URL
    let voteSelection: PostVote?
    let scoreDelta: Int
    let isVoting: Bool
    let voteError: String?
    let isOnlyAuthor: Bool
    let onUser: () -> Void
    let onImage: (URL) -> Void
    let onQuote: () -> Void
    let onFavorite: () -> Void
    let onOnlyAuthor: () -> Void
    let onVote: (PostVote) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onUser) {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(url: post.avatar, name: post.author, size: 46)
                        VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text(post.author.isEmpty ? "匿名用户" : post.author)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink).lineLimit(1)
                        if post.floor == 0 {
                            Text("楼主").font(.caption2.weight(.bold)).foregroundStyle(AppTheme.forumAccent)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(AppTheme.forumAccentSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    if let date = post.date {
                        Text(AppTheme.postTime(date)).font(.caption).foregroundStyle(AppTheme.inkSoft)
                    }
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(post.user?.isAnonymous != false)
                .accessibilityLabel(post.user?.isAnonymous == false ? "查看 \(post.author) 的用户资料" : post.author)
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 12) {
                    Text("#\(post.floor)")
                        .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.quietChrome)
                    Menu {
                        Button(isOnlyAuthor ? "查看全部回复" : "只看该作者",
                               systemImage: isOnlyAuthor ? "person.2" : "person.crop.circle.badge.checkmark",
                               action: onOnlyAuthor)
                            .disabled(post.user?.uid.isEmpty != false)
                        Divider()
                        Button("回复", systemImage: "bubble.right", action: onQuote)
                        Button("引用", systemImage: "quote.opening", action: onQuote)
                        Button("收藏", systemImage: "star", action: onFavorite)
                        ShareLink(item: shareURL) { Label("转发", systemImage: "square.and.arrow.up") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.quietChrome)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }
                .frame(height: 28, alignment: .center)
            }
            NativeContentView(nodes: BBCode.parse(displayContent))
                .foregroundStyle(AppTheme.ink)
                .environment(\.postImagePreviewAction, onImage)
            Divider().overlay(AppTheme.line.opacity(0.65))
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    postAction("回复", systemImage: "bubble.right") { onQuote() }
                    postAction("引用", systemImage: "quote.opening") { onQuote() }
                    postAction("收藏", systemImage: "star") { onFavorite() }
                    ShareLink(item: shareURL) {
                        Label("转发", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.medium)).foregroundStyle(AppTheme.inkSoft)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("转发本楼")
                }
                .frame(maxWidth: .infinity)
                voteControl
            }
            if let voteError {
                Label(voteError, systemImage: "exclamationmark.circle")
                    .font(.caption2).foregroundStyle(AppTheme.alert)
                    .transition(.opacity)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: 18)
    }

    private func postAction(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.medium)).foregroundStyle(AppTheme.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var voteControl: some View {
        let score = post.score + scoreDelta
        return HStack(spacing: 6) {
            voteButton(.agree, systemImage: "hand.thumbsup", selectedImage: "hand.thumbsup.fill",
                       label: "赞同", count: score > 0 ? score : nil)
            voteButton(.disagree, systemImage: "hand.thumbsdown", selectedImage: "hand.thumbsdown.fill",
                       label: "反对", count: score < 0 ? abs(score) : nil)
        }
    }

    private func voteButton(_ direction: PostVote, systemImage: String, selectedImage: String,
                            label: String, count: Int?) -> some View {
        let selected = voteSelection == direction
        let selectedColor: Color = direction == .agree ? AppTheme.brand : AppTheme.forumAccent
        return Button { onVote(direction) } label: {
            HStack(spacing: 4) {
                if isVoting {
                    ProgressView().controlSize(.mini).tint(selectedColor)
                } else {
                    Image(systemName: selected ? selectedImage : systemImage)
                        .font(.caption.weight(.semibold))
                }
                if let count {
                    Text("\(count)").font(.caption2.monospacedDigit().weight(selected ? .bold : .regular))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(selected ? selectedColor : AppTheme.inkSoft)
            .padding(.horizontal, count == nil ? 7 : 8)
            .frame(height: 28)
            .background(selected ? selectedColor.opacity(0.14) : AppTheme.line.opacity(0.18), in: Capsule())
            .overlay {
                Capsule().stroke(selected ? selectedColor.opacity(0.55) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isVoting)
        .accessibilityLabel(label)
        .accessibilityHint(selected ? "再次点按取消" : "点按提交")
    }
}

struct ConnectionNotice: View {
    let message: String
    let retry: () -> Void
    let connect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("暂时无法读取", systemImage: "network.slash").font(.headline).foregroundStyle(AppTheme.ink)
            Text(message).font(.subheadline).foregroundStyle(AppTheme.inkSoft)
            HStack(spacing: 12) {
                Button("重试", action: retry).buttonStyle(.bordered).tint(AppTheme.brand)
                Button("账户与连接", action: connect).buttonStyle(.borderedProminent).tint(AppTheme.brand)
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.radiusCard))
    }
}
