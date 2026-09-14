import Foundation
import CoreFoundation

/// NGA's static forum index (`bbs_index_data.js`): a JS file holding the whole board tree.
/// The file is fetched from an image CDN, a leading JS assignment is stripped, and the
/// remainder is JSON. This reader only picks out the name + fid of each board and groups
/// them by their top-level category.
public enum ForumIndex {
    /// Candidate CDN URLs for the board index. Newer NGA hosts use `img*.nga.cn`.
    static let urls: [URL] = [
        URL(string: "https://img4.nga.178.com/proxy/cache_attach/bbs_index_data.js")!,
        URL(string: "https://img4.nga.cn/proxy/cache_attach/bbs_index_data.js")!,
        URL(string: "https://img.nga.cn/proxy/cache_attach/bbs_index_data.js")!,
        URL(string: "https://img4.nga.178.com/proxy/cache_attach/bbs_index_data2.js")!,
    ]

    /// Decode the index bytes. NGA serves this file in GB18030 by default, so fall back from UTF-8.
    public static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8), !text.contains("\u{FFFD}") { return text }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb) ?? String(decoding: data, as: UTF8.self)
    }

    /// Strip a leading `var x =` / `window.x =` assignment and a trailing `;`.
    static func stripJS(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        text = String(text.trimmingCharacters(in: CharacterSet(charactersIn: ";")))
        if let brace = text.firstIndex(of: "{"), text[text.startIndex..<brace].contains("=") {
            text = String(text[brace...])
        }
        return text
    }

    static func parseAny(_ text: String) -> Any? {
        let cleaned = stripJS(text)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Best-effort parse into categorized boards. NGA's index nests categories; this reads the
    /// common `name` / `sub` / `fid` shapes and falls back to raw text on failure so the caller
    /// can surface what it got.
    public static func parse(_ text: String) -> [BoardSection] {
        guard let object = parseAny(text) else { return [] }
        return sections(from: object)
    }

    /// Return the named groups that belong to one large forum, such as the
    /// World of Warcraft hub's main boards, class boards and guide boards.
    public static func childSections(_ text: String, parentFID: Int) -> [BoardSection] {
        guard let object = parseAny(text) else { return [] }
        let root = (object as? [String: Any])?["data"] as? [String: Any] ?? (object as? [String: Any])
        guard let root else { return [] }

        // The index does not key a hub by its public negative fid. For example,
        // `fid=-7` lives in `data.0.all.wow`, whose nested first board has fid 7.
        // Locate the hub that contains the requested board, then retain the
        // intermediate named groups instead of flattening all descendants.
        let target = abs(parentFID)
        var fallback: [BoardSection] = []
        for (_, categoryValue) in root.sorted(by: { numeric($0.key) < numeric($1.key) }) {
            guard let category = categoryValue as? [String: Any] else { continue }
            guard let hubs = category["all"] as? [String: Any] else { continue }
            for (hubKey, value) in hubs.sorted(by: { $0.key < $1.key }) {
                guard let hub = value as? [String: Any],
                      containsBoard(hub["content"], fid: target) else { continue }
                let sections = sections(forHub: hub, hubKey: hubKey)
                guard !sections.isEmpty else { continue }

                // A board may also occur in `new` (recent additions), favourites,
                // or another cross-list. Its canonical hub is the one whose first
                // group starts with that board, e.g. wow starts with FID 7.
                if ["new", "fast", "follow"].contains(hubKey) { continue }
                if sections.first?.boards.first?.id.magnitude == target.magnitude { return sections }
                if fallback.isEmpty { fallback = sections }
            }
        }
        return fallback
    }

    /// Preserve the subgroup headings of one exact top-level hub. `parse(_:)`
    /// intentionally flattens them for search; the 版块 screen uses this method
    /// to show sections such as 职业讨论区 and 冒险心得 in their proper place.
    public static func hubSections(_ text: String, hubID: String) -> [BoardSection] {
        guard let object = parseAny(text) else { return [] }
        let root = (object as? [String: Any])?["data"] as? [String: Any] ?? (object as? [String: Any])
        guard let root else { return [] }
        for (_, categoryValue) in root.sorted(by: { numeric($0.key) < numeric($1.key) }) {
            guard let category = categoryValue as? [String: Any],
                  let hubs = category["all"] as? [String: Any],
                  let hub = hubs[hubID] as? [String: Any] else { continue }
            return sections(forHub: hub, hubKey: hubID)
        }
        return []
    }

    private static func sections(forHub hub: [String: Any], hubKey: String) -> [BoardSection] {
        guard let groups = hub["content"] as? [String: Any] else { return [] }
        return groups.sorted(by: { numeric($0.key) < numeric($1.key) }).compactMap { key, value -> BoardSection? in
            guard let group = value as? [String: Any] else { return nil }
            let items = boards(from: group["content"] ?? group)
            guard !items.isEmpty else { return nil }
            let fallback = key == "0" ? (readableName(hub) ?? "主要版面") : "子版面"
            return BoardSection(id: "\(hubKey).\(key)", title: readableName(group) ?? fallback, boards: items)
        }
    }

    /// Short factual description for a board from the same static catalogue.
    public static func boardDescription(_ text: String, fid: Int) -> String? {
        guard let object = parseAny(text) else { return nil }
        return findBoardDescription(object, fid: abs(fid))
    }

    /// A board can occur in several cross-lists. Keep searching when the first
    /// matching occurrence has no description instead of returning nil early.
    private static func findBoardDescription(_ value: Any, fid: Int) -> String? {
        if let map = value as? [String: Any] {
            if boardFID(map).map(abs) == fid {
                for key in ["info", "infoL", "description", "desc"] {
                    if let text = map[key] as? String, !text.isEmpty { return HTMLText.decode(text) }
                }
            }
            for key in map.keys.sorted(by: { numeric($0) < numeric($1) }) {
                if let child = map[key], let result = findBoardDescription(child, fid: fid) { return result }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = findBoardDescription(child, fid: fid) { return result }
            }
        }
        return nil
    }

    private static func containsBoard(_ value: Any?, fid: Int) -> Bool {
        guard let value else { return false }
        if let map = value as? [String: Any] {
            if boardFID(map).map(abs) == fid { return true }
            return map.values.contains { containsBoard($0, fid: fid) }
        }
        if let array = value as? [Any] { return array.contains { containsBoard($0, fid: fid) } }
        return false
    }

    private static func findBoardNode(_ value: Any, fid: Int) -> [String: Any]? {
        if let map = value as? [String: Any] {
            if boardFID(map).map(abs) == fid { return map }
            for child in map.values {
                if let found = findBoardNode(child, fid: fid) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findBoardNode(child, fid: fid) { return found }
            }
        }
        return nil
    }

    static func sections(from object: Any) -> [BoardSection] {
        var sections: [BoardSection] = []
        // NGA's index wraps the real map in a `data` envelope; unwrap it.
        let root = (object as? [String: Any])?["data"] as? [String: Any] ?? (object as? [String: Any])

        if let dict = root {
            for (catKey, catVal) in dict.sorted(by: { numeric($0.key) < numeric($1.key) }) {
                guard let cat = catVal as? [String: Any] else { continue }
                // Boards are grouped under `all` (each group -> {name, id, content}).
                if let all = cat["all"] as? [String: Any] {
                    // Stable order so the category pills don't reorder between renders.
                    let groups = all.sorted { a, b in
                        let na = readableName(a.value as? [String: Any] ?? [:]) ?? a.key
                        let nb = readableName(b.value as? [String: Any] ?? [:]) ?? b.key
                        return na < nb
                    }
                    for (groupKey, groupVal) in groups {
                        let group = groupVal as? [String: Any] ?? [:]
                        let title = readableName(group) ?? groupKey
                        let boardsIn = boards(from: group["content"])
                        if !boardsIn.isEmpty {
                            sections.append(BoardSection(id: "\(catKey).\(groupKey)", title: title, boards: boardsIn))
                        }
                    }
                } else {
                    let boardsIn = boards(in: cat)
                    if !boardsIn.isEmpty {
                        sections.append(BoardSection(id: catKey, title: readableName(cat) ?? catKey, boards: boardsIn))
                    }
                }
            }
        } else if let list = object as? [Any] {
            for (i, item) in list.enumerated() {
                guard let cat = item as? [String: Any] else { continue }
                let boardsIn = boards(in: cat)
                if !boardsIn.isEmpty {
                    sections.append(BoardSection(id: "\(i)", title: readableName(cat) ?? "分类 \(i + 1)", boards: boardsIn))
                }
            }
        }
        return sections
    }

    /// Parse boards out of a `content` node. NGA nests boards at arbitrary depths, so this
    /// recursively collects every node that carries both a `fid` and a readable name.
    static func boards(from value: Any?) -> [Board] {
        guard let value else { return [] }
        var out: [Board] = []; var seen = Set<Int>()
        collectBoards(value, into: &out, seen: &seen, depth: 0)
        return out
    }

    static func collectBoards(_ v: Any, into out: inout [Board], seen: inout Set<Int>, depth: Int) {
        guard depth < 10 else { return }
        if let d = v as? [String: Any] {
            // A board node: has a real `fid` and a name. (Category nodes use `id`, so they don't match.)
            if let fid = boardFID(d), let name = readableName(d), !name.isEmpty {
                if seen.insert(fid).inserted { out.append(Board(id: fid, name: name)) }
                return
            }
            for (key, val) in d.sorted(by: { numeric($0.key) < numeric($1.key) }) {
                if key.hasPrefix("__") { continue }
                collectBoards(val, into: &out, seen: &seen, depth: depth + 1)
            }
        } else if let a = v as? [Any] {
            for item in a { collectBoards(item, into: &out, seen: &seen, depth: depth + 1) }
        }
    }

    /// Read a board's real fid; only the `fid` field (category nodes expose `id`, not `fid`).
    static func boardFID(_ d: [String: Any]) -> Int? {
        let fid = (d["fid"] as? NSNumber)?.intValue ?? Int(d["fid"] as? String ?? "")
        return (fid != nil && fid != 0) ? fid : nil
    }

    /// Read a human category/board name from a node, trying several key spellings.
    static func readableName(_ node: [String: Any]) -> String? {
        for key in ["name", "n", "title", "name_cn", "label"] {
            if let v = node[key] as? String, !v.isEmpty { return v }
            if let v = node[key] as? NSNumber { return v.stringValue }
        }
        return nil
    }

    /// Pull boards out of a category node: either a `sub`/`boards`/`fid` child dict of
    /// fid->name entries, or the node itself when it looks like a bare board map.
    static func boards(in node: [String: Any]) -> [Board] {
        var raw: [String: Any] = [:]
        for key in ["sub", "boards", "fid", "forum", "list", "children"] {
            if let v = node[key] as? [String: Any] { raw = v; break }
        }
        if raw.isEmpty, isBoardMap(node) { raw = node }
        return raw.compactMap { key, value -> Board? in
            guard let fid = Int(key), fid != 0 else { return nil }
            let name: String
            if let v = value as? [String: Any] { name = readableName(v) ?? "\(fid)" }
            else if let v = value as? String { name = v }
            else if let v = value as? NSNumber { name = v.stringValue }
            else { name = "版块 \(fid)" }
            return Board(id: fid, name: name.isEmpty ? "版块 \(fid)" : name)
        }
    }

    /// Heuristic: a bare map of fid -> name entries (no category name / sub).
    static func isBoardMap(_ node: [String: Any]) -> Bool {
        let keys = node.keys.compactMap { Int($0) }
        guard !keys.isEmpty else { return false }
        return node.values.allSatisfy { $0 is String || $0 is NSNumber || ($0 as? [String: Any])?["name"] != nil }
    }

    static func numeric(_ s: String) -> Int { Int(s) ?? Int.max }
    static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    /// Parse a `forum.php?key=` search response into boards. The response is a JSON object;
    /// boards may appear as a fid->name map or as a list of objects under a container key.
    static func boards(fromResponse body: [String: Any]) -> [Board] {
        if isBoardMap(body) { return boards(in: body) }
        for key in ["__F", "list", "rows", "data", "forum", "boards", "result", "items"] {
            if let list = body[key] as? [Any] {
                let parsed = list.compactMap { ($0 as? [String: Any]).flatMap(board(from:)) }
                if !parsed.isEmpty { return parsed }
            }
            if let map = body[key] as? [String: Any] {
                let parsed = boards(in: map)
                if !parsed.isEmpty { return parsed }
            }
        }
        return []
    }

    /// Parse a single board object candidate (name + fid from a few key spellings).
    static func board(from d: [String: Any]) -> Board? {
        let fid = (d["fid"] as? NSNumber)?.intValue
            ?? Int(d["fid"] as? String ?? "")
            ?? (d["id"] as? NSNumber)?.intValue
        guard let fid, fid != 0 else { return nil }
        let name = readableName(d) ?? "版块 \(fid)"
        return Board(id: fid, name: name.isEmpty ? "版块 \(fid)" : name)
    }

    /// Pretty-print the index JSON so its structure can be inspected (used while calibrating
    /// the parser against NGA's real format).
    public static func pretty(_ text: String) -> String {
        guard let object = parseAny(text),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else {
            return String(text.prefix(2000))
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A compact structural inventory (root keys, category count, non-metadata keys per
    /// category) used to pin down where boards live after fetching the real index.
    public static func summary(_ text: String) -> String {        guard let object = parseAny(text) else { return "parse fail: " + String(text.prefix(400)) }
        var lines: [String] = []
        func keys(_ o: Any) -> [String] { (o as? [String: Any])?.keys.map { $0 } ?? [] }
        lines.append("root keys: " + keys(object).sorted().joined(separator: ", "))
        guard let data = (object as? [String: Any])?["data"] as? [String: Any] else {
            lines.append("no `data` object"); return lines.joined(separator: "\n")
        }
        lines.append("data categories: \(data.count)")
        for (catKey, catVal) in data.sorted(by: { numeric($0.key) < numeric($1.key) }).prefix(8) {
            guard let cat = catVal as? [String: Any] else { continue }
            let nonMeta = cat.keys.filter { !$0.hasPrefix("__") }.sorted()
            lines.append("cat[\(catKey)] nonmeta: \(nonMeta.joined(separator: ", "))")
            for k in ["all", "single", "double", "iconBase"] {
                guard let child = cat[k] as? [String: Any] else { continue }
                let childKeys = child.keys.sorted()
                let sample = childKeys.prefix(5).map { ky -> String in
                    if let vd = child[ky] as? [String: Any] {
                        let fields = vd.keys.filter { !$0.hasPrefix("_") }.prefix(8).joined(separator: ",")
                        return "\(ky){\(fields)}"
                    }
                    return "\(ky)=(\(child[ky] ?? "nil"))"
                }.joined(separator: " | ")
                lines.append("   \(k): \(childKeys.count) keys; e.g. \(sample)")
                // Dive into the first board group's `content` to reveal its shape.
                if k == "all", let firstKey = childKeys.first, let g = child[firstKey] as? [String: Any], let c = g["content"] {
                    if let cd = c as? [String: Any] {
                        let ck = cd.keys.prefix(5)
                        let vSample = ck.compactMap { ky in (cd[ky] as? [String: Any]).map { "\(ky){\($0.keys.prefix(6).joined(separator: ","))}" } }.joined(separator: " | ")
                        lines.append("      all.<g>.content dict: \(cd.count) keys; e.g. \(vSample)")
                    } else if let ca = c as? [Any] {
                        lines.append("      all.<g>.content array: \(ca.count) elems; first keys: \((ca.first as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "?")")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A deeper tree dump of the real index so the nested group/board structure can be read.
    public static func tree(_ text: String) -> String {
        guard let object = parseAny(text) else { return "parse fail" }
        func label(_ d: [String: Any]) -> String { readableName(d) ?? "?" }
        var lines: [String] = []
        func dumpValue(_ v: Any, indent: String, depth: Int) {
            guard depth < 5 else { return }
            if let d = v as? [String: Any] {
                lines.append("\(indent){\(d.count) keys}")
                for (k, val) in d.sorted(by: { numeric($0.key) < numeric($1.key) }).prefix(12) {
                    lines.append("\(indent)  \(k) = \(labelOrType(val))")
                    dumpValue(val, indent: indent + "     ", depth: depth + 1)
                }
            } else if let a = v as? [Any] {
                lines.append("\(indent)[array \(a.count)]")
                if let f = a.first { dumpValue(f, indent: indent + "  ", depth: depth + 1) }
            }
        }
        func labelOrType(_ v: Any) -> String {
            if let d = v as? [String: Any] { return "{name=\(label(d)), keys=\(d.keys.count)}" }
            return "\(v)"
        }
        if let data = (object as? [String: Any])?["data"] as? [String: Any] {
            for (_, cv) in data.sorted(by: { numeric($0.key) < numeric($1.key) }).prefix(1) {
                guard let cat = cv as? [String: Any] else { continue }
                if let all = cat["all"] as? [String: Any] {
                    for (gk, gv) in all.prefix(3) {
                        guard let g = gv as? [String: Any] else { continue }
                        lines.append("GROUP \(gk) name=\(label(g))")
                        dumpValue(g["content"] ?? "?", indent: "  ", depth: 0)
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
