import Foundation

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        #if DEBUG
        let from = response.url?.absoluteString ?? "unknown"
        let to = request.url?.absoluteString ?? "unknown"
        print("[NGAReader][redirect] status=\(response.statusCode) from=\(from) to=\(to)")
        #endif
        // Session credentials must never be forwarded to a different host.
        guard request.url?.scheme == "https", request.url?.host == task.originalRequest?.url?.host else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

public actor NGAClient {
    public let host: NGAHost
    private let session: URLSession
    private static let userCache = NGAUserCache()
    public init(host: NGAHost = .primary) {
        self.host = host
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }
    public func topics(fid: Int, page: Int = 1, recommend: Bool = false, cookie: String? = nil) async throws -> TopicPage {
        var query = ["fid": String(fid), "page": String(max(page, 1))]
        if recommend { query["recommend"] = "1" }
        let (data, response) = try await get(path: "thread.php", query: query, cookie: cookie)
        return try ResponseDecoder.topics(from: data, status: response.statusCode, charset: response.textEncodingName, page: page, forceDigest: recommend)
    }

    /// Official app filters. Service selectors belong in the query string;
    /// board and paging values belong in the POST form.
    public func officialTopics(fid: Int, action: String, page: Int = 1, days: Int? = nil, recommend: Bool = false,
                               cookie: String? = nil) async throws -> TopicPage {
        var form = ["fid": String(fid), "page": String(max(page, 1))]
        if let days { form["days"] = String(days) }
        if recommend { form["recommend"] = "1" }
        let query = ["__lib": "subject", "__act": action, "__inchst": "UTF8", "__output": "11"]
        let (data, response) = try await post(path: "app_api.php", query: query, form: form, cookie: cookie, addOutput: false)
        return try ResponseDecoder.appTopics(from: data, status: response.statusCode,
                                              charset: response.textEncodingName, page: page,
                                              sticky: action == "topped", digest: recommend)
    }

    /// Topics in the signed-in user's default NGA favourite folder.
    public func favoriteTopics(folderID: Int = 1, page: Int = 1, cookie: String? = nil) async throws -> TopicPage {
        let page = max(page, 1)
        let (data, response) = try await get(path: "thread.php", query: ["favor": String(folderID), "page": String(page)], cookie: cookie)
        return try ResponseDecoder.topics(from: data, status: response.statusCode, charset: response.textEncodingName, page: page)
    }

    /// The signed-in user's topic favourite folders.
    public func favoriteFolders(uid: String? = nil, page: Int = 1, cookie: String? = nil) async throws -> [FavoriteFolder] {
        // nuke.php list_folder rejects `__output=11`, so POST without it (like the message endpoint).
        var form = ["__lib": "topic_favor_v2", "__act": "list_folder", "page": String(max(page, 1)), "raw": "3"]
        if let uid, !uid.isEmpty { form["uid"] = uid }
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie, addOutput: false)
        let body = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
        var result: [FavoriteFolder] = []
        var seen = Set<Int>()
        func walk(_ value: Any) {
            if let row = value as? [String: Any] {
                let folderID = ResponseDecoder.integer(row["folder"] ?? row["folder_id"] ?? row["fid"] ?? row["id"])
                let name = HTMLText.decode(ResponseDecoder.string(row["name"] ?? row["title"] ?? row["folder_name"] ?? row["subject"]))
                if let folderID, folderID > 0, !name.isEmpty, seen.insert(folderID).inserted {
                    let count = ResponseDecoder.integer(row["count"] ?? row["topics"] ?? row["num"] ?? row["total"])
                    result.append(FavoriteFolder(id: folderID, name: name, count: count, isDefault: isDefaultFolder(row)))
                }
                for child in row.values { walk(child) }
            } else if let list = value as? [Any] {
                for child in list { walk(child) }
            }
        }
        walk(body)
        return result.sorted { lhs, rhs in
            if lhs.id == 1 { return true }
            if rhs.id == 1 { return false }
            return lhs.id < rhs.id
        }
    }

    // MARK: User centre

    public func userDetail(_ fallback: NGAUser, cookie: String? = nil) async throws -> NGAUser {
        // The app_api user service requires an official-client request signature;
        // a valid browser login cookie alone is rejected with “签名错误”. The
        // website's own UCP endpoint exposes the same public profile and avatar
        // fields and works with the WebKit session used by this client.
        let form = ["__lib": "ucp", "__act": "get", "uid": fallback.uid]
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie)
        let user = try ResponseDecoder.user(from: data, status: response.statusCode,
                                            charset: response.textEncodingName, fallback: fallback)
        guard user.avatar == nil, !user.uid.isEmpty else { return user }

        // NGA's user detail response does not consistently include an avatar.
        // The official UID lookup is the authoritative fallback for that field.
        let avatarForm = ["__lib": "ucp", "__act": "get_avatar", "uid": user.uid]
        guard let (avatarData, avatarResponse) = try? await post(path: "nuke.php", form: avatarForm, cookie: cookie),
              let avatarBody = try? ResponseDecoder.decode(avatarData, status: avatarResponse.statusCode,
                                                           charset: avatarResponse.textEncodingName),
              let avatar = BBCode.avatarURL(ResponseDecoder.string(avatarBody["0"])) else { return user }
        return NGAUser(uid: user.uid, name: user.name, avatar: avatar,
                       groupTitle: user.groupTitle, memberTitle: user.memberTitle, signature: user.signature)
    }

    public func userTopics(uid: String, page: Int = 1, replies: Bool = false,
                           cookie: String? = nil) async throws -> TopicPage {
        // Use the public web search used by NGA's user centre. Unlike app_api's
        // subjects/replys actions it needs no private official-app signature.
        var query = ["authorid": uid, "page": String(max(page, 1))]
        if replies { query["searchpost"] = "1" }
        let (data, response) = try await get(path: "thread.php", query: query, cookie: cookie)
        return try ResponseDecoder.topics(from: data, status: response.statusCode,
                                          charset: response.textEncodingName, page: page)
    }

    public func followUser(uid: String, add: Bool, cookie: String? = nil) async throws {
        let form = ["__lib": "follow_v2", "__act": "follow", "type": add ? "1" : "8", "id": uid]
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie)
        _ = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
    }

    public func followedUser(uid: String, cookie: String? = nil) async throws -> Bool {
        let form = ["__lib": "follow_v2", "__act": "get_follow", "page": "1"]
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie)
        let body = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
        return containsUser(uid, in: body)
    }

    public func blockedUser(uid: String, cookie: String? = nil) async throws -> Bool {
        let form = ["__lib": "message", "__act": "message", "act": "list_block"]
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie, addOutput: false)
        let body = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
        return containsUser(uid, in: body)
    }

    public func blockUser(uid: String, add: Bool, cookie: String? = nil) async throws {
        let form = ["__lib": "message", "__act": "message",
                    "act": add ? "add_block" : "del_block", "buids": uid]
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie, addOutput: false)
        _ = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
    }

    public func sendPrivateMessage(uid: String, subject: String, content: String,
                                   cookie: String? = nil) async throws {
        // MNGA posts subject+content with __output=8 and __inchst=UTF8.
        // Without __inchst, NGA decodes the UTF-8 form body as GB18030 and garbles Chinese.
        let query = ["__lib": "message", "__act": "message", "act": "new",
                     "__output": "8", "__inchst": "UTF8"]
        let form = ["to": uid, "subject": subject, "content": content]
        let (data, response) = try await post(path: "nuke.php", query: query, form: form,
                                              cookie: cookie, addOutput: false)
        try ResponseDecoder.acceptWrite(data, status: response.statusCode, charset: response.textEncodingName)
    }

    /// Reply inside an existing short-message conversation.
    /// Subject is required by NGA; pass the conversation title.
    public func replyPrivateMessage(mid: String, subject: String, content: String,
                                    cookie: String? = nil) async throws {
        let query = ["__lib": "message", "__act": "message", "act": "reply",
                     "__output": "8", "__inchst": "UTF8"]
        let form = ["mid": mid, "subject": subject, "content": content]
        let (data, response) = try await post(path: "nuke.php", query: query, form: form,
                                              cookie: cookie, addOutput: false)
        try ResponseDecoder.acceptWrite(data, status: response.statusCode, charset: response.textEncodingName)
    }

    private func containsUser(_ uid: String, in value: Any, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        if let map = value as? [String: Any] {
            for key in ["uid", "id", "user_id", "authorid", "buid", "buids"] {
                let ids = ResponseDecoder.string(map[key]).split(whereSeparator: { !$0.isNumber && $0 != "-" })
                if ids.contains(where: { String($0) == uid }) { return true }
            }
            return map.values.contains { containsUser(uid, in: $0, depth: depth + 1) }
        }
        if let list = value as? [Any] { return list.contains { containsUser(uid, in: $0, depth: depth + 1) } }
        return false
    }

    private func isDefaultFolder(_ row: [String: Any]) -> Bool {
        for key in ["is_default", "isdefault", "default", "isDefault", "d", "type"] {
            if let v = ResponseDecoder.integer(row[key]), v != 0 { return true }
            if ResponseDecoder.string(row[key]).lowercased() == "1" { return true }
        }
        return false
    }
    public func posts(tid: Int, page: Int = 1, authorID: String? = nil,
                      anonymousAuthorPID: Int? = nil, cookie: String? = nil) async throws -> PostPage {
        let page = try await loadPosts(tid: tid, page: page, authorID: authorID,
                                       anonymousAuthorPID: anonymousAuthorPID, cookie: cookie)
        return await Self.userCache.stabilize(page, host: host)
    }

    private func loadPosts(tid: Int, page: Int = 1, authorID: String? = nil,
                           anonymousAuthorPID: Int? = nil, cookie: String? = nil) async throws -> PostPage {
        var query = ["tid": String(tid), "page": String(max(page, 1))]
        if let authorID, !authorID.isEmpty { query["authorid"] = authorID }
        if let anonymousAuthorPID {
            query["pid"] = String(anonymousAuthorPID)
            query["opt"] = "512"
        }
        do { return try await readPosts(tid: tid, page: page, query: query, cookie: cookie, output: "11", attempts: 3) }
        catch let error as NGAError where isInvalidResponse(error) {
            do { return try await readPosts(tid: tid, page: page, query: query, cookie: cookie, output: "8", attempts: 2) }
            catch let fallbackError as NGAError where isInvalidResponse(fallbackError) {
                // The current read endpoint supports a newer response shape. These
                // flags avoid its legacy script prefix and have proved more stable
                // for long, formatted announcement posts.
                var v2Query = query
                v2Query["v2"] = "1"
                v2Query["noprefix"] = "1"
                do { return try await readPosts(tid: tid, page: page, query: v2Query, cookie: cookie, output: "8", attempts: 2) }
                catch let v2Error as NGAError where isInvalidResponse(v2Error) {
                    return try await inspectHTMLFallback(tid: tid, page: page, query: query, cookie: cookie)
                }
            }
        }
    }

    /// Find the first real image posted by the topic author. JSON is fastest,
    /// while rendered HTML covers attachment tables omitted by some JSON nodes.
    public func topicThumbnail(tid: Int, cookie: String? = nil) async -> URL? {
        await topicThumbnails(tid: tid, cookie: cookie).first
    }

    public func topicThumbnails(tid: Int, cookie: String? = nil) async -> [URL] {
        if let page = try? await posts(tid: tid, page: 1, cookie: cookie),
           let post = page.posts.first(where: { $0.floor == 0 }) ?? page.posts.first {
            // Images inside a quoted post in the OP body must not surface as the
            // OP's preview. `attachs`-only fallback (post.imageURLs) would also
            // miss OP-embedded [img] tags, so prefer the inline scan with the
            // quote filter, then fall back to actual attachments.
            let inlineImages = BBCode.imageURLs(in: post.content, skipInsideQuotes: true)
            var images = inlineImages.isEmpty ? post.imageURLs : inlineImages
            images = BBCode.uniqueImageURLs(images, limit: 3)
            if !images.isEmpty {
            #if DEBUG
                print("[NGAReader][thumbnail] tid=\(tid) source=json count=\(images.count)")
            #endif
                return images
            }
        }
        guard let (data, response) = try? await get(path: "read.php", query: ["tid": String(tid), "noBBCode": "1"], cookie: cookie, output: nil),
              (200..<300).contains(response.statusCode) else { return [] }
        let html = ForumIndex.decode(data)
        let patterns = [
            #"(?is)id=['\"]postcontent0['\"][^>]*>(.*?)id=['\"]postcontent1['\"]"#,
            #"(?is)id=['\"]postcontent0['\"][^>]*>(.*?)</(?:p|span)>"#
        ]
        var images: [URL] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let bodyRange = Range(match.range(at: 1), in: html) else { continue }
            let body = String(html[bodyRange])
            let imageRegex = try? NSRegularExpression(pattern: #"(?is)<img[^>]+(?:src|data-src)=['\"]([^'\"]+)['\"]"#)
            for imageMatch in imageRegex?.matches(in: body, range: NSRange(body.startIndex..., in: body)) ?? [] {
                guard let range = Range(imageMatch.range(at: 1), in: body), let url = BBCode.imageURL(String(body[range])) else { continue }
                let path = url.path.lowercased()
                guard !path.contains("/post/smile/"), !path.contains("/face/"), !path.contains("/avatar") else { continue }
                #if DEBUG
                print("[NGAReader][thumbnail] tid=\(tid) source=html url=\(url.absoluteString)")
                #endif
                images = BBCode.uniqueImageURLs(images + [url], limit: 3)
                if images.count == 3 { return images }
            }
        }
        #if DEBUG
        print("[NGAReader][thumbnail] tid=\(tid) source=none")
        #endif
        return images
    }

    /// NGA occasionally closes an individual read response before the final JSON
    /// string quote. A fresh request usually succeeds, so retry only malformed
    /// responses; access errors and server messages are still returned immediately.
    private func readPosts(tid: Int, page: Int, query: [String: String], cookie: String?, output: String, attempts: Int) async throws -> PostPage {
        var lastError: NGAError?
        for attempt in 1...attempts {
            let (data, response) = try await get(path: "read.php", query: query, cookie: cookie, output: output)
            #if DEBUG
            let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            print("[NGAReader][read] tid=\(tid) output=\(output) attempt=\(attempt) status=\(response.statusCode) bytes=\(data.count) contentType=\(contentType)")
            #endif
            do {
                let charset = output == "8" ? "GB18030" : response.textEncodingName
                return try ResponseDecoder.posts(from: data, status: response.statusCode, charset: charset, tid: tid, page: page)
            } catch let error as NGAError where isInvalidResponse(error) {
                lastError = error
                if attempt < attempts {
                    try? await Task.sleep(for: .milliseconds(350))
                    continue
                }
            }
        }
        throw lastError ?? NGAError.invalidResponse("帖子数据不完整")
    }

    private func isInvalidResponse(_ error: NGAError) -> Bool {
        if case .invalidResponse = error { return true }
        return false
    }

    /// Native compatibility path for old/formatted posts whose JSON response is
    /// truncated by NGA. The ordinary page retains the same BBCode payload, which
    /// is extracted into `Post` values here; it is never shown in a web view.
    private func inspectHTMLFallback(tid: Int, page: Int, query baseQuery: [String: String], cookie: String?) async throws -> PostPage {
        var query = baseQuery
        query["noBBCode"] = "1"
        let (data, response) = try await get(path: "read.php", query: query, cookie: cookie, output: nil)
        #if DEBUG
        print("[NGAReader][html] tid=\(tid) status=\(response.statusCode) bytes=\(data.count)")
        #endif
        return try HTMLPostDecoder.posts(from: data, tid: tid, page: page)
    }

    private func get(path: String, query: [String: String], cookie: String?, output: String? = "11") async throws -> (Data, HTTPURLResponse) {
        var parts = URLComponents(url: host.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var query = query
        if let output { query["__output"] = output }
        query["__inchst"] = "UTF8"
        parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: parts.url!)
        request.setValue("NGA_WP_JW", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/json", forHTTPHeaderField: "Accept")
        if let cookie, !cookie.contains("\r"), !cookie.contains("\n") { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NGAError.invalidResponse("非 HTTP 响应") }
        if (300..<400).contains(http.statusCode) { throw NGAError.untrustedRedirect }
        return (data, http)
    }

    // MARK: Board catalogue

    /// Raw text of NGA's static board index (the first URL that answers).
    public func forumIndexRaw(cookie: String? = nil) async throws -> String {
        var lastError: Error = NGAError.invalidResponse("没有可用的版块目录来源")
        for url in ForumIndex.urls {
            do {
                let (data, response) = try await rawGet(url, cookie: cookie)
                guard (200..<300).contains(response.statusCode) else { continue }
                return ForumIndex.decode(data)
            } catch { lastError = error; continue }
        }
        throw lastError
    }

    /// Parsed, categorized boards from the static index.
    public func forums(cookie: String? = nil) async throws -> [BoardSection] {
        let raw = try await forumIndexRaw(cookie: cookie)
        let sections = ForumIndex.parse(raw)
        if sections.isEmpty { throw NGAError.invalidResponse("版块目录已获取但无法解析为分类") }
        return sections
    }

    /// Search boards by a name fragment via `forum.php?key=`.
    public func searchBoards(_ key: String, cookie: String? = nil) async throws -> [Board] {
        let (data, response) = try await get(path: "forum.php", query: ["key": key], cookie: cookie)
        let body = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
        return ForumIndex.boards(fromResponse: body)
    }

    // MARK: Messages

    /// Private-message conversation list.
    /// MNGA uses POST + compact JSON (`__output=8`) and posts `access_uid` /
    /// `access_token` from the session cookies; GET + `__output=11` returns an
    /// empty or rejected payload for this endpoint.
    public func messages(page: Int = 1, cookie: String? = nil) async throws -> [Message] {
        let query = ["__lib": "message", "__act": "message", "act": "list", "__output": "8", "__inchst": "UTF8"]
        let form = ["page": String(max(page, 1))]
        let (data, response) = try await post(path: "nuke.php", query: query, form: form, cookie: cookie, addOutput: false)
        let body = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
        return ResponseDecoder.privateMessages(from: body)
    }

    public func privateMessagePosts(mid: String, page: Int = 1, cookie: String? = nil) async throws -> [Message] {
        try await privateMessageThread(mid: mid, page: page, cookie: cookie).posts
    }

    public func privateMessageThread(mid: String, page: Int = 1, cookie: String? = nil) async throws -> PrivateMessageThread {
        let query = ["__lib": "message", "__act": "message", "act": "read", "__output": "8", "__inchst": "UTF8"]
        let form = ["mid": mid, "page": String(max(page, 1))]
        let (data, response) = try await post(path: "nuke.php", query: query, form: form, cookie: cookie, addOutput: false)
        let body = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
        return ResponseDecoder.privateMessageThread(from: body)
    }

    /// Invite another account into a short-message group conversation (web: 邀请其他用户加入对话).
    public func inviteToPrivateMessage(mid: String, username: String, cookie: String? = nil) async throws {
        let query = ["__lib": "message", "__act": "message", "act": "invite", "__output": "8", "__inchst": "UTF8"]
        let form = ["mid": mid, "to": username]
        let (data, response) = try await post(path: "nuke.php", query: query, form: form,
                                              cookie: cookie, addOutput: false)
        try ResponseDecoder.acceptWrite(data, status: response.statusCode, charset: response.textEncodingName)
    }

    /// Leave a short-message conversation (web: 退出对话; app API documents `__act=leave`).
    public func leavePrivateMessage(mid: String, cookie: String? = nil) async throws {
        // Preferred: the same nuke.php message router used by list/read/reply.
        let query = ["__lib": "message", "__act": "message", "act": "exit", "__output": "8", "__inchst": "UTF8"]
        let form = ["mid": mid]
        do {
            let (data, response) = try await post(path: "nuke.php", query: query, form: form,
                                                  cookie: cookie, addOutput: false)
            try ResponseDecoder.acceptWrite(data, status: response.statusCode, charset: response.textEncodingName)
            return
        } catch let error as NGAError {
            switch error {
            case .server, .invalidResponse:
                break // fall through to the documented app_api leave action
            default:
                throw error
            }
        }
        let appQuery = ["__lib": "message", "__act": "leave", "__inchst": "UTF8", "__output": "11"]
        let appForm = ["mid": mid, "id": mid]
        let (data, response) = try await post(path: "app_api.php", query: appQuery, form: appForm,
                                              cookie: cookie, addOutput: false)
        try ResponseDecoder.acceptWrite(data, status: response.statusCode, charset: response.textEncodingName)
    }

    /// Notifications / reminders (nuke.php noti). Match MNGA: POST + `__output=8`,
    /// no `raw` flag — the three buckets live under `data["0"]` as arrays.
    public func notifications(cookie: String? = nil) async throws -> [Message] {
        let query = ["__lib": "noti", "__act": "get_all", "__output": "8", "__inchst": "UTF8"]
        let (data, response) = try await post(path: "nuke.php", query: query, form: [:], cookie: cookie, addOutput: false)
        let body = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
        return ResponseDecoder.notifications(from: body)
    }

    // MARK: Board extras

    /// Search topics inside a board (thread.php?key).
    /// Debug: dump the raw search response so the search parsing can be calibrated.
    public func searchDebug(fid: Int, key: String, cookie: String? = nil) async throws -> String {
        let query = ["fid": String(fid), "key": key, "page": "1", "content": "4"]
        let (data, response) = try await get(path: "thread.php", query: query, cookie: cookie)
        return "HTTP \(response.statusCode)\n" + String(ForumIndex.decode(data).prefix(1600))
    }

    public func searchTopics(fid: Int, key: String, page: Int = 1, recommend: Bool = false, cookie: String? = nil) async throws -> TopicPage {
        // content=4 = "搜索主题标题" (NGA's title-search mode); without it the board search returns nothing.
        // recommend=1 narrows the search to NGA's 推荐/精华 topics (the 「精华区」 view).
        var query = ["fid": String(fid), "key": key, "page": String(page), "content": "4"]
        if recommend { query["recommend"] = "1" }
        let (data, response) = try await get(path: "thread.php", query: query, cookie: cookie)
        return try ResponseDecoder.topics(from: data, status: response.statusCode, charset: response.textEncodingName, page: page, forceDigest: recommend)
    }

    /// Hot topics selected by NGA's official subject service for the last day.
    public func hotTopics(fid: Int, days: Int = 1, page: Int = 1, cookie: String? = nil) async throws -> TopicPage {
        try await officialTopics(fid: fid, action: "hot", page: page, days: days, cookie: cookie)
    }

    /// Favourite a board on NGA (nuke.php forum_favor2). Needs a signed-in account.
    public func favoriteBoard(fid: Int, add: Bool = true, cookie: String? = nil) async throws {
        let form: [String: String] = ["__lib": "forum_favor2", "__act": "forum_favor", "action": add ? "add" : "del", "fid": String(fid)]
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie, addOutput: false)
        _ = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
    }

    /// A direct GET that does not inject `__output`/`__inchst` (used for static CDN files).
    private func rawGet(_ url: URL, cookie: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("NGA_WP_JW", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/json", forHTTPHeaderField: "Accept")
        if let cookie, !cookie.contains("\r"), !cookie.contains("\n") { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NGAError.invalidResponse("非 HTTP 响应") }
        if (300..<400).contains(http.statusCode) { throw NGAError.untrustedRedirect }
        return (data, http)
    }

    // MARK: Write actions (best effort; depend on a valid session)

    /// Favourite a topic or a specific floor (nuke.php topic_favor_v2).
    public func favorite(tid: Int, pid: Int? = nil, cookie: String? = nil) async throws {
        let query: [String: String] = [
            "__lib": "topic_favor_v2", "__act": "add", "action": "add", "folder": "1",
            "tid": String(tid), "pid": pid.map(String.init) ?? "0"
        ]
        let (data, response) = try await post(path: "nuke.php", form: query, cookie: cookie)
        _ = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
    }

    /// Agree or disagree with a floor through NGA's topic_recommend service.
    /// The returned delta is supplied by NGA and reflects toggling/changing the vote.
    public func vote(tid: Int, pid: Int, direction: PostVote, cookie: String? = nil) async throws -> PostVoteResult {
        let form = [
            "__lib": "topic_recommend", "__act": "add",
            "value": String(direction.rawValue), "tid": String(tid), "pid": String(pid)
        ]
        let (data, response) = try await post(path: "nuke.php", form: form, cookie: cookie)
        return try ResponseDecoder.voteResult(from: data, status: response.statusCode,
                                              charset: response.textEncodingName, direction: direction)
    }

    /// Reply to a topic (post.php, step 2). Content is raw BBCode.
    public func reply(tid: Int, pid: Int?, content: String, cookie: String? = nil) async throws {
        var form: [String: String] = [
            "__lib": "post", "__act": "reply", "step": "2", "tid": String(tid),
            "post_content": content, "__inchst": "UTF8"
        ]
        if let pid { form["pid"] = String(pid) }
        let (data, response) = try await post(path: "post.php", form: form, cookie: cookie)
        _ = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
    }

    public func newTopic(fid: Int, subject: String, content: String, cookie: String? = nil) async throws {
        let form: [String: String] = [
            "__lib": "post", "__act": "new", "action": "new", "step": "2", "fid": String(fid),
            "post_subject": subject, "post_content": content, "__inchst": "UTF8"
        ]
        let (data, response) = try await post(path: "post.php", form: form, cookie: cookie)
        _ = try ResponseDecoder.decode(data, status: response.statusCode, charset: response.textEncodingName)
    }

    /// Extract the account credentials NGA expects as form fields on
    /// session-bound nuke.php calls. Web cookies alone are not enough for
    /// private messages; MNGA posts `access_uid`/`access_token` from the
    /// same `ngaPassportUid`/`ngaPassportCid` pair.
    private func accessFields(from cookie: String?) -> [String: String] {
        guard let cookie else { return [:] }
        var fields: [String: String] = [:]
        for part in cookie.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let name = pieces[0].trimmingCharacters(in: .whitespaces)
            let value = pieces[1].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            switch name {
            case "ngaPassportUid": fields["access_uid"] = value
            case "ngaPassportCid": fields["access_token"] = value
            default: break
            }
        }
        return fields
    }

    /// A form-url-encoded POST that does not follow cross-host redirects.
    /// Always advertises UTF-8 input (`__inchst=UTF8`) like MNGA; without it NGA
    /// treats the UTF-8 form body as GB18030 and Chinese text arrives garbled.
    private func post(path: String, query: [String: String] = [:], form: [String: String], cookie: String?, addOutput: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var parts = URLComponents(url: host.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var query = query
        if query["__inchst"] == nil { query["__inchst"] = "UTF8" }
        parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("NGA_WP_JW", forHTTPHeaderField: "User-Agent")
        if path == "app_api.php" { request.setValue("Nga_Official", forHTTPHeaderField: "X-User-Agent") }
        var form = form
        for (key, value) in accessFields(from: cookie) where form[key] == nil {
            form[key] = value
        }
        var items = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        if addOutput { items.append(URLQueryItem(name: "__output", value: "11")) }
        var formAllowed = CharacterSet.urlQueryAllowed
        formAllowed.remove(charactersIn: "&=+?")
        request.httpBody = items.map { "\($0.name)=\($0.value?.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        if let cookie, !cookie.contains("\r"), !cookie.contains("\n") { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NGAError.invalidResponse("非 HTTP 响应") }
        if (300..<400).contains(http.statusCode) { throw NGAError.untrustedRedirect }
        return (data, http)
    }
}

/// A small in-memory identity directory smooths over NGA's per-request response
/// variants. If a later HTML compatibility response omits `userInfo`, a name and
/// avatar already returned by NGA during this app run remain stable.
private actor NGAUserCache {
    private var users: [String: NGAUser] = [:]

    func stabilize(_ page: PostPage, host: NGAHost) -> PostPage {
        let posts = page.posts.map { post in
            guard let current = post.user, !current.isAnonymous, !current.uid.isEmpty else { return post }
            let key = "\(host.rawValue):\(current.uid)"
            let cached = users[key]
            let currentHasName = !current.name.hasPrefix("UID ") && current.name != "用户"
            let merged = NGAUser(
                uid: current.uid,
                name: currentHasName ? current.name : (cached?.name ?? current.name),
                avatar: current.avatar ?? cached?.avatar,
                groupTitle: current.groupTitle ?? cached?.groupTitle,
                memberTitle: current.memberTitle ?? cached?.memberTitle,
                signature: current.signature ?? cached?.signature
            )
            if currentHasName || cached != nil { users[key] = merged }
            return Post(id: post.id, pid: post.pid, floor: post.floor, author: merged.name,
                        content: post.content, date: post.date, avatar: merged.avatar,
                        imageURLs: post.imageURLs, user: merged, score: post.score, vote: post.vote)
        }
        return PostPage(title: page.title, posts: posts, page: page.page,
                        hasMore: page.hasMore, totalPages: page.totalPages)
    }
}
