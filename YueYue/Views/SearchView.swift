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
        LogManager.shared.add("开始搜索: \(keyword), 源: \(rule.name)", level: .info)
        
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let baseURL = URL(string: rule.baseURL) else {
            LogManager.shared.add("无效的 baseURL: \(rule.baseURL)", level: .error)
            throw URLError(.badURL)
        }
        let searchURL = baseURL.appendingPathComponent(rule.searchRule.url)
        
        var request = URLRequest(url: searchURL)
        request.httpMethod = rule.searchRule.method?.uppercased() ?? "GET"
        
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        
        if request.httpMethod == "POST", let bodyTemplate = rule.searchRule.body {
            let bodyString = bodyTemplate.replacingOccurrences(of: "%@", with: encodedKeyword)
            request.httpBody = bodyString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else if request.httpMethod == "GET" {
            let paramName = rule.searchRule.body ?? "q"
            var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: paramName, value: encodedKeyword))
            components?.queryItems = queryItems
            request.url = components?.url
        }
        
        // 记录请求详情
        LogManager.shared.add("请求方法: \(request.httpMethod ?? "")", level: .debug)
        LogManager.shared.add("请求 URL: \(request.url?.absoluteString ?? "")", level: .debug)
        if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            LogManager.shared.add("请求 Body: \(bodyStr)", level: .debug)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            LogManager.shared.add("无效的HTTP响应", level: .error)
            throw URLError(.badServerResponse)
        }
        LogManager.shared.add("响应状态码: \(httpResponse.statusCode)", level: .info)
        
        guard let html = String(data: data, encoding: .utf8) else {
            LogManager.shared.add("网页编码不是 UTF-8", level: .error)
            throw NSError(domain: "SearchService", code: 1, userInfo: [NSLocalizedDescriptionKey: "网页编码不是 UTF-8"])
        }
        
        let doc = try SwiftSoup.parse(html)
        let elements = try doc.select(rule.searchRule.list)
        var results: [SearchResult] = []
        for element in elements {
            let titleElem = try element.select(rule.searchRule.title).first()
            let title = try titleElem?.text() ?? ""
            let href = try titleElem?.attr(rule.searchRule.urlAttr) ?? ""
            let fullUrl = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
            if !title.isEmpty && !fullUrl.isEmpty {
                results.append(SearchResult(title: title, url: fullUrl, author: nil, coverData: nil))
            }
        }
        LogManager.shared.add("找到 \(results.count) 个搜索结果", level: .info)
        return (results, html)
    }
}