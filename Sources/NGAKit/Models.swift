import Foundation

public enum NGAHost: String, CaseIterable, Sendable, Identifiable {
    case primary = "bbs.nga.cn"
    case community = "ngabbs.com"
    case legacy = "nga.178.com"
    public var id: String { rawValue }
    public var url: URL { URL(string: "https://\(rawValue)")! }
}

public struct Board: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

public struct Topic: Identifiable, Hashable, Sendable {
    public let id: Int
    public let subject: String
    public let author: String
    public let replies: Int
    public let date: Date?
    public let flags: TopicStatus
    public let thumbnails: [URL]
    public let sourceBoardID: Int?
    public let sourceBoardName: String?
    public var thumbnail: URL? { thumbnails.first }
    public init(id: Int, subject: String, author: String, replies: Int, date: Date?, flags: TopicStatus = TopicStatus(), thumbnail: URL? = nil, thumbnails: [URL] = [], sourceBoardID: Int? = nil, sourceBoardName: String? = nil) {
        self.id = id; self.subject = subject; self.author = author; self.replies = replies; self.date = date; self.flags = flags
        self.thumbnails = BBCode.uniqueImageURLs(thumbnails.isEmpty ? thumbnail.map { [$0] } ?? [] : thumbnails, limit: 3)
        self.sourceBoardID = sourceBoardID
        self.sourceBoardName = sourceBoardName
    }
}

/// Bit flags decoded from a thread's `type` integer and `ifmark`, per NGA's status encoding.
/// Only bits this reader understands are surfaced; the raw value is kept for debugging.
public struct TopicStatus: Hashable, Sendable {
    public let raw: Int
    public let ifmark: Int
    public let sticky: Bool
    public init(raw: Int = 0, ifmark: Int = 0, sticky: Bool = false) {
        self.raw = raw; self.ifmark = ifmark; self.sticky = sticky
    }

    /// 精华/被标记. Bit 5 of `type` is the "被标记" flag; `ifmark == 1` is the digest marker.
    public var isDigest: Bool { ifmark == 1 || (raw & (1 << 5)) != 0 }
    /// Sticky is supplied by NGA's dedicated list. `type` bits describe post
    /// state and attachments, so they must not be guessed as sticky markers.
    public var isSticky: Bool { sticky }
}

/// A named group of boards, used by the board catalogue.
public struct BoardSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let boards: [Board]
    public init(id: String, title: String, boards: [Board]) { self.id = id; self.title = title; self.boards = boards }
}

public struct Post: Identifiable, Sendable {
    public let id: String
    public let pid: Int
    public let floor: Int
    public let author: String
    public let content: String
    public let date: Date?
    public let avatar: URL?
    public let imageURLs: [URL]
    public let user: NGAUser?
    /// NGA's current recommendation score for this floor.
    public let score: Int
    /// The signed-in account's vote state returned by NGA for this floor.
    public let vote: PostVote?
    public init(id: String, pid: Int, floor: Int, author: String, content: String, date: Date?, avatar: URL? = nil, imageURLs: [URL] = [], user: NGAUser? = nil, score: Int = 0, vote: PostVote? = nil) {
        self.id = id; self.pid = pid; self.floor = floor; self.author = author; self.content = content; self.date = date; self.avatar = avatar
        self.imageURLs = imageURLs
        self.user = user
        self.score = score
        self.vote = vote
    }
}

public enum PostVote: Int, Sendable {
    case agree = 1
    case disagree = -1
}

public struct PostVoteResult: Sendable {
    public let delta: Int
    public let selection: PostVote?
    public init(delta: Int, selection: PostVote?) {
        self.delta = delta
        self.selection = selection
    }
}

/// Identity fields supplied by NGA alongside a post. Optional profile fields
/// stay optional: the UI must not manufacture values that were absent from the
/// server response.
public struct NGAUser: Identifiable, Hashable, Sendable {
    public let uid: String
    public let name: String
    public let avatar: URL?
    public let groupTitle: String?
    public let memberTitle: String?
    public let signature: String?
    public var id: String { uid.isEmpty ? name : uid }

    public init(uid: String, name: String, avatar: URL? = nil, groupTitle: String? = nil,
                memberTitle: String? = nil, signature: String? = nil) {
        self.uid = uid
        self.name = name
        self.avatar = avatar
        self.groupTitle = groupTitle
        self.memberTitle = memberTitle
        self.signature = signature
    }

    public var isAnonymous: Bool { uid.hasPrefix("-") || name == "匿名用户" }
}

/// A private message or notification in the message centre.
public enum MessageKind: String, Hashable, Sendable {
    case interaction
    case direct
    case system
}

public struct Message: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sender: String
    public let body: String?
    public let date: Date?
    public let kind: MessageKind
    public let topicID: Int?
    public let postID: Int?
    public let page: Int?
    /// NGA uid of the message author when the response provides it.
    public let authorUID: String?
    public init(id: String, title: String, sender: String, body: String?, date: Date?,
                kind: MessageKind = .system, topicID: Int? = nil, postID: Int? = nil, page: Int? = nil,
                authorUID: String? = nil) {
        self.id = id; self.title = title; self.sender = sender; self.body = body; self.date = date
        self.kind = kind; self.topicID = topicID; self.postID = postID; self.page = page
        self.authorUID = authorUID
    }
}

public struct TopicPage: Sendable {
    public let topics: [Topic]
    public let page: Int
    public let hasMore: Bool
    public let subForums: [Board]
    public let boardDescription: String?
    public let headerTopicID: Int?
    public init(topics: [Topic], page: Int, hasMore: Bool, subForums: [Board] = [], boardDescription: String? = nil, headerTopicID: Int? = nil) {
        self.topics = topics; self.page = page; self.hasMore = hasMore; self.subForums = subForums; self.boardDescription = boardDescription; self.headerTopicID = headerTopicID
    }
}

public struct FavoriteFolder: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let count: Int?
    public let isDefault: Bool
    public init(id: Int, name: String, count: Int? = nil, isDefault: Bool = false) {
        self.id = id; self.name = name; self.count = count; self.isDefault = isDefault
    }
}

public struct PostPage: Sendable {
    public let title: String
    public let posts: [Post]
    public let page: Int
    public let hasMore: Bool
    public let totalPages: Int?

    public init(title: String, posts: [Post], page: Int, hasMore: Bool, totalPages: Int? = nil) {
        self.title = title
        self.posts = posts
        self.page = page
        self.hasMore = hasMore
        self.totalPages = totalPages
    }
}

/// One short-message conversation: ordered posts plus the group roster.
public struct PrivateMessageThread: Sendable {
    public let posts: [Message]
    /// uid → display name for everyone NGA returned in this conversation.
    public let participants: [String: String]

    public init(posts: [Message], participants: [String: String] = [:]) {
        self.posts = posts
        self.participants = participants
    }
}

public enum NGAError: Error, LocalizedError, Sendable, Equatable {
    case verificationRequired
    case http(Int)
    case server(String)
    case invalidResponse(String)
    case untrustedRedirect
    public var errorDescription: String? {
        switch self {
        case .verificationRequired: "需要先在 NGA 网页完成访问验证或登录，再返回重试。"
        case .http(let code): "NGA 返回 HTTP \(code)，请稍后重试。"
        case .server(let text): text
        case .invalidResponse(let reason): "暂时无法读取 NGA 数据：\(reason)"
        case .untrustedRedirect: "请求跳转到了其他站点，请在网页中继续。"
        }
    }
}
