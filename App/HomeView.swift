import SwiftUI
import NGAKit
import Observation

/// 首页: editorial entry point with one strong continue-reading story, a compact
/// board shelf and recent threads. All content remains backed by local history or
/// the user's real board favourites.
struct HomeView: View {
    let session: SessionStore
    let store: BoardStore
    @Binding var tabBarVisibility: Visibility
    @State private var showingAccount = false
    @State private var history = ReadingHistoryStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                readingHero
                boardSection
                recentSection
            }
            .padding(.horizontal, AppTheme.pad)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .sceneCanvas()
        .sheet(isPresented: $showingAccount) { AccountView(session: session) }
    }

    @ViewBuilder private var recentSection: some View {
        if history.items.count > 1 {
            VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近阅读").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                Spacer()
                Button("清除") { history.clear() }.font(.caption).foregroundStyle(AppTheme.inkSoft)
            }
            VStack(spacing: 0) {
                    ForEach(Array(history.items.dropFirst().prefix(3).enumerated()), id: \.element.id) { index, item in
                        NavigationLink { ReaderView(topic: item.topic, board: item.board, session: session, tabBarVisibility: $tabBarVisibility) } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill((item.board.map { AppTheme.starColor(for: $0.id) } ?? AppTheme.brand).opacity(0.16))
                                    Image(systemName: "text.bubble")
                                        .foregroundStyle(item.board.map { AppTheme.starColor(for: $0.id) } ?? AppTheme.brand)
                                }
                                .frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.subject).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink).lineLimit(2)
                                    HStack(spacing: 6) {
                                        if let board = item.board { Text(board.name).lineLimit(1) }
                                        Text(AppTheme.timeAgo(item.openedAt))
                                    }.font(.caption).foregroundStyle(AppTheme.inkSoft)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.inkSoft.opacity(0.55))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }.buttonStyle(.plain)
                        if index < min(history.items.count - 2, 2) {
                            Divider().overlay(AppTheme.line.opacity(0.55)).padding(.leading, 68)
                        }
                    }
            }
            .glassSurface(radius: 20)
            }
        }
    }

    @ViewBuilder private var readingHero: some View {
        if let item = history.items.first {
            NavigationLink { ReaderView(topic: item.topic, board: item.board, session: session, tabBarVisibility: $tabBarVisibility) } label: {
                ZStack(alignment: .bottomLeading) {
                    if let artwork = AppTheme.boardArtwork(for: item.board?.name) {
                        GeometryReader { proxy in
                            Image(uiImage: artwork)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        }
                    } else {
                        LinearGradient(
                            colors: [
                                item.board.map { AppTheme.starColor(for: $0.id) } ?? AppTheme.brand,
                                AppTheme.brandDeep,
                                Color.black.opacity(0.82)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                    LinearGradient(colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("继续阅读")
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        Text(item.subject).font(.title3.weight(.bold)).foregroundStyle(.white).lineLimit(3)
                        HStack {
                            Text(item.board?.name ?? item.author).lineLimit(1)
                            Spacer()
                            Text(AppTheme.timeAgo(item.openedAt))
                            Image(systemName: "arrow.right.circle.fill").font(.title3)
                        }.font(.caption).foregroundStyle(.white.opacity(0.76))
                    }.padding(18)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.42), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
            }.buttonStyle(.plain)
        } else {
            Button { showingAccount = true } label: {
                ZStack(alignment: .bottomLeading) {
                    if let artwork = AppTheme.bundledArtwork(named: "BoardAzeroth") {
                        GeometryReader { proxy in
                            Image(uiImage: artwork)
                                .resizable().scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        }
                    } else {
                        LinearGradient(colors: [AppTheme.brand, AppTheme.brandDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    LinearGradient(colors: [.clear, Color.black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("开始你的 NGA 阅读空间").font(.title3.weight(.bold)).foregroundStyle(.white)
                        Text("连接 NGA 后浏览真实版块与主题")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.76))
                        Spacer()
                        Label(session.isLoggedIn ? "会话已连接" : "连接 NGA", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }.padding(18)
                }
                .frame(height: 184)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 9)
            }.buttonStyle(.plain)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("NGA Orbit")
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("聚集热爱 · 分享真实").font(.footnote.weight(.medium)).foregroundStyle(AppTheme.inkSoft)
            }
            Spacer()
            Button { showingAccount = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(url: session.accountProfile?.avatar,
                               name: session.accountProfile?.name ?? (session.isLoggedIn ? "我" : "访客"),
                               size: 46)
                    Circle().fill(session.isLoggedIn ? AppTheme.online : AppTheme.alert)
                        .frame(width: 11, height: 11).overlay(Circle().stroke(AppTheme.page, lineWidth: 2))
                }
            }.accessibilityLabel("账户与连接")
        }
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("我的版块").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                Spacer()
                Text("共 \(store.boards.count) 个收藏").font(.footnote).foregroundStyle(AppTheme.inkSoft)
            }
            if store.boards.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "star").font(.title3).foregroundStyle(AppTheme.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("还没有收藏版面").font(.headline).foregroundStyle(AppTheme.ink)
                        Text("前往“版块”页，在具体版面卡片上点星标收藏。")
                            .font(.caption).foregroundStyle(AppTheme.inkSoft)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(radius: 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.boards) { board in
                            NavigationLink { TopicListView(board: board, session: session, store: store, tabBarVisibility: $tabBarVisibility) } label: {
                                ZStack(alignment: .bottomLeading) {
                                    if let artwork = AppTheme.boardArtwork(for: board.name) {
                                        GeometryReader { proxy in
                                            Image(uiImage: artwork)
                                                .resizable().scaledToFill()
                                                .frame(width: proxy.size.width, height: proxy.size.height)
                                                .clipped()
                                        }
                                        LinearGradient(colors: [.clear, Color.black.opacity(0.78)],
                                                       startPoint: .top, endPoint: .bottom)
                                    }
                                    VStack(alignment: .leading, spacing: 13) {
                                        BoardIcon(board: board, size: 42)
                                        Spacer(minLength: 0)
                                        Text(board.name)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(AppTheme.boardArtworkName(for: board.name) == nil ? AppTheme.ink : .white)
                                            .lineLimit(2)
                                    }
                                    .padding(14)
                                }
                                .frame(width: 142, height: 132, alignment: .leading)
                                .glassSurface(radius: 20, fill: AppTheme.starWash(for: board.id))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
    }

}

struct RecentTopic: Codable, Identifiable, Hashable {
    let id: Int
    let subject: String
    let author: String
    let replies: Int
    let board: Board?
    let openedAt: Date
    var topic: Topic { Topic(id: id, subject: subject, author: author, replies: replies, date: nil) }
}

@MainActor @Observable final class ReadingHistoryStore {
    static let shared = ReadingHistoryStore()
    private let key = "nga.reading-history.v1"
    var items: [RecentTopic]
    private init() {
        items = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([RecentTopic].self, from: $0) } ?? []
    }
    func record(_ topic: Topic, board: Board?) {
        guard topic.id > 0, !topic.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.id == topic.id }
        items.insert(RecentTopic(id: topic.id, subject: topic.subject, author: topic.author,
                                 replies: topic.replies, board: board, openedAt: Date()), at: 0)
        if items.count > 20 { items.removeLast(items.count - 20) }
        persist()
    }
    func clear() { items = []; persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// A list-style board row used on the home screen.
struct BoardHomeRow: View {
    let board: Board
    var body: some View {
        HStack(spacing: 12) {
            BoardIcon(board: board)
            Text(board.name).font(.headline.weight(.semibold)).foregroundStyle(AppTheme.ink).lineLimit(2)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.inkSoft.opacity(0.5))
        }
        .padding(12)
        .glassSurface(radius: 18, fill: AppTheme.starWash(for: board.id))
    }
}

/// Session status card with stat chips and a manage-session action.
struct SessionHeroCard: View {
    let session: SessionStore
    let onTap: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(session.isLoggedIn ? AppTheme.online : AppTheme.alert).frame(width: 9, height: 9)
                Text(session.isLoggedIn ? "已连接" : "未连接").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                Spacer()
            }
            Text(session.isLoggedIn ? "已登录 · \(session.status)" : "登录 NGA，发现更大的世界")
                .font(.footnote).foregroundStyle(AppTheme.inkSoft).lineLimit(2)
            HStack(spacing: 8) {
                StatChip(label: "当前站点", value: session.host.rawValue)
                StatChip(label: "网络状态", value: session.network.available ? "正常" : "受限")
                StatChip(label: "登录状态", value: session.isLoggedIn ? "Cookie 有效" : "未登录")
                Spacer()
                Button(action: onTap) {
                    Text("管理会话").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.brand)
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .background(AppTheme.brand.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassSurface(radius: 24)
    }
}

struct StatChip: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(AppTheme.inkSoft)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(AppTheme.cardSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}
