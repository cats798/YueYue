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
    @State private var selectedSourceResults: [NSManagedObjectID: [SearchResult]] = [:]
    @State private var sourceErrors: [NSManagedObjectID: String] = [:]
    
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
                        if let results = selectedSourceResults[source.objectID], !results.isEmpty {
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
                        } else if let error = sourceErrors[source.objectID] {
                            Section(header: Text(source.name ?? "未知源")) {
                                Text("搜索失败: \(error)")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        } else if selectedSourceResults[source.objectID] != nil {
                            Section(header: Text(source.name ?? "未知源")) {
                                Text("未找到结果")
                                    .foregroundColor(.secondary)
                            }
                        }
                        // 否则尚未搜索，不显示该源
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .navigationTitle("聚合搜索")
    }
    
    private func search() {
        isLoading = true
        selectedSourceResults = [:]
        sourceErrors = [:]
        
        Task {
            await withTaskGroup(of: (NSManagedObjectID, [SearchResult]?, String?).self) { group in
                for source in sources {
                    group.addTask {
                        do {
                            let ruleData = source.ruleData!
                            let rule = try JSONDecoder().decode(Rule.self, from: ruleData)
                            let (results, _) = try await SearchService.searchWithHtml(keyword: keyword, rule: rule)
                            return (source.objectID, results, nil)
                        } catch {
                            return (source.objectID, nil, error.localizedDescription)
                        }
                    }
                }
                
                for await (id, results, error) in group {
                    await MainActor.run {
                        if let results = results {
                            selectedSourceResults[id] = results
                        } else if let error = error {
                            sourceErrors[id] = error
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
        // 可添加提示，比如展示一个短暂的toast或简单alert
    }
}