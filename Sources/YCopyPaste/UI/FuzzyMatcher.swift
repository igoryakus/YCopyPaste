import Foundation

/// Нечёткий поиск: каждое слово запроса должно встретиться в тексте
/// подстрокой (высокий вес) или подпоследовательностью символов (низкий вес).
enum FuzzyMatcher {
    static func score(query: String, text: String) -> Int? {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return 0 }
        let haystack = String(text.prefix(5000)).lowercased()
        var total = 0
        for token in tokens {
            guard let s = tokenScore(String(token), in: haystack) else { return nil }
            total += s
        }
        return total
    }

    private static func tokenScore(_ token: String, in text: String) -> Int? {
        if let range = text.range(of: token) {
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            var s = 1000 - min(offset, 500)
            if offset == 0 { s += 300 }
            else {
                let prev = text[text.index(before: range.lowerBound)]
                if !prev.isLetter && !prev.isNumber { s += 150 } // начало слова
            }
            return s
        }
        // Подпоследовательность: «gtcm» найдёт «git commit».
        var score = 0
        var streak = 0
        var ti = text.startIndex
        for ch in token {
            var found = false
            while ti < text.endIndex {
                let c = text[ti]
                ti = text.index(after: ti)
                if c == ch {
                    streak += 1
                    score += 10 * streak
                    found = true
                    break
                } else {
                    streak = 0
                }
            }
            if !found { return nil }
        }
        return score
    }
}
