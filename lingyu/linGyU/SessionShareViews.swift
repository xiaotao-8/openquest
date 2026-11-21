import SwiftUI
import UIKit

/// Renders a chat timeline into one shareable image (FishPocket
/// ConversationShareCard.draw, reimplemented): a header with the bot
/// name and date, then one block per message — user messages in a grey
/// bubble on the right, agent messages as plain text on the left, tool
/// rows as small grey lines, notices centred. Drawn with Core
/// Graphics, never a screenshot, so the image is identical on every
/// device. Light palette only: the shared image is a document, not UI.
enum SessionShareImageRenderer {
    static let maxEntries = 200
    private static let maxHeight: CGFloat = 12000

    private enum Kind { case user, agent, tool, notice, question }

    private struct Row {
        var kind: Kind
        var text: String
        var author: String?
    }

    private struct Measured {
        var row: Row
        var height: CGFloat
        var textSize: CGSize
        var textWidth: CGFloat
    }

    static func render(botName: String, entries: [Entry], authorName: (Entry) -> String) -> UIImage {
        var rows: [Row] = []
        for entry in entries.suffix(maxEntries) {
            switch entry.kind {
            case "user":
                if let text = entry.data.text, !text.isEmpty {
                    rows.append(Row(kind: .user, text: text, author: nil))
                }
            case "agent":
                if let text = entry.data.text, !text.isEmpty {
                    rows.append(Row(kind: .agent, text: text, author: authorName(entry)))
                }
            case "tool", "call":
                if let title = entry.data.title, !title.isEmpty {
                    rows.append(Row(kind: .tool, text: title, author: nil))
                }
            case "notice":
                if let text = entry.data.text, !text.isEmpty {
                    rows.append(Row(kind: .notice, text: text, author: nil))
                }
            case "permission":
                if let question = entry.data.question, !question.isEmpty {
                    rows.append(Row(kind: .question, text: question, author: nil))
                } else if let title = entry.data.title, !title.isEmpty {
                    rows.append(Row(kind: .tool, text: title, author: nil))
                }
            default:
                break
            }
        }

        let width: CGFloat = 750
        let margin: CGFloat = 40
        let contentWidth = width - margin * 2
        let titleFont = UIFont.systemFont(ofSize: 36, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 24)
        let bodyFont = UIFont.systemFont(ofSize: 27)
        let smallFont = UIFont.systemFont(ofSize: 23)
        let smallSemiboldFont = UIFont.systemFont(ofSize: 23, weight: .semibold)
        let footerFont = UIFont.systemFont(ofSize: 22)
        let ink = UIColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
        let secondary = UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6B / 255, alpha: 1)
        let userBubble = UIColor(red: 0xE2 / 255, green: 0xE2 / 255, blue: 0xE2 / 255, alpha: 1)
        let cardFill = UIColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255, alpha: 1)
        let lineColor = UIColor(red: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE6 / 255, alpha: 1)
        let rowGap: CGFloat = 26

        let dateText = shareDateString()

        // Measure every row first, then drop the oldest rows until the
        // image fits the height cap (the newest messages are kept).
        var measured: [Measured] = []
        for row in rows {
            switch row.kind {
            case .user:
                let maxTextWidth = contentWidth - 140
                let size = textSize(row.text, font: bodyFont, maxWidth: maxTextWidth)
                measured.append(Measured(row: row, height: size.height + 32, textSize: size, textWidth: size.width))
            case .agent:
                var height: CGFloat = 0
                if let author = row.author, !author.isEmpty {
                    height += textSize(author, font: smallSemiboldFont, maxWidth: contentWidth).height + 6
                }
                let size = textSize(row.text, font: bodyFont, maxWidth: contentWidth)
                height += size.height
                measured.append(Measured(row: row, height: height, textSize: size, textWidth: size.width))
            case .tool:
                let size = textSize(row.text, font: smallFont, maxWidth: contentWidth)
                measured.append(Measured(row: row, height: size.height, textSize: size, textWidth: size.width))
            case .notice:
                let size = textSize(row.text, font: smallFont, maxWidth: contentWidth)
                measured.append(Measured(row: row, height: size.height, textSize: size, textWidth: size.width))
            case .question:
                let size = textSize(row.text, font: bodyFont, maxWidth: contentWidth - 40)
                measured.append(Measured(row: row, height: size.height + 40, textSize: size, textWidth: size.width))
            }
        }

        let headerHeight = margin
            + textSize(botName, font: titleFont, maxWidth: contentWidth).height + 8
            + textSize(dateText, font: subtitleFont, maxWidth: contentWidth).height + 16
            + 1 + 30
        let footerHeight: CGFloat = 1 + 16 + footerFont.lineHeight + 8 + footerFont.lineHeight + margin
        var totalHeight = headerHeight + footerHeight
        if measured.isEmpty {
            totalHeight += textSize(L("还没有消息。"), font: bodyFont, maxWidth: contentWidth).height + rowGap
        } else {
            for item in measured { totalHeight += item.height + rowGap }
        }
        while totalHeight > maxHeight, measured.count > 1 {
            let dropped = measured.removeFirst()
            totalHeight -= dropped.height + rowGap
        }
        let renderedCount = measured.count
        let truncated = renderedCount < entries.count

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: totalHeight), format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))
            var y = margin
            drawText(botName, font: titleFont, color: ink, rect: CGRect(x: margin, y: y, width: contentWidth, height: titleFont.lineHeight))
            y += textSize(botName, font: titleFont, maxWidth: contentWidth).height + 8
            drawText(dateText, font: subtitleFont, color: secondary, rect: CGRect(x: margin, y: y, width: contentWidth, height: subtitleFont.lineHeight))
            y += textSize(dateText, font: subtitleFont, maxWidth: contentWidth).height + 16
            lineColor.setFill()
            context.fill(CGRect(x: margin, y: y, width: contentWidth, height: 1))
            y += 1 + 30

            if measured.isEmpty {
                drawText(L("还没有消息。"), font: bodyFont, color: secondary, rect: CGRect(x: margin, y: y, width: contentWidth, height: bodyFont.lineHeight))
                y += bodyFont.lineHeight + rowGap
            }
            for item in measured {
                let row = item.row
                switch row.kind {
                case .user:
                    let bubbleWidth = item.textWidth + 44
                    let bubbleX = width - margin - bubbleWidth
                    let bubbleRect = CGRect(x: bubbleX, y: y, width: bubbleWidth, height: item.height)
                    UIBezierPath(roundedRect: bubbleRect, cornerRadius: 26).fill(with: userBubble)
                    drawText(row.text, font: bodyFont, color: ink, rect: CGRect(x: bubbleX + 22, y: y + 16, width: item.textWidth, height: item.textSize.height))
                case .agent:
                    var bodyY = y
                    if let author = row.author, !author.isEmpty {
                        let authorHeight = textSize(author, font: smallSemiboldFont, maxWidth: contentWidth).height
                        drawText(author, font: smallSemiboldFont, color: secondary, rect: CGRect(x: margin, y: y, width: contentWidth, height: authorHeight))
                        bodyY = y + authorHeight + 6
                    }
                    drawText(row.text, font: bodyFont, color: ink, rect: CGRect(x: margin, y: bodyY, width: contentWidth, height: item.textSize.height))
                case .tool:
                    drawText(row.text, font: smallFont, color: secondary, rect: CGRect(x: margin, y: y, width: contentWidth, height: item.textSize.height))
                case .notice:
                    drawText(row.text, font: smallFont, color: secondary, rect: CGRect(x: margin, y: y, width: contentWidth, height: item.textSize.height), alignment: .center)
                case .question:
                    let boxRect = CGRect(x: margin, y: y, width: contentWidth, height: item.height)
                    UIBezierPath(roundedRect: boxRect, cornerRadius: 16).fill(with: cardFill)
                    drawText(row.text, font: bodyFont, color: ink, rect: CGRect(x: margin + 20, y: y + 20, width: contentWidth - 40, height: item.textSize.height))
                }
                y += item.height + rowGap
            }

            lineColor.setFill()
            context.fill(CGRect(x: margin, y: y, width: contentWidth, height: 1))
            y += 1 + 16
            drawText("Codync · \(dateText)", font: footerFont, color: secondary, rect: CGRect(x: margin, y: y, width: contentWidth, height: footerFont.lineHeight))
            y += footerFont.lineHeight + 8
            if truncated {
                drawText(L("仅显示最近 %d 条", renderedCount), font: footerFont, color: secondary, rect: CGRect(x: margin, y: y, width: contentWidth, height: footerFont.lineHeight))
            }
        }
    }

    private static func shareDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    private static func paragraph(alignment: NSTextAlignment = .left) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = alignment
        return style
    }

    private static func textSize(_ text: String, font: UIFont, maxWidth: CGFloat) -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph()],
            context: nil)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private static func drawText(_ text: String, font: UIFont, color: UIColor, rect: CGRect, alignment: NSTextAlignment = .left) {
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph(alignment: alignment),
        ])
    }
}

private extension UIBezierPath {
    /// Fills the path with a colour (UIBezierPath has no fill(with:)).
    func fill(with color: UIColor) {
        color.setFill()
        fill()
    }
}

/// The plain-text log of a session: one line per entry, newest last,
/// with a header naming the bot and the session id.
enum SessionShareLog {
    static func text(botName: String, sessionId: String, entries: [Entry], authorName: (Entry) -> String) -> String {
        var lines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        lines.append(botName)
        lines.append("\(L("会话 ID"))：\(sessionId)")
        lines.append(dateFormatter.string(from: Date()))
        lines.append("")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        for entry in entries {
            let time = timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.createdAt) / 1000))
            switch entry.kind {
            case "user":
                if let text = entry.data.text, !text.isEmpty {
                    lines.append("[\(time)] \(L("你"))：\(text)")
                }
            case "agent":
                if let text = entry.data.text, !text.isEmpty {
                    lines.append("[\(time)] \(authorName(entry))：\(text)")
                }
            case "tool", "call":
                if let title = entry.data.title, !title.isEmpty {
                    lines.append("[\(time)] \(L("工具调用"))：\(title)")
                }
            case "notice":
                if let text = entry.data.text, !text.isEmpty {
                    lines.append("[\(time)] \(text)")
                }
            case "permission":
                if let question = entry.data.question, !question.isEmpty {
                    lines.append("[\(time)] \(question)")
                } else if let title = entry.data.title, !title.isEmpty {
                    lines.append("[\(time)] \(L("工具调用"))：\(title)")
                }
            default:
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// The system share sheet for an image or a text log.
struct ActivityShareView: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
