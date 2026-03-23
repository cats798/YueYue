import SwiftUI
import CoreData
import SwiftSoup

struct SearchView: View {
    let source: Source
    @State private var keyword = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            HStack {
                TextField("输入书名", text: $keyword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit { search() }
                Button("搜索") { search() }
                    .disabled(keyword.isEmpty || isLoading)
            }
            .padding()
            
            if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                List(searchResults) { result in
                    Button {
                        addToBookshelf(result)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.author ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .alert("搜索失败", isPresented: .constant(errorMessage != nil), actions: {
            Button("确定") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }
    
    private func search() {
        guard let ruleData = source.ruleData,
              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData) else {
            errorMessage = "源规则无效"
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let results = try await SearchService.search(keyword: keyword, rule: rule)
                await MainActor.run {
                    searchResults = results
                    isLoading = false
                    if results.isEmpty {
                        errorMessage = "未找到相关小说"
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "搜索失败：\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func addToBookshelf(_ result: SearchResult) {
        let book = Book(context: viewContext)
        book.title = result.title
        book.type = source.type
        book.source = source
        book.bookURL = result.url
        book.currentChapter = 0
        book.progress = 0
        if let coverData = result.coverData {
            book.cover = coverData
        }
        try? viewContext.save()
        dismiss()
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let url: String
    let author: String?
    let coverData: Data?
}

class SearchService {
    static func search(keyword: String, rule: Rule) async throws -> [SearchResult] {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = rule.baseURL + String(format: rule.searchRule.url, encodedKeyword)
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        // 调试：打印请求 URL
        print("搜索URL: \(urlString)")
        
        let html = try await fetchHTML(url: url)
        
        // 调试：打印 HTML 开头（可选）
        // print("HTML: \(html.prefix(500))")
        
        let doc = try SwiftSoup.parse(html)
        let elements = try doc.select(rule.searchRule.list)
        
        var results: [SearchResult] = []
        for element in elements {
            let titleElem = try element.select(rule.searchRule.title).first()
            let title = try titleElem?.text() ?? ""
            let urlAttr = rule.searchRule.urlAttr
            let href = try titleElem?.attr(urlAttr) ?? ""
            let fullUrl = URL(string: href, relativeTo: URL(string: rule.baseURL))?.absoluteString ?? href
            results.append(SearchResult(title: title, url: fullUrl, author: nil, coverData: nil))
        }
        return results
    }
    
    private static func fetchHTML(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SearchService", code: 1, userInfo: [NSLocalizedDescriptionKey: "网页编码不是 UTF-8"])
        }
        return html
    }
}