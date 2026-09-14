import Foundation
import NGAKit

@main struct Probe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2, ["board", "topic", "thumbnail"].contains(args[0]), let id = Int(args[1]) else {
            print("Usage: swift run nga-probe board <fid> | topic <tid> | thumbnail <tid> [bbs.nga.cn|ngabbs.com|nga.178.com]")
            return
        }
        let host = args.count > 2 ? NGAHost(rawValue: args[2]) : .primary
        guard let host else { print("Unsupported host"); exit(2) }
        let client = NGAClient(host: host)
        // Optional session is read from the environment, never printed or committed.
        let cookie = ProcessInfo.processInfo.environment["NGA_COOKIE"]
        do {
            if args[0] == "board" {
                let result = try await client.topics(fid: id, cookie: cookie)
                print("OK host=\(host.rawValue) topics=\(result.topics.count) hasMore=\(result.hasMore)")
            } else if args[0] == "topic" {
                let result = try await client.posts(tid: id, cookie: cookie)
                print("OK host=\(host.rawValue) posts=\(result.posts.count) hasMore=\(result.hasMore)")
            } else {
                let image = await client.topicThumbnail(tid: id, cookie: cookie)
                print(image.map { "OK host=\(host.rawValue) thumbnail=\($0.absoluteString)" }
                      ?? "NO_THUMBNAIL host=\(host.rawValue)")
            }
        } catch {
            print("FAILED host=\(host.rawValue): \(error.localizedDescription)")
            exit(1)
        }
    }
}
