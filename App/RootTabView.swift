import SwiftUI
import NGAKit

/// Root shell: the three tabs (首页 / 版块 / 我的) over a glass scene.
struct RootTabView: View {
    let session: SessionStore
    @State private var store = BoardStore()
    @State private var tab = 0
    /// Kept for destination initializer compatibility; the outer NavigationStack
    /// now owns the transition, so the tab bar leaves and returns with the root.
    @State private var tabBarVisibility: Visibility = .visible
    @State private var debugBoard: Board?
    @State private var debugTopic: Topic?
    @State private var demo = false

    var body: some View {
        NavigationStack {
            TabView(selection: $tab) {
                HomeView(session: session, store: store, tabBarVisibility: $tabBarVisibility)
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(0)
                CommunityView(session: session, store: store, tabBarVisibility: $tabBarVisibility)
                    .tabItem { Label("版块", systemImage: "square.grid.2x2") }
                    .tag(1)
                MessagesView(session: session, tabBarVisibility: $tabBarVisibility)
                    .tabItem { Label("消息", systemImage: "envelope.badge") }
                    .tag(2)
                ProfileView(session: session, tabBarVisibility: $tabBarVisibility)
                    .tabItem { Label("我的", systemImage: "person.crop.circle") }
                    .tag(3)
            }
            .tint(AppTheme.brand)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $debugBoard) { b in NavigationStack { TopicListView(board: b, session: session, store: store) } }
        .fullScreenCover(item: $debugTopic) { t in NavigationStack { ReaderView(topic: t, session: session) } }
        .sheet(isPresented: $demo) { DemoReaderView() }
        .onAppear { handleDebugLaunch() }
        .task(id: session.accountUID) {
            guard session.isLoggedIn else { return }
            guard let boards = try? await session.favoriteBoards(), !Task.isCancelled else { return }
            store.replace(with: boards)
        }
    }

    /// Dev helper: `--dsh-tab <0|1|2>`, `--dsh-board <fid>`, `--dsh-read <tid>`, `--dsh-demo`.
    /// Add `--dsh-ui-preview` to render local data for visual QA; it never affects normal launches.
    /// open the matching screen so it can be screenshotted without tapping.
    private func handleDebugLaunch() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--dsh-demo") { demo = true }
        else if let i = args.firstIndex(of: "--dsh-tab"), i + 1 < args.count, let t = Int(args[i + 1]) { tab = t }
        else if let i = args.firstIndex(of: "--dsh-board"), i + 1 < args.count, let fid = Int(args[i + 1]) {
            debugBoard = Board(id: fid, name: "版块 \(fid)")
        } else if let i = args.firstIndex(of: "--dsh-read"), i + 1 < args.count, let tid = Int(args[i + 1]) {
            debugTopic = Topic(id: tid, subject: "", author: "", replies: 0, date: nil)
        }
    }
}

/// A sample post rendered by the BBCode engine, used to verify styling during development.
private struct DemoReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let sample = """
    [align=center][size=150%]2026年9月4日在线修正[/size][/align]
    原帖地址：[color=blue][b]蓝贴[/b][/color]
    [size=130%]成就[/size]
    [list][*]修复了如玩家在盘卷蛇岛、瓦尔或奈格塔尔完成战争火花任务无法获得“午夜火花”成就进度的问题。[*]调整了相关任务奖励。[b]加粗[/b]与[i]斜体[/i]测试。[/list]
    [size=130%]职业[/size]
    [list][*]牧师：神圣——修复了烈毒之渊2件套效果中，恢复无法稳定提供焕发精力的问题。[*]萨满祭司：恢复——修复了涌动超载未正确提升涌动图腾和溢流海潮治疗法力消耗的问题。[/list]
    普通段落文字，[u]下划线[/u]、[s]删除线[/s]测试。一只[emote]不属于BBCode的说明。
    """
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    NativeContentView(nodes: BBCode.parse(sample))
                }
                .padding(AppTheme.pad)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sceneCanvas()
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("渲染测试").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
