import Foundation

public indirect enum ContentNode: Sendable, Equatable {
    case text(String)
    case image(URL)
    case link(String, URL)
    case quote([ContentNode])
    case collapse(String, [ContentNode])
    case bold([ContentNode])
    case italic([ContentNode])
    case underline([ContentNode])
    case strike([ContentNode])
    case align(String, [ContentNode])   // left / center / right
    case size(CGFloat, [ContentNode])   // relative font scale
    case color(String, [ContentNode])   // hex or named colour
    case list([ContentNode])
    case bullet([ContentNode])
    case code(String)
    case emote(String, String) // group, name
    case divider
    case table([[[ContentNode]]]) // rows -> cells -> content
    case dice([ContentNode])
}

/// A bounded BBCode subset that covers common NGA posts. Unsupported tags remain visible.
public enum BBCode {
    public static let emoteGroups = ["ac", "a2", "pst", "dt", "pg"]

    public static func emoteNames(in group: String) -> [String] {
        (emoteFiles[group]?.keys.map { $0 } ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func parse(_ content: String) -> [ContentNode] {
        expandEmotes(cleanupQuotes(parse(cleanReplyMetadata(content), depth: 0)))
    }

    /// Target pid carried by NGA's compact “Reply to” form. This form references
    /// a post but omits its text, unlike a full `[quote]` block.
    public static func looseReplyTargetPID(in content: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)^\s*(?:\[b\]\s*)?(?:Reply\s+to\s*)?\[pid=(\d+)[^\]]*\]"#),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return Int(content[range])
    }

    /// Page carried by NGA's `[pid=post,topic,page]` compact reference.
    public static func looseReplyTargetPage(in content: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)^\s*(?:\[b\]\s*)?(?:Reply\s+to\s*)?\[pid=([^\]]+)\]"#),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        let values = content[range].split(separator: ",", omittingEmptySubsequences: false)
        guard values.count >= 3 else { return nil }
        return Int(values[2].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Turn a compact reply reference into the same native quote structure as a
    /// full NGA quote when the referenced post is available on the current page.
    public static func restoringLooseReply(_ content: String, referencedContent: String) -> String {
        guard looseReplyTargetPID(in: content) != nil,
              let regex = try? NSRegularExpression(
                pattern: #"(?is)^\s*((?:\[b\]\s*)?(?:Reply\s+to\s*)?\[pid=[^\]]+\].*?\([^\)]+\):?(?:\[/b\])?(?:\[/pid\])?)\s*"#),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let headerRange = Range(match.range(at: 1), in: content),
              let wholeRange = Range(match.range, in: content) else { return content }
        let quoted = ownPostBody(referencedContent)
        guard !quoted.isEmpty else { return content }
        let ownReply = String(content[wholeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let header = String(content[headerRange])
        return "[quote]\(header)\n\(quoted)[/quote]" + (ownReply.isEmpty ? "" : "\n\(ownReply)")
    }

    /// Content authored on the referenced floor, excluding the quote/reply
    /// context that floor itself was responding to. NGA's official reader uses
    /// this flattened form when quoting a reply, so quote chains do not grow one
    /// nested card deeper on every response.
    public static func ownPostBody(_ content: String) -> String {
        var result = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if looseReplyTargetPID(in: result) != nil,
           let metadata = compactReplyMetadataRange(in: result) {
            result.removeSubrange(metadata)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while let quote = leadingBalancedBlockRange(tag: "quote", in: result) {
            result.removeSubrange(quote)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func compactReplyMetadataRange(in content: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)^\s*(?:\[b\]\s*)?(?:Reply\s+to\s*)?\[pid=[^\]]+\].*?\([^\)]+\):?(?:\[/b\])?(?:\[/pid\])?\s*"#),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) else { return nil }
        return Range(match.range, in: content)
    }

    private static func leadingBalancedBlockRange(tag: String, in content: String) -> Range<String.Index>? {
        guard let open = try? NSRegularExpression(pattern: "(?is)^\\s*\\[\(tag)(?:=[^\\]]*)?\\]"),
              let first = open.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let firstRange = Range(first.range, in: content),
              let token = try? NSRegularExpression(pattern: "(?is)\\[(/?)\(tag)(?:=[^\\]]*)?\\]") else { return nil }
        var depth = 1
        for match in token.matches(in: content, range: NSRange(firstRange.upperBound..., in: content)) {
            if let slash = Range(match.range(at: 1), in: content), !content[slash].isEmpty { depth -= 1 }
            else { depth += 1 }
            if depth == 0, let close = Range(match.range, in: content) {
                return firstRange.lowerBound..<close.upperBound
            }
        }
        return nil
    }

    private static func parse(_ content: String, depth: Int) -> [ContentNode] {
        guard depth < 12, content.count < 250_000 else { return [.text(HTMLText.decode(content))] }
        let text = repairCrossedQuoteListTags(content)
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        let pattern = #"\[(quote|collapse|img|url|tid|pid|uid|flash|iframe|dice|font|table|code|h|l|r|b|i|u|s|del|strike|bold|italic|underline|color|size|align|list)(?:=([^\]]*))?\]"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        var nodes: [ContentNode] = [], cursor = text.startIndex
        while cursor < text.endIndex,
              let match = regex.firstMatch(in: text, range: NSRange(cursor..., in: text)),
              let openRange = Range(match.range, in: text), let tagRange = Range(match.range(at: 1), in: text) {
            let tag = text[tagRange].lowercased()
            let argument = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            let token = try! NSRegularExpression(pattern: "\\[(/?)" + tag + "(?:=[^\\]]*)?\\]", options: .caseInsensitive)
            var nesting = 1, closeRange: Range<String.Index>?
            for next in token.matches(in: text, range: NSRange(openRange.upperBound..., in: text)) {
                if let slash = Range(next.range(at: 1), in: text), !text[slash].isEmpty { nesting -= 1 }
                else { nesting += 1 }
                if nesting == 0 { closeRange = Range(next.range, in: text); break }
            }
            guard let closeRange else {
                nodes.append(.text(HTMLText.decode(String(text[cursor..<openRange.upperBound]))))
                cursor = openRange.upperBound; continue
            }
            if cursor < openRange.lowerBound { nodes.append(.text(HTMLText.decode(String(text[cursor..<openRange.lowerBound])))) }
            let inner = String(text[openRange.upperBound..<closeRange.lowerBound])
            let plain = HTMLText.decode(inner)
            let children = parse(inner, depth: depth + 1)
            switch tag {
            case "quote": nodes.append(.quote(children))
            case "collapse": nodes.append(.collapse(argument.map(HTMLText.decode) ?? "展开内容", children))
            case "b", "bold": nodes.append(.bold(children))
            case "i", "italic": nodes.append(.italic(children))
            case "u", "underline": nodes.append(.underline(children))
            case "s", "strike", "del": nodes.append(.strike(children))
            case "color": nodes.append(.color(argument ?? "", children))
            case "size": nodes.append(.size(sizeScale(argument), children))
            case "align": nodes.append(.align((argument ?? "left").lowercased(), children))
            case "l": nodes.append(.align("left", children))
            case "r": nodes.append(.align("right", children))
            case "list": nodes.append(.list(splitListItems(inner).map { .bullet(parse($0, depth: depth + 1)) }))
            case "code": nodes.append(.code(plain))
            case "h":
                nodes.append(.divider)
                if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nodes.append(contentsOf: children)
                    nodes.append(.divider)
                }
            case "font", "uid": nodes.append(contentsOf: children)
            case "table": nodes.append(.table(parseTable(inner, depth: depth + 1)))
            case "dice": nodes.append(.dice(children))
            case "img":
                if let url = imageURL(plain) { nodes.append(.image(url)) }
                else { nodes.append(.text("[图片地址不支持]")) }
            case "url": nodes.append(linkNode(argument: argument, inner: inner, plain: plain))
            case "tid", "pid":
                // pid/tid wrappers around real post bodies (quote headers plus the
                // quoted text) must render as content; only short plain wrappers
                // become tappable links. Collapsing rich wrappers into one link is
                // what made quotes show a bare header with the body lost.
                if isRichInternalWrapper(inner) { nodes.append(contentsOf: children) }
                else { nodes.append(internalLinkNode(kind: tag, argument: argument, label: plain)) }
            case "flash", "iframe": nodes.append(mediaNode(kind: tag, inner: inner, plain: plain))
            default: nodes.append(.text(plain))
            }
            cursor = closeRange.upperBound
        }
        if cursor < text.endIndex { nodes.append(.text(HTMLText.decode(String(text[cursor...])))) }
        return nodes
    }

    /// Some old NGA posts close a list after its surrounding quote. The legacy
    /// renderer accepts this crossed structure; normalize it before parsing.
    private static func repairCrossedQuoteListTags(_ input: String) -> String {
        input.replacingOccurrences(
            of: #"(?is)(\[quote(?:=[^\]]*)?\].*?\[list(?:=[^\]]*)?\].*?)\[/quote\](\s*)\[/list\]"#,
            with: "$1[/list]$2[/quote]",
            options: .regularExpression
        )
    }

    /// NGA quotations carry navigation-only pid/uid markup. Convert it into a
    /// compact native attribution instead of exposing the raw tags to readers.
    private static func cleanReplyMetadata(_ input: String) -> String {
        var text = input.replacingOccurrences(
            of: #"(?is)Reply\s+to\s*(?=\[pid=)"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)Reply\s+to\s*(?=\[tid=)"#,
            with: "",
            options: .regularExpression
        )
        // The source-topic link inside a quote header is pure navigation noise;
        // leaving it in shifted the「引用 作者 · 时间」attribution with a title.
        text = text.replacingOccurrences(
            of: #"(?is)(?:Reply\s+to\s*)?\[tid=[^\]]*\]\s*(?:Topic|主题|主题帖)\s*\[/tid\]\s*"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)\[pid=[^\]]+\]\s*(?:Reply|回复)?\s*\[/pid\]\s*"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)(?:\[b\])?Post\s+by\s+\[uid=[^\]]+\](.*?)\[/uid\]\s*\(([^\)]+)\):?(?:\[/b\])?"#,
            with: "[b]引用 $1[/b] · $2\n",
            options: .regularExpression
        )
        return text
    }

    /// `[pid=..]`/`[tid=..]` wrapping that carries a real post body (a quote header
    /// plus quoted text, or any nested markup/newlines) renders as its content.
    private static func isRichInternalWrapper(_ inner: String) -> Bool {
        inner.contains("\n") ||
        inner.range(of: #"\[[a-z]+(?:=[^\]]*)?\]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Walk the parsed tree and rescue any quote block where a wrapper left the
    /// body as a single tappable .link instead of real content. The inline-link
    /// heuristic (dissolve only the single-child case) preserves navigation
    /// links that share a quote with surrounding text.
    private static func cleanupQuotes(_ nodes: [ContentNode]) -> [ContentNode] {
        nodes.map { node in
            switch node {
            case .quote(let children): return .quote(dissolveSwallowedLink(children))
            case .bold(let c): return .bold(cleanupQuotes(c))
            case .italic(let c): return .italic(cleanupQuotes(c))
            case .underline(let c): return .underline(cleanupQuotes(c))
            case .strike(let c): return .strike(cleanupQuotes(c))
            case .align(let a, let c): return .align(a, cleanupQuotes(c))
            case .size(let s, let c): return .size(s, cleanupQuotes(c))
            case .color(let co, let c): return .color(co, cleanupQuotes(c))
            case .collapse(let t, let c): return .collapse(t, cleanupQuotes(c))
            case .list(let c): return .list(cleanupQuotes(c))
            case .bullet(let c): return .bullet(cleanupQuotes(c))
            case .dice(let c): return .dice(cleanupQuotes(c))
            case .table(let rows): return .table(rows.map { $0.map(cleanupQuotes) })
            default: return node
            }
        }
    }

    /// If the only child of a quote is a .link, the wrapper never dissolved
    /// and the body is buried as a tappable link. Surface the label as text.
    private static func dissolveSwallowedLink(_ children: [ContentNode]) -> [ContentNode] {
        if children.count == 1, case .link(let label, _) = children[0] {
            return [.text(label)]
        }
        return children
    }

    /// Map a `[size=N]`/`[size=N%]` argument to a relative font scale.
    static func sizeScale(_ arg: String?) -> CGFloat {
        let s = arg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if s.hasSuffix("%"), let p = Double(s.dropLast()) { return CGFloat(p / 100) }
        if let n = Double(s) {
            if s.contains(".") || n > 7 { return CGFloat(n / 16) }
            let map: [CGFloat] = [0.85, 1.0, 1.13, 1.28, 1.45, 1.7, 2.0]
            let idx = min(max(Int(n) - 1, 0), map.count - 1)
            return map[idx]
        }
        return 1
    }

    /// Split a `[list]` body into items separated by `[*]`.
    static func splitListItems(_ inner: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\[\*\]"#)
        var parts: [String] = []; var cursor = inner.startIndex
        for m in regex.matches(in: inner, range: NSRange(inner.startIndex..., in: inner)) {
            guard let r = Range(m.range, in: inner) else { continue }
            let seg = String(inner[cursor..<r.lowerBound])
            if !seg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(seg) }
            cursor = r.upperBound
        }
        let tail = String(inner[cursor...])
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(tail) }
        return parts
    }

    /// Parse NGA's table rows/cells while deliberately ignoring desktop-only
    /// width/rowspan hints. The native renderer keeps every cell readable in a
    /// horizontal scroll area rather than reproducing an over-wide web table.
    static func parseTable(_ inner: String, depth: Int) -> [[[ContentNode]]] {
        let rowRegex = try! NSRegularExpression(pattern: #"(?is)\[tr(?:=[^\]]*)?\](.*?)\[/tr\]"#)
        let cellRegex = try! NSRegularExpression(pattern: #"(?is)\[td[^\]]*\](.*?)\[/td\]"#)
        var rows: [[[ContentNode]]] = []
        for rowMatch in rowRegex.matches(in: inner, range: NSRange(inner.startIndex..., in: inner)) {
            guard let rowRange = Range(rowMatch.range(at: 1), in: inner) else { continue }
            let row = String(inner[rowRange])
            let cells = cellRegex.matches(in: row, range: NSRange(row.startIndex..., in: row)).compactMap { match -> [ContentNode]? in
                guard let range = Range(match.range(at: 1), in: row) else { return nil }
                return parse(String(row[range]), depth: depth + 1)
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }

    private static func linkNode(argument: String?, inner: String, plain: String) -> ContentNode {
        let target = HTMLText.decode(argument ?? inner)
        let label = readableLinkLabel(plain)
        if let url = webURL(target) { return .link(label.isEmpty ? target : label, url) }
        return .text(label.isEmpty ? plain : label)
    }

    /// A link label may itself contain presentational BBCode. The link node owns
    /// the tap target, so remove those wrappers instead of exposing them verbatim.
    private static func readableLinkLabel(_ input: String) -> String {
        input.replacingOccurrences(of: #"(?is)\[/?[a-z][^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func internalLinkNode(kind: String, argument: String?, label: String) -> ContentNode {
        let raw = (argument ?? "").split(separator: ",").first.map(String.init) ?? ""
        guard let id = Int(raw), id > 0,
              let url = URL(string: "https://ngabbs.com/read.php?\(kind)=\(id)") else { return .text(label) }
        return .link(label.isEmpty ? "查看\(kind == "tid" ? "主题" : "回复")" : label, url)
    }

    private static func mediaNode(kind: String, inner: String, plain: String) -> ContentNode {
        let candidates = [HTMLText.decode(inner), plain]
        for candidate in candidates {
            if let url = webURL(candidate) {
                return .link(kind == "flash" ? "打开音频或视频" : "打开嵌入内容", url)
            }
        }
        return .text(plain)
    }

    public static func webURL(_ raw: String) -> URL? {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("/") { return URL(string: raw, relativeTo: URL(string: "https://ngabbs.com"))?.absoluteURL }
        guard var parts = URLComponents(string: raw), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host != nil, parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = "https"
        return parts.url
    }
    public static func imageURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") { value = "https:" + value }
        if value.hasPrefix("./") { value.removeFirst(2) }
        if value.hasPrefix("mon_") { value = "https://img.nga.cn/attachments/" + value }
        if value.range(of: #"^[A-Za-z0-9.-]+\.[A-Za-z]{2,}/"#, options: .regularExpression) != nil { value = "https://" + value }
        guard let url = webURL(value), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let oldHosts = ["img.nga.178.com": "img.nga.cn", "img4.nga.178.com": "img4.nga.cn"]
        if let host = parts.host, let replacement = oldHosts[host] { parts.host = replacement }
        return parts.url
    }

    /// NGA can describe one attachment with an original URL, a CDN alias and a
    /// generated preview URL. Compare their normalized attachment path so one
    /// physical image occupies only one slot in a topic preview.
    public static func uniqueImageURLs(_ urls: [URL], limit: Int = .max) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            var path = url.path.removingPercentEncoding ?? url.path
            path = path.replacingOccurrences(of: "/./", with: "/")
            if let range = path.range(of: "/attachments/", options: .caseInsensitive) {
                path = String(path[range.upperBound...])
            }
            path = path.lowercased()
            for suffix in [".thumb.jpg", ".medium.jpg", ".small.jpg"] where path.hasSuffix(suffix) {
                path.removeLast(suffix.count)
                path += ".jpg"
            }
            guard seen.insert(path).inserted else { continue }
            result.append(url)
            if result.count == limit { break }
        }
        return result
    }

    /// First inline image in a post, used for a bounded topic-list preview.
    public static func firstImageURL(in content: String) -> URL? {
        imageURLs(in: content).first
    }

    /// Inline post images in source order, excluding smile tags. Topic lists use
    /// at most the first three, matching NGA's compact multi-image preview.
    ///
    /// Only URLs whose normalized path extension looks like an image
    /// (`jpg`/`jpeg`/`png`/`gif`/`webp`) are returned. NGA's `[attach]` tag is
    /// also used for `.rar`/`.zip`/`.pdf` file releases; without the extension
    /// filter those URLs would still parse, then crash the list thumbnail loader
    /// and leave a stale "ghost" rectangle in the row.
    ///
    /// When `skipInsideQuotes` is `true`, the scanner ignores image URLs that
    /// appear inside `[quote]…[/quote]` or `[collapse]…[/collapse]` blocks, so
    /// a quoted post with its own image does not surface as the OP's preview.
    public static func imageURLs(in content: String, skipInsideQuotes: Bool = false) -> [URL] {
        let source = skipInsideQuotes ? removeNestedBlocks(content) : content
        let decoded = HTMLText.decode(source)
        let patterns = [
            #"(?is)\[img(?:=[^\]]*)?\](.*?)\[/img\]"#,
            #"(?is)\[attach(?:=[^\]]*)?\](.*?)\[/attach\]"#,
            #"(?i)((?:https?:)?//[^\s\[\]<>'\"]+\.(?:jpe?g|png|gif|webp)(?:\?[^\s\[\]<>'\"]*)?)"#,
            #"(?i)((?:\./)?mon_\d+/[^\s\[\]<>'\"]+\.(?:jpe?g|png|gif|webp))"#
        ]
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]
        var found: [(Int, URL)] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)) {
                guard let range = Range(match.range(at: 1), in: decoded),
                      let url = imageURL(String(decoded[range])),
                      imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
                found.append((match.range.location, url))
            }
        }
        return uniqueImageURLs(found.sorted { $0.0 < $1.0 }.map(\.1))
    }

    /// Strip the body of nested quote/collapse regions so the image scanner
    /// does not pick up images that came from a quoted post. The replacement
    /// keeps byte offsets stable (single space per block) which keeps the
    /// caller's image ordering consistent with the rest of the post.
    private static func removeNestedBlocks(_ content: String) -> String {
        var result = content
        for tag in ["quote", "collapse"] {
            let pattern = "(?is)\\[\(tag)(?:=[^\\]]*)?\\].*?\\[/\(tag)\\]"
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
    }

    /// Resolve a user avatar field to an image URL (best effort; nil → show an initial).
    public static func avatarURL(_ raw: String) -> URL? {
        var v = raw.components(separatedBy: "|.a").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let decoded = v.removingPercentEncoding, decoded != v { v = decoded }
        guard !v.isEmpty else { return nil }
        if v.hasPrefix("//") { v = "https:" + v }
        if v.hasPrefix("/") { return URL(string: "https://bbs.nga.cn" + v) }
        if v.hasPrefix("./") { v.removeFirst(2) }
        if v.hasPrefix("mon_") { return URL(string: "https://img.nga.cn/attachments/" + v) }
        if v.hasPrefix("avatars/") { return URL(string: "https://img.nga.cn/" + v) }
        if v.hasPrefix("ngabbs/") { return URL(string: "https://img4.nga.cn/" + v) }
        if v.hasPrefix("http"), var parts = URLComponents(string: v) {
            if let host = parts.host?.lowercased(),
               host.hasSuffix(".nga.178.com") || host.hasSuffix(".ngacn.cc") || host.hasSuffix(".ngabbs.com") {
                parts.scheme = "https"
                parts.host = parts.path.hasPrefix("/ngabbs/") ? "img4.nga.cn" : "img.nga.cn"
            }
            return parts.url
        }
        if v.contains(".") { return URL(string: "https://img4.nga.cn/ngabbs/face/" + v) }
        return nil
    }

    /// Build a quote block for referencing a floor when replying.
    public static func quoteText(author: String, content: String) -> String {
        let body = content.replacingOccurrences(of: #"(?s)\[quote.*?\[/quote\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "[quote]\(author)\n\(body)[/quote]\n"
    }

    /// The image URL for a `[s:组:名称]` smile.
    public static func emoteURL(group: String, name: String) -> URL? {
        let file = emoteFiles[group]?[name]
            ?? emoteGroups.lazy.compactMap { emoteFiles[$0]?[name] }.first
            ?? (name.lowercased().hasSuffix(".png") || name.lowercased().hasSuffix(".gif") ? name : nil)
        guard let file else { return nil }
        return URL(string: "https://img4.nga.cn/ngabbs/post/smile/\(file)")
    }

    private static let emoteFiles: [String: [String: String]] = [
        "ac": [
            "blink":"ac0.png", "goodjob":"ac1.png", "上":"ac2.png", "中枪":"ac3.png", "偷笑":"ac4.png",
            "冷":"ac5.png", "凌乱":"ac6.png", "反对":"ac7.png", "吓":"ac8.png", "吻":"ac9.png",
            "呆":"ac10.png", "咦":"ac11.png", "哦":"ac12.png", "哭":"ac13.png", "哭1":"ac14.png",
            "哭笑":"ac15.png", "哼":"ac16.png", "喘":"ac17.png", "喷":"ac18.png", "嘲笑":"ac19.png",
            "嘲笑1":"ac20.png", "囧":"ac21.png", "委屈":"ac22.png", "心":"ac23.png", "忧伤":"ac24.png",
            "怒":"ac25.png", "怕":"ac26.png", "惊":"ac27.png", "愁":"ac28.png", "抓狂":"ac29.png",
            "抠鼻":"ac30.png", "擦汗":"ac31.png", "无语":"ac32.png", "晕":"ac33.png", "汗":"ac34.png",
            "瞎":"ac35.png", "羞":"ac36.png", "羡慕":"ac37.png", "花痴":"ac38.png", "茶":"ac39.png",
            "衰":"ac40.png", "计划通":"ac41.png", "赞同":"ac42.png", "闪光":"ac43.png", "黑枪":"ac44.png"
        ],
        "a2": [
            "goodjob":"a2_02.png", "偷笑":"a2_03.png", "怒":"a2_04.png", "诶嘿":"a2_05.png",
            "笑":"a2_07.png", "那个…":"a2_08.png", "哦嗬嗬嗬":"a2_09.png", "舔":"a2_10.png",
            "有何贵干":"a2_11.png", "病娇":"a2_12.png", "lucky":"a2_13.png", "鬼脸":"a2_14.png",
            "大哭":"a2_15.png", "冷":"a2_16.png", "哭":"a2_17.png", "妮可妮可妮":"a2_18.png",
            "惊":"a2_19.png", "poi":"a2_20.png", "恨":"a2_21.png", "囧2":"a2_22.png",
            "中枪":"a2_23.png", "囧":"a2_24.png", "你看看你":"a2_25.png", "yes":"a2_26.png",
            "doge":"a2_27.png", "自戳双目":"a2_28.png", "偷吃":"a2_30.png", "冷笑":"a2_31.png",
            "壁咚":"a2_32.png", "不活了":"a2_33.png", "不明觉厉":"a2_36.png",
            "jojo立":"a2_37.png", "jojo立2":"a2_38.png", "jojo立3":"a2_39.png", "jojo立5":"a2_40.png",
            "jojo立4":"a2_41.png", "威吓":"a2_42.png", "你已经死了":"a2_45.png", "异议":"a2_47.png",
            "认真":"a2_48.png", "你这种人…":"a2_49.png", "是在下输了":"a2_51.png", "抢镜头":"a2_52.png",
            "你为猴这么":"a2_53.png", "干杯":"a2_54.png", "干杯2":"a2_55.png"
        ],
        "pst": [
            "举手":"pt00.png", "亲":"pt01.png", "偷笑":"pt02.png", "偷笑2":"pt03.png", "偷笑3":"pt04.png",
            "傻眼":"pt05.png", "傻眼2":"pt06.png", "兔子":"pt07.png", "发光":"pt08.png", "呆":"pt09.png",
            "呆2":"pt10.png", "呆3":"pt11.png", "呕":"pt12.png", "呵欠":"pt13.png", "哭":"pt14.png",
            "哭2":"pt15.png", "哭3":"pt16.png", "嘲笑":"pt17.png", "基":"pt18.png", "宅":"pt19.png",
            "安慰":"pt20.png", "幸福":"pt21.png", "开心":"pt22.png", "开心2":"pt23.png", "开心3":"pt24.png",
            "怀疑":"pt25.png", "怒":"pt26.png", "怒2":"pt27.png", "怨":"pt28.png", "惊吓":"pt29.png",
            "惊吓2":"pt30.png", "惊呆":"pt31.png", "惊呆2":"pt32.png", "惊呆3":"pt33.png", "惨":"pt34.png",
            "斜眼":"pt35.png", "晕":"pt36.png", "汗":"pt37.png", "泪":"pt38.png", "泪2":"pt39.png",
            "泪3":"pt40.png", "泪4":"pt41.png", "满足":"pt42.png", "满足2":"pt43.png", "火星":"pt44.png",
            "牙疼":"pt45.png", "电击":"pt46.png", "看戏":"pt47.png", "眼袋":"pt48.png", "眼镜":"pt49.png",
            "笑而不语":"pt50.png", "紧张":"pt51.png", "美味":"pt52.png", "背":"pt53.png", "脸红":"pt54.png",
            "脸红2":"pt55.png", "腐":"pt56.png", "星星眼":"pt57.png", "谢":"pt58.png", "醉":"pt59.png",
            "闷":"pt60.png", "闷2":"pt61.png", "音乐":"pt62.png", "黑脸":"pt63.png", "鼻血":"pt64.png"
        ],
        "dt": [
            "ROLL":"dt01.png", "上":"dt02.png", "傲娇":"dt03.png", "叉出去":"dt04.png", "发光":"dt05.png",
            "呵欠":"dt06.png", "哭":"dt07.png", "啃古头":"dt08.png", "嘲笑":"dt09.png", "心":"dt10.png",
            "怒":"dt11.png", "怒2":"dt12.png", "怨":"dt13.png", "惊":"dt14.png", "惊2":"dt15.png",
            "无语":"dt16.png", "星星眼":"dt17.png", "星星眼2":"dt18.png", "晕":"dt19.png", "注意":"dt20.png",
            "注意2":"dt21.png", "泪":"dt22.png", "泪2":"dt23.png", "烧":"dt24.png", "笑":"dt25.png",
            "笑2":"dt26.png", "笑3":"dt27.png", "脸红":"dt28.png", "药":"dt29.png", "衰":"dt30.png",
            "鄙视":"dt31.png", "闲":"dt32.png", "黑脸":"dt33.png"
        ],
        "pg": [
            "战斗力":"pg01.png", "哈啤":"pg02.png", "满分":"pg03.png", "衰":"pg04.png", "拒绝":"pg05.png",
            "心":"pg06.png", "严肃":"pg07.png", "吃瓜":"pg08.png", "嘣":"pg09.png", "嘣2":"pg10.png",
            "冻":"pg11.png", "谢":"pg12.png", "哭":"pg13.png", "响指":"pg14.png", "转身":"pg15.png"
        ]
    ]

    /// Splits `[s:组:名称]` tokens out of text nodes into `.emote` nodes (recursively).
    static func expandEmotes(_ nodes: [ContentNode]) -> [ContentNode] {
        nodes.flatMap { expand($0) }
    }
    static func expand(_ n: ContentNode) -> [ContentNode] {
        switch n {
        case .text(let s): return splitEmotes(s)
        case .quote(let c): return [.quote(expandEmotes(c))]
        case .bold(let c): return [.bold(expandEmotes(c))]
        case .italic(let c): return [.italic(expandEmotes(c))]
        case .underline(let c): return [.underline(expandEmotes(c))]
        case .strike(let c): return [.strike(expandEmotes(c))]
        case .align(let a, let c): return [.align(a, expandEmotes(c))]
        case .size(let s, let c): return [.size(s, expandEmotes(c))]
        case .color(let c0, let c): return [.color(c0, expandEmotes(c))]
        case .list(let c): return [.list(expandEmotes(c))]
        case .bullet(let c): return [.bullet(expandEmotes(c))]
        case .collapse(let t, let c): return [.collapse(t, expandEmotes(c))]
        case .table(let rows): return [.table(rows.map { $0.map(expandEmotes) })]
        case .dice(let c): return [.dice(expandEmotes(c))]
        default: return [n]
        }
    }
    static func splitEmotes(_ text: String) -> [ContentNode] {
        let regex = try! NSRegularExpression(pattern: #"\[(?:s:([^:\]]+):|:)([^\]]+)\]"#)
        var out: [ContentNode] = []; var cursor = text.startIndex
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text), let nameR = Range(m.range(at: 2), in: text) else { continue }
            if cursor < r.lowerBound { out.append(.text(String(text[cursor..<r.lowerBound]))) }
            let group = Range(m.range(at: 1), in: text).map { String(text[$0]) } ?? "ac"
            out.append(.emote(group, String(text[nameR])))
            cursor = r.upperBound
        }
        if cursor < text.endIndex { out.append(.text(String(text[cursor...]))) }
        return out
    }
}
