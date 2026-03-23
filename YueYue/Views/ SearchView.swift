import SwiftUI
import CoreData
import SwiftSoup

struct SearchView: View {
    let source: Source
    @State private var keyword = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isLoading = false
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
    }
    
    private func search() {
        guard let ruleData = source.ruleData,
              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData) else { return }
        isLoading = true
        Task {
            do {
                let results = try await SearchService.search(keyword: keyword, rule: rule)
                await MainActor.run {
                    searchResults = results
                    isLoading = false
                }
            } catch {
                await MainActor.run {
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
        let urlString = rule.baseURL + String(format: rule.searchRule.url, keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let html = try await fetchHTML(url: url)
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
        return String(data: data, encoding: .utf8) ?? ""
    }
}