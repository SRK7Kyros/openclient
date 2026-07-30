import SwiftUI

struct MarkdownMessageText: View {
    enum Style {
        case standard
        case reasoning
    }

    fileprivate enum MarkdownBlock: Identifiable {
        case text(id: Int, value: String)
        case heading(id: Int, level: Int, value: String)
        case blockQuote(id: Int, value: String)
        case listItem(id: Int, marker: ListMarker, value: String)
        case table(id: Int, headers: [String], rows: [[String]])
        case codeBlock(id: Int, language: String?, value: String)

        var id: Int {
            switch self {
            case let .text(id, _), let .heading(id, _, _), let .blockQuote(id, _), let .listItem(id, _, _), let .table(id, _, _), let .codeBlock(id, _, _):
                return id
            }
        }
    }

    fileprivate enum ListMarker {
        case unordered
        case ordered(String)
        case checkbox(isChecked: Bool)
    }

    let text: String
    let isUser: Bool
    let style: Style
    var isStreaming = false
    var animatesStreamingText = true
    var streamingAnimationID: String? = nil
    var onStreamingRevealCompleted: (() -> Void)? = nil

    var body: some View {
        switch style {
        case .standard:
            content
                .padding(.vertical, 0)
        case .reasoning:
            content
        }
    }

    private var content: some View {
        Group {
            if isStreaming {
                streamingRichMarkdownContent
            } else {
                richMarkdownContent
            }
        }
        .frame(maxWidth: isUser ? nil : .infinity, alignment: .leading)
        .modifier(ConditionalTextSelectionModifier(isEnabled: !isStreaming))
    }

    private var richMarkdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                markdownBlockView(block)
            }
        }
    }

    @ViewBuilder
    private var streamingRichMarkdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                markdownBlockView(block)
            }
        }
    }

    @ViewBuilder
    private func markdownBlockView(_ block: MarkdownBlock) -> some View {
        Group {
            switch block {
            case let .text(id, value):
                if shouldUseNativeStreamingChunkText {
#if canImport(UIKit)
                    NativeStreamingChunkTextLabel(
                        text: value,
                        isUser: isUser,
                        style: style,
                        lineSpacing: textLineSpacing,
                        animationID: streamingBlockAnimationID(blockID: id)
                    )
                    .padding(.bottom, textBlockBottomPadding(for: value))
#else
                    styledText(markdownText(value))
                        .padding(.bottom, textBlockBottomPadding(for: value))
#endif
                } else {
                    styledText(markdownText(value))
                        .padding(.bottom, textBlockBottomPadding(for: value))
                }
            case let .heading(_, level, value):
                styledHeading(markdownText(value), level: level)
            case let .blockQuote(_, value):
                styledBlockQuote(markdownText(value))
            case let .listItem(_, marker, value):
                styledListItem(markdownText(value), marker: marker)
            case let .table(_, headers, rows):
                styledTable(headers: headers, rows: rows)
            case let .codeBlock(id, language, value):
                HighlightedCodeBlock(code: value, language: language)
                    .padding(.vertical, codeBlockOuterPadding)
                    .overlay(alignment: .bottom) {
                        if id == activeStreamingCodeBlockID {
                            StreamingTurnBottomGradient()
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private func streamingBlockAnimationID(blockID: Int) -> String? {
        streamingAnimationID.map { "\($0):block-\(blockID)" }
    }

    private var activeStreamingCodeBlockID: Int? {
        guard isStreaming, let lastBlock = blocks.last else { return nil }
        if case let .codeBlock(id, _, _) = lastBlock {
            return id
        }
        return nil
    }

    private var shouldUseNativeStreamingChunkText: Bool {
        isStreaming && animatesStreamingText && !isUser && style == .standard
    }

    private func styledText(_ text: Text) -> some View {
        text
            .font(textFont)
            .foregroundStyle(textForegroundStyle)
            .lineSpacing(textLineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func styledHeading(_ text: Text, level: Int) -> some View {
        text
            .font(headingFont(level: level))
            .foregroundStyle(textForegroundStyle)
            .lineSpacing(textLineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, headingTopPadding(level: level))
            .padding(.bottom, headingBottomPadding(level: level))
    }

    private func styledBlockQuote(_ text: Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(blockQuoteAccentStyle)
                .frame(width: 3)

            styledText(text)
                .foregroundStyle(blockQuoteForegroundStyle)
        }
        .padding(.vertical, blockQuoteVerticalPadding)
        .padding(.horizontal, 10)
        .background(blockQuoteBackgroundStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, blockQuoteOuterPadding)
    }

    private func styledListItem(_ text: Text, marker: ListMarker) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            listMarkerView(marker)
                .frame(width: listMarkerWidth(for: marker), alignment: .trailing)

            styledText(text)
        }
        .padding(.vertical, listItemVerticalPadding)
    }

    private func styledTable(headers: [String], rows: [[String]]) -> some View {
        let minimumHeight = estimatedTableHeight(headers: headers, rows: rows)

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, isHeader: true)

                ForEach(rows.indices, id: \.self) { rowIndex in
                    Divider()
                        .overlay(tableDividerStyle)

                    tableRow(rows[rowIndex], isHeader: false)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: minimumHeight, alignment: .top)
            .background(tableBackgroundStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tableBorderStyle, lineWidth: 1)
            }
            .padding(.horizontal, tableHorizontalScrollBleed)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, -tableHorizontalScrollBleed)
        .padding(.vertical, tableOuterPadding)
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells.indices, id: \.self) { columnIndex in
                tableCell(cells[columnIndex], isHeader: isHeader)

                if columnIndex < cells.count - 1 {
                    Rectangle()
                        .fill(tableDividerStyle)
                        .frame(width: 1)
                }
            }
        }
        .background(isHeader ? tableHeaderBackgroundStyle : .clear)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func estimatedTableHeight(headers: [String], rows: [[String]]) -> CGFloat {
        let dividerHeight = CGFloat(rows.count)
        return estimatedTableRowHeight(headers, isHeader: true)
            + rows.reduce(0) { $0 + estimatedTableRowHeight($1, isHeader: false) }
            + dividerHeight
            + estimatedTableHeightSafetyPadding
    }

    private func estimatedTableRowHeight(_ cells: [String], isHeader: Bool) -> CGFloat {
        let verticalPadding: CGFloat = isHeader ? 16 : 14
        let contentHeight = cells
            .map { estimatedTableCellTextHeight(for: $0, isHeader: isHeader) }
            .max() ?? estimatedTableLineHeight

        return ceil(contentHeight) + verticalPadding
    }

    private func estimatedTableCellTextHeight(for value: String, isHeader: Bool) -> CGFloat {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let text = normalized.isEmpty ? " " : normalized

#if canImport(UIKit)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = textLineSpacing

        let boundingSize = (text as NSString).boundingRect(
            with: CGSize(width: estimatedTableCellTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: estimatedTableUIFont(isHeader: isHeader),
                .paragraphStyle: paragraph
            ],
            context: nil
        )

        return max(estimatedTableLineHeight, ceil(boundingSize.height))
#else
        let charactersPerLine = style == .standard ? 28 : 30

        let lineCount = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { count, line in
                count + max(1, Int(ceil(Double(line.count) / Double(charactersPerLine))))
            }

        return CGFloat(max(1, lineCount)) * estimatedTableLineHeight
#endif
    }

#if canImport(UIKit)
    private func estimatedTableUIFont(isHeader: Bool) -> UIFont {
        let textStyle: UIFont.TextStyle = style == .standard ? .body : .caption1
        let baseFont = UIFont.preferredFont(forTextStyle: textStyle)

        guard isHeader else { return baseFont }

        return .systemFont(ofSize: baseFont.pointSize, weight: .semibold)
    }
#endif

    private var estimatedTableCellTextWidth: CGFloat {
        max(1, tableCellMaxWidth - 20)
    }

    private var estimatedTableLineHeight: CGFloat {
        switch style {
        case .standard:
            return 22
        case .reasoning:
            return 17
        }
    }

    private var estimatedTableHeightSafetyPadding: CGFloat {
        switch style {
        case .standard:
            return 8
        case .reasoning:
            return 6
        }
    }

    private func tableCell(_ value: String, isHeader: Bool) -> some View {
        markdownText(value)
            .font(isHeader ? tableHeaderFont : textFont)
            .foregroundStyle(isHeader ? tableHeaderForegroundStyle : textForegroundStyle)
            .lineSpacing(textLineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: tableCellMinWidth, maxWidth: tableCellMaxWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, isHeader ? 8 : 7)
    }

    @ViewBuilder
    private func listMarkerView(_ marker: ListMarker) -> some View {
        switch marker {
        case .unordered:
            Text("•")
                .font(listMarkerFont)
                .foregroundStyle(listMarkerForegroundStyle)
        case let .ordered(value):
            Text(value)
                .font(listMarkerFont)
                .foregroundStyle(listMarkerForegroundStyle)
        case let .checkbox(isChecked):
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .font(checkboxMarkerFont)
                .foregroundStyle(isChecked ? checkboxCheckedForegroundStyle : listMarkerForegroundStyle)
        }
    }

    private func markdownText(_ value: String) -> Text {
        if let attributed = OpenCodeMarkdownRenderCache.shared.inlineMarkdown(for: value) {
            return Text(attributed)
        }

        return Text(value)
    }

    private var blocks: [MarkdownBlock] {
        OpenCodeMarkdownRenderCache.shared.blocks(for: text) {
            let normalizedText = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\u{2029}", with: "\n\n")
                .replacingOccurrences(of: "\u{2028}", with: "\n")
            let lines = normalizedText.components(separatedBy: "\n")
            var result: [MarkdownBlock] = []
            var index = 0
            var id = 0

            while index < lines.count {
                let line = lines[index]

                if let codeBlock = fencedCodeBlock(in: lines, startingAt: index) {
                    result.append(.codeBlock(id: id, language: codeBlock.language, value: codeBlock.value))
                    id += 1
                    index = codeBlock.nextIndex
                    continue
                }

                if let table = markdownTable(in: lines, startingAt: index) {
                    result.append(.table(id: id, headers: table.headers, rows: table.rows))
                    id += 1
                    index = table.nextIndex
                    continue
                }

                if let quote = blockQuoteLine(from: line) {
                    var values = [quote]
                    index += 1

                    while index < lines.count, let nextQuote = blockQuoteLine(from: lines[index]) {
                        values.append(nextQuote)
                        index += 1
                    }

                    result.append(.blockQuote(id: id, value: values.joined(separator: "\n")))
                    id += 1
                    continue
                }

                if let heading = heading(from: line) {
                    result.append(.heading(id: id, level: heading.level, value: heading.value))
                } else if let item = listItem(from: line) {
                    result.append(.listItem(id: id, marker: item.marker, value: item.value))
                } else {
                    result.append(.text(id: id, value: line))
                }

                id += 1
                index += 1
            }

            return result
        }
    }

#if DEBUG
    @MainActor
    static func _testFirstTableRowCount(in text: String) -> Int? {
        let messageText = MarkdownMessageText(text: text, isUser: false, style: .standard)
        for block in messageText.blocks {
            if case let .table(_, _, rows) = block {
                return rows.count
            }
        }

        return nil
    }

    @MainActor
    static func _testFirstTableEstimatedHeight(in text: String) -> CGFloat? {
        let messageText = MarkdownMessageText(text: text, isUser: false, style: .standard)
        for block in messageText.blocks {
            if case let .table(_, headers, rows) = block {
                return messageText.estimatedTableHeight(headers: headers, rows: rows)
            }
        }

        return nil
    }

    @MainActor
    static func _testHasActiveStreamingCodeBlock(in text: String) -> Bool {
        MarkdownMessageText(
            text: text,
            isUser: false,
            style: .standard,
            isStreaming: true
        ).activeStreamingCodeBlockID != nil
    }
#endif

    private func heading(from line: String) -> (level: Int, value: String)? {
        for level in 1...3 {
            let marker = String(repeating: "#", count: level) + " "
            guard line.hasPrefix(marker) else { continue }

            let value = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }

            return (level, value)
        }

        return nil
    }

    private func fencedCodeBlock(in lines: [String], startingAt startIndex: Int) -> (language: String?, value: String, nextIndex: Int)? {
        guard let fence = codeFence(from: lines[startIndex]) else { return nil }

        var values: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            if isClosingCodeFence(lines[index], fence: fence.marker) {
                return (fence.language, values.joined(separator: "\n"), index + 1)
            }

            values.append(lines[index])
            index += 1
        }

        return (fence.language, values.joined(separator: "\n"), index)
    }

    private func codeFence(from line: String) -> (marker: String, language: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marker: String

        if trimmed.hasPrefix("```") {
            marker = "```"
        } else if trimmed.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }

        let language = String(trimmed.dropFirst(marker.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first

        return (marker, language?.isEmpty == false ? language : nil)
    }

    private func isClosingCodeFence(_ line: String, fence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(fence)
    }

    private func listItem(from line: String) -> (marker: ListMarker, value: String)? {
        if let checkbox = checkboxListItem(from: line) {
            return checkbox
        }

        if let unordered = unorderedListItem(from: line) {
            return unordered
        }

        return orderedListItem(from: line)
    }

    private func checkboxListItem(from line: String) -> (marker: ListMarker, value: String)? {
        let prefixes: [(prefix: String, isChecked: Bool)] = [
            ("- [ ] ", false),
            ("- [x] ", true),
            ("- [X] ", true),
            ("* [ ] ", false),
            ("* [x] ", true),
            ("* [X] ", true),
            ("+ [ ] ", false),
            ("+ [x] ", true),
            ("+ [X] ", true)
        ]

        for prefix in prefixes where line.hasPrefix(prefix.prefix) {
            let value = String(line.dropFirst(prefix.prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            return (.checkbox(isChecked: prefix.isChecked), value)
        }

        return nil
    }

    private func unorderedListItem(from line: String) -> (marker: ListMarker, value: String)? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            return (.unordered, value)
        }

        return nil
    }

    private func orderedListItem(from line: String) -> (marker: ListMarker, value: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }

        let number = String(line[..<dotIndex])
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let valueStart = line.index(after: dotIndex)
        guard valueStart < line.endIndex, line[valueStart] == " " else { return nil }

        let value = String(line[line.index(after: valueStart)...]).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        return (.ordered("\(number)."), value)
    }

    private func markdownTable(in lines: [String], startingAt startIndex: Int) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
        guard startIndex + 1 < lines.count,
              let headers = tableCells(from: lines[startIndex]),
              isTableSeparator(lines[startIndex + 1]) else {
            return nil
        }

        var rows: [[String]] = []
        var index = startIndex + 2

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                let nextRowIndex = nextTableRowIndex(afterBlankLineAt: index, in: lines)
                guard let nextRowIndex else { break }
                index = nextRowIndex
                continue
            }

            guard let cells = tableCells(from: lines[index]), !isTableSeparator(lines[index]) else {
                break
            }

            rows.append(normalizedTableRow(cells, count: headers.count))
            index += 1
        }

        guard !rows.isEmpty else { return nil }
        return (headers, rows, index)
    }

    private func nextTableRowIndex(afterBlankLineAt index: Int, in lines: [String]) -> Int? {
        var nextIndex = index + 1
        while nextIndex < lines.count, lines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            nextIndex += 1
        }

        guard nextIndex < lines.count,
              tableCells(from: lines[nextIndex]) != nil,
              !isTableSeparator(lines[nextIndex]) else {
            return nil
        }

        return nextIndex
    }

    private func tableCells(from line: String) -> [String]? {
        guard line.contains("|") else { return nil }

        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") {
            value.removeFirst()
        }
        if value.hasSuffix("|") {
            value.removeLast()
        }

        let cells = value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        guard cells.count >= 2, cells.contains(where: { !$0.isEmpty }) else { return nil }
        return cells
    }

    private func isTableSeparator(_ line: String) -> Bool {
        guard let cells = tableCells(from: line) else { return false }

        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("-"), trimmed.count >= 3 else { return false }
            return trimmed.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private func normalizedTableRow(_ cells: [String], count: Int) -> [String] {
        if cells.count == count {
            return cells
        }

        if cells.count > count {
            return Array(cells.prefix(count))
        }

        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func blockQuoteLine(from line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }

        let value = String(line.dropFirst())
        if value.hasPrefix(" ") {
            return String(value.dropFirst())
        }

        return value
    }

    private var textFont: Font {
        switch style {
        case .standard:
            return .body
        case .reasoning:
            return .caption
        }
    }

    private func headingFont(level: Int) -> Font {
        switch style {
        case .standard:
            switch level {
            case 1:
                return .title3.weight(.bold)
            case 2:
                return .headline.weight(.bold)
            default:
                return .subheadline.weight(.semibold)
            }
        case .reasoning:
            switch level {
            case 1:
                return .subheadline.weight(.bold)
            case 2:
                return .caption.weight(.bold)
            default:
                return .caption.weight(.semibold)
            }
        }
    }

    private var textForegroundStyle: Color {
        if isUser {
            return .white
        }

        switch style {
        case .standard:
            return .primary
        case .reasoning:
            return .secondary
        }
    }

    private var blockQuoteForegroundStyle: Color {
        isUser ? .white.opacity(0.86) : .secondary
    }

    private var blockQuoteAccentStyle: Color {
        isUser ? .white.opacity(0.55) : .secondary.opacity(0.45)
    }

    private var blockQuoteBackgroundStyle: Color {
        isUser ? .white.opacity(0.12) : .secondary.opacity(0.09)
    }

    private var listMarkerForegroundStyle: Color {
        isUser ? .white.opacity(0.78) : .secondary
    }

    private var checkboxCheckedForegroundStyle: Color {
        isUser ? .white : .accentColor
    }

    private var tableHeaderForegroundStyle: Color {
        isUser ? .white : .primary
    }

    private var tableBackgroundStyle: Color {
        isUser ? .white.opacity(0.08) : .secondary.opacity(0.06)
    }

    private var tableHeaderBackgroundStyle: Color {
        isUser ? .white.opacity(0.12) : .secondary.opacity(0.11)
    }

    private var tableBorderStyle: Color {
        isUser ? .white.opacity(0.18) : .secondary.opacity(0.2)
    }

    private var tableDividerStyle: Color {
        isUser ? .white.opacity(0.16) : .secondary.opacity(0.18)
    }

    private var textLineSpacing: CGFloat {
        switch style {
        case .standard:
            return isUser ? 1 : 3
        case .reasoning:
            return 2
        }
    }

    private func headingTopPadding(level: Int) -> CGFloat {
        switch style {
        case .standard:
            return level == 1 ? 8 : 6
        case .reasoning:
            return 4
        }
    }

    private func headingBottomPadding(level: Int) -> CGFloat {
        switch style {
        case .standard:
            return level == 1 ? 6 : 4
        case .reasoning:
            return 3
        }
    }

    private func textBlockBottomPadding(for value: String) -> CGFloat {
        value.isEmpty ? textFontLinePadding : 0
    }

    private var textFontLinePadding: CGFloat {
        switch style {
        case .standard:
            return 7
        case .reasoning:
            return 5
        }
    }

    private var blockQuoteVerticalPadding: CGFloat {
        switch style {
        case .standard:
            return 8
        case .reasoning:
            return 6
        }
    }

    private var blockQuoteOuterPadding: CGFloat {
        switch style {
        case .standard:
            return 4
        case .reasoning:
            return 3
        }
    }

    private var listMarkerFont: Font {
        switch style {
        case .standard:
            return .body.weight(.semibold)
        case .reasoning:
            return .caption.weight(.semibold)
        }
    }

    private var checkboxMarkerFont: Font {
        switch style {
        case .standard:
            return .body
        case .reasoning:
            return .caption
        }
    }

    private func listMarkerWidth(for marker: ListMarker) -> CGFloat {
        switch marker {
        case .unordered, .checkbox:
            return 18
        case let .ordered(value):
            return max(22, CGFloat(value.count) * 8)
        }
    }

    private var listItemVerticalPadding: CGFloat {
        switch style {
        case .standard:
            return 2
        case .reasoning:
            return 1
        }
    }

    private var tableHeaderFont: Font {
        switch style {
        case .standard:
            return .body.weight(.semibold)
        case .reasoning:
            return .caption.weight(.semibold)
        }
    }

    private var tableCellMinWidth: CGFloat {
        switch style {
        case .standard:
            return 96
        case .reasoning:
            return 82
        }
    }

    private var tableCellMaxWidth: CGFloat {
        switch style {
        case .standard:
            return 260
        case .reasoning:
            return 220
        }
    }

    private var tableOuterPadding: CGFloat {
        switch style {
        case .standard:
            return 5
        case .reasoning:
            return 4
        }
    }

    private var tableHorizontalScrollBleed: CGFloat {
        isUser ? 0 : 16
    }

    private var codeBlockOuterPadding: CGFloat {
        switch style {
        case .standard:
            return 5
        case .reasoning:
            return 4
        }
    }
}

@MainActor
fileprivate final class OpenCodeMarkdownRenderCache {
    static let shared = OpenCodeMarkdownRenderCache()

    private var blocksByText: [String: [MarkdownMessageText.MarkdownBlock]] = [:]
    private var inlineMarkdownByText: [String: AttributedString] = [:]

    func blocks(for text: String, build: () -> [MarkdownMessageText.MarkdownBlock]) -> [MarkdownMessageText.MarkdownBlock] {
        if let cached = blocksByText[text] {
            return cached
        }

        let blocks = build()
        if text.count <= 24_000 {
            trimIfNeeded(&blocksByText, limit: 220)
            blocksByText[text] = blocks
        }
        return blocks
    }

    func inlineMarkdown(for text: String) -> AttributedString? {
        if let cached = inlineMarkdownByText[text] {
            return cached
        }

        guard text.count <= 4_000,
              let attributed = try? AttributedString(
                  markdown: text,
                  options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              ) else {
            return nil
        }

        trimIfNeeded(&inlineMarkdownByText, limit: 600)
        inlineMarkdownByText[text] = attributed
        return attributed
    }

    private func trimIfNeeded<Value>(_ cache: inout [String: Value], limit: Int) {
        if cache.count >= limit {
            cache.removeAll(keepingCapacity: true)
        }
    }
}

private struct ConditionalTextSelectionModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

#if canImport(UIKit)
private struct NativeStreamingChunkTextLabel: UIViewRepresentable {
    let text: String
    let isUser: Bool
    let style: MarkdownMessageText.Style
    let lineSpacing: CGFloat
    let animationID: String?

    func makeUIView(context: Context) -> StreamingChunkUILabel {
        let label = StreamingChunkUILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: StreamingChunkUILabel, context: Context) {
        label.configure(
            text: text,
            font: uiFont,
            textColor: uiTextColor,
            lineSpacing: lineSpacing,
            animationID: animationID
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: StreamingChunkUILabel, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    static func dismantleUIView(_ label: StreamingChunkUILabel, coordinator: ()) {
        label.stopAnimatingChunks()
    }

    private var uiFont: UIFont {
        switch style {
        case .standard:
            return UIFont.preferredFont(forTextStyle: .body)
        case .reasoning:
            return UIFont.preferredFont(forTextStyle: .caption1)
        }
    }

    private var uiTextColor: UIColor {
        if isUser { return .white }

        switch style {
        case .standard:
            return .label
        case .reasoning:
            return .secondaryLabel
        }
    }
}

@MainActor
final class StreamingChunkAnimationCache {
    struct FadingChunk: Equatable {
        let range: NSRange
        let startedAt: CFTimeInterval
    }

    struct Snapshot: Equatable {
        let chunks: [FadingChunk]
    }

    private struct Entry {
        var text: String
        var chunks: [FadingChunk]
        var lastAccess: UInt64
    }

    static let shared = StreamingChunkAnimationCache()
    static let fadeDuration: CFTimeInterval = 0.32

    private var entries: [String: Entry] = [:]
    private var accessCounter: UInt64 = 0

    func snapshot(
        animationID: String,
        text: String,
        animatesAppend: Bool,
        at time: CFTimeInterval
    ) -> Snapshot {
        accessCounter &+= 1
        var entry = entries[animationID] ?? Entry(text: "", chunks: [], lastAccess: accessCounter)
        entry.chunks.removeAll { time - $0.startedAt >= Self.fadeDuration }
        if !animatesAppend {
            entry.chunks.removeAll(keepingCapacity: true)
        }

        if entry.text != text {
            let previousUTF16Length = (entry.text as NSString).length
            let currentUTF16Length = (text as NSString).length
            if animatesAppend, text.hasPrefix(entry.text), currentUTF16Length > previousUTF16Length {
                entry.chunks.append(FadingChunk(
                    range: NSRange(
                        location: previousUTF16Length,
                        length: currentUTF16Length - previousUTF16Length
                    ),
                    startedAt: time
                ))
            } else {
                entry.chunks.removeAll(keepingCapacity: true)
            }
            entry.text = text
        }

        entry.lastAccess = accessCounter
        entries[animationID] = entry
        trimIfNeeded()
        return Snapshot(chunks: entry.chunks)
    }

    private func trimIfNeeded() {
        guard entries.count > 600 else { return }
        let expiredIDs = entries
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
            .prefix(150)
            .map(\.key)
        for id in expiredIDs {
            entries.removeValue(forKey: id)
        }
    }
}

private final class StreamingChunkUILabel: UILabel {
    private var configuredText = ""
    private var configuredFont: UIFont?
    private var configuredTextColor: UIColor?
    private var configuredLineSpacing: CGFloat = 0
    private var configuredAnimationID: String?
    private var fadingChunks: [StreamingChunkAnimationCache.FadingChunk] = []
    private var displayLink: CADisplayLink?
    private let fallbackAnimationID = UUID().uuidString

    private let chunkMinimumOpacity: CGFloat = 0.08

    func configure(text: String, font: UIFont, textColor: UIColor, lineSpacing: CGFloat, animationID: String?) {
        guard configuredText != text
                || configuredFont != font
                || configuredTextColor != textColor
                || configuredLineSpacing != lineSpacing
                || configuredAnimationID != animationID else {
            return
        }

        let now = CACurrentMediaTime()
        configuredText = text
        configuredFont = font
        configuredTextColor = textColor
        configuredLineSpacing = lineSpacing
        configuredAnimationID = animationID

        let snapshot = StreamingChunkAnimationCache.shared.snapshot(
            animationID: animationID ?? fallbackAnimationID,
            text: text,
            animatesAppend: !UIAccessibility.isReduceMotionEnabled,
            at: now
        )
        fadingChunks = snapshot.chunks

        if !fadingChunks.isEmpty {
            renderText(at: now)
            startDisplayLink()
        } else {
            renderText(at: now)
            stopAnimatingChunks()
        }
    }

    func stopAnimatingChunks() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func renderText(at time: CFTimeInterval) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = configuredLineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        let color = configuredTextColor ?? .label
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: configuredFont ?? UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let attributed = NSMutableAttributedString(string: configuredText, attributes: baseAttributes)
        for chunk in fadingChunks {
            let elapsed = max(0, time - chunk.startedAt)
            let linear = min(1, elapsed / StreamingChunkAnimationCache.fadeDuration)
            let eased = 1 - pow(1 - linear, 2.2)
            let opacity = chunkMinimumOpacity + (1 - chunkMinimumOpacity) * CGFloat(eased)
            attributed.addAttribute(
                .foregroundColor,
                value: color.withAlphaComponent(opacity),
                range: chunk.range
            )
        }
        attributedText = attributed
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkDidTick() {
        let now = CACurrentMediaTime()
        removeCompletedChunks(at: now)
        renderText(at: now)

        if fadingChunks.isEmpty {
            stopAnimatingChunks()
        }
    }

    private func removeCompletedChunks(at time: CFTimeInterval) {
        fadingChunks.removeAll { time - $0.startedAt >= StreamingChunkAnimationCache.fadeDuration }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        if preferredMaxLayoutWidth != width {
            preferredMaxLayoutWidth = width
            invalidateIntrinsicContentSize()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimatingChunks()
        } else if !fadingChunks.isEmpty {
            startDisplayLink()
        }
    }
}
#endif
