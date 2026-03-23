import SwiftUI
import CoreData
import SwiftSoup

struct SearchView: View {
    let source: Source
    @State private var keyword = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var debugHtml: String?
    @State private var showDebug = false
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
                VStack {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                    if debugHtml != nil {
                        Button("查看调试信息") {
                            showDebug = true
                        }
                        .font(.caption)
                    }
                }
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
        .sheet(isPresented: $showDebug) {
            NavigationView {
                ScrollView {
                    Text(debugHtml ?? "无数据")
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                .navigationTitle("HTML 调试")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showDebug = false }
                    }
                }
            }
        }
    }
    
    private func search() {
        guard let ruleData = source.ruleData,
              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData) else {
            errorMessage = "源规则无效"
            return
        }
        isLoading = true
        errorMessage = nil
        debugHtml = nil
        Task {
            do {
                let (results, html) = try await SearchService.searchWithHtml(keyword: keyword, rule: rule)
                await MainActor.run {
                    searchResults = results
                    isLoading = false
                    if results.isEmpty {
                        errorMessage = "未找到相关小说"
                        debugHtml = html
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
    static func searchWithHtml(keyword: String, rule: Rule) async throws -> ([SearchResult], String) {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // 构建完整 URL
        let urlString = rule.baseURL + rule.searchRule.url
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        // 准备请求
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 5.2) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.122 Safari/534.30", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        // 判断请求方法
        let method = rule.searchRule.method?.uppercased() ?? "GET"
        request.httpMethod = method
        
        if method == "POST", let bodyTemplate = rule.searchRule.body {
            let bodyString = bodyTemplate.replacingOccurrences(of: "%@", with: encodedKeyword)
            request.httpBody = bodyString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else {
            // GET 请求，拼接 URL
            let fullURLString = urlString + (urlString.contains("?") ? "&" : "?") + String(format: rule.searchRule.url, encodedKeyword)
            request.url = URL(string: fullURLString)
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SearchService", code: 1, userInfo: [NSLocalizedDescriptionKey: "网页编码不是 UTF-8"])
        }
        
        let doc = try SwiftSoup.parse(html)
        let elements = try doc.select(rule.searchRule.list)
        
        var results: [SearchResult] = []
        for element in elements {
            let titleElem = try element.select(rule.searchRule.title).first()
            let title = try titleElem?.text() ?? ""
            let urlAttr = rule.searchRule.urlAttr
            let href = try titleElem?.attr(urlAttr) ?? ""
            let fullUrl = URL(string: href, relativeTo: URL(string: rule.baseURL))?.absoluteString ?? href
            if !title.isEmpty && !fullUrl.isEmpty {
                results.append(SearchResult(title: title, url: fullUrl, author: nil, coverData: nil))
            }
        }
        return (results, html)
    }
}