import Foundation

// MARK: - 源规则模型
struct Rule: Codable {
    let name: String
    let type: String          // "novel" 或 "comic"
    let baseURL: String
    let searchRule: SearchRule
    let chapterRule: ChapterRule
    let contentRule: ContentRule
    let discover: DiscoverRule?  // 可选，用于分类发现
}

struct SearchRule: Codable {
    let url: String
    let method: String?          // GET 或 POST，默认 GET
    let body: String?            // POST 时的 body 模板，使用 %@ 占位关键词
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

struct DiscoverRule: Codable {
    let categories: [String: String]
    let list: String
    let title: String
    let urlAttr: String
}