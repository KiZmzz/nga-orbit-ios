import SwiftUI
import NGAKit

/// Account & connection sheet: session status, website verification / login, and local cleanup.
struct AccountView: View {
    @Bindable var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var website: WebsitePurpose?
    @State private var clearing = false
    enum WebsitePurpose: String, Identifiable { case verify, login; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    Text(session.network.message).font(.footnote).foregroundStyle(AppTheme.inkSoft)
                    if !session.network.available {
                        Button("打开系统设置，检查联网权限") { session.network.openSettings() }
                            .foregroundStyle(AppTheme.brand)
                    }
                    Picker("NGA 站点", selection: $session.host) {
                        ForEach(NGAHost.allCases) { host in Text(host.rawValue).tag(host) }
                    }
                    Text(session.status).font(.footnote).foregroundStyle(AppTheme.inkSoft)
                    Button("打开网页完成访问验证") { website = .verify }.foregroundStyle(AppTheme.brand)
                    Button("登录 NGA 账号") { website = .login }.foregroundStyle(AppTheme.brand)
                }
                Section {
                    Text("账号密码在 NGA 网页内输入。会话保存在本机网站存储与钥匙串中；本原型没有代理服务器。")
                        .font(.footnote).foregroundStyle(AppTheme.inkSoft)
                    if let error = session.storageError { Text(error).foregroundStyle(AppTheme.alert) }
                    Button("退出登录并清除本地数据", role: .destructive) {
                        clearing = true
                        Task { await session.clear(); clearing = false }
                    }.disabled(clearing)
                }
                Section("关于此原型") {
                    Text("已接入版块、主题、帖子分页与回复请求。图片、引用、表格、链接和折叠内容使用原生视图展示。")
                    Text("访问权限和返回内容由 NGA 决定。网页完成后回到列表重试即可。")
                }.font(.footnote)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .sceneCanvas()
            .toolbarBackground(AppTheme.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("账户与连接").navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.brand)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.foregroundStyle(AppTheme.brand) } }
            .sheet(item: $website) { purpose in WebsiteLogin(session: session, login: purpose == .login) }
            .task(id: session.host) { await session.restore() }
        }
    }
}
