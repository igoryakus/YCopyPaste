import AppKit
import CryptoKit

/// Определяет тип содержимого буфера, текст для поиска и хэш для схлопывания повторов.
enum ClipClassifier {
    static func make(payload: ClipPayload, sourceBundle: String?, sourceName: String?) -> CapturedClip? {
        guard let first = payload.first else { return nil }

        func data(_ type: String, in entries: [PasteboardEntry]) -> Data? {
            entries.first { $0.type == type }?.data
        }

        let total = payload.reduce(0) { $0 + $1.reduce(0) { $0 + $1.data.count } }
        guard total <= PasteboardTypes.maxTotalBytes else { return nil }

        let fileURLs: [URL] = payload.compactMap { entries in
            guard let d = data(PasteboardTypes.fileURL, in: entries),
                  let s = String(data: d, encoding: .utf8) else { return nil }
            return URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { $0.isFileURL }

        let string = data(PasteboardTypes.plainText, in: first).flatMap { String(data: $0, encoding: .utf8) }
        let imageData = PasteboardTypes.imageTypes.lazy.compactMap { data($0, in: first) }.first
        let isRich = [PasteboardTypes.rtf, PasteboardTypes.rtfd, PasteboardTypes.html].contains { data($0, in: first) != nil }

        let kind: ClipKind
        let text: String
        let hashBasis: Data

        if !fileURLs.isEmpty {
            kind = .file
            text = fileURLs.map(\.path).joined(separator: "\n")
            hashBasis = Data(("file:" + text).utf8)
        } else if let s = string, !s.isEmpty {
            text = s
            kind = isURL(s) ? .url : (isRich ? .rich : .text)
            hashBasis = Data(("text:" + s).utf8)
        } else if let img = imageData {
            kind = .image
            if let rep = NSBitmapImageRep(data: img) {
                text = "Изображение \(rep.pixelsWide)×\(rep.pixelsHigh)"
            } else {
                text = "Изображение"
            }
            hashBasis = img
        } else if let rtf = data(PasteboardTypes.rtf, in: first),
                  let attr = NSAttributedString(rtf: rtf, documentAttributes: nil),
                  !attr.string.isEmpty {
            kind = .rich
            text = attr.string
            hashBasis = Data(("text:" + text).utf8)
        } else {
            return nil
        }

        let digest = SHA256.hash(data: hashBasis)
        let hash = String(kind.rawValue.prefix(1)) + digest.map { String(format: "%02x", $0) }.joined()

        return CapturedClip(kind: kind, text: text, hash: hash, payload: payload,
                            sourceBundle: sourceBundle, sourceName: sourceName, byteSize: total)
    }

    static func isURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 2048, t.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: t), let scheme = url.scheme?.lowercased() else { return false }
        if ["http", "https", "ftp"].contains(scheme) { return url.host != nil }
        return ["mailto", "tel"].contains(scheme)
    }
}
