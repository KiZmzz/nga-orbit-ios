import SwiftUI
import NGAKit

/// 消息: private messages, interaction reminders and system notices.
struct MessagesView: View {
    let session: SessionStore
    @Binding var tabBarVisibility: Visibility
    @State private var kind: Kind = .interactions
    @State private var items: [Message] = []
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()

    enum Kind: String, CaseIterable, Identifiable {
        case interactions = "互动", dms = "私信", system = "系统"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .interactions: "at"
            case .dms: "bubble.left.and.bubble.right"
            case .system: "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: kind) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("消息")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if !items.isEmpty {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.brand)
                            .frame(width: 44, height: 32, alignment: .trailing)
                    }
                    .accessibilityLabel("刷新")
                }
            }

            HStack(spacing: 8) {
                ForEach(Kind.allCases) { tab in
                    Button {
                        guard kind != tab else { return }
                        kind = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol).font(.caption.weight(.semibold))
                            Text(tab.rawValue).font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(kind == tab ? Color.white : AppTheme.ink)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(kind == tab ? AppTheme.brand : AppTheme.brand.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AppTheme.pad)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var content: some View {
        if loading && items.isEmpty {
            ProgressView("正在读取…")
                .tint(AppTheme.brand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, items.isEmpty {
            emptyState(
                title: "消息暂时读取失败",
                detail: error,
                systemImage: "wifi.exclamationmark",
                actionTitle: "重试"
            ) { Task { await load() } }
        } else if items.isEmpty {
            emptyState(
                title: emptyTitle,
                detail: emptyHint,
                systemImage: kind == .dms ? "bubble.left.and.bubble.right" : "tray",
                actionTitle: nil
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, message in
                        messageItem(message)
                        if index < items.count - 1 {
                            Divider().overlay(AppTheme.line.opacity(0.5)).padding(.leading, 72)
                        }
                    }
                }
                .padding(.vertical, 8)
                .glassSurface(radius: 24)
                .padding(.horizontal, AppTheme.pad)
                .padding(.top, 12).padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .sceneCanvas()
            .refreshable { await load() }
        }
    }

    @ViewBuilder private func emptyState(
        title: String,
        detail: String,
        systemImage: String,
        actionTitle: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(AppTheme.brand.opacity(0.75))
            Text(title).font(.headline.weight(.semibold)).foregroundStyle(AppTheme.ink)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let actionTitle, let action {
                Button(actionTitle) { action() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.brand)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sceneCanvas()
    }

    @ViewBuilder private func messageItem(_ message: Message) -> some View {
        if message.kind == .direct {
            NavigationLink {
                PrivateMessageDetailView(conversation: message, session: session)
            } label: {
                MessageCard(message: message)
            }
            .buttonStyle(.plain)
        } else if let tid = message.topicID, tid > 0 {
            NavigationLink {
                ReaderView(topic: Topic(id: tid, subject: message.title, author: message.sender,
                                        replies: 0, date: message.date),
                           session: session, tabBarVisibility: $tabBarVisibility)
                    .id(tid)
            } label: {
                MessageCard(message: message)
            }
            .buttonStyle(.plain)
        } else {
            MessageCard(message: message, showsChevron: false)
        }
    }

    private var emptyTitle: String {
        switch kind { case .interactions: "没有互动提醒"; case .dms: "没有私信"; case .system: "没有系统消息" }
    }
    private var emptyHint: String {
        switch kind {
        case .interactions: "回复、@、点赞等提醒会出现在这里。"
        case .dms: "别人发给你的私信会出现在这里，点进去可以回复。"
        case .system: "系统通知会出现在这里。"
        }
    }

    @MainActor private func load() async {
        let token = UUID(); requestID = token
        loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            let result: [Message]
            switch kind {
            case .dms: result = try await session.messages()
            case .interactions:
                result = try await session.notifications().filter { $0.kind == .interaction }
            case .system:
                result = try await session.notifications().filter { $0.kind == .system }
            }
            guard !Task.isCancelled, token == requestID else { return }
            items = result
        } catch {
            if !Task.isCancelled, token == requestID { self.error = session.network.describe(error) }
        }
    }
}

// MARK: - List card

private struct MessageCard: View {
    let message: Message
    var showsChevron = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarCircle(name: message.sender, size: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.sender)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = message.date {
                        Text(AppTheme.timeAgo(date))
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkSoft)
                            .layoutPriority(1)
                    }
                }

                Text(message.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)
                        .lineLimit(2)
                } else if message.kind == .direct {
                    Text("打开会话查看内容")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft.opacity(0.85))
                }
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkSoft.opacity(0.45))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Conversation detail (Apple Messages)

private struct PrivateMessageDetailView: View {
    let conversation: Message
    let session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var posts: [Message] = []
    @State private var participants: [String: String] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var actionError: String?
    @State private var showingInvite = false
    @State private var showingLeaveConfirm = false
    @State private var inviteUsername = ""
    @State private var workingAction = false
    @FocusState private var composerFocused: Bool

    /// NGA requires both subject and content. Reuse the conversation title.
    private var replySubject: String {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "无标题" : title
    }

    private var partnerTitle: String {
        conversation.sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "私信" : conversation.sender
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle(partnerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        inviteUsername = ""
                        showingInvite = true
                    } label: {
                        Label("邀请加入对话", systemImage: "person.badge.plus")
                    }
                    Button(role: .destructive) {
                        showingLeaveConfirm = true
                    } label: {
                        Label("退出对话", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.brand)
                }
                .disabled(workingAction)
            }
        }
        .refreshable { await load() }
        .task(id: conversation.id) { await load() }
        .alert("邀请用户加入对话", isPresented: $showingInvite) {
            TextField("用户名", text: $inviteUsername)
            Button("取消", role: .cancel) {}
            Button("邀请") { Task { await invite() } }
                .disabled(inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("输入对方的 NGA 用户名，不是 UID。")
        }
        .confirmationDialog(
            "退出这个对话？",
            isPresented: $showingLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("退出对话", role: .destructive) { Task { await leave() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后将不再接收这个会话的消息。")
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if loading && posts.isEmpty {
                        ProgressView("正在读取…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 72)
                            .tint(AppTheme.brand)
                    } else if error != nil, posts.isEmpty {
                        errorPlaceholder
                    } else if posts.isEmpty {
                        ContentUnavailableView("没有私信内容", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("这个会话暂时没有正文。"))
                            .padding(.top, 72)
                    } else {
                        threadMeta
                        ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                            if let stamp = dateSeparator(at: index) {
                                Text(stamp)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AppTheme.inkSoft)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            MessageBubble(
                                post: post,
                                isMine: isMine(post),
                                showsName: shouldShowName(at: index)
                            )
                            .id(post.id)
                        }
                        if let sendError {
                            inlineNotice(sendError)
                        }
                        if let actionError {
                            inlineNotice(actionError)
                        }
                    }
                    Color.clear.frame(height: 10)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemBackground))
            .onChange(of: posts.count) {
                guard let last = posts.last else { return }
                withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var threadMeta: some View {
        VStack(spacing: 6) {
            Text(conversation.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
            let names = participantNames()
            if !names.isEmpty {
                Text(names)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private func participantNames() -> String {
        var names = participants.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.isEmpty {
            names = Set(posts.compactMap { post -> String? in
                guard !isMine(post) else { return nil }
                let name = post.sender.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty || name == "NGA 用户" ? nil : name
            }).sorted()
        }
        guard !names.isEmpty else { return "" }
        return "参与对话：" + names.joined(separator: "、")
    }

    private var errorPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.inkSoft)
            Text("私信读取失败").font(.headline).foregroundStyle(AppTheme.ink)
            Text(error ?? "")
                .font(.footnote)
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
            Button("重试") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 64)
    }

    private func inlineNotice(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppTheme.alert)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.top, 8)
    }

    /// Centered timestamp when the gap since the previous bubble is large.
    private func dateSeparator(at index: Int) -> String? {
        guard let date = posts[index].date else { return nil }
        if index == 0 { return absoluteStamp(date) }
        guard let previous = posts[index - 1].date else { return absoluteStamp(date) }
        if date.timeIntervalSince(previous) >= 3600 { return absoluteStamp(date) }
        return nil
    }

    private func absoluteStamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return AppTheme.timeAgo(date) }
        if calendar.isDateInYesterday(date) {
            return "昨天 " + date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func shouldShowName(at index: Int) -> Bool {
        let current = posts[index]
        if isMine(current) { return false }
        guard index > 0 else { return true }
        let previous = posts[index - 1]
        return isMine(previous) || previous.authorUID != current.authorUID
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("信息", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.line, lineWidth: 1)
                    )
                    .focused($composerFocused)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canSend ? AppTheme.brand : AppTheme.brand.opacity(0.3))
                }
                .disabled(!canSend || sending)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isMine(_ post: Message) -> Bool {
        guard let uid = session.accountUID, let author = post.authorUID, !author.isEmpty else { return false }
        return uid == author
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let thread = try await session.privateMessageThread(mid: conversation.id)
            posts = thread.posts
            participants = thread.participants
        } catch {
            self.error = session.network.describe(error)
        }
    }

    @MainActor private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            try await session.replyPrivateMessage(mid: conversation.id, subject: replySubject, content: text)
            draft = ""
            composerFocused = false
            await load()
        } catch {
            sendError = session.network.describe(error)
        }
    }

    @MainActor private func invite() async {
        let name = inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !workingAction else { return }
        workingAction = true
        actionError = nil
        defer { workingAction = false }
        do {
            try await session.inviteToPrivateMessage(mid: conversation.id, username: name)
            await load()
        } catch {
            actionError = session.network.describe(error)
        }
    }

    @MainActor private func leave() async {
        guard !workingAction else { return }
        workingAction = true
        actionError = nil
        defer { workingAction = false }
        do {
            try await session.leavePrivateMessage(mid: conversation.id)
            dismiss()
        } catch {
            actionError = session.network.describe(error)
        }
    }
}

private struct MessageBubble: View {
    let post: Message
    let isMine: Bool
    let showsName: Bool

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            if showsName && !isMine {
                Text(post.sender)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.quietChrome)
                    .padding(.leading, 12)
            }

            HStack {
                if isMine { Spacer(minLength: 52) }

                content
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isMine ? AppTheme.brand : Color(uiColor: .secondarySystemBackground))
                    )
                    .frame(maxWidth: 280, alignment: isMine ? .trailing : .leading)

                if !isMine { Spacer(minLength: 52) }
            }

            if let date = post.date {
                Text(AppTheme.timeAgo(date))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkSoft.opacity(0.85))
                    .padding(.horizontal, 8)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let body = post.body, !body.isEmpty {
            // Keep BBCode layout, but force the chat text colour.
            NativeContentView(nodes: BBCode.parse(body))
                .environment(\.colorScheme, isMine ? .dark : .light)
                .foregroundStyle(isMine ? .white : AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("（空消息）")
                .font(.subheadline)
                .foregroundStyle(isMine ? Color.white.opacity(0.8) : AppTheme.inkSoft)
        }
    }
}
