import AppKit
import Foundation

struct Note: Identifiable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var folder: String

    /// When the note was moved to Trash (nil = active). Persisted in YAML front matter.
    var trashedAt: Date?

    /// The filename currently on disk (nil for brand-new notes not yet saved).
    /// Used to detect renames when the title changes.
    var savedFilename: String?

    /// Filename derived from sanitized title: "Title.md"
    var filename: String {
        "\(FileStorage.sanitizeForFilename(title)).md"
    }

    /// Relative path from storage root: "folder/Title.md" or just "Title.md".
    var relativePath: String {
        folder.isEmpty ? filename : "\(folder)/\(filename)"
    }

    /// User-facing display path: "folder/title.md" or "title.md".
    var displayPath: String {
        relativePath
    }

    /// Directory portion only: "/FolderName/" or "/" for root notes.
    var displayDirectory: String {
        folder.isEmpty ? "/" : "/\(folder)/"
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        folder: String = "",
        trashedAt: Date? = nil,
        savedFilename: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.folder = folder
        self.trashedAt = trashedAt
        self.savedFilename = savedFilename
    }

    /// Compare all UI-visible properties. Exclude savedFilename (transient storage metadata).
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.content == rhs.content
            && lhs.createdAt == rhs.createdAt
            && lhs.modifiedAt == rhs.modifiedAt
            && lhs.folder == rhs.folder
            && lhs.trashedAt == rhs.trashedAt
    }
}

extension Note: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Note {
    /// Plain-text preview from the note body, stripping the title heading and markdown syntax.
    var previewText: String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        let bodyLines = lines.dropFirst()
        let raw = bodyLines.prefix(3).joined(separator: " ")
        return raw
            .replacingOccurrences(of: "#{1,6}\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*{1,2}([^*]+)\\*{1,2}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            .prefix(120)
            .description
    }

    /// RTF data converted from Markdown via HTML → NSAttributedString, preserving
    /// headings (with proper font sizes), bold, italic, strikethrough, code, and lists.
    var rtfData: Data? {
        Note.rtfData(from: content)
    }

    /// Full plain text with all Markdown syntax stripped.
    var plainText: String {
        Note.plainText(from: content)
    }
}

// MARK: - Static text conversion helpers (used by Coordinator for selection copy)

extension Note {
    /// Convert markdown to RTF data using the HTML → NSAttributedString pipeline.
    /// Must be called on the main thread (NSAttributedString HTML parsing uses WebKit).
    static func rtfData(from markdown: String) -> Data? {
        let html = markdownToHTML(markdown)
        guard let htmlData = html.data(using: .utf8),
              let attrStr = try? NSAttributedString(
                  data: htmlData,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil,
              )
        else { return nil }
        return try? attrStr.rtf(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
        )
    }

    /// Strip all Markdown syntax and return plain text.
    static func plainText(from markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "^```[^\\n]*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*{3}([^*]+)\\*{3}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "_{3}([^_]+)_{3}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\*{2}([^*]+)\\*{2}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "_{2}([^_]+)_{2}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?<=\\s|^)_([^_]+)_(?=\\s|$)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "~~([^~]+)~~", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "!\\[([^\\]]*)]\\([^)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^>\\s?", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^[-*_]{3,}\\s*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+\\[[ xX]\\]\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s*\\d+\\.\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML conversion for RTF pipeline

    private static func markdownToHTML(_ text: String) -> String {
        let style = """
        body{font-family:-apple-system,sans-serif;font-size:14px;line-height:1.5}\
        h1{font-size:24px;font-weight:bold;margin:6px 0}\
        h2{font-size:20px;font-weight:bold;margin:6px 0}\
        h3{font-size:17px;font-weight:bold;margin:6px 0}\
        h4{font-size:15px;font-weight:bold;margin:4px 0}\
        p{margin:6px 0}ul,ol{margin:4px 0;padding-left:20px}\
        blockquote{margin:4px 0 4px 8px;padding-left:8px;border-left:3px solid #888}\
        pre{font-family:monospace;margin:6px 0}code{font-family:monospace}
        """
        var html = "<html><head><meta charset='utf-8'><style>\(style)</style></head><body>"
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var inCodeBlock = false
        var codeLines: [String] = []
        var openList = ""

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if inCodeBlock {
                    html += escapeHTML(codeLines.joined(separator: "\n")) + "</code></pre>"
                    codeLines = []; inCodeBlock = false
                } else {
                    if !openList.isEmpty { html += "</\(openList)>"; openList = "" }
                    html += "<pre><code>"; inCodeBlock = true
                }
                i += 1; continue
            }
            if inCodeBlock { codeLines.append(line); i += 1; continue }

            // Close open list unless this line continues it or is blank
            if !openList.isEmpty, !line.isEmpty,
               line.range(of: "^\\s*[-*+]\\s", options: .regularExpression) == nil,
               line.range(of: "^\\s*\\d+\\.\\s", options: .regularExpression) == nil
            {
                html += "</\(openList)>"; openList = ""
            }

            if line.hasPrefix("# ") {
                html += "<h1>" + inlineHTML(String(line.dropFirst(2))) + "</h1>"
            } else if line.hasPrefix("## ") {
                html += "<h2>" + inlineHTML(String(line.dropFirst(3))) + "</h2>"
            } else if line.hasPrefix("### ") {
                html += "<h3>" + inlineHTML(String(line.dropFirst(4))) + "</h3>"
            } else if line.hasPrefix("#### ") {
                html += "<h4>" + inlineHTML(String(line.dropFirst(5))) + "</h4>"
            } else if line.hasPrefix("> ") {
                html += "<blockquote><p>" + inlineHTML(String(line.dropFirst(2))) + "</p></blockquote>"
            } else if line.range(of: "^\\s*[-*+]\\s+\\[[xX ]\\]", options: .regularExpression) != nil {
                let checked = line.contains("[x]") || line.contains("[X]")
                let content = line.replacingOccurrences(of: "^\\s*[-*+]\\s+\\[[xX ]?\\]\\s*", with: "", options: .regularExpression)
                if openList != "ul" { html += "<ul>"; openList = "ul" }
                html += "<li>" + (checked ? "&#x2611; " : "&#x2610; ") + inlineHTML(content) + "</li>"
            } else if line.range(of: "^\\s*[-*+]\\s", options: .regularExpression) != nil {
                let content = line.replacingOccurrences(of: "^\\s*[-*+]\\s+", with: "", options: .regularExpression)
                if openList != "ul" { html += "<ul>"; openList = "ul" }
                html += "<li>" + inlineHTML(content) + "</li>"
            } else if line.range(of: "^\\s*\\d+\\.\\s", options: .regularExpression) != nil {
                let content = line.replacingOccurrences(of: "^\\s*\\d+\\.\\s+", with: "", options: .regularExpression)
                if openList != "ol" { html += "<ol>"; openList = "ol" }
                html += "<li>" + inlineHTML(content) + "</li>"
            } else if line.range(of: "^[-*_]{3,}\\s*$", options: .regularExpression) != nil {
                html += "<hr>"
            } else if line.isEmpty {
                html += "<p>&nbsp;</p>"
            } else {
                html += "<p>" + inlineHTML(line) + "</p>"
            }
            i += 1
        }

        if !openList.isEmpty { html += "</\(openList)>" }
        if inCodeBlock { html += escapeHTML(codeLines.joined(separator: "\n")) + "</code></pre>" }
        html += "</body></html>"
        return html
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func inlineHTML(_ text: String) -> String {
        var s = escapeHTML(text)
        s = s.replacingOccurrences(of: "\\*{3}(.+?)\\*{3}", with: "<strong><em>$1</em></strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "_{3}(.+?)_{3}", with: "<strong><em>$1</em></strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*{2}(.+?)\\*{2}", with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "_{2}(.+?)_{2}", with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*([^*\\n]+)\\*", with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(of: "~~(.+?)~~", with: "<del>$1</del>", options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return s
    }
}
