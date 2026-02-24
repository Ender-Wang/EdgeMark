import AppKit

final class MarkdownHighlighter {
    private weak var textView: NSTextView?

    // MARK: - Fonts

    private let bodyFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let h1Font = NSFont.systemFont(ofSize: 20, weight: .bold)
    private let h2Font = NSFont.systemFont(ofSize: 17, weight: .semibold)
    private let h3Font = NSFont.systemFont(ofSize: 15, weight: .medium)

    // MARK: - Colors

    private let syntaxColor = NSColor.tertiaryLabelColor
    private let codeColor = NSColor.systemOrange
    private let linkColor = NSColor.systemBlue
    private let quoteColor = NSColor.secondaryLabelColor

    // MARK: - Regex Patterns (compiled once)

    private static let patterns: [(regex: NSRegularExpression, style: HighlightStyle)] = {
        func re(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }
        return [
            // Fenced code blocks: ```...``` (must be before inline patterns)
            (re("^```.*$\\n[\\s\\S]*?^```\\s*$", [.anchorsMatchLines]), .codeBlock),

            // Headings
            (re("^(#{1})\\s+(.+)$", .anchorsMatchLines), .heading(level: 1)),
            (re("^(#{2})\\s+(.+)$", .anchorsMatchLines), .heading(level: 2)),
            (re("^(#{3,6})\\s+(.+)$", .anchorsMatchLines), .heading(level: 3)),

            // Bold: **text** or __text__
            (re("(\\*\\*|__)(.+?)(\\1)"), .bold),

            // Italic: *text* or _text_ (not adjacent to another * or _)
            (re("(?<![*_])(\\*|_)(?![*_\\s])(.+?)(?<![*_\\s])\\1(?![*_])"), .italic),

            // Strikethrough: ~~text~~
            (re("(~~)(.+?)(~~)"), .strikethrough),

            // Inline code: `text`
            (re("`([^`\\n]+)`"), .inlineCode),

            // Task lists: - [ ] or - [x]
            (re("^(\\s*[-*]\\s+\\[)([xX ])\\]", .anchorsMatchLines), .taskList),

            // Unordered list markers: - or * or +
            (re("^(\\s*[-*+])\\s", .anchorsMatchLines), .listMarker),

            // Ordered list markers: 1. 2. etc.
            (re("^(\\s*\\d+\\.)\\s", .anchorsMatchLines), .listMarker),

            // Blockquotes: > text
            (re("^(>)\\s?(.*)$", .anchorsMatchLines), .blockquote),

            // Links: [text](url)
            (re("(\\[)([^\\]]+)(\\]\\()([^)]+)(\\))"), .link),

            // Horizontal rules: ---, ***, ___
            (re("^([\\-*_]{3,})\\s*$", .anchorsMatchLines), .horizontalRule),
        ]
    }()

    init(textView: NSTextView) {
        self.textView = textView
    }

    // MARK: - Public

    func highlightAll() {
        guard let textView, let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        applyHighlighting(in: fullRange)
    }

    func highlightVisible(around editedRange: NSRange) {
        guard let textView, let textStorage = textView.textStorage else { return }
        let text = textStorage.string as NSString

        // Expand to full lines around the edit
        let lineRange = text.lineRange(for: editedRange)

        // Expand further for multi-line constructs (code blocks)
        let expandedStart = max(0, lineRange.location - 3000)
        let expandedEnd = min(textStorage.length, NSMaxRange(lineRange) + 3000)
        let expandedRange = NSRange(location: expandedStart, length: expandedEnd - expandedStart)

        applyHighlighting(in: expandedRange)
    }

    // MARK: - Internal

    private func applyHighlighting(in range: NSRange) {
        guard let textView, let textStorage = textView.textStorage else { return }
        guard range.length > 0 else { return }

        textView.undoManager?.disableUndoRegistration()
        textStorage.beginEditing()

        // Reset to default attributes
        textStorage.setAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
        ], range: range)

        let text = textStorage.string as NSString

        for (regex, style) in Self.patterns {
            regex.enumerateMatches(in: text as String, options: [], range: range) { match, _, _ in
                guard let match else { return }
                applyStyle(style, match: match, textStorage: textStorage)
            }
        }

        textStorage.endEditing()
        textView.undoManager?.enableUndoRegistration()
    }

    private func applyStyle(
        _ style: HighlightStyle,
        match: NSTextCheckingResult,
        textStorage: NSTextStorage,
    ) {
        switch style {
        case let .heading(level):
            let font = level == 1 ? h1Font : level == 2 ? h2Font : h3Font
            textStorage.addAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ], range: match.range)
            // Dim the # markers (capture group 1)
            if match.numberOfRanges > 1 {
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
            }

        case .bold:
            let boldFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
            textStorage.addAttribute(.font, value: boldFont, range: match.range)
            // Dim ** markers (groups 1 and 3)
            if match.numberOfRanges > 3 {
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 3))
            }

        case .italic:
            let italicFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
            textStorage.addAttribute(.font, value: italicFont, range: match.range)
            // Dim * marker (group 1)
            if match.numberOfRanges > 1 {
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
                // Closing marker is the same char, at end of match
            }

        case .strikethrough:
            textStorage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: match.range)
            // Dim ~~ markers
            if match.numberOfRanges > 2 {
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 3))
            }

        case .inlineCode:
            textStorage.addAttributes([
                .foregroundColor: codeColor,
                .backgroundColor: NSColor.quaternaryLabelColor,
            ], range: match.range)

        case .codeBlock:
            textStorage.addAttributes([
                .foregroundColor: codeColor,
                .backgroundColor: NSColor.quaternaryLabelColor,
            ], range: match.range)

        case .blockquote:
            textStorage.addAttribute(.foregroundColor, value: quoteColor, range: match.range)
            // Dim the > marker
            if match.numberOfRanges > 1 {
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
            }

        case .link:
            textStorage.addAttribute(.foregroundColor, value: linkColor, range: match.range)
            // Dim brackets and parens (groups 1, 3, 5)
            if match.numberOfRanges > 4 {
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 3))
                textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 5))
            }

        case .listMarker:
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)

        case .taskList:
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)

        case .horizontalRule:
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)
        }
    }
}

private enum HighlightStyle {
    case heading(level: Int)
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case blockquote
    case link
    case listMarker
    case taskList
    case horizontalRule
}
