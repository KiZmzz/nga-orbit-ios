import SwiftUI
import WebKit
import Security
import NGAKit

extension Notification.Name {
    /// Sent after an explicit local sign-out so account-scoped UI stores can
    /// discard both their persisted values and their currently displayed state.
    static let ngaSessionDidClear = Notification.Name("nga.session-did-clear")
}

@MainActor @Observable final class SessionStore {
    var host: NGAHost {
        didSet { UserDefaults.standard.set(host.rawValue, forKey: "nga.host"); revision += 1 }
    }
    var revision = 0
    var status = "尚未连接 NGA"
    var isLoggedIn = false
    /// uid from `ngaPassportUid` when a signed-in session is present.
    var accountUID: String?
    /// Current NGA profile loaded through the official user detail/avatar actions.
    var accountProfile: NGAUser?
    var storageError: String?
    let websiteStore = WKWebsiteDataStore.default()
    let network = Connectivity()
    private let service = "local.nga.reader.session"
    init() {
        host = NGAHost(rawValue: UserDefaults.standard.string(forKey: "nga.host") ?? "") ?? .primary
    }
    private struct SavedCookie: Codable {
        let name: String, value: String, domain: String, path: String
        let expires: Date?
        let secure: Bool
        init(_ cookie: HTTPCookie) {
            name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
            expires = cookie.expiresDate; secure = cookie.isSecure
        }
        var cookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
            if secure { properties[.secure] = "TRUE" }
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)
        }
    }
    private func matches(_ cookie: HTTPCookie, host: NGAHost) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (domain == host.rawValue || host.rawValue.hasSuffix("." + domain)) &&
            (cookie.expiresDate.map { $0 > Date() } ?? true)
    }
    func restore() async {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: host.rawValue,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let saved = try? JSONDecoder().decode([SavedCookie].self, from: data) {
            for record in saved {
                if let cookie = record.cookie, matches(cookie, host: host) { await websiteStore.httpCookieStore.setCookie(cookie) }
            }
        }
        await sync()
    }
    func sync() async {
        let selectedHost = host
        let cookies = await websiteStore.httpCookieStore.allCookies().filter { matches($0, host: selectedHost) }
        guard selectedHost == host else { return }
        let uidCookie = cookies.first { $0.name == "ngaPassportUid" && !$0.value.isEmpty && $0.value != "0" }?.value
        let cidCookie = cookies.first { $0.name == "ngaPassportCid" && !$0.value.isEmpty }?.value
        isLoggedIn = uidCookie != nil && cidCookie != nil
        accountUID = isLoggedIn ? uidCookie : nil
        if isLoggedIn { await refreshAccountProfile() } else { accountProfile = nil }
        status = isLoggedIn ? "已读取登录会话，访问权限以实际请求为准" :
            (cookies.contains { $0.name == "guestJs" } ? "已读取访客会话，可以尝试浏览" : "尚未完成网页验证或登录")
        do {
            let data = try JSONEncoder().encode(cookies.map(SavedCookie.init))
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: selectedHost.rawValue]
            let values: [String: Any] = [kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            var result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
            if result == errSecItemNotFound {
                result = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            }
            storageError = result == errSecSuccess ? nil : "会话无法保存到钥匙串（\(result)）"
        } catch { storageError = "会话保存失败" }
        revision += 1
    }
    func cookieHeader(for selectedHost: NGAHost) async -> String? {
        let cookies = await websiteStore.httpCookieStore.allCookies().filter { matches($0, host: selectedHost) }
        return cookies.isEmpty ? nil : HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }
    func clear() async {
        // User-requested local sign-out clears all NGA domains and the account login site.
        let cookies = await websiteStore.httpCookieStore.allCookies()
        for cookie in cookies {
            if NGAHost.allCases.contains(where: { matches(cookie, host: $0) }) || cookie.domain.contains("account.178.com") {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    websiteStore.httpCookieStore.delete(cookie) { continuation.resume() }
                }
            }
        }
        let records = await websiteStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let ngaRecords = records.filter { ["nga.cn", "ngabbs.com", "178.com"].contains($0.displayName) }
        await websiteStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: ngaRecords)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        isLoggedIn = false; accountUID = nil; accountProfile = nil
        status = "本机 NGA 会话与个人数据已清除"; storageError = nil; revision += 1
        NotificationCenter.default.post(name: .ngaSessionDidClear, object: nil)
    }

    // MARK: Write actions (best effort; need a valid session)

    func favoriteTopic(_ topic: Topic) async throws {
        try await NGAClient(host: host).favorite(tid: topic.id, cookie: await cookieHeader(for: host))
    }
    func favoriteTopics(folderID: Int = 1, page: Int = 1) async throws -> TopicPage {
        try await NGAClient(host: host).favoriteTopics(folderID: folderID, page: page, cookie: await cookieHeader(for: host))
    }
    func favoriteFolders() async throws -> [FavoriteFolder] {
        try await NGAClient(host: host).favoriteFolders(cookie: await cookieHeader(for: host))
    }

    func userDetail(_ user: NGAUser) async throws -> NGAUser {
        try await NGAClient(host: host).userDetail(user, cookie: await cookieHeader(for: host))
    }
    func refreshAccountProfile() async {
        guard let uid = accountUID, !uid.isEmpty else { accountProfile = nil; return }
        let fallback = accountProfile ?? NGAUser(uid: uid, name: "我")
        guard let detail = try? await userDetail(fallback), accountUID == uid else { return }
        accountProfile = detail
    }
    func userTopics(uid: String, page: Int = 1, replies: Bool = false) async throws -> TopicPage {
        try await NGAClient(host: host).userTopics(uid: uid, page: page, replies: replies,
                                                   cookie: await cookieHeader(for: host))
    }
    func publicFavoriteFolders(uid: String) async throws -> [FavoriteFolder] {
        try await NGAClient(host: host).favoriteFolders(uid: uid, cookie: await cookieHeader(for: host))
    }
    func publicFavoriteTopics(folderID: Int, page: Int = 1) async throws -> TopicPage {
        try await NGAClient(host: host).favoriteTopics(folderID: folderID, page: page,
                                                      cookie: await cookieHeader(for: host))
    }
    func followedUser(uid: String) async throws -> Bool {
        try await NGAClient(host: host).followedUser(uid: uid, cookie: await cookieHeader(for: host))
    }
    func followUser(uid: String, add: Bool) async throws {
        try await NGAClient(host: host).followUser(uid: uid, add: add, cookie: await cookieHeader(for: host))
    }
    func blockedUser(uid: String) async throws -> Bool {
        try await NGAClient(host: host).blockedUser(uid: uid, cookie: await cookieHeader(for: host))
    }
    func blockUser(uid: String, add: Bool) async throws {
        try await NGAClient(host: host).blockUser(uid: uid, add: add, cookie: await cookieHeader(for: host))
    }
    func sendPrivateMessage(uid: String, subject: String, content: String) async throws {
        try await NGAClient(host: host).sendPrivateMessage(uid: uid, subject: subject, content: content,
                                                          cookie: await cookieHeader(for: host))
    }
    func replyPrivateMessage(mid: String, subject: String, content: String) async throws {
        try await NGAClient(host: host).replyPrivateMessage(mid: mid, subject: subject, content: content,
                                                            cookie: await cookieHeader(for: host))
    }
    func favoritePost(topic: Topic, post: Post) async throws {
        try await NGAClient(host: host).favorite(tid: topic.id, pid: post.pid, cookie: await cookieHeader(for: host))
    }
    func vote(topic: Topic, post: Post, direction: PostVote) async throws -> PostVoteResult {
        try await NGAClient(host: host).vote(tid: topic.id, pid: post.pid, direction: direction,
                                             cookie: await cookieHeader(for: host))
    }
    func reply(topic: Topic, pid: Int?, content: String) async throws {
        try await NGAClient(host: host).reply(tid: topic.id, pid: pid, content: content, cookie: await cookieHeader(for: host))
    }
    func newTopic(board: Board, subject: String, content: String) async throws {
        try await NGAClient(host: host).newTopic(fid: board.id, subject: subject, content: content, cookie: await cookieHeader(for: host))
    }
    func favoriteBoard(fid: Int, add: Bool = true) async throws {
        try await NGAClient(host: host).favoriteBoard(fid: fid, add: add, cookie: await cookieHeader(for: host))
    }

    // MARK: Messages

    func messages() async throws -> [Message] {
        try await NGAClient(host: host).messages(cookie: await cookieHeader(for: host))
    }
    func privateMessagePosts(mid: String, page: Int = 1) async throws -> [Message] {
        try await NGAClient(host: host).privateMessagePosts(mid: mid, page: page,
                                                            cookie: await cookieHeader(for: host))
    }
    func privateMessageThread(mid: String, page: Int = 1) async throws -> PrivateMessageThread {
        try await NGAClient(host: host).privateMessageThread(mid: mid, page: page,
                                                             cookie: await cookieHeader(for: host))
    }
    func inviteToPrivateMessage(mid: String, username: String) async throws {
        try await NGAClient(host: host).inviteToPrivateMessage(mid: mid, username: username,
                                                               cookie: await cookieHeader(for: host))
    }
    func leavePrivateMessage(mid: String) async throws {
        try await NGAClient(host: host).leavePrivateMessage(mid: mid, cookie: await cookieHeader(for: host))
    }
    func notifications() async throws -> [Message] {
        try await NGAClient(host: host).notifications(cookie: await cookieHeader(for: host))
    }
}
