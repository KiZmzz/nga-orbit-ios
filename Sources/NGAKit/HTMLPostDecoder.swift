import Foundation

/// Extracts the post payload from NGA's ordinary read page. This is a data
/// compatibility decoder: it never presents HTML or creates a web view.
/// Some old, formatted topics make NGA truncate both documented JSON variants
/// while their standard page remains complete.
enum HTMLPostDecoder {
    static func posts(from data: Data, tid: Int, page: Int) throws -> PostPage {
        let html = ForumIndex.decode(data)
        let title = text(matching: #"<h3\s+id=['\"]postsubject0['\"][^>]*>(.*?)</h3>"#, in: html) ?? "主题详情"
        let users = userDirectory(in: html)
        let postMatches = matches(#"(?s)<(?:p|span)\s+id=['\"]postcontent(\d+)['\"][^>]*>(.*?)</(?:p|span)>"#, in: html)
        let posts = postMatches.enumerated().compactMap { _, match -> Post? in
            guard let floor = Int(match.values[1]) else { return nil }
            let content = cleanContent(match.values[2])
            guard !content.isEmpty else { return nil }
            let after = String(html[match.range.upperBound...])
            let nextPost = after.range(of: #"id=['\"]postcontent"#, options: .regularExpression)
            let metadata = nextPost.map { String(after[..<$0.lowerBound]) } ?? after
            let pid = integer(matching: #"postArg\.proc\([\s\S]*?null,null,(\d+),"#, in: metadata) ?? 0
            let uid = text(matching: #"postArg\.proc\([\s\S]*?,\s*['\"]?(-?\d+)['\"]?\s*,\s*\d+\s*\)"#, in: metadata)
                ?? text(matching: #"null\s*,\s*['\"](-?\d+)['\"]"#, in: metadata) ?? ""
            let user = users[uid] ?? [:]
            let username = ResponseDecoder.string(user["username"])
            let author = username.hasPrefix("#anony_") ? "匿名用户" : (username.isEmpty ? (uid.isEmpty ? "用户" : "UID \(uid)") : HTMLText.decode(username))
            let avatar = BBCode.avatarURL(ResponseDecoder.string(user["avatar"] ?? user["avatar_url"] ?? user["avatarUrl"] ?? user["face"] ?? user["icon"]))
            let profile = NGAUser(uid: uid, name: author, avatar: avatar,
                                  groupTitle: optionalText(["groupname", "group_name"], in: user),
                                  memberTitle: optionalText(["membertitle", "member_title", "title"], in: user),
                                  signature: optionalText(["signature", "sign"], in: user))
            let date = date(matching: #"id=['\"]postdate\d+['\"][^>]*>([^<]+)<"#, in: metadata)
            return Post(id: "\(tid):\(pid):\(page):\(floor)", pid: pid, floor: floor,
                        author: author, content: content, date: date, avatar: avatar, user: profile)
        }
        guard !posts.isEmpty else { throw NGAError.invalidResponse("此帖的 HTML 中未找到帖子内容") }
        return PostPage(title: cleanContent(title), posts: posts, page: page, hasMore: posts.count >= 20)
    }

    /// The HTML page leaves author links empty and hydrates them from this JSON
    /// object. Reading the object gives the native fallback the same names and
    /// avatars as the normal JSON endpoint without executing any page script.
    private static func userDirectory(in html: String) -> [String: [String: Any]] {
        guard let marker = try? NSRegularExpression(pattern: #"commonui\.userInfo\.setAll\s*\("#, options: .caseInsensitive) else { return [:] }
        var result: [String: [String: Any]] = [:]
        for match in marker.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html),
                  let object = ResponseDecoder.firstJSONObject(in: String(html[range.upperBound...])),
                  let data = ResponseDecoder.normalize(object).data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) else { continue }
            func walk(_ value: Any, key: String? = nil, depth: Int = 0) {
                guard depth < 5 else { return }
                if let map = value as? [String: Any] {
                    if map["username"] != nil || map["uid"] != nil {
                        let embedded = ResponseDecoder.string(map["uid"] ?? map["authorid"] ?? map["id"])
                        if !embedded.isEmpty { result[embedded] = map }
                        if let key, !key.isEmpty, result[key] == nil { result[key] = map }
                    }
                    for (childKey, child) in map where child is [String: Any] || child is [Any] {
                        walk(child, key: childKey, depth: depth + 1)
                    }
                } else if let list = value as? [Any] {
                    for child in list { walk(child, depth: depth + 1) }
                }
            }
            walk(decoded)
        }
        return result
    }

    private static func optionalText(_ keys: [String], in record: [String: Any]) -> String? {
        for key in keys {
            let value = HTMLText.decode(ResponseDecoder.string(record[key])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func cleanContent(_ source: String) -> String {
        let withImages = source.replacingOccurrences(of: #"(?is)<img[^>]+src=['\"]([^'\"]+)['\"][^>]*>"#, with: "[img]$1[/img]", options: .regularExpression)
        let withoutTags = withImages.replacingOccurrences(of: #"(?is)<(?!br\b)[^>]+>"#, with: "", options: .regularExpression)
        return HTMLText.decode(withoutTags).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(matching pattern: String, in text: String) -> Date? {
        guard let value = self.text(matching: pattern, in: text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func integer(matching pattern: String, in source: String) -> Int? {
        text(matching: pattern, in: source).flatMap(Int.init)
    }

    private static func text(matching pattern: String, in source: String) -> String? {
        matches(pattern, in: source).first?.values[1]
    }

    private static func matches(_ pattern: String, in text: String) -> [(range: Range<String.Index>, values: [String])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text) else { return nil }
            let values = (0..<match.numberOfRanges).map { index -> String in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
            return (whole, values)
        }
    }
}
