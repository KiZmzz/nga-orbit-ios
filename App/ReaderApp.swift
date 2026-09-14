import SwiftUI
import NGAKit

@main struct ReaderApp: App {
    @State private var session = SessionStore()
    @State private var started = false
    @State private var permissionCheckFinished = false
    @State private var showingNetworkPermission = false
    @State private var permissionNoticeShown = false
    @State private var showingSplash = true
    @AppStorage("nga.appearance") private var appearance = AppearancePreference.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView(session: session)
                if showingSplash {
                    AnimatedSplashView {
                        withAnimation(.easeOut(duration: 0.35)) { showingSplash = false }
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
                .tint(AppTheme.brand)
                .preferredColorScheme(AppearancePreference(rawValue: appearance)?.colorScheme)
                .task {
                    guard !started else { return }
                    started = true
                    await session.restore()
                    // A native request at launch triggers the system's first-use network prompt,
                    // where applicable. App code cannot grant or reset that system permission.
                    await session.network.requestAccess(to: session.host.url)
                    permissionCheckFinished = true
                    showNetworkPermissionIfNeeded()
                }
                .onChange(of: session.network.permissionDenied) { _, _ in showNetworkPermissionIfNeeded() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { showNetworkPermissionIfNeeded() }
                }
                .alert("允许 NGA Orbit 联网", isPresented: $showingNetworkPermission) {
                    Button("去设置") { session.network.openSettings() }
                    Button("稍后", role: .cancel) {}
                } message: {
                    Text("系统尚未允许此 App 使用当前网络。请在设置中将 NGA Orbit 的无线数据设为「无线局域网与蜂窝数据」。")
                }
        }
    }
    private func showNetworkPermissionIfNeeded() {
        guard permissionCheckFinished, scenePhase == .active,
              session.network.permissionDenied, !permissionNoticeShown else { return }
        permissionNoticeShown = true
        showingNetworkPermission = true
    }
}
