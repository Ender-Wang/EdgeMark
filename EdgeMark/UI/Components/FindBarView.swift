import AppKit
import SwiftUI

// MARK: - FindBarView

/// Overlay bar that slides down from the top of the editor to provide Find and
/// Replace. It communicates with the underlying NativeTextViewWrapper via the
/// MarkdownEditorBus notification names defined in MarkdownEditorView.swift:
///
///   `.editorFindScrollToRange`  — tell the engine which ranges to highlight
///   `.editorFindClearHighlights` — tell the engine to clear highlights
///
/// The bar owns match computation and text mutation; the engine only renders
/// the highlight colors and scrolls the focused match into view.
struct FindBarView: View {
    /// Controls visibility. Set to false to dismiss.
    var isPresented: Binding<Bool>
    /// The editor's live text — used for match computation and Replace mutations.
    @Binding var editorText: String

    @State private var query = ""
    @State private var replaceQuery = ""
    @State private var matches: [NSRange] = []
    @State private var currentIndex = 0
    @State private var caseSensitive = false

    @FocusState private var isSearchFocused: Bool

    @Environment(L10n.self) private var l10n

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                // Row 1: search field + navigation + options + close
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)

                    TextField(l10n["find.placeholder"], text: $query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit { navigateForward() }
                        .onKeyPress(.escape) {
                            dismiss()
                            return .handled
                        }

                    // Match counter / no-results indicator
                    Group {
                        if query.isEmpty {
                            EmptyView()
                        } else if matches.isEmpty {
                            Text(l10n["find.noResults"])
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            Text(l10n.t(
                                "find.matchCount",
                                "\(currentIndex + 1)",
                                "\(matches.count)",
                            ))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .monospacedDigit()
                        }
                    }
                    .frame(minWidth: 48, alignment: .trailing)

                    Divider().frame(height: 14)

                    GlassControlGroup {
                        HStack(spacing: 0) {
                            AdaptiveIconButton(
                                systemName: "chevron.up",
                                help: "Previous match (⇧↩)",
                                action: navigateBackward,
                            )
                            .disabled(matches.isEmpty)

                            AdaptiveIconButton(
                                systemName: "chevron.down",
                                help: "Next match (↩)",
                                action: navigateForward,
                            )
                            .disabled(matches.isEmpty)
                        }
                    }

                    Divider().frame(height: 14)

                    caseSensitivityButton

                    Divider().frame(height: 14)

                    AdaptiveIconButton(
                        systemName: "xmark",
                        help: l10n["find.close"],
                        action: dismiss,
                    )
                }

                // Row 2: replace field + buttons
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)

                    TextField(l10n["find.replace.placeholder"], text: $replaceQuery)
                        .textFieldStyle(.plain)
                        .onSubmit { replaceCurrent() }

                    Divider().frame(height: 14)

                    Button(l10n["find.replace"]) { replaceCurrent() }
                        .buttonStyle(.plain)
                        .disabled(matches.isEmpty || query.isEmpty)
                        .foregroundStyle(matches.isEmpty || query.isEmpty ? .tertiary : .primary)

                    Button(l10n["find.replaceAll"]) { replaceAll() }
                        .buttonStyle(.plain)
                        .disabled(matches.isEmpty || query.isEmpty)
                        .foregroundStyle(matches.isEmpty || query.isEmpty ? .tertiary : .primary)

                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()
        }
        .onAppear {
            isSearchFocused = true
        }
        .onDisappear {
            postClearHighlights()
        }
        .onChange(of: query) { _, _ in recomputeMatches() }
        .onChange(of: caseSensitive) { _, _ in recomputeMatches() }
        .onChange(of: editorText) { _, _ in
            // Recompute after Replace mutations so the counter stays accurate.
            // Avoid recomputing on every keystroke the user types in the editor
            // while the bar is open — but that cost is low and keeps things correct.
            recomputeMatches()
        }
    }

    @ViewBuilder
    private var caseSensitivityButton: some View {
        if #available(macOS 26.0, *) {
            Button {
                caseSensitive.toggle()
            } label: {
                caseSensitivityLabel
            }
            .buttonStyle(.glass)
            .help(l10n["find.caseSensitive"])
            .accessibilityLabel(l10n["find.caseSensitive"])
        } else {
            Button {
                caseSensitive.toggle()
            } label: {
                caseSensitivityLabel
                    .background {
                        RoundedRectangle(cornerRadius: SurfaceMetrics.compactControlCornerRadius)
                            .fill(Color.primary.opacity(caseSensitive ? 0.12 : 0))
                    }
            }
            .buttonStyle(.plain)
            .help(l10n["find.caseSensitive"])
            .accessibilityLabel(l10n["find.caseSensitive"])
        }
    }

    private var caseSensitivityLabel: some View {
        Text("Aa")
            .font(.system(size: 11, weight: caseSensitive ? .bold : .regular))
            .foregroundStyle(caseSensitive ? Color.accentColor : .secondary)
            .frame(
                width: SurfaceMetrics.compactControlSize,
                height: SurfaceMetrics.compactControlSize,
            )
            .contentShape(Rectangle())
    }

    // MARK: - Match engine

    private static func findMatches(
        in text: String,
        query: String,
        caseSensitive: Bool,
    ) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let ns = text as NSString
        let options: NSString.CompareOptions = caseSensitive ? [] : .caseInsensitive
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.length > 0 {
            let found = ns.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }
            results.append(found)
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: ns.length - next)
        }
        return results
    }

    private func recomputeMatches() {
        let newMatches = Self.findMatches(in: editorText, query: query, caseSensitive: caseSensitive)
        matches = newMatches
        if !newMatches.isEmpty {
            currentIndex = min(currentIndex, newMatches.count - 1)
        } else {
            currentIndex = 0
        }
        postHighlight()
    }

    // MARK: - Navigation

    private func navigateForward() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        postHighlight()
    }

    private func navigateBackward() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        postHighlight()
    }

    // MARK: - Replace

    private func replaceCurrent() {
        guard !matches.isEmpty else { return }
        let idx = min(currentIndex, matches.count - 1)
        // Preserve intent: stay on the same ordinal. recomputeMatches() via
        // onChange(of: editorText) will clamp and post a single highlight notification.
        currentIndex = idx
        let ns = editorText as NSString
        editorText = ns.replacingCharacters(in: matches[idx], with: replaceQuery)
    }

    private func replaceAll() {
        guard !matches.isEmpty else { return }
        // Apply right-to-left so earlier UTF-16 offsets stay valid.
        var ns = editorText as NSString
        for range in matches.reversed() {
            ns = ns.replacingCharacters(in: range, with: replaceQuery) as NSString
        }
        editorText = ns as String
        // recomputeMatches() via onChange(of: editorText) will clear matches
        // (none left) and post a single clearHighlights notification.
    }

    // MARK: - Bus notifications

    private func postHighlight() {
        guard !matches.isEmpty else {
            postClearHighlights()
            return
        }
        let idx = min(currentIndex, matches.count - 1)
        NotificationCenter.default.post(
            name: .editorFindScrollToRange,
            object: nil,
            userInfo: [
                "range": matches[idx],
                "currentIndex": idx,
                "allRanges": matches,
            ],
        )
    }

    private func postClearHighlights() {
        NotificationCenter.default.post(name: .editorFindClearHighlights, object: nil)
    }

    // MARK: - Dismiss

    private func dismiss() {
        // onDisappear handles the bus cleanup; just flip the binding.
        isPresented.wrappedValue = false
    }
}
