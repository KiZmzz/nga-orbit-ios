import SwiftUI
import NGAKit

/// The "版块星河" home screen.
///
/// The user's boards are rendered as a constellation — each a "star" card carrying a stable
/// colour derived from its `fid`. A teal hero card anchors the NGA connection state; everything
/// else stays quiet so the constellation is the one memorable thing.
struct BoardListView: View {
    let session: SessionStore
    @State private var store = BoardStore()
    @State private var showingAccount = false
    @State private var showingCatalog = false
    @State private var debugBoard: Board?
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    SessionHero(session: session) { showingAccount = true }
                    boardSection
                    catalogSection
                    footerNote
                }
                .padding(.horizontal, AppTheme.pad)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .pageCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAccount) { AccountView(session: session) }
            .sheet(isPresented: $showingCatalog) { BoardCatalogView(session: session, store: store) }
            .sheet(item: $debugBoard) { board in TopicListView(board: board, session: session, store: store) }
            .onAppear { handleDebugLaunch() }
        }
    }

    /// Development helper: a launch argument can auto-open a screen so it can be verified by
    /// screenshot without tapping on the phone. `--dsh-catalog` opens the board catalogue;
    /// `--dsh-board <fid>` opens a board's topic list. Normal launches are unaffected.
    private func handleDebugLaunch() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--dsh-catalog") { showingCatalog = true }
        else if let i = args.firstIndex(of: "--dsh-board"),
                i + 1 < args.count, let fid = Int(args[i + 1]) {
            debugBoard = Board(id: fid, name: "版块 \(fid)")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("版块")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Button { showingAccount = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("账户与连接")
        }
        .padding(.top, 4)
    }

    // MARK: Sections

    @ViewBuilder private var boardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("我的版块").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                Spacer()
                Text("\(store.boards.count) 个版块").font(.footnote.monospacedDigit()).foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.horizontal, 4)

            if store.boards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("还没有版块", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Text("前往版块目录，在具体版面上点星标收藏。").font(.footnote).foregroundStyle(AppTheme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: AppTheme.radiusCard))
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.boards) { board in
                        NavigationLink {
                            TopicListView(board: board, session: session, store: store)
                        } label: {
                            BoardCard(board: board)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Catalogue entry

    @ViewBuilder private var catalogSection: some View {
        Button { showingCatalog = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(AppTheme.brand.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: "square.grid.2x2").font(.system(size: 20, weight: .semibold)).foregroundStyle(AppTheme.brand)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("浏览版块目录").font(.headline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Text("按分类或名字查找具体版面").font(.footnote).foregroundStyle(AppTheme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.inkSoft.opacity(0.55))
            }
            .padding(14)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.radiusCard))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var footerNote: some View {
        Text("这里仅展示你从版块目录收藏的具体版面。")
            .font(.footnote).foregroundStyle(AppTheme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

}

// MARK: - Board "star" card

struct BoardCard: View {
    let board: Board
    var body: some View {
        let color = AppTheme.starColor(for: board.id)
        let initial = board.name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "版"
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.16))
                    Text(initial)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: 46, height: 46)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.inkSoft.opacity(0.55))
            }
            Spacer(minLength: 8)
            Text(board.name).font(.headline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 134)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.radiusCard).stroke(color.opacity(0.20), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            RadialGradient(colors: [color.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 130)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusCard))
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusCard))
    }
}

// MARK: - Session hero card

struct SessionHero: View {
    let session: SessionStore
    let onTap: () -> Void

    var body: some View {
        let loggedIn = session.isLoggedIn
        let dot = loggedIn ? AppTheme.online : AppTheme.alert
        let status = loggedIn ? "已连接 NGA" : "需要完成网页验证"
        let headline = loggedIn ? "登录生效，专注读帖" : "连接 NGA，进入你的版块"
        let subline = loggedIn
            ? session.status
            : "先完成一次 NGA 网页验证或登录，就能浏览实时的主题与帖子。"
        let cta = loggedIn ? "管理 NGA 会话" : "连接 NGA"

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 9, height: 9)
                    .shadow(color: dot.opacity(0.6), radius: 3)
                Text(status).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.94))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(headline).font(.title2.weight(.bold)).foregroundStyle(.white)
                Text(subline).font(.footnote).foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Text(cta).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.brandDeep)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [AppTheme.brandDeep, AppTheme.brand],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(alignment: .topTrailing) {
            // A faint field of dots — a whisper of the constellation.
            ZStack {
                Circle().fill(.white.opacity(0.12)).frame(width: 4)
                Circle().fill(.white.opacity(0.10)).frame(width: 3).offset(x: 22, y: 8)
                Circle().fill(.white.opacity(0.08)).frame(width: 5).offset(x: -16, y: 26)
            }
            .padding(18)
        }
    }
}
