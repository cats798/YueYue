import Foundation
import SwiftSoup

class ContentFetcher {
    func fetchNovelContent(url: String, rule: ContentRule) async throws -> String {
        let html = try await fetchHTML(url: url)
        let doc = try SwiftSoup.parse(html)
        let elements = try doc.select(rule.selector)
        if rule.text == "html" {
            return try elements.html()
        } else {
            return try elements.text()
        }
    }
    
    private func fetchHTML(url: String) async throws -> String {
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ContentFetcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid encoding"])
        }
        return html
    }
}