import SwiftUI

struct ReaderView: View {
    let book: Book
    @State private var content: String = ""
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(content)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(LinearGradient(colors: [.black.opacity(0.8), .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        .navigationTitle(book.title ?? "阅读")
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        guard let source = book.source,
              let ruleData = source.ruleData,
              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData) else {
            content = "无效的源配置"
            isLoading = false
            return
        }
        
        // 示例：简单模拟获取内容，实际需根据源规则解析章节列表和正文
        let fetcher = ContentFetcher()
        let url = "\(rule.baseURL)/chapter/1" // 简化处理，实际应获取真实章节URL
        do {
            content = try await fetcher.fetchNovelContent(url: url, rule: rule.contentRule)
            isLoading = false
        } catch {
            content = "加载失败：\(error.localizedDescription)"
            isLoading = false
        }
    }
}

// 临时规则模型，后续可独立文件
struct Rule: Codable {
    let name: String
    let type: String
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
    let text: String
}