import SwiftUI
import CoreData

struct AggregateSearchView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Source.name, ascending: true)],
        animation: .default)
    private var sources: FetchedResults<Source>
    
    @State private var keyword = ""
    @State private var isLoading = false
    @State private var resultsBySource: [NSManagedObjectID: [SearchResult]] = [:]
    @State private var errorMessages: [String] = []
    
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
                List {
                    ForEach(sources) { source in
                        if let results = resultsBySource[source.objectID], !results.isEmpty {
                            Section(header: Text(source.name ?? "未知源")) {
                                ForEach(results) { result in
                                    Button {
                                        addToBookshelf(result, source: source)
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
                        } else if resultsBySource[source.objectID] == nil {
                            // 尚未搜索该源，不显示
                            EmptyView()
                        } else {
                            Section(header: Text(source.name ?? "未知源")) {
                                Text("未找到结果")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .navigationTitle("聚合搜索")
    }
    
    private func search() {
        isLoading = true
        resultsBySource = [:]
        errorMessages = []
        
        Task {
            await withTaskGroup(of: (NSManagedObjectID, [SearchResult], String?).self) { group in
                for source in sources {
                    group.addTask {
                        guard let ruleData = source.ruleData,
                              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData) else {
                            return (source.objectID, [], "源规则无效")
                        }
                        do {
                            let (results, _) = try await SearchService.searchWithHtml(keyword: keyword, rule: rule)
                            return (source.objectID, results, nil)
                        } catch {
                            return (source.objectID, [], error.localizedDescription)
                        }
                    }
                }
                
                for await (id, results, error) in group {
                    await MainActor.run {
                        resultsBySource[id] = results
                        if let error = error {
                            errorMessages.append(error)
                        }
                    }
                }
            }
            isLoading = false
        }
    }
    
    private func addToBookshelf(_ result: SearchResult, source: Source) {
        let book = Book(context: viewContext)
        book.title = result.title
        book.type = source.type
        book.source = source
        book.bookURL = result.url
        book.currentChapter = 0
        book.progress = 0
        try? viewContext.save()
        // 可选：显示提示
    }
}