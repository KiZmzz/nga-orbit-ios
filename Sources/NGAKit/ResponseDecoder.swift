import Foundation
import CoreFoundation

/// Handles known NGA wire irregularities without evaluating remote JavaScript.
public enum ResponseDecoder {
    public static func decode(_ data: Data, status: Int = 200, charset: String? = nil) throws -> [String: Any] {
        guard data.count <= 12_000_000 else { throw NGAError.invalidResponse("响应过大") }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let isGB = charset?.lowercased().hasPrefix("gb") == true
        guard var text = isGB ? String(data: data, encoding: gb) :
                (String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb)) else {
            throw NGAError.invalidResponse("字符编码不支持")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        if status == 403 { throw NGAError.verificationRequired }
        guard (200..<300).contains(status) else { throw NGAError.http(status) }
        // `read.php` may put page script before/after this assignment. Locate the
        // exact known NGA symbol and structurally extract its one object value.
        // We never evaluate any response JavaScript.
        if let marker = text.range(of: "window.script_muti_get_var_store") {
            let suffix = text[marker.upperBound...]
            guard let equal = suffix.firstIndex(of: "=") else {
                throw NGAError.invalidResponse("NGA 返回的数据包装格式异常")
            }
            guard let object = firstJSONObject(in: String(suffix[suffix.index(after: equal)...])) else {
                throw NGAError.invalidResponse("NGA 返回的数据包装不完整")
            }
            text = object
        }
        // HTML with no NGA data assignment is normally a verification/login page.
        if text.hasPrefix("<") { throw NGAError.verificationRequired }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(";") { text.removeLast() }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: Data(normalize(text).utf8)) }
        catch {
            #if DEBUG
            let markerOffset = text.range(of: "window.script_muti_get_var_store").map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? -1
            let details = (error as NSError).userInfo[NSDebugDescriptionErrorKey] ?? error.localizedDescription
            print("[NGAReader][decode] bytes=\(data.count) text=\(text.count) marker=\(markerOffset) parser=\(details)")
            #endif
            throw NGAError.invalidResponse("NGA 返回的数据格式暂不受支持")
        }
        guard let root = object as? [String: Any] else { throw NGAError.invalidResponse("缺少响应对象") }
        if let error = root["error"], !(error is NSNull) {
            let message = ((error as? [Any])?.first as? String) ?? (error as? String) ?? "NGA 请求未完成"
            // Write endpoints report success via an error-shaped payload ("完毕").
            if isSuccessMessage(message) {
                if let map = root["data"] as? [String: Any] { return map }
                // Some write services (notably topic_recommend) return the
                // useful result as an array alongside the success message.
                if let value = root["data"] { return ["data": value] }
                return [:]
            }
            if message.contains("访客") || message.contains("登录") || message.contains("驗證") || message.contains("验证") {
                throw NGAError.verificationRequired
            }
            throw NGAError.server(String(HTMLText.decode(message).prefix(200)))
        }
        return root["data"] as? [String: Any] ?? root
    }

    /// Messages NGA returns in the error channel for successful write actions.
    private static func isSuccessMessage(_ message: String) -> Bool {
        let decoded = HTMLText.decode(message)
        return ["完毕", "没找到", "没有符合条件的结果", "今天已经签到", "找不到用户"]
            .contains { decoded.contains($0) }
    }

    /// Accept a write-action response. Success pages and 完毕 payloads are not failures.
    public static func acceptWrite(_ data: Data, status: Int = 200, charset: String? = nil) throws {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let isGB = charset?.lowercased().hasPrefix("gb") == true
        let text = (isGB ? String(data: data, encoding: gb)
                    : (String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb))) ?? ""
        let decoded = HTMLText.decode(text)
        if decoded.contains("完毕") || decoded.contains("操作完成") { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            // HTML after a write is usually the posted page, not a login wall.
            if decoded.contains("成功") || decoded.contains("完毕") { return }
            // Still try JSON path below in case the body is a wrapped payload.
        }
        _ = try decode(data, status: status, charset: charset)
    }

    /// Quote bare object keys and escape literal control characters only inside strings.
    /// Does not run JS, alter existing quoted strings, or remove meaningful tabs.
    static func normalize(_ text: String) -> String {
        let chars = Array(text)
        var result = "", i = 0, inString = false, escaped = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                if escaped { result.append(c); escaped = false }
                else if c == "\\" { result.append(c); escaped = true }
                else if c == "\"" { result.append(c); inString = false }
                else if c.unicodeScalars.allSatisfy({ $0.value < 32 }) {
                    for scalar in c.unicodeScalars { result += String(format: "\\u%04x", scalar.value) }
                } else { result.append(c) }
                i += 1; continue
            }
            if c == "\"" { inString = true; result.append(c); i += 1; continue }
            result.append(c); i += 1
            if c == "{" || c == "," {
                while i < chars.count && chars[i].isWhitespace { result.append(chars[i]); i += 1 }
                let start = i
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "-") { i += 1 }
                var end = i
                while end < chars.count && chars[end].isWhitespace { end += 1 }
                if i > start && end < chars.count && chars[end] == ":" {
                    result += "\"" + String(chars[start..<i]) + "\""
                } else { result += String(chars[start..<i]) }
            }
        }
        return result
    }

    /// Returns the first complete JSON object, respecting quoted strings and
    /// escapes. This is used only after finding NGA's fixed wrapper variable.
    static func firstJSONObject(in text: String) -> String? {
        let chars = Array(text)
        guard let start = chars.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<chars.count {
            let char = chars[index]
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
                continue
            }
            if char == "\"" { inString = true; continue }
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 { return String(chars[start...index]) }
            }
        }
        return nil
    }

    static func rows(_ value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] { return array }
        if let map = value as? [String: Any] {
            return map.keys.filter { Int($0) != nil }.sorted { Int($0)! < Int($1)! }.compactMap { map[$0] as? [String: Any] }
        }
        return []
    }
    static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
    static func string(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
    static func date(_ value: Any?) -> Date? {
        guard let seconds = integer(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(seconds))
    }

    public static func topics(from data: Data, status: Int = 200, charset: String? = nil, page: Int, forceDigest: Bool = false) throws -> TopicPage {
        let body = try decode(data, status: status, charset: charset)
        guard body["__T"] != nil else { throw NGAError.invalidResponse("缺少主题列表 __T") }
        let rows = rows(body["__T"])
        var seen = Set<Int>()
        let topics = rows.compactMap { row -> Topic? in
            guard let id = integer(row["tid"]), id > 0, seen.insert(id).inserted else { return nil }
            let thumbnails = topicThumbnails(row)
            return Topic(id: id, subject: HTMLText.decode(string(row["subject"])),
                         author: HTMLText.decode(string(row["author"])), replies: integer(row["replies"]) ?? 0,
                         date: date(row["lastpost"] ?? row["postdate"]),
                         flags: TopicStatus(raw: integer(row["type"]) ?? 0,
                                            ifmark: forceDigest ? 1 : (integer(row["ifmark"]) ?? 0),
                                            sticky: isStickyTopic(row)),
                         thumbnails: thumbnails,
                         sourceBoardID: topicSourceBoardID(row),
                         sourceBoardName: topicSourceBoardName(row))
        }
        let perPage = max(1, integer(body["__T__ROWS_PAGE"]) ?? 35)
        let more = integer(body["__ROWS"]).map { page * perPage < $0 } ?? (rows.count >= perPage)
        let forum = body["__F"] as? [String: Any] ?? [:]
        return TopicPage(topics: topics, page: page, hasMore: more,
                         subForums: parseSubForums(forum["sub_forums"] ?? body["sub_forums"]),
                         boardDescription: boardDescription(body["__F"]),
                         headerTopicID: integer(forum["topped_topic"]))
    }

    /// Decode `forum_favor2`'s nested numeric maps into concrete boards.
    public static func favoriteBoards(from data: Data, status: Int = 200, charset: String? = nil) throws -> [Board] {
        let body = try decode(data, status: status, charset: charset)
        var boards: [Board] = []
        var seen = Set<Int>()

        func walk(_ value: Any) {
            if let row = value as? [String: Any] {
                if let fid = integer(row["fid"] ?? row["id"]), fid != 0,
                   row["fid"] != nil, seen.insert(fid).inserted {
                    let name = HTMLText.decode(string(row["name"] ?? row["title"]))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { boards.append(Board(id: fid, name: name)) }
                }
                let keys = row.keys.sorted { lhs, rhs in
                    if let left = Int(lhs), let right = Int(rhs) { return left < right }
                    if Int(lhs) != nil { return true }
                    if Int(rhs) != nil { return false }
                    return lhs < rhs
                }
                for key in keys { if let child = row[key] { walk(child) } }
            } else if let list = value as? [Any] {
                for child in list { walk(child) }
            }
        }
        walk(body)
        return boards
    }

    /// Decode the official app's `subject` service (`result.data`).
    public static func appTopics(from data: Data, status: Int = 200, charset: String? = nil,
                                 page: Int, sticky: Bool = false, digest: Bool = false) throws -> TopicPage {
        let body = try decode(data, status: status, charset: charset)
        if let code = integer(body["code"]), code != 0 {
            throw NGAError.server(HTMLText.decode(string(body["msg"])).isEmpty ? "NGA 主题筛选失败" : HTMLText.decode(string(body["msg"])))
        }
        guard let result = body["result"] as? [String: Any] else { throw NGAError.invalidResponse("缺少主题筛选结果") }
        let rawRows = rows(result["data"])
        var seen = Set<Int>()
        let topics = rawRows.compactMap { row -> Topic? in
            guard let id = integer(row["tid"]), id > 0, seen.insert(id).inserted else { return nil }
            return Topic(id: id, subject: HTMLText.decode(string(row["subject"])),
                         author: HTMLText.decode(string(row["author"])), replies: integer(row["replies"]) ?? 0,
                         date: date(row["lastpost"] ?? row["postdate"]),
                         flags: TopicStatus(raw: integer(row["type"]) ?? 0,
                                            ifmark: digest ? 1 : (integer(row["ifmark"]) ?? 0),
                                            sticky: sticky || isStickyTopic(row)),
                         thumbnails: topicThumbnails(row),
                         sourceBoardID: topicSourceBoardID(row),
                         sourceBoardName: topicSourceBoardName(row))
        }
        let header = result["header"] as? [String: Any]
        let currentPage = integer(body["currentPage"]) ?? page
        let hasMore = integer(body["totalPage"]).map { currentPage < $0 }
            ?? integer(body["total"]).map { currentPage * max(1, integer(body["perPage"]) ?? 35) < $0 }
            ?? (rawRows.count >= max(1, integer(body["perPage"]) ?? 35))
        return TopicPage(topics: topics, page: currentPage, hasMore: hasMore,
                         subForums: parseAppSubForums(result["subForum"]),
                         headerTopicID: integer(header?["opendata"]))
    }

    /// Decode the official user detail service while keeping every field
    /// optional except the identity already known from the tapped post.
    public static func user(from data: Data, status: Int = 200, charset: String? = nil,
                            fallback: NGAUser) throws -> NGAUser {
        let body = try decode(data, status: status, charset: charset)
        if let code = integer(body["code"]), code != 0 {
            throw NGAError.server(HTMLText.decode(string(body["msg"])).isEmpty ? "NGA 用户资料读取失败" : HTMLText.decode(string(body["msg"])))
        }
        func record(in value: Any, depth: Int = 0) -> [String: Any]? {
            guard depth < 6 else { return nil }
            if let map = value as? [String: Any] {
                if map["username"] != nil || map["uid"] != nil { return map }
                for child in map.values {
                    if let found = record(in: child, depth: depth + 1) { return found }
                }
            } else if let list = value as? [Any] {
                for child in list {
                    if let found = record(in: child, depth: depth + 1) { return found }
                }
            }
            return nil
        }
        let row = record(in: body) ?? [:]
        func optionalText(_ keys: [String]) -> String? {
            for key in keys {
                let value = HTMLText.decode(string(row[key])).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
            return nil
        }
        let uid = string(row["uid"] ?? row["authorid"] ?? row["id"])
        let name = optionalText(["username", "name"]) ?? fallback.name
        let rawAvatar: String = {
            let v = row["avatar"] ?? row["avatar_url"] ?? row["avatarUrl"] ?? row["face"] ?? row["icon"]
            return string(v)
        }()
        let avatar = BBCode.avatarURL(rawAvatar) ?? fallback.avatar
        return NGAUser(uid: uid.isEmpty ? fallback.uid : uid, name: name, avatar: avatar,
                       groupTitle: optionalText(["groupname", "group_name"]) ?? fallback.groupTitle,
                       memberTitle: optionalText(["membertitle", "member_title", "title"]) ?? fallback.memberTitle,
                       signature: optionalText(["signature", "sign"]) ?? fallback.signature)
    }

    /// Decode `topic_recommend` without assuming one fixed NGA container shape.
    /// The service has returned the signed delta as either a numbered field or
    /// inside `data`/`result` arrays across different hosts and response modes.
    public static func voteResult(from data: Data, status: Int = 200, charset: String? = nil,
                                  direction: PostVote) throws -> PostVoteResult {
        let body = try decode(data, status: status, charset: charset)

        func delta(in value: Any, depth: Int = 0) -> Int? {
            guard depth < 6 else { return nil }
            if let map = value as? [String: Any] {
                for key in ["delta", "1", "0"] {
                    if let value = integer(map[key]), value != 0 { return value }
                }
                for key in ["data", "result"] {
                    if let child = map[key], let value = delta(in: child, depth: depth + 1) { return value }
                }
            } else if let list = value as? [Any] {
                for child in list {
                    if let value = integer(child), value != 0 { return value }
                    if let value = delta(in: child, depth: depth + 1) { return value }
                }
            }
            return nil
        }

        guard let change = delta(in: body) else {
            throw NGAError.invalidResponse("NGA 未确认本次赞同或反对操作")
        }
        let selection: PostVote? = (direction == .agree && change > 0)
            || (direction == .disagree && change < 0) ? direction : nil
        return PostVoteResult(delta: change, selection: selection)
    }

    private static func parseAppSubForums(_ value: Any?) -> [Board] {
        rows(value).compactMap { row in
            guard let id = integer(row["id"] ?? row["fid"] ?? row["0"]), id != 0 else { return nil }
            let name = HTMLText.decode(string(row["name"] ?? row["1"]))
            return Board(id: id, name: name.isEmpty ? "子版面 \(id)" : name)
        }
    }

    private static func isStickyTopic(_ row: [String: Any]) -> Bool {
        for key in ["topped", "is_topped", "istop", "is_top"] {
            if let value = integer(row[key]), value != 0 { return true }
        }
        // The official subject service uses bit 0 of topic_misc_var_bit1 for
        // navigation/sticky topics; this is separate from the legacy `type`
        // flags, whose bit meanings describe other topic attributes.
        return ((integer(row["topic_misc_var_bit1"]) ?? 0) & 1) != 0
    }

    private static func topicSourceBoardID(_ row: [String: Any]) -> Int? {
        integer(row["as_forum_fid"] ?? row["forum_as_set"] ?? row["set_elm_parent"] ?? row["fid"])
    }

    private static func topicSourceBoardName(_ row: [String: Any]) -> String? {
        let value = HTMLText.decode(string(row["forumname"] ?? row["forum_name"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func topicThumbnails(_ row: [String: Any]) -> [URL] {
        var result: [URL] = []
        var foundExplicit = false
        func append(_ url: URL) {
            result = BBCode.uniqueImageURLs(result + [url], limit: 3)
        }
        for key in ["tpcurl", "topicimg", "topic_img", "thumb", "thumbnail", "cover", "image", "img"] {
            let raw = string(row[key])
            if !raw.isEmpty, let url = BBCode.imageURL(raw), isImageURL(url) {
                append(url); foundExplicit = true
            }
        }
        // Newer topic-list responses expose the OP preview in `attachs`.  `tpcurl`
        // usually points to /read.php and must not suppress this attachment or the
        // later OP inspection pass.
        let attached = attachmentImages(row["attachs"] ?? row["attachments"] ?? row["attach"])
        if !attached.isEmpty { foundExplicit = true }
        for image in attached { append(image) }
        // Snippet body is a best-effort fallback only. It often misleads the
        // scanner with quoted images or [attach] links to .rar/.zip releases
        // whose URLs would survive into the list and stall the row's
        // thumbnail loader. Use the quote-aware variant so the OP really did
        // embed a [img] before we promote it to a preview slot.
        if !foundExplicit {
            let content = string(row["content"] ?? row["postcontent"] ?? row["subject_content"])
            for image in BBCode.imageURLs(in: content, skipInsideQuotes: true) { append(image) }
        }
        return result
    }

    private static func isImageURL(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp"].contains(url.pathExtension.lowercased())
    }

    private static func attachmentImages(_ value: Any?) -> [URL] {
        guard let value else { return [] }
        var result: [URL] = []
        func walk(_ value: Any) {
        if let map = value as? [String: Any] {
            for key in ["url", "attachurl", "path", "src", "file", "name"] {
                    if let url = BBCode.imageURL(string(map[key])), isImageURL(url), !result.contains(url) { result.append(url) }
            }
                // Inspect only nested containers after reading known URL keys.
                // Scalar fields include generated thumb URLs for the same file.
                for child in map.values where child is [String: Any] || child is [Any] { walk(child) }
        } else if let list = value as? [Any] {
                for child in list { walk(child) }
        } else if let raw = value as? String,
                  let url = BBCode.imageURL(raw), isImageURL(url) {
                result = BBCode.uniqueImageURLs(result + [url])
            }
        }
        walk(value)
        return BBCode.uniqueImageURLs(result, limit: 3)
    }

    private static func boardDescription(_ value: Any?) -> String? {
        guard let value else { return nil }
        let keys = Set(["description", "desc", "info", "content", "rule", "notice", "subtitle"])
        func search(_ node: Any, depth: Int) -> String? {
            guard depth < 5 else { return nil }
            if let map = node as? [String: Any] {
                for key in keys {
                    let value = HTMLText.decode(string(map[key])).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty, value.count < 800 { return value }
                }
                for child in map.values { if let found = search(child, depth: depth + 1) { return found } }
            } else if let array = node as? [Any] {
                for child in array { if let found = search(child, depth: depth + 1) { return found } }
            }
            return nil
        }
        return search(value, depth: 0)
    }

    /// Read `sub_forums` — nested boards of the current board (best effort).
    static func parseSubForums(_ value: Any?) -> [Board] {
        guard let map = value as? [String: Any] else { return [] }
        return map.compactMap { key, val -> Board? in
            let raw = key.hasPrefix("t") ? String(key.dropFirst()) : key
            guard let fid = Int(raw), fid != 0 else { return nil }
            var name: String?
            if let arr = val as? [Any] {
                for item in arr {
                    if let s = item as? String, !s.isEmpty, Int(s) == nil { name = s; break }
                }
            }
            return Board(id: fid, name: name ?? "子版面 \(fid)")
        }
    }

    public static func posts(from data: Data, status: Int = 200, charset: String? = nil, tid: Int, page: Int) throws -> PostPage {
        let body = try decode(data, status: status, charset: charset)
        guard body["__R"] != nil else { throw NGAError.invalidResponse("缺少回复列表 __R") }
        let users = userDirectory(body["__U"])
        let topic = body["__T"] as? [String: Any] ?? [:]
        let perPage = max(1, integer(body["__R__ROWS_PAGE"]) ?? 20)
        let rows = rows(body["__R"])
        let posts = rows.enumerated().map { offset, row -> Post in
            let pid = integer(row["pid"]) ?? 0
            let floor = integer(row["lou"]) ?? ((page - 1) * perPage + offset)
            let uid = string(row["authorid"])
            let user = users[uid] ?? [:]
            let username = string(user["username"] ?? user["name"] ?? row["author"] ?? row["username"])
            let author = username.hasPrefix("#anony_") ? "匿名用户" : (username.isEmpty ? (uid.isEmpty ? "用户" : "UID \(uid)") : HTMLText.decode(username))
            let rawAvatar: String = {
                let u = user["avatar"] ?? user["avatar_url"] ?? user["avatarUrl"] ?? user["face"] ?? user["icon"]
                let r = row["avatar"] ?? row["avatar_url"] ?? row["avatarUrl"] ?? row["face"] ?? row["icon"]
                return string(u ?? r)
            }()
            let avatar = BBCode.avatarURL(rawAvatar)
            let profile = userProfile(uid: uid, author: author, avatar: avatar, record: user)
            let images = attachmentImageURLs(row["attachs"] ?? row["attachments"] ?? row["attach"])
            let scoreTuple = string(row["score"]).split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let score = integer(row["score"]) ?? (scoreTuple.count > 1 ? scoreTuple[1] : 0)
            let recommend = integer(row["recommend"]) ?? (scoreTuple.count > 2 ? scoreTuple[2] : 0)
            return Post(id: "\(tid):\(pid):\(page):\(offset)", pid: pid, floor: floor, author: author,
                        content: string(row["content"]),
                        date: date(row["postdatetimestamp"] ?? row["postdate"] ?? row["time"]), avatar: avatar,
                        imageURLs: images, user: profile, score: score, vote: PostVote(rawValue: recommend))
        }
        let totalRows = integer(body["__ROWS"])
        let totalPages = totalRows.map { max(1, ($0 + perPage - 1) / perPage) }
        let more = totalRows.map { page * perPage < $0 } ?? (rows.count >= perPage)
        return PostPage(title: HTMLText.decode(string(topic["subject"])), posts: posts, page: page,
                        hasMore: more, totalPages: totalPages)
    }

    /// NGA short-message conversations are returned under data["0"], keyed by mid.
    public static func privateMessages(from body: [String: Any]) -> [Message] {
        let container = body["0"] ?? body
        let records = objectRows(container)
        return records.compactMap { row -> Message? in
            let id = string(row["mid"] ?? row["id"])
            guard !id.isEmpty else { return nil }
            let title = HTMLText.decode(string(row["subject"]))
            let sender = HTMLText.decode(string(row["from_username"] ?? row["from"] ?? row["username"]))
            let date = date(row["last_modify"] ?? row["time"])
            return Message(id: id, title: title.isEmpty ? "（无标题）" : title,
                           sender: sender.isEmpty ? "NGA 用户" : sender, body: nil, date: date, kind: .direct)
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Parse the positional arrays returned by nuke.php?__lib=noti&__act=get_all.
    public static func notifications(from body: [String: Any]) -> [Message] {
        var records: [[String: Any]] = []
        func walk(_ value: Any, depth: Int = 0) {
            guard depth < 6 else { return }
            if let row = value as? [String: Any] {
                if row["0"] != nil, row["9"] != nil, row["6"] != nil { records.append(row); return }
                for child in row.values { walk(child, depth: depth + 1) }
            } else if let list = value as? [Any] {
                for child in list { walk(child, depth: depth + 1) }
            }
        }
        walk(body["0"] ?? body)
        return records.compactMap { row -> Message? in
            guard let type = integer(row["0"]), let seconds = integer(row["9"]) else { return nil }
            let topicID = integer(row["6"])
            let postID = integer(row["7"])
            let page = integer(row["10"])
            let subject = HTMLText.decode(string(row["5"]))
            let sender = HTMLText.decode(string(row["2"]))
            let kind: MessageKind
            switch type {
            case 1, 2, 7, 8, 17: kind = .interaction
            case 10, 11: kind = .direct
            default: kind = .system
            }
            let description: String
            switch type {
            case 1: description = "回复了你的主题"
            case 2: description = "回复了你的帖子"
            case 7, 8: description = "在帖子中提到了你"
            case 10: description = "发起了私信"
            case 11: description = "回复了私信"
            case 17: description = "赞同了你的帖子"
            default: description = "NGA 系统通知"
            }
            let id = "\(seconds)-\(type)-\(topicID ?? 0)-\(postID ?? 0)"
            return Message(id: id, title: subject.isEmpty ? description : subject,
                           sender: sender.isEmpty ? "NGA" : sender, body: description,
                           date: Date(timeIntervalSince1970: Double(seconds)), kind: kind,
                           topicID: topicID, postID: postID, page: page)
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Posts inside one short-message conversation (act=read).
    public static func privateMessagePosts(from body: [String: Any]) -> [Message] {
        privateMessageThread(from: body).posts
    }

    /// Conversation posts plus the roster NGA returns under userInfo / allUsers.
    public static func privateMessageThread(from body: [String: Any]) -> PrivateMessageThread {
        guard let root = body["0"] as? [String: Any] else {
            return PrivateMessageThread(posts: [], participants: [:])
        }
        var users = messageUserDirectory(root["userInfo"])
        for (uid, name) in messageUserDirectory(root["allUsers"]) where users[uid] == nil {
            users[uid] = name
        }
        // `all_user` is a tab-separated "uid\tname\tuid\tname" roster on some payloads.
        let allUser = string(root["all_user"])
        if !allUser.isEmpty {
            let parts = allUser.split(separator: "\t", omittingEmptySubsequences: false)
            var index = 0
            while index + 1 < parts.count {
                let uid = String(parts[index])
                let name = HTMLText.decode(String(parts[index + 1]))
                if !uid.isEmpty, !name.isEmpty { users[uid] = name }
                index += 2
            }
        }
        let posts = objectRows(root["allmsgs"]).compactMap { row -> Message? in
            let id = string(row["id"] ?? row["mid"] ?? row["time"])
            guard !id.isEmpty else { return nil }
            let uid = string(row["from"])
            let author = users[uid] ?? HTMLText.decode(string(row["from_username"] ?? row["username"]))
            let content = string(row["content"])
            return Message(id: id, title: HTMLText.decode(string(row["subject"])),
                           sender: author.isEmpty ? (uid.isEmpty ? "NGA 用户" : "UID \(uid)") : author,
                           body: content.isEmpty ? nil : content, date: date(row["time"]), kind: .direct,
                           authorUID: uid.isEmpty ? nil : uid)
        }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        return PrivateMessageThread(posts: posts, participants: users)
    }

    private static func objectRows(_ value: Any?) -> [[String: Any]] {
        if let list = value as? [[String: Any]] { return list }
        guard let map = value as? [String: Any] else { return [] }
        return map.values.compactMap { $0 as? [String: Any] }
    }

    private static func messageUserDirectory(_ value: Any?) -> [String: String] {
        var result: [String: String] = [:]
        func walk(_ value: Any, key: String? = nil, depth: Int = 0) {
            guard depth < 5 else { return }
            if let map = value as? [String: Any] {
                let uid = string(map["uid"] ?? map["id"] ?? key)
                let name = HTMLText.decode(string(map["username"] ?? map["name"]))
                if !uid.isEmpty, !name.isEmpty { result[uid] = name }
                for (childKey, child) in map { walk(child, key: childKey, depth: depth + 1) }
            } else if let list = value as? [Any] {
                for child in list { walk(child, depth: depth + 1) }
            }
        }
        if let value { walk(value) }
        return result
    }

    /// NGA emits `__U` in more than one shape. Some threads key users by UID,
    /// while others use array/sequence indexes and keep the real UID in each
    /// record. Build one UID keyed directory so both responses resolve names.
    private static func userDirectory(_ value: Any?) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]

        func add(_ record: [String: Any], key: String? = nil) {
            let embeddedUID = string(record["uid"] ?? record["authorid"] ?? record["id"])
            if !embeddedUID.isEmpty { result[embeddedUID] = record }
            if let key, !key.isEmpty, result[key] == nil { result[key] = record }
        }

        func walk(_ value: Any, key: String? = nil, depth: Int = 0) {
            guard depth < 5 else { return }
            if let map = value as? [String: Any] {
                let looksLikeUser = map["username"] != nil || map["uid"] != nil || map["authorid"] != nil
                if looksLikeUser { add(map, key: key) }
                for (childKey, child) in map where child is [String: Any] || child is [Any] {
                    walk(child, key: childKey, depth: depth + 1)
                }
            } else if let list = value as? [Any] {
                for child in list { walk(child, depth: depth + 1) }
            }
        }
        if let value { walk(value) }
        return result
    }

    private static func userProfile(uid: String, author: String, avatar: URL?, record: [String: Any]) -> NGAUser? {
        guard !uid.isEmpty || !author.isEmpty else { return nil }
        func optionalText(_ keys: [String]) -> String? {
            for key in keys {
                let value = HTMLText.decode(string(record[key])).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
            return nil
        }
        return NGAUser(uid: uid, name: author, avatar: avatar,
                       groupTitle: optionalText(["groupname", "group_name"]),
                       memberTitle: optionalText(["membertitle", "member_title", "title"]),
                       signature: optionalText(["signature", "sign"]))
    }

    private static func attachmentImageURLs(_ value: Any?) -> [URL] {
        var result: [URL] = []
        func walk(_ value: Any) {
            if let map = value as? [String: Any] {
                for key in ["url", "attachurl", "path", "src", "file", "name"] {
                    let raw = string(map[key])
                    if let url = BBCode.imageURL(raw), ["jpg", "jpeg", "png", "gif", "webp"].contains(url.pathExtension.lowercased()), !result.contains(url) {
                        result.append(url)
                    }
                }
                for child in map.values where child is [String: Any] || child is [Any] { walk(child) }
            } else if let list = value as? [Any] {
                for child in list { walk(child) }
            } else if let raw = value as? String,
                      let url = BBCode.imageURL(raw), ["jpg", "jpeg", "png", "gif", "webp"].contains(url.pathExtension.lowercased()), !result.contains(url) {
                        result = BBCode.uniqueImageURLs(result + [url])
            }
        }
        if let value { walk(value) }
        return BBCode.uniqueImageURLs(result)
    }
}

public enum HTMLText {
    public static func decode(_ input: String) -> String {
        var text = input.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        // NGA sometimes escapes a numeric entity's ampersand once more
        // (`&amp;#128516;`). Unwrap only that numeric form before the normal
        // one-pass decoder, while preserving intentionally double-escaped tags.
        text = text.replacingOccurrences(
            of: #"&amp;(#x[0-9a-fA-F]+|#[0-9]+);"#,
            with: "&$1;",
            options: .regularExpression
        )
        // Decode entities exactly once, so escaped BBCode remains escaped until parsing completes.
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);"#)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text), let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange])
            let named = ["amp":"&", "lt":"<", "gt":">", "quot":"\"", "apos":"'", "nbsp":" "]
            var replacement = named[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let value = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(value) {
                    replacement = String(scalar)
                }
            }
            if let replacement { text.replaceSubrange(range, with: replacement) }
        }
        return text
    }
}
