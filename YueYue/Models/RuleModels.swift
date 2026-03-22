import Foundation

// MARK: - 源规则模型
struct Rule: Codable {
    let name: String
    let type: String          // "novel" 或 "comic"
    let baseURL: String
    let searchRule: SearchRule
    let chapterRule: ChapterRule
    let contentRule: ContentRule
}

struct SearchRule: Codable {
    let url: String
    let list: String
    let title: String
    let urlAttr: String
}

struct ChapterRule: Codable {
    let list: String
    let title: String
    let urlAttr: String
}

struct ContentRule: Codable {
    let selector: String
    let text: String          // "text" 或 "html"
}