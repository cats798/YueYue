import SwiftUI
import CoreData
import SwiftSoup

struct ReaderView: View {
    let book: Book
    @State private var chapters: [Chapter] = []
    @State private var selectedChapter: Chapter?
    @State private var isLoading = true
    
    var body: some View {
        List(chapters) { chapter in
            Button(chapter.title) {
                selectedChapter = chapter
            }
            .foregroundColor(.primary)
        }
        .listStyle(.plain)
        .background(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.2)], startPoint: .top, endPoint: .bottom))
        .navigationTitle(book.title ?? "章节")
        .task {
            await loadChapters()
        }
        .sheet(item: $selectedChapter) { chapter in
            NavigationView {
                ChapterReaderView(chapter: chapter, source: book.source!)
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }
    
    private func loadChapters() async {
        guard let source = book.source,
              let ruleData = source.ruleData,
              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData),
              let bookURL = book.bookURL else {
            isLoading = false
            return
        }
        do {
            let html = try await fetchHTML(url: bookURL)
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(rule.chapterRule.list)
            var tempChapters: [Chapter] = []
            for element in elements {
                let titleElem = try element.select(rule.chapterRule.title).first()
                let title = try titleElem?.text() ?? ""
                let href = try titleElem?.attr(rule.chapterRule.urlAttr) ?? ""
                let fullUrl = URL(string: href, relativeTo: URL(string: rule.baseURL))?.absoluteString ?? href
                tempChapters.append(Chapter(title: title, url: fullUrl))
            }
            await MainActor.run {
                chapters = tempChapters
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
    
    private func fetchHTML(url: String) async throws -> String {
        guard let url = URL(string: url) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct Chapter: Identifiable {
    let id = UUID()
    let title: String
    let url: String
}

struct ChapterReaderView: View {
    let chapter: Chapter
    let source: Source
    @State private var content = ""
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
        .navigationTitle(chapter.title)
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        guard let ruleData = source.ruleData,
              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData) else { return }
        let fetcher = ContentFetcher()
        do {
            content = try await fetcher.fetchNovelContent(url: chapter.url, rule: rule.contentRule)
            isLoading = false
        } catch {
            content = "加载失败：\(error.localizedDescription)"
            isLoading = false
        }
    }
}