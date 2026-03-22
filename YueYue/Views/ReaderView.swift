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
        
        let fetcher = ContentFetcher()
        // 注意：实际应动态获取章节URL，这里仅为示例
        let chapterURL = "\(rule.baseURL)/chapter/1" 
        do {
            content = try await fetcher.fetchNovelContent(url: chapterURL, rule: rule.contentRule)
            isLoading = false
        } catch {
            content = "加载失败：\(error.localizedDescription)"
            isLoading = false
        }
    }
}