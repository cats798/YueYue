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
        isLoading = true
        errorMessage = nil
        debugHtml = nil
        Task {
            do {
                let (results, html) = try await SearchService.searchWithHtml(keyword: keyword, source: source)
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
    static func searchWithHtml(keyword: String, source: Source) async throws -> ([SearchResult], String) {
        guard let searchURLString = source.searchURL,
              let method = source.searchMethod?.uppercased() else {
            throw NSError(domain: "Search", code: 1, userInfo: [NSLocalizedDescriptionKey: "源未配置搜索URL"])
        }
        
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        var request: URLRequest
        if method == "POST", let bodyTemplate = source.searchBody {
            let bodyString = bodyTemplate.replacingOccurrences(of: "%@", with: encodedKeyword)
            guard let url = URL(string: searchURLString) else { throw URLError(.badURL) }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else {
            // GET
            let paramName = source.searchBody ?? "q"
            let fullURLString = searchURLString + (searchURLString.contains("?") ? "&" : "?") + "\(paramName)=\(encodedKeyword)"
            guard let url = URL(string: fullURLString) else { throw URLError(.badURL) }
            request = URLRequest(url: url)
            request.httpMethod = "GET"
        }
        
        // 添加真实浏览器头
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Search", code: 2, userInfo: [NSLocalizedDescriptionKey: "网页编码不是 UTF-8"])
        }
        
        let doc = try SwiftSoup.parse(html)
        let listSelector = source.listSelector ?? ".result-list .item, .search-list .item"
        let titleSelector = source.titleSelector ?? "h3 a, .book-title a"
        let linkSelector = source.linkSelector ?? "a@href"
        
        let elements = try doc.select(listSelector)
        var results: [SearchResult] = []
        for element in elements {
            let titleElem = try element.select(titleSelector).first()
            let title = try titleElem?.text() ?? ""
            let href = try titleElem?.attr(linkSelector) ?? ""
            let baseURL = source.searchURL.flatMap { URL(string: $0)?.deletingLastPathComponent() }
            let fullUrl = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
            if !title.isEmpty && !fullUrl.isEmpty {
                results.append(SearchResult(title: title, url: fullUrl, author: nil, coverData: nil))
            }
        }
        return (results, html)
    }
}