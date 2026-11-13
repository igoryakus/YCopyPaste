import Foundation

enum ClipKind: String {
    case text, url, rich, image, file

    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .rich: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var title: String {
        switch self {
        case .text: return "Текст"
        case .url: return "Ссылка"
        case .rich: return "Форматированный текст"
        case .image: return "Изображение"
        case .file: return "Файлы"
        }
    }
}

/// Одно представление данных в буфере (тип UTI + байты).
struct PasteboardEntry {
    let type: String
    let data: Data
}

/// Полное содержимое буфера: массив элементов буфера, у каждого — набор представлений.
typealias ClipPayload = [[PasteboardEntry]]

/// Элемент истории (метаданные без тяжёлых данных).
struct ClipItem: Identifiable, Hashable {
    let id: Int64
    var kind: ClipKind
    var text: String
    var hash: String
    var sourceBundle: String?
    var sourceName: String?
    var created: Date
    var used: Date
    var pinned: Bool
    var copyCount: Int
    var byteSize: Int

    /// Однострочный заголовок для списка.
    var displayTitle: String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(300)
            .replacingOccurrences(of: "\r\n", with: " ⏎ ")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
            .replacingOccurrences(of: "\t", with: " ")
        if collapsed.isEmpty { return kind == .text ? "(пробелы)" : kind.title }
        if kind == .file {
            let names = text.split(separator: "\n").map { ($0 as NSString).lastPathComponent }
            return names.joined(separator: ", ")
        }
        return collapsed
    }

    var filePaths: [String] {
        kind == .file ? text.split(separator: "\n").map(String.init) : []
    }
}

/// Только что захваченное содержимое буфера, ещё не сохранённое.
struct CapturedClip {
    let kind: ClipKind
    let text: String
    let hash: String
    let payload: ClipPayload
    let sourceBundle: String?
    let sourceName: String?
    let byteSize: Int
}
