import Foundation
import CoreFoundation
import Testing
@testable import NGAKit

@Test func topicDictionaryIsNumericallyOrderedAndDeduplicated() throws {
    let data = Data(#"{"data":{"__T":{"10":{"tid":"11","subject":"A &amp; B","author":"甲","replies":"9"},"2":{"tid":3,"subject":"先显示","author":"乙"},"11":{"tid":11,"subject":"重复"}},"__ROWS":80,"__T__ROWS_PAGE":35}}"#.utf8)
    let result = try ResponseDecoder.topics(from: data, page: 1)
    #expect(result.topics.map(\.id) == [3, 11])
    #expect(result.topics.last?.subject == "A & B")
    #expect(result.topics.last?.replies == 9)
    #expect(result.hasMore)
}

@Test func rawTabsAndBareKeysPreserveText() throws {
    let data = Data("{data:{\"text\":\"at 10:00,1:keep\tend\",0:{\"value\":2}}}".utf8)
    let body = try ResponseDecoder.decode(data)
    #expect(body["text"] as? String == "at 10:00,1:keep\tend")
    #expect((body["0"] as? [String: Any])?["value"] as? Int == 2)
}

@Test func wrappedResponseAllowsWhitespaceAroundAssignment() throws {
    let data = Data("<script>ignored()</script> window.script_muti_get_var_store = {data:{value:1, note:\"} stays in text\"}};</script>".utf8)
    let body = try ResponseDecoder.decode(data)
    #expect(body["value"] as? Int == 1)
    #expect(body["note"] as? String == "} stays in text")
}

@Test func javascriptIsNeverExecutedOrAccepted() {
    #expect(throws: NGAError.invalidResponse("NGA 返回的数据格式暂不受支持")) {
        try ResponseDecoder.decode(Data("{data: alert('unsafe')}".utf8))
    }
}

@Test func malformedVisitorErrorIsActionable() {
    #expect(throws: NGAError.verificationRequired) {
        try ResponseDecoder.decode(Data(#"{"error":["15:访客不能直接访问"],"data":{"#.utf8), status: 403)
    }
}

@Test func htmlDoesNotBecomeAnEmptyList() {
    #expect(throws: NGAError.verificationRequired) {
        try ResponseDecoder.topics(from: Data("<!DOCTYPE html><html>Login</html>".utf8), page: 1)
    }
    #expect(throws: NGAError.invalidResponse("缺少主题列表 __T")) {
        try ResponseDecoder.topics(from: Data("{}".utf8), page: 1)
    }
}

@Test func gb18030ResponseIsDecoded() throws {
    let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    let source = #"{"data":{"__T":[{"tid":1,"subject":"中文繁體測試","author":"测试"}],"__ROWS":1}}"#
    let data = try #require(source.data(using: encoding))
    let result = try ResponseDecoder.topics(from: data, charset: "GBK", page: 1)
    #expect(result.topics.first?.subject == "中文繁體測試")
    #expect(!result.hasMore)
}

@Test func postArrayAndAnonymousUserAreSupported() throws {
    let data = Data(##"{"data":{"__T":{"subject":"主题"},"__R":[{"pid":0,"lou":0,"authorid":-1,"content":"正文","postdate":1700000000,"score":7}],"__U":{"-1":{"username":"#anony_private"}},"__ROWS":1}}"##.utf8)
    let result = try ResponseDecoder.posts(from: data, tid: 10, page: 1)
    #expect(result.posts.first?.author == "匿名用户")
    #expect(result.posts.first?.floor == 0)
    #expect(result.posts.first?.date == Date(timeIntervalSince1970: 1700000000))
    #expect(result.posts.first?.score == 7)
    #expect(!result.hasMore)
}

@Test func postUsersResolveFromSequenceKeyedDirectoryAndRowFallback() throws {
    let data = Data(##"{"data":{"__T":{"subject":"主题"},"__R":[{"pid":1,"authorid":6829394,"content":"一"},{"pid":2,"authorid":66910986,"author":"紫菜蛋花汤0","content":"二"}],"__U":{"0":{"uid":6829394,"username":"mwd244","avatar":"https://img.nga.cn/avatars/42.png"}},"__ROWS":2}}"##.utf8)
    let result = try ResponseDecoder.posts(from: data, tid: 10, page: 1)
    #expect(result.posts.map(\.author) == ["mwd244", "紫菜蛋花汤0"])
    #expect(result.posts.first?.avatar?.absoluteString == "https://img.nga.cn/avatars/42.png")
}

@Test func postUsersResolveFromArrayDirectory() throws {
    let data = Data(##"{"data":{"__T":{"subject":"主题"},"__R":[{"pid":1,"authorid":40645280,"content":"正文"}],"__U":[{"uid":40645280,"username":"monsternic07"}],"__ROWS":1}}"##.utf8)
    let result = try ResponseDecoder.posts(from: data, tid: 10, page: 1)
    #expect(result.posts.first?.author == "monsternic07")
}

@Test func postVoteStateAndTimestampComeFromOfficialFields() throws {
    let data = Data(#"{"data":{"__T":{"subject":"主题"},"__R":[{"pid":1,"authorid":42,"content":"正文","postdatetimestamp":1700000000,"score":"0,3,1"}],"__U":{"42":{"uid":42,"username":"甲"}},"__ROWS":1}}"#.utf8)
    let post = try #require(ResponseDecoder.posts(from: data, tid: 10, page: 1).posts.first)
    #expect(post.date == Date(timeIntervalSince1970: 1700000000))
    #expect(post.score == 3)
    #expect(post.vote == .agree)
}

@Test func voteResultAcceptsNestedAndNumberedDeltaShapes() throws {
    let nested = try ResponseDecoder.voteResult(
        from: Data(#"{"data":{"result":{"data":[-2]}}}"#.utf8), direction: .disagree)
    #expect(nested.delta == -2)
    #expect(nested.selection == .disagree)

    let numbered = try ResponseDecoder.voteResult(
        from: Data(#"{"data":{"1":1}}"#.utf8), direction: .agree)
    #expect(numbered.delta == 1)
    #expect(numbered.selection == .agree)

    let successChannel = try ResponseDecoder.voteResult(
        from: Data(#"{"error":["操作完毕"],"data":[-1]}"#.utf8), direction: .disagree)
    #expect(successChannel.delta == -1)
    #expect(successChannel.selection == .disagree)
}

@Test func postUsersResolveFromNestedOfficialDirectoryAndExposeProfile() throws {
    let data = Data(##"{"data":{"__T":{"subject":"主题"},"__R":[{"pid":1,"authorid":42,"content":"正文"}],"__U":{"users":{"0":{"uid":42,"username":"测试用户","groupname":"用户组","signature":"签名"}}},"__ROWS":1}}"##.utf8)
    let result = try ResponseDecoder.posts(from: data, tid: 10, page: 1)
    #expect(result.posts.first?.author == "测试用户")
    #expect(result.posts.first?.user?.uid == "42")
    #expect(result.posts.first?.user?.groupTitle == "用户组")
    #expect(result.posts.first?.user?.signature == "签名")
}

@Test func privateMessageListUsesOfficialZeroContainer() throws {
    let body = try ResponseDecoder.decode(Data(#"{"data":{"0":{"12":{"mid":"12","subject":"测试私信","from":"42","from_username":"发送者","time":"1700000000","last_modify":"1700000300","posts":"2"}},"nextPage":""}}"#.utf8))
    let messages = ResponseDecoder.privateMessages(from: body)
    #expect(messages.count == 1)
    #expect(messages.first?.id == "12")
    #expect(messages.first?.sender == "发送者")
    #expect(messages.first?.kind == .direct)
}

@Test func privateMessageDetailsResolveAuthorsAndBodies() throws {
    let body = try ResponseDecoder.decode(Data(#"{"data":{"0":{"userInfo":{"42":{"uid":"42","username":"发送者"}},"allmsgs":{"1":{"id":"1","from":"42","subject":"标题","content":"正文","time":"1700000000"}}}}}"#.utf8))
    let posts = ResponseDecoder.privateMessagePosts(from: body)
    #expect(posts.first?.sender == "发送者")
    #expect(posts.first?.body == "正文")
}

@Test func notificationsAreSeparatedByOfficialType() throws {
    let body = try ResponseDecoder.decode(Data(#"{"data":{"0":{"0":[{"0":"2","2":"回复者","5":"帖子标题","6":"100","7":"200","9":"1700000000","10":"2"}],"1":[{"0":"99","5":"系统维护","6":"0","9":"1700000100"}]}}}"#.utf8))
    let messages = ResponseDecoder.notifications(from: body)
    #expect(messages.count == 2)
    #expect(messages.first?.kind == .system)
    #expect(messages.last?.kind == .interaction)
    #expect(messages.last?.topicID == 100)
}

@Test func nestedQuotesAndEscapedLiteralTags() {
    #expect(BBCode.parse("[quote]甲[quote]乙[/quote]丙[/quote]") == [.quote([.text("甲"), .quote([.text("乙")]), .text("丙")])])
    #expect(BBCode.parse("&#91;b&#93;原样&#91;/b&#93;") == [.text("[b]原样[/b]")])
    #expect(BBCode.parse("[unknown]保留[/unknown]") == [.text("[unknown]保留[/unknown]")])
    #expect(BBCode.parse("[quote]未闭合") == [.text("[quote]"), .text("未闭合")])
}

@Test func crossedQuoteAndListKeepsListStructure() {
    let nodes = BBCode.parse("[quote][list][*]甲[*]乙[/quote][/list]")
    #expect(nodes == [.quote([.list([.bullet([.text("甲")]), .bullet([.text("乙")])])])])
}

@Test func imageAndLinkURLsAreRestricted() {
    #expect(BBCode.imageURL("./mon_202609/07/test.png")?.absoluteString == "https://img.nga.cn/attachments/mon_202609/07/test.png")
    #expect(BBCode.imageURL("http://img.nga.178.com/attachments/test.jpg")?.host == "img.nga.cn")
    #expect(BBCode.webURL("javascript:alert(1)") == nil)
    #expect(BBCode.webURL("file:///etc/passwd") == nil)
    #expect(BBCode.webURL("https://user:password@example.com") == nil)
    #expect(BBCode.avatarURL("./mon_202609/07/avatar.jpg|.aother.jpg")?.absoluteString == "https://img.nga.cn/attachments/mon_202609/07/avatar.jpg")
    #expect(BBCode.avatarURL("default.png|.aother.png")?.absoluteString == "https://img4.nga.cn/ngabbs/face/default.png")
    #expect(BBCode.avatarURL("avatars/2002/03a/000/000/58_0.jpg")?.absoluteString == "https://img.nga.cn/avatars/2002/03a/000/000/58_0.jpg")
    #expect(BBCode.avatarURL("%2Favatars%2F2002%2Favatar.jpg")?.absoluteString == "https://bbs.nga.cn/avatars/2002/avatar.jpg")
}

@Test func nonImageAttachmentsAreNotTopicThumbnails() {
    // .rar / .zip / .pdf are real [attach] use cases for file releases; if
    // they leaked into a topic's thumbnail list the list row would render
    // a stale placeholder that never decodes.
    let body = """
    UnderlightAnglerAuto 原版下载地址
    2026年9月8日修改版: [attach],/mon_20260908/7Q47-jrcvK2.rar[/attach]
    同时提供 [attach]https://cdn.example.com/补丁.zip[/attach]
    文档见 [attach]https://docs.example.com/readme.pdf[/attach]
    """
    #expect(BBCode.imageURLs(in: body).isEmpty)
}

@Test func inlineImgKeepsImageExtensionOnly() {
    let body = """
    看图 [img]https://cdn.example.com/screenshot.png[/img]
    这个是视频链接不是图 [img]https://cdn.example.com/trailer.mp4[/img]
    """
    let urls = BBCode.imageURLs(in: body)
    #expect(urls.count == 1)
    #expect(urls.first?.absoluteString == "https://cdn.example.com/screenshot.png")
}

@Test func imageURLsSkipQuotedAndCollapsedRegions() {
    // OP quoted another post that contains an image; that image must not
    // become the OP's preview.
    let body = """
    引用内容里有一张图：
    [quote]楼主说：[img]https://cdn.example.com/quoted.png[/img][/quote]
    我自己的正文里也有一张图：
    [img]https://cdn.example.com/own.jpg[/img]
    折叠块里再放一张：
    [collapse=附件][img]https://cdn.example.com/hidden.gif[/img][/collapse]
    """
    let urls = BBCode.imageURLs(in: body, skipInsideQuotes: true)
    #expect(urls.map(\.absoluteString) == ["https://cdn.example.com/own.jpg"])
    // The default scan still picks up the quoted image — the filter is opt-in
    // so other call sites that want the historical behavior are unaffected.
    let legacy = BBCode.imageURLs(in: body)
    #expect(legacy.count == 3)
}

@Test func topicListKeepsAttachmentEvenWhenSnippetHasNonImageAttach() throws {
    // Topic list row: OP uploaded a real image, but the snippet also quotes a
    // .rar release. The release must not displace the real preview.
    let data = Data(#"""
    {"data":{"__T":[{"tid":42,"subject":"图文混排","author":"甲","attachs":[{"attachurl":"mon_202609/08/topic.png"}],"content":"UnderlightAnglerAuto原版下载地址 [attach],/mon_20260908/7Q47-jrcvK2.rar[/attach]"}],"__ROWS":1}}
    """#.utf8)
    let result = try ResponseDecoder.topics(from: data, page: 1)
    let thumbnails = result.topics.first?.thumbnails ?? []
    #expect(thumbnails.count == 1)
    #expect(thumbnails.first?.absoluteString == "https://img.nga.cn/attachments/mon_202609/08/topic.png")
}

@Test func topicListFallsBackToSnippetImageWhenNoAttachment() throws {
    // No attachs: the snippet's own [img] (not quoted) becomes the preview.
    let data = Data(#"""
    {"data":{"__T":[{"tid":43,"subject":"贴图分享","author":"乙","content":"看图 [img]https://cdn.example.com/screenshot.png[/img]"}],"__ROWS":1}}
    """#.utf8)
    let result = try ResponseDecoder.topics(from: data, page: 1)
    #expect(result.topics.first?.thumbnails.first?.absoluteString == "https://cdn.example.com/screenshot.png")
}

@Test func htmlEntitiesDecodeOnce() {
    #expect(HTMLText.decode("&amp;lt; &#x1F600; &#65;") == "&lt; 😀 A")
    #expect(HTMLText.decode("欢迎体验&amp;#128516;") == "欢迎体验😄")
}

@Test func ngaEmotesAndQuoteMetadataBecomeNativeNodes() {
    #expect(BBCode.parse("[:哭笑]") == [.emote("ac", "哭笑")])
    #expect(BBCode.emoteURL(group: "ac", name: "不明觉厉")?.absoluteString == "https://img4.nga.cn/ngabbs/post/smile/a2_36.png")
    #expect(BBCode.parse("[s:a2:doge]") == [.emote("a2", "doge")])
    #expect(BBCode.emoteURL(group: "ac", name: "哭笑")?.absoluteString == "https://img4.nga.cn/ngabbs/post/smile/ac15.png")

    let nodes = BBCode.parse("[quote][pid=880514032,47490984,1]Reply[/pid] Post by [uid=21830063]mini190[/uid] (2026-09-03 12:10):\n欢迎体验[/quote]")
    let debug = String(describing: nodes)
    #expect(!debug.contains("pid="))
    #expect(!debug.contains("uid="))
    #expect(debug.contains("mini190"))
    #expect(debug.contains("欢迎体验"))

    let unwrapped = BBCode.parse("Reply to [pid=1,2,3]Reply[/pid] Post by [uid=21830063]mini190[/uid] (2026-09-03 12:10):\n欢迎体验")
    let unwrappedDebug = String(describing: unwrapped)
    #expect(!unwrappedDebug.contains("Reply to"))
    #expect(!unwrappedDebug.contains("pid="))
    #expect(!unwrappedDebug.contains("uid="))
    #expect(unwrappedDebug.contains("引用 mini190"))
}

@Test func layoutGuideBBCodesHaveMobileNativeNodes() {
    let nodes = BBCode.parse("[h][/h][table][tr][td][b]标题[/b][/td][td]内容[/td][/tr][/table][dice]d100[/dice]")
    #expect(nodes == [
        .divider,
        .table([[[.bold([.text("标题")])], [.text("内容")]]]),
        .dice([.text("d100")])
    ])
    #expect(BBCode.parse("[r]右侧[/r]") == [.align("right", [.text("右侧")])])
    #expect(BBCode.imageURL("pic3.178.com/a.png")?.absoluteString == "https://pic3.178.com/a.png")
    #expect(BBCode.parse("[tid=9268613]排版指南[/tid]") == [.link("排版指南", URL(string: "https://ngabbs.com/read.php?tid=9268613")!)])
    #expect(BBCode.parse("[url]/read.php?tid=1[/url]") == [.link("/read.php?tid=1", URL(string: "https://ngabbs.com/read.php?tid=1")!)])
    #expect(BBCode.parse("[url=https://ngabbs.com/read.php?tid=1][b][color=red]活动报名帖[/color][/b][/url]") == [.link("活动报名帖", URL(string: "https://ngabbs.com/read.php?tid=1")!)])

    let nested = String(describing: BBCode.parse("[b][size=120%][color=red][size=130%]>>>活动报名帖<<<[/size][/color][/size][/b]"))
    #expect(!nested.contains("[size="))
    #expect(nested.contains("活动报名帖"))
}

@Test func topicMetadataIncludesDescriptionAndThumbnail() throws {
    let data = Data(#"{"data":{"__F":{"info":"新版与高阶讨论"},"__T":[{"tid":9,"subject":"图文帖","author":"甲","tpcurl":"./mon_202609/07/topic.jpg"}],"__ROWS":1}}"#.utf8)
    let result = try ResponseDecoder.topics(from: data, page: 1)
    #expect(result.boardDescription == "新版与高阶讨论")
    #expect(result.topics.first?.thumbnail?.absoluteString == "https://img.nga.cn/attachments/mon_202609/07/topic.jpg")
}

@Test func topicMetadataReadsNestedSubForumsAndBoardHeader() throws {
    let data = Data(#"{"data":{"__F":{"topped_topic":"13888322","sub_forums":{"369":["问答区"],"t27822292":["低保合集"]}},"__T":[],"__ROWS":0}}"#.utf8)
    let result = try ResponseDecoder.topics(from: data, page: 1)
    #expect(result.headerTopicID == 13_888_322)
    #expect(Set(result.subForums.map(\.name)) == Set(["问答区", "低保合集"]))
}

@Test func officialTopicListUsesServerPaginationAndMetadata() throws {
    let data = Data(#"{"code":0,"result":{"data":[{"tid":9,"fid":369,"forumname":"问答区","subject":"指南","author":"甲","replies":3,"attachs":[{"attachurl":"mon_202609/08/a.jpg"}]}],"subForum":[{"id":369,"name":"问答区"}],"header":{"opendata":"13888322"}},"currentPage":1,"totalPage":1,"total":1,"perPage":35}"#.utf8)
    let result = try ResponseDecoder.appTopics(from: data, page: 1, digest: true)
    #expect(result.topics.first?.flags.isDigest == true)
    #expect(result.topics.first?.thumbnail != nil)
    #expect(result.subForums.first == Board(id: 369, name: "问答区"))
    #expect(result.headerTopicID == 13_888_322)
    #expect(result.topics.first?.sourceBoardID == 369)
    #expect(result.topics.first?.sourceBoardName == "问答区")
    #expect(!result.hasMore)
}

@Test func officialTopicListDeduplicatesTopicIdentity() throws {
    let data = Data(#"{"code":0,"result":{"data":[{"tid":91,"subject":"原始主题"},{"tid":91,"subject":"重复身份"},{"tid":92,"subject":"下一主题"}]},"currentPage":1,"totalPage":1}"#.utf8)
    let result = try ResponseDecoder.appTopics(from: data, page: 1)
    #expect(result.topics.map(\.id) == [91, 92])
    #expect(result.topics.map(\.subject) == ["原始主题", "下一主题"])
}

@Test func stickyTopicUsesExplicitServerMetadata() throws {
    let data = Data(#"{"code":0,"result":{"data":[{"tid":1,"subject":"导航置顶","topic_misc_var_bit1":1},{"tid":2,"subject":"普通主题","type":512}]},"currentPage":1,"totalPage":1}"#.utf8)
    let result = try ResponseDecoder.appTopics(from: data, page: 1)
    #expect(result.topics[0].flags.isSticky)
    #expect(!result.topics[1].flags.isSticky)
}

@Test func topicReadURLIsNotMistakenForThumbnail() throws {
    let data = Data(#"{"data":{"__T":[{"tid":9,"subject":"图文帖","author":"甲","tpcurl":"/read.php?tid=9"}],"__ROWS":1}}"#.utf8)
    let result = try ResponseDecoder.topics(from: data, page: 1)
    #expect(result.topics.first?.thumbnail == nil)
}

@Test func topicListAttachmentBecomesThumbnail() throws {
    let data = Data(#"{"data":{"__T":[{"tid":9,"subject":"图文帖","author":"甲","tpcurl":"/read.php?tid=9","attachs":[{"attachurl":"mon_202609/08/topic.jpeg"}]}],"__ROWS":1}}"#.utf8)
    let result = try ResponseDecoder.topics(from: data, page: 1)
    #expect(result.topics.first?.thumbnail?.absoluteString == "https://img.nga.cn/attachments/mon_202609/08/topic.jpeg")
}

@Test func duplicateAttachmentAliasesUseOnePreviewSlot() {
    let urls = [
        URL(string: "https://img.nga.cn/attachments/mon_202609/08/topic.jpg?download=1")!,
        URL(string: "https://img4.nga.cn/attachments/mon_202609/08/topic.jpg")!,
        URL(string: "https://img.nga.cn/attachments/mon_202609/08/topic.thumb.jpg")!
    ]
    #expect(BBCode.uniqueImageURLs(urls, limit: 3).count == 1)
}

@Test func largeForumKeepsNestedBoardGroups() {
    let source = #"window.x={"data":{"0":{"all":{"new":{"id":"new","name":"最近新增","content":{"0":{"content":{"0":{"fid":7,"name":"错误的跨分类引用"},"1":{"fid":335,"name":"网事杂谈"}}}}},"wow":{"id":"wow","name":"魔兽世界","content":{"0":{"content":{"0":{"fid":7,"name":"艾泽拉斯议事厅","info":"魔兽主讨论区"},"1":{"fid":310,"name":"前瞻资讯"}}},"1":{"name":"职业讨论区","content":{"0":{"fid":181,"name":"铁血沙场"},"1":{"fid":182,"name":"魔法圣堂"}}},"2":{"name":"冒险心得","content":{"0":{"fid":218,"name":"副本专区"}}}}}}}}};"#
    let sections = ForumIndex.childSections(source, parentFID: -7)
    #expect(sections.map(\.title) == ["魔兽世界", "职业讨论区", "冒险心得"])
    #expect(sections[0].boards.map(\.id) == [7, 310])
    #expect(sections[1].boards.map(\.name) == ["铁血沙场", "魔法圣堂"])
    #expect(ForumIndex.hubSections(source, hubID: "wow") == sections)
    #expect(!sections.flatMap(\.boards).contains { $0.name == "网事杂谈" })
    #expect(ForumIndex.boardDescription(source, fid: -7) == "魔兽主讨论区")
}

@Test func htmlFallbackRetainsUserNameAndAvatar() throws {
    let html = #"<script>commonui.userInfo.setAll({"42":{"username":"测试用户","avatar":"https://img.nga.cn/avatars/42.png|.a/42_1.png"}})</script><h3 id='postsubject0'>主题</h3><p id='postcontent0'>正文</p><span id='postdate0'>2026-09-07 12:00</span><script>commonui.postArg.proc(0,null,null,null,null,null,null,null,null,9,1,null,'42',1)</script>"#
    let page = try HTMLPostDecoder.posts(from: Data(html.utf8), tid: 1, page: 1)
    #expect(page.posts.first?.author == "测试用户")
    #expect(page.posts.first?.avatar?.absoluteString == "https://img.nga.cn/avatars/42.png")
}

// MARK: - 引用解析（回归：引用正文不得丢失）

@Test func quoteVariantsAlwaysKeepQuotedContent() {
    let sources = [
        // 元数据裸写，正文跟在头部之后
        "[quote][b]Post by [uid=579]安娜[/uid] (2026-09-07 14:04):[/b]\n被引用的内容[/quote]",
        // pid 只包住头部，正文在 pid 之外
        "[quote][pid=283165406,242975,1]Reply to [tid=39977465]某主题[/tid] Post by [uid=579]安娜[/uid] (2026-09-07 14:04):[/pid]\n被引用的内容[/quote]",
        // pid 把头部和正文一起包住
        "[quote][pid=283165406,242975,1][b]Post by [uid=579]安娜[/uid] (2026-09-07 14:04):[/b]\n被引用的内容[/pid][/quote]",
        // 老格式：Reply to 前缀 + pid 全包
        "[quote]Reply to [pid=283165406,242975,1][b]Post by [uid=579]安娜[/uid] (2026-09-07 14:04):[/b]\n被引用的内容[/pid][/quote]",
    ]
    for (index, source) in sources.enumerated() {
        guard case .quote(let children)? = BBCode.parse(source).first else {
            Issue.record("case \(index): 未解析出引用块")
            continue
        }
        let text = flattenedContent(children)
        #expect(text.contains("被引用的内容"), "case \(index): 引用正文丢失，只剩引用头")
        #expect(text.contains("引用 安娜"), "case \(index): 引用署名丢失")
        #expect(!text.contains("Reply to"), "case \(index): Reply to 残留")
        for node in children {
            if case .link(let label, _) = node {
                #expect(!label.contains("\n"), "case \(index): 引用正文被并进单个链接节点")
            }
        }
    }
}

@Test func compactReplyReferenceRestoresTheTargetPost() {
    let compact = "Reply to [pid=283165406,242975,1]Reply[/pid] Post by [uid=579]安娜[/uid] (2026-09-07 14:04):\n这是回复者自己的内容"
    #expect(BBCode.looseReplyTargetPID(in: compact) == 283165406)
    let restored = BBCode.restoringLooseReply(compact, referencedContent: "这是被引用楼层的原文")
    let nodes = BBCode.parse(restored)
    guard case .quote(let quote)? = nodes.first else {
        Issue.record("紧凑回复没有恢复为引用块")
        return
    }
    #expect(flattenedContent(quote).contains("这是被引用楼层的原文"))
    #expect(flattenedContent(nodes).contains("这是回复者自己的内容"))
}

@Test func compactReplyAcceptsBoldPrefixAndCarriesTargetPage() {
    let compact = "[b]Reply to [pid=283165406,39977465,2]Reply[/pid] Post by [uid=579]安娜[/uid] (2026-09-07 14:04):[/b]\n自己的内容"
    #expect(BBCode.looseReplyTargetPID(in: compact) == 283165406)
    #expect(BBCode.looseReplyTargetPage(in: compact) == 2)
    #expect(flattenedContent(BBCode.parse(BBCode.restoringLooseReply(compact, referencedContent: "被引用正文"))).contains("被引用正文"))
}

@Test func restoredReplyQuotesOnlyTheTargetFloorsOwnBody() {
    let targetWithQuote = "[quote][b]Post by [uid=1]上一层[/uid] (2026-09-06 21:53):[/b]\n旧内容[/quote]\n目标楼自己的内容"
    #expect(BBCode.ownPostBody(targetWithQuote) == "目标楼自己的内容")

    let targetWithCompactReply = "Reply to [pid=1,2,1]Reply[/pid] Post by [uid=1]上一层[/uid] (2026-09-06 21:53):\n目标楼自己的内容"
    #expect(BBCode.ownPostBody(targetWithCompactReply) == "目标楼自己的内容")

    let reply = "Reply to [pid=3,2,1]Reply[/pid] Post by [uid=2]目标楼[/uid] (2026-09-06 22:25):\n本楼回复"
    let restored = BBCode.restoringLooseReply(reply, referencedContent: targetWithQuote)
    let text = flattenedContent(BBCode.parse(restored))
    #expect(text.contains("目标楼自己的内容"))
    #expect(text.contains("本楼回复"))
    #expect(!text.contains("旧内容"))
}

@Test func quoteTopicNavigationMarkerIsRemoved() {
    let source = "[quote][pid=1,2,1]Reply[/pid] [tid=2]Topic[/tid] Post by [uid=3]甲[/uid] (2026-09-06 19:32):\n正文[/quote]"
    let nodes = BBCode.parse(source)
    let text = flattenedContent(nodes)
    #expect(!text.contains("Topic"))
    #expect(text.contains("正文"))
    #expect(!nodes.contains { if case .link = $0 { return true }; return false })
}

@Test func nestedQuoteKeepsInnerContent() {
    let source = "[quote][b]Post by [uid=1]B[/uid] (2026-01-01 08:00):[/b]\n[quote][b]Post by [uid=2]C[/uid] (2026-01-01 07:00):[/b]\nC 的话[/quote]\nB 的话[/quote]"
    guard case .quote(let children)? = BBCode.parse(source).first else {
        Issue.record("未解析出引用块")
        return
    }
    let text = flattenedContent(children)
    #expect(text.contains("C 的话"))
    #expect(text.contains("B 的话"))
}

@Test func plainInternalLinksStayTappable() {
    let nodes = BBCode.parse("看这个 [tid=39977465]某主题[/tid] 不错")
    #expect(nodes.contains { node in
        if case .link(let label, _) = node { return label == "某主题" }
        return false
    })
}

@Test func quoteWhoseOnlyChildIsALinkDissolvesToText() {
    // 引用正文被包装成唯一一个链接节点时，必须还原为正文文本，
    // 而不是渲染成一个可点链接（视觉上会像「只有引用头、没有正文」）。
    let source = "[quote][b]引用 安娜[/b] · 2026-09-07 14:04\n[tid=39977465]这句话被包成了链接[/tid][/quote]"
    guard case .quote(let children)? = BBCode.parse(source).first else {
        Issue.record("未解析出引用块")
        return
    }
    let text = flattenedContent(children)
    #expect(text.contains("这句话被包成了链接"))
}

@Test func quoteBodySwallowedAsSoleLinkIsRescued() {
    // 整段被引用正文（含嵌套头部）落到一个非富包装 pid/tid 里、
    // 成为引用块的唯一子节点时，cleanupQuotes 必须把它溶解回正文文本。
    let source = "[quote][tid=39977465]这句话是唯一内容[/tid][/quote]"
    guard case .quote(let children)? = BBCode.parse(source).first else {
        Issue.record("未解析出引用块")
        return
    }
    let text = flattenedContent(children)
    #expect(text.contains("这句话是唯一内容"))
    // 溶解后：引用块应只剩一个文本节点，不再有裸链接
    #expect(children.count == 1)
    if case .text(let value) = children[0] {
        #expect(value.contains("这句话是唯一内容"))
    } else {
        Issue.record("溶解失败：引用块唯一子节点不是文本")
    }
}

private func flattenedContent(_ nodes: [ContentNode]) -> String {
    var result = ""
    func walk(_ values: [ContentNode]) {
        for node in values {
            switch node {
            case .text(let value): result += value
            case .link(let label, _): result += label
            case .code(let value): result += value
            case .quote(let inner), .collapse(_, let inner), .bold(let inner), .italic(let inner),
                 .underline(let inner), .strike(let inner), .align(_, let inner), .size(_, let inner),
                 .color(_, let inner), .list(let inner), .bullet(let inner), .dice(let inner):
                walk(inner)
            case .table(let rows):
                for row in rows { for cell in row { walk(cell) } }
            default: break
            }
        }
    }
    walk(nodes)
    return result
}
