import SwiftUI
import NGAKit

/// NGA user centre. Every piece of content and every account action is backed
/// by an NGA response; unavailable/private fields are shown as unavailable.
struct NGAUserView: View {
    let user: NGAUser
    let posts: [Post]
    let session: SessionStore

    @State private var profile: NGAUser
    @State private var section: Section = .topics
    @State private var topics: [Topic] = []
    @State private var replies: [Topic] = []
    @State private var favorites: [Topic] = []
    @State private var folders: [FavoriteFolder] = []
    @State private var selectedFolder: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var notice: String?
    @State private var followed: Bool?
    @State private var blocked: Bool?
    @State private var showingMessage = false
    @State private var messageSubject = ""
    @State private var messageBody = ""

    enum Section: String, CaseIterable, Identifiable {
        case topics = "主题"
        case replies = "回复"
        case favorites = "收藏"
        case signature = "签名"
        var id: String { rawValue }
    }

    init(user: NGAUser, posts: [Post], session: SessionStore) {
        self.user = user
        self.posts = posts
        self.session = session
        _profile = State(initialValue: user)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                identityHeader
                sectionPicker
                if let notice { statusBanner(notice, warning: false) }
                if let error { statusBanner(error, warning: true) }
                sectionContent
            }
            .padding(.horizontal, AppTheme.pad)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .sceneCanvas()
        .navigationTitle("用户资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(blocked == true ? "取消拉黑" : "拉黑", role: blocked == true ? nil : .destructive) {
                        Task { await toggleBlock() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(profile.isAnonymous)
                .accessibilityLabel("更多用户操作")
            }
        }
        .sheet(isPresented: $showingMessage) { messageComposer }
        .task(id: profile.uid) { await loadProfileAndRelationships() }
        .task(id: section) { await load(section) }
        .onChange(of: selectedFolder) { _, folder in
            if let folder { Task { await loadFavorites(folderID: folder) } }
        }
    }

    private var identityHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(url: profile.avatar, name: profile.name, size: 54)
                .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name)
                    .font(.headline.weight(.bold)).foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .textSelection(.enabled)
                if !profile.uid.isEmpty {
                    Text("UID: \(profile.uid)")
                        .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.inkSoft)
                        .textSelection(.enabled)
                }
                if profile.memberTitle != nil || profile.groupTitle != nil {
                    HStack(spacing: 5) {
                        if let title = profile.memberTitle { profileChip(title, icon: "person.text.rectangle") }
                        if let group = profile.groupTitle { profileChip(group, icon: "person.2") }
                    }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(spacing: 7) {
                compactUserAction(followed == true ? "已关注" : "关注",
                                  systemImage: followed == true ? "checkmark" : "plus",
                                  prominent: true) {
                    Task { await toggleFollow() }
                }
                compactUserAction("私聊", systemImage: "bubble.left.and.bubble.right", prominent: false) {
                    openMessageComposer()
                }
            }
            .disabled(profile.isAnonymous)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [AppTheme.color(for: profile.name).opacity(0.20), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .glassSurface(radius: 18, fill: .clear)
    }

    private func compactUserAction(_ title: String, systemImage: String, prominent: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 76, height: 30)
                .foregroundStyle(prominent ? Color.white : AppTheme.brand)
                .background(prominent ? AnyShapeStyle(AppTheme.brand) : AnyShapeStyle(AppTheme.brand.opacity(0.10)),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var sectionPicker: some View {
        HStack(spacing: 3) {
            ForEach(Section.allCases) { item in
                Button(item.rawValue) { section = item }
                    .font(.subheadline.weight(section == item ? .bold : .medium))
                    .foregroundStyle(section == item ? AppTheme.forumAccent : AppTheme.inkSoft)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(section == item ? AppTheme.forumAccentSoft : .clear,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
        .padding(4).glassSurface(radius: 15)
    }

    @ViewBuilder private var sectionContent: some View {
        if loading { ProgressView("正在读取…").frame(maxWidth: .infinity).padding(30).tint(AppTheme.brand) }
        else {
            switch section {
            case .topics: topicList(topics, emptyTitle: "没有公开主题", emptyIcon: "text.bubble")
            case .replies: topicList(replies, emptyTitle: "没有公开回复", emptyIcon: "arrowshape.turn.up.left")
            case .favorites: favoritesContent
            case .signature: signatureContent
            }
        }
    }

    private func topicList(_ values: [Topic], emptyTitle: String, emptyIcon: String) -> some View {
        VStack(spacing: 10) {
            if values.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptyIcon,
                                       description: Text("NGA 未返回公开内容。"))
                    .frame(maxWidth: .infinity).padding(.vertical, 22).glassSurface(radius: 18)
            } else {
                ForEach(values) { topic in
                    NavigationLink { ReaderView(topic: topic, session: session) } label: {
                        userTopicRow(topic)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var favoritesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if folders.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(folders) { folder in
                            Button(folder.name) { selectedFolder = folder.id }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedFolder == folder.id ? .white : AppTheme.ink)
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(selectedFolder == folder.id ? AnyShapeStyle(AppTheme.brand) : AnyShapeStyle(AppTheme.cardSoft), in: Capsule())
                        }
                    }
                }
            }
            topicList(favorites, emptyTitle: "没有公开收藏", emptyIcon: "star")
        }
    }

    private var signatureContent: some View {
        Group {
            if let signature = profile.signature?.trimmingCharacters(in: .whitespacesAndNewlines), !signature.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("签名", systemImage: "signature").font(.headline).foregroundStyle(AppTheme.quietChrome)
                    NativeContentView(nodes: BBCode.parse(signature)).foregroundStyle(AppTheme.ink)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassSurface(radius: 18)
            } else {
                ContentUnavailableView("没有公开签名", systemImage: "signature",
                                       description: Text("NGA 未返回该用户的签名。"))
                    .frame(maxWidth: .infinity).padding(.vertical, 22).glassSurface(radius: 18)
            }
        }
    }

    private func userTopicRow(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.subject.isEmpty ? "（无标题）" : topic.subject)
                .font(.headline).foregroundStyle(AppTheme.ink).lineLimit(3)
            HStack(spacing: 10) {
                if let board = topic.sourceBoardName { Text(board).lineLimit(1) }
                Spacer()
                Label("\(topic.replies)", systemImage: "bubble.left")
                if let date = topic.date { Text(AppTheme.timeAgo(date)) }
                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
            }.font(.caption).foregroundStyle(AppTheme.inkSoft)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassSurface(radius: 17)
    }

    private func profileChip(_ value: String, icon: String) -> some View {
        Label(value, systemImage: icon).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.quietChrome)
            .padding(.horizontal, 7).frame(height: 22).background(AppTheme.cardSoft.opacity(0.78), in: Capsule())
    }

    private func statusBanner(_ text: String, warning: Bool) -> some View {
        Label(text, systemImage: warning ? "exclamationmark.triangle" : "checkmark.circle")
            .font(.footnote).foregroundStyle(warning ? AppTheme.alert : AppTheme.online)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background((warning ? AppTheme.alert : AppTheme.online).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor private func loadProfileAndRelationships() async {
        guard !profile.uid.isEmpty else { return }
        if let detail = try? await session.userDetail(profile) { profile = detail }
        guard session.isLoggedIn else { return }
        async let follow = try? session.followedUser(uid: profile.uid)
        async let block = try? session.blockedUser(uid: profile.uid)
        followed = await follow
        blocked = await block
    }

    @MainActor private func load(_ target: Section) async {
        guard !profile.uid.isEmpty else { return }
        error = nil
        switch target {
        case .signature: return
        case .topics where !topics.isEmpty, .replies where !replies.isEmpty, .favorites where !folders.isEmpty: return
        default: break
        }
        loading = true
        defer { loading = false }
        do {
            switch target {
            case .topics: topics = try await session.userTopics(uid: profile.uid).topics
            case .replies: replies = try await session.userTopics(uid: profile.uid, replies: true).topics
            case .favorites:
                folders = try await session.publicFavoriteFolders(uid: profile.uid)
                selectedFolder = folders.first?.id
                if let folder = selectedFolder { await loadFavorites(folderID: folder) }
            case .signature: break
            }
        } catch { self.error = session.network.describe(error) }
    }

    @MainActor private func loadFavorites(folderID: Int) async {
        loading = true; error = nil
        defer { loading = false }
        do { favorites = try await session.publicFavoriteTopics(folderID: folderID).topics }
        catch { self.error = session.network.describe(error); favorites = [] }
    }

    @MainActor private func toggleFollow() async {
        guard requireLogin() else { return }
        let add = followed != true
        do {
            try await session.followUser(uid: profile.uid, add: add)
            followed = add; notice = add ? "已关注 \(profile.name)" : "已取消关注"
        } catch { self.error = session.network.describe(error) }
    }

    @MainActor private func toggleBlock() async {
        guard requireLogin() else { return }
        let add = blocked != true
        do {
            try await session.blockUser(uid: profile.uid, add: add)
            blocked = add; notice = add ? "已将 \(profile.name) 加入私信黑名单" : "已取消拉黑"
        } catch { self.error = session.network.describe(error) }
    }

    private func openMessageComposer() {
        guard requireLogin() else { return }
        showingMessage = true
    }

    @discardableResult private func requireLogin() -> Bool {
        guard session.isLoggedIn else { error = "登录 NGA 后才能执行这个操作。"; return false }
        return true
    }

    private var messageComposer: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("收件人") { Text(profile.name); Text("UID: \(profile.uid)").font(.caption).foregroundStyle(.secondary) }
                SwiftUI.Section("主题") { TextField("私信主题", text: $messageSubject) }
                SwiftUI.Section("内容") { TextEditor(text: $messageBody).frame(minHeight: 150) }
            }
            .navigationTitle("发起私聊").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showingMessage = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { Task { await sendMessage() } }
                        .disabled(messageSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor private func sendMessage() async {
        do {
            try await session.sendPrivateMessage(uid: profile.uid, subject: messageSubject, content: messageBody)
            showingMessage = false; messageSubject = ""; messageBody = ""; notice = "私信已发送"
        } catch { showingMessage = false; self.error = session.network.describe(error) }
    }
}
