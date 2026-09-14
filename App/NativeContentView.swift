import SwiftUI
import UIKit
import NGAKit

private struct PostImagePreviewActionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((URL) -> Void)? = nil
}

extension EnvironmentValues {
    var postImagePreviewAction: ((URL) -> Void)? {
        get { self[PostImagePreviewActionKey.self] }
        set { self[PostImagePreviewActionKey.self] = newValue }
    }
}

struct NativeContentView: View {
    let nodes: [ContentNode]
    var textSize: CGFloat = 16
    var paragraphAlignment = "left"
    @Environment(\.postImagePreviewAction) private var previewImage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(Self.renderGroups(nodes).enumerated()), id: \.offset) { _, group in
                switch group {
                case .inline(let inlineNodes):
                    InlineRichTextView(nodes: inlineNodes, textSize: textSize, alignment: paragraphAlignment)
                case .block(let node):
                    block(node)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func block(_ node: ContentNode) -> some View {
        switch node {
                case .image(let url):
                    if let previewImage {
                        Button { previewImage(url) } label: {
                            postImage(url)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("放大帖子图片")
                    } else {
                        NavigationLink { ImageDetailView(url: url) } label: {
                            postImage(url)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看图片")
                    }
                case .quote(let children):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(AppTheme.brand).frame(width: 3)
                        NativeContentView(nodes: children, textSize: textSize).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(12).background(AppTheme.cardSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                case .collapse(let title, let children):
                    DisclosureGroup(title) { NativeContentView(nodes: children, textSize: textSize).padding(.top, 6) }
                case .align(let a, let children):
                    NativeContentView(nodes: children, textSize: textSize, paragraphAlignment: a)
                        .frame(maxWidth: .infinity, alignment: alignment(for: a))
                case .list(let children): NativeContentView(nodes: children, textSize: textSize)
                case .bullet(let children):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(.system(size: textSize)).foregroundStyle(AppTheme.inkSoft)
                        NativeContentView(nodes: children, textSize: textSize).frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .code(let code):
                    CodeBlockView(code: code)
                case .divider:
                    Divider().overlay(AppTheme.line).padding(.vertical, 5)
                case .table(let rows):
                    NativeTableView(rows: rows, textSize: textSize)
                case .dice(let children):
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "die.face.5.fill").foregroundStyle(AppTheme.forumAccent)
                        NativeContentView(nodes: children, textSize: textSize)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(AppTheme.forumAccentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                default:
                    InlineRichTextView(nodes: [node], textSize: textSize, alignment: paragraphAlignment)
        }
    }

    private func postImage(_ url: URL) -> some View {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit().frame(maxHeight: 480)
                            case .failure: Label("图片加载失败 · 点按查看", systemImage: "photo").padding()
                            default: ProgressView().frame(maxWidth: .infinity).frame(height: 140)
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func alignment(for a: String) -> Alignment { a == "center" ? .center : (a == "right" ? .trailing : .leading) }

    private enum RenderGroup {
        case inline([ContentNode])
        case block(ContentNode)
    }

    /// NGA BBCode is mostly inline. Keeping adjacent text, styles, links and
    /// smiles in one attributed paragraph prevents every tag from forcing a new line.
    private static func renderGroups(_ nodes: [ContentNode]) -> [RenderGroup] {
        var groups: [RenderGroup] = []
        var inline: [ContentNode] = []
        func flush() {
            if !inline.isEmpty { groups.append(.inline(inline)); inline.removeAll(keepingCapacity: true) }
        }
        for node in nodes {
            if isInline(node) { inline.append(node) }
            else { flush(); groups.append(.block(node)) }
        }
        flush()
        return groups
    }

    private static func isInline(_ node: ContentNode) -> Bool {
        switch node {
        case .text, .link, .bold, .italic, .underline, .strike, .size, .color, .emote: true
        default: false
        }
    }

    static func color(from raw: String) -> Color {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 6, let v = UInt64(hex, radix: 16) {
                return Color(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255)
            }
        }
        let named: [String: Color] = [
            "red": .red, "blue": .blue, "green": .green, "orange": .orange, "yellow": .yellow,
            "purple": .purple, "gray": .gray, "grey": .gray, "silver": .gray, "brown": .brown,
            "teal": .teal, "white": .white, "black": .black,
            "skyblue": rgb(0x87CEEB), "royalblue": rgb(0x4169E1), "darkblue": rgb(0x00008B),
            "orangered": rgb(0xFF4500), "crimson": rgb(0xDC143C), "firebrick": rgb(0xB22222),
            "darkred": rgb(0x8B0000), "limegreen": rgb(0x32CD32), "seagreen": rgb(0x2E8B57),
            "deeppink": rgb(0xFF1493), "tomato": rgb(0xFF6347), "coral": rgb(0xFF7F50),
            "indigo": rgb(0x4B0082), "burlywood": rgb(0xDEB887), "sandybrown": rgb(0xF4A460),
            "chocolate": rgb(0xD2691E), "sienna": rgb(0xA0522D)
        ]
        return named[s] ?? AppTheme.ink
    }

    static func uiColor(from raw: String) -> UIColor { UIColor(color(from: raw)) }

    private static func rgb(_ value: UInt64) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }

    /// Server content commonly places several blank lines around every BBCode
    /// element. Keep paragraph separation but avoid turning it into empty screens.
    static func compact(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n[\t ]*\n[\t ]*\n+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One native attributed paragraph for adjacent inline BBCode. NSTextAttachment
/// lets remote NGA smiles share a baseline with the surrounding words, and
/// UITextView keeps links tappable and text selectable.
private struct InlineRichTextView: View {
    let nodes: [ContentNode]
    let textSize: CGFloat
    let alignment: String
    @State private var emoteImages: [URL: UIImage] = [:]

    private var emoteURLs: [URL] {
        var result: [URL] = []
        func collect(_ values: [ContentNode]) {
            for node in values {
                switch node {
                case .emote(let group, let name):
                    if let url = BBCode.emoteURL(group: group, name: name), !result.contains(url) { result.append(url) }
                case .bold(let c), .italic(let c), .underline(let c), .strike(let c),
                     .size(_, let c), .color(_, let c): collect(c)
                default: break
                }
            }
        }
        collect(nodes)
        return result
    }

    var body: some View {
        AttributedTextView(value: attributedString)
            .task(id: emoteURLs.map(\.absoluteString).joined(separator: "|")) {
                for url in emoteURLs where emoteImages[url] == nil {
                    guard !Task.isCancelled,
                          let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let image = UIImage(data: data) else { continue }
                    emoteImages[url] = image
                }
            }
    }

    private var attributedString: NSAttributedString {
        let result = NSMutableAttributedString()
        append(nodes, to: result, style: InlineStyle(size: textSize))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.alignment = alignment == "center" ? .center : (alignment == "right" ? .right : .left)
        if result.length > 0 { result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length)) }
        return result
    }

    private func append(_ values: [ContentNode], to result: NSMutableAttributedString, style: InlineStyle) {
        for node in values {
            switch node {
            case .text(let value):
                var text = value.replacingOccurrences(of: "\r\n", with: "\n")
                text = text.replacingOccurrences(of: #"\n[\t ]*\n[\t ]*\n+"#, with: "\n\n", options: .regularExpression)
                result.append(NSAttributedString(string: text, attributes: style.attributes))
            case .link(let label, let url):
                var attrs = style.attributes
                attrs[.link] = url
                attrs[.foregroundColor] = UIColor(AppTheme.forumAccent)
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                result.append(NSAttributedString(string: label.isEmpty ? url.absoluteString : label, attributes: attrs))
            case .bold(let c): append(c, to: result, style: style.with(bold: true))
            case .italic(let c): append(c, to: result, style: style.with(italic: true))
            case .underline(let c): append(c, to: result, style: style.with(underline: true))
            case .strike(let c): append(c, to: result, style: style.with(strike: true))
            case .size(let scale, let c): append(c, to: result, style: style.with(size: min(max(textSize * scale, 14), 24)))
            case .color(let raw, let c): append(c, to: result, style: style.with(color: NativeContentView.uiColor(from: raw)))
            case .emote(let group, let name):
                if let url = BBCode.emoteURL(group: group, name: name), let image = emoteImages[url] {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    // NGA smile groups use different source pixel dimensions,
                    // but their visual height in a post should stay consistent.
                    let height = min(max(style.size * 2.0, 38), 44)
                    let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
                    attachment.bounds = CGRect(x: 0, y: -8, width: height * ratio, height: height)
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    result.append(NSAttributedString(string: "[:\(name)]", attributes: style.attributes))
                }
            default: break
            }
        }
    }
}

private struct InlineStyle {
    var size: CGFloat
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var color: UIColor = UIColor(AppTheme.ink)

    var attributes: [NSAttributedString.Key: Any] {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFont.systemFont(ofSize: size)
        let font = base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: size) } ?? base
        var result: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if underline { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strike { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return result
    }

    func with(size: CGFloat? = nil, bold: Bool? = nil, italic: Bool? = nil,
              underline: Bool? = nil, strike: Bool? = nil, color: UIColor? = nil) -> InlineStyle {
        InlineStyle(size: size ?? self.size, bold: bold ?? self.bold, italic: italic ?? self.italic,
                    underline: underline ?? self.underline, strike: strike ?? self.strike, color: color ?? self.color)
    }
}

private struct AttributedTextView: UIViewRepresentable {
    let value: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if !view.attributedText.isEqual(to: value) { view.attributedText = value }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}

private struct NativeTableView: View {
    let rows: [[[ContentNode]]]
    let textSize: CGFloat

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .topLeading, horizontalSpacing: 1, verticalSpacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                        GridRow(alignment: .top) {
                            ForEach(0..<columnCount, id: \.self) { column in
                                let cell = column < cells.count ? cells[column] : []
                                NativeTableCell(nodes: cell, textSize: textSize,
                                                width: columnWidth,
                                                alternate: rowIndex.isMultiple(of: 2))
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.line))
            }
        }
    }

    private var columnCount: Int { max(1, rows.map(\.count).max() ?? 1) }
    private var columnWidth: CGFloat {
        columnCount == 1 ? 300 : (columnCount == 2 ? 190 : 156)
    }
}

private struct NativeTableCell: View {
    let nodes: [ContentNode]
    let textSize: CGFloat
    let width: CGFloat
    let alternate: Bool

    var body: some View {
        NativeContentView(nodes: nodes, textSize: textSize)
            .padding(9)
            .frame(width: width, alignment: .topLeading)
            .frame(minHeight: 42, maxHeight: .infinity, alignment: .topLeading)
            .background(alternate ? AppTheme.cardSoft.opacity(0.72) : AppTheme.card.opacity(0.72))
    }
}

private struct ImageDetailView: View {
    let url: URL
    @State private var scale: CGFloat = 1
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit().containerRelativeFrame(.horizontal).scaleEffect(scale)
                case .failure: ContentUnavailableView("图片未能加载", systemImage: "photo", description: Text("可以通过右上角在浏览器中打开。"))
                default: ProgressView().padding(40)
                }
            }.gesture(MagnifyGesture().onChanged { scale = min(max($0.magnification, 1), 4) })
        }.navigationTitle("图片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Link(destination: url) { Image(systemName: "safari") }.accessibilityLabel("在浏览器中打开") } }
    }
}

/// A lightweight viewer layered over the still-alive reader. UIKit's scroll
/// view supplies fluid pinch zooming and panning without decoding the image at
/// an unbounded size.
struct PostImagePreviewView: View {
    let url: URL
    let close: () -> Void
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            if let image {
                ZoomablePostImage(image: image)
                    .ignoresSafeArea(edges: .horizontal)
            } else if failed {
                ContentUnavailableView("图片未能加载", systemImage: "photo",
                                       description: Text("请检查网络后重试。"))
                    .foregroundStyle(.white)
            } else {
                ProgressView("正在载入原图…").tint(.white).foregroundStyle(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.46), in: Circle())
                    }
                    .accessibilityLabel("关闭图片")
                }
                Spacer()
                Text("双击或双指缩放 · 拖动查看")
                    .font(.caption).foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(.black.opacity(0.42), in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .task(id: url) {
            image = await RemoteImageStore.image(at: url, maxPixel: 4096)
            failed = image == nil
        }
    }
}

private struct ZoomablePostImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.decelerationRate = .fast
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5,
                                  height: scrollView.bounds.height / 2.5)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                           width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// A real code block: monospaced, wrapped, with a header bar and a copy button.
private struct CodeBlockView: View {
    let code: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("代码", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.inkSoft)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? AppTheme.online : AppTheme.inkSoft)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(AppTheme.cardSoft.opacity(0.55))
            Divider().overlay(AppTheme.line)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(AppTheme.cardSoft, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
