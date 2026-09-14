import SwiftUI
import NGAKit

/// 我的: session summary card, then a grouped list of account actions, then "更多" placeholders.
struct ProfileView: View {
    @Bindable var session: SessionStore
    @Binding var tabBarVisibility: Visibility
    @State private var website: WebsitePurpose?
    @State private var clearing = false
    @AppStorage("nga.appearance") private var appearance = AppearancePreference.system.rawValue
    enum WebsitePurpose: String, Identifiable { case verify, login; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                sessionCard
                personalContent
                appearanceGroup
                settingsGroup
                moreGroup
            }
            .padding(AppTheme.pad).padding(.top, 6).padding(.bottom, 40)
        }
        .sceneCanvas()
        .sheet(item: $website) { purpose in WebsiteLogin(session: session, login: purpose == .login) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("我的").font(.system(size: 32, weight: .heavy)).foregroundStyle(AppTheme.ink)
            Text("属于你的阅读空间").font(.footnote.weight(.medium)).foregroundStyle(AppTheme.inkSoft)
        }
    }

    private var sessionCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(AppTheme.brand.opacity(0.18)).frame(width: 190, height: 190).blur(radius: 34).offset(x: 66, y: 78)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(.ultraThinMaterial).frame(width: 66, height: 66)
                        AvatarView(url: session.accountProfile?.avatar,
                                   name: session.accountProfile?.name ?? (session.isLoggedIn ? "我" : "访客"),
                                   size: 56)
                    }
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.accountProfile?.name ?? (session.isLoggedIn ? "已连接 NGA" : "尚未登录"))
                            .font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                        Label(session.host.rawValue, systemImage: "globe.asia.australia.fill")
                            .font(.caption).foregroundStyle(AppTheme.inkSoft)
                    }
                    Spacer()
                    Circle().fill(session.isLoggedIn ? AppTheme.online : AppTheme.alert).frame(width: 10, height: 10)
                }
                Button { website = .login } label: {
                    HStack {
                        Text(session.isLoggedIn ? "管理账户与连接" : "连接 NGA")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(AppTheme.brand)
                    .padding(.horizontal, 14).frame(height: 42)
                    .background(AppTheme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(18)
        }
        .glassSurface(radius: 26)
    }

    private var personalContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("我的内容").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink).padding(.leading, 4)
            HStack(spacing: 12) {
                NavigationLink { FavoriteTopicsView(session: session, tabBarVisibility: $tabBarVisibility) } label: {
                    PersonalContentTile(title: "收藏的主题", subtitle: "服务端收藏夹", systemImage: "star.fill", accent: AppTheme.forumAccent)
                }.buttonStyle(.plain)
                if let uid = session.accountUID {
                    NavigationLink {
                        NGAUserView(user: session.accountProfile ?? NGAUser(uid: uid, name: "我的资料"),
                                    posts: [], session: session)
                    } label: {
                        PersonalContentTile(title: "个人资料", subtitle: "主题与回复", systemImage: "person.text.rectangle.fill", accent: AppTheme.brand)
                    }.buttonStyle(.plain)
                } else {
                    Button { website = .login } label: {
                        PersonalContentTile(title: "登录账户", subtitle: "解锁收藏与私信", systemImage: "person.badge.key.fill", accent: AppTheme.brand)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var settingsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("功能与设置").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink).padding(.leading, 4)
            VStack(spacing: 0) {
                ProfileRow(title: "NGA 站点与连接", systemImage: "globe") { website = .login }
                ProfileDivider()
                ProfileRow(title: "打开网页完成访问验证", systemImage: "arrow.up.forward.square") { website = .verify }
                ProfileDivider()
                destructiveRow
            }
            .glassSurface(radius: 20)
        }
    }

    private var destructiveRow: some View {
        Button {
            clearing = true
            Task { await session.clear(); clearing = false }
        } label: {
            HStack {
                Label("清除本机 NGA 会话", systemImage: "trash").foregroundStyle(.red).font(.subheadline.weight(.semibold))
                Spacer()
                if clearing { ProgressView().tint(.red) }
            }.padding(.horizontal, 14).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private var appearanceGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("外观").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink).padding(.leading, 4)
            HStack(spacing: 8) {
                ForEach(AppearancePreference.allCases) { option in
                    Button {
                        appearance = option.rawValue
                    } label: {
                        Text(option.title).font(.subheadline.weight(option.rawValue == appearance ? .bold : .medium))
                            .foregroundStyle(option.rawValue == appearance ? AppTheme.forumAccent : AppTheme.inkSoft)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(option.rawValue == appearance ? AppTheme.forumAccentSoft : .clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("外观：\(option.title)")
                }
            }
            .padding(4).glassSurface(radius: 16)
            Text("默认跟随 iPhone 的浅色或深色外观。").font(.caption).foregroundStyle(AppTheme.inkSoft).padding(.leading, 4)
        }
    }

    private var moreGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于与存储").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink).padding(.leading, 4)
            VStack(spacing: 0) {
                ProfileRow(title: "缓存管理", systemImage: "internaldrive", trailing: "开发中") { }
                ProfileDivider()
                ProfileRow(title: "关于 NGA Orbit", systemImage: "info.circle", trailing: "0.1.0") { }
            }
            .glassSurface(radius: 20)
        }
    }
}

private struct PersonalContentTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.16))
                Image(systemName: systemImage).font(.title3.weight(.semibold)).foregroundStyle(accent)
            }.frame(width: 44, height: 44)
            Spacer(minLength: 4)
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(AppTheme.ink)
            Text(subtitle).font(.caption).foregroundStyle(AppTheme.inkSoft).lineLimit(1)
        }
        .padding(15).frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
        .glassSurface(radius: 22, fill: accent.opacity(0.08))
    }
}

private struct ProfileDivider: View {
    var body: some View { Divider().overlay(AppTheme.line.opacity(0.55)).padding(.leading, 56) }
}

private struct ProfileRow: View {
    let title: String
    let systemImage: String
    var trailing: String = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ProfileRowContent(title: title, systemImage: systemImage, trailing: trailing)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileRowContent: View {
    let title: String
    let systemImage: String
    var trailing: String = ""
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(AppTheme.brand.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: systemImage).font(.system(size: 15)).foregroundStyle(AppTheme.brand)
            }
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.ink)
            Spacer()
            if !trailing.isEmpty { Text(trailing).font(.caption).foregroundStyle(AppTheme.inkSoft) }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.inkSoft.opacity(0.5))
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
    }
}

private struct FavoriteTopicsView: View {
    let session: SessionStore
    let tabBarVisibility: Binding<Visibility>
    @State private var folders: [FavoriteFolder] = []
    @State private var selectedFolder = 1
    @State private var topics: [Topic] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Group {
            if !session.isLoggedIn {
                ContentUnavailableView("需要登录 NGA", systemImage: "person.crop.circle.badge.exclamationmark",
                                       description: Text("登录后可读取账号默认收藏夹中的主题。"))
            } else if loading && topics.isEmpty {
                ProgressView("正在读取收藏…").tint(AppTheme.brand)
            } else if let error, topics.isEmpty {
                ContentUnavailableView("收藏读取失败", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if topics.isEmpty {
                VStack(spacing: 0) {
                    folderPicker
                    ContentUnavailableView("这个收藏夹还是空的", systemImage: "star",
                                           description: Text("在帖子详情页点右上角星标即可收藏。"))
                }
            } else {
                VStack(spacing: 0) {
                    folderPicker
                    ScrollView {
                      LazyVStack(spacing: 10) {
                        ForEach(topics) { topic in
                            NavigationLink { ReaderView(topic: topic, session: session, tabBarVisibility: tabBarVisibility) } label: {
                                FavoriteTopicRow(topic: topic)
                            }.buttonStyle(.plain)
                        }
                        if hasMore {
                            Button(loading ? "正在载入…" : "载入更多") { Task { await load(page + 1, append: true) } }
                                .disabled(loading).buttonStyle(.bordered).tint(AppTheme.brand).padding(.vertical, 8)
                        }
                      }.padding(AppTheme.pad)
                    }.refreshable { await load(1, append: false) }
                }
            }
        }
        .sceneCanvas()
        .navigationTitle("收藏的主题").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: session.revision) {
            if session.isLoggedIn { await loadFolders() }
        }
        .onChange(of: selectedFolder) { _, _ in Task { await load(1, append: false) } }
    }

    private var folderPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(folders) { folder in
                    Button { selectedFolder = folder.id } label: {
                        HStack(spacing: 6) {
                            Text(folder.name)
                            if folder.isDefault || folder.id == 1 {
                                Text("默认").font(.caption2.weight(.semibold))
                                    .foregroundStyle(selectedFolder == folder.id ? AppTheme.brand : AppTheme.inkSoft)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(selectedFolder == folder.id ? Color.white.opacity(0.92) : AppTheme.cardSoft, in: Capsule())
                            }
                            if let count = folder.count { Text("\(count)").opacity(0.68) }
                        }
                        .font(.subheadline.weight(selectedFolder == folder.id ? .bold : .medium))
                        .foregroundStyle(selectedFolder == folder.id ? .white : AppTheme.ink)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(selectedFolder == folder.id ? AnyShapeStyle(AppTheme.brand) : AnyShapeStyle(AppTheme.glassFill), in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.glassStroke))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, AppTheme.pad).padding(.vertical, 10)
        }
    }

    @MainActor private func loadFolders() async {
        loading = true; error = nil
        do {
            let result = try await session.favoriteFolders()
            folders = result.isEmpty ? [FavoriteFolder(id: 1, name: "默认收藏夹")] : result
            if !folders.contains(where: { $0.id == selectedFolder }) { selectedFolder = folders[0].id }
            loading = false
            await load(1, append: false)
        } catch {
            // The topic endpoint remains useful when an older NGA node does not
            // expose folder metadata.
            folders = [FavoriteFolder(id: 1, name: "默认收藏夹")]
            loading = false
            await load(1, append: false)
        }
    }

    @MainActor private func load(_ requestedPage: Int, append: Bool) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await session.favoriteTopics(folderID: selectedFolder, page: requestedPage)
            topics = append ? topics + result.topics.filter { item in !topics.contains(where: { $0.id == item.id }) } : result.topics
            page = result.page; hasMore = result.hasMore
        } catch { self.error = session.network.describe(error) }
    }
}

private struct FavoriteTopicRow: View {
    let topic: Topic
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.subject).font(.headline).foregroundStyle(AppTheme.ink)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(topic.author.isEmpty ? "NGA 用户" : topic.author)
                Spacer()
                Label("\(topic.replies)", systemImage: "bubble.left")
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }.font(.caption).foregroundStyle(AppTheme.inkSoft)
        }
        .padding(14).glassSurface(radius: 17)
    }
}
