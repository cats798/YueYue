import SwiftUI
import CoreData

struct SourceManagerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Source.name, ascending: true)],
        animation: .default)
    private var sources: FetchedResults<Source>
    
    @State private var showAddSource = false
    @State private var showQuickAdd = false
    @State private var quickURL = ""
    
    var body: some View {
        List {
            ForEach(sources) { source in
                VStack(alignment: .leading) {
                    Text(source.name ?? "未命名")
                        .font(.headline)
                    Text(source.type ?? "未知类型")
                        .font(.caption)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .padding(.vertical, 4)
                )
                .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteSources)
        }
        .listStyle(.plain)
        .background(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.2)], startPoint: .top, endPoint: .bottom))
        .navigationTitle("源管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("快速添加（网址）") { showQuickAdd = true }
                    Button("手动添加 JSON") { showAddSource = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceView()
        }
        .sheet(isPresented: $showQuickAdd) {
            NavigationView {
                Form {
                    TextField("输入网址，如 https://www.biquge365.net", text: $quickURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("添加") {
                        addSourceFromURL(quickURL)
                        showQuickAdd = false
                    }
                    .disabled(quickURL.isEmpty)
                }
                .navigationTitle("快速添加源")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showQuickAdd = false }
                    }
                }
            }
        }
    }
    
    private func deleteSources(offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(sources[index])
        }
        try? viewContext.save()
    }
    
    private func addSourceFromURL(_ urlString: String) {
        guard let url = URL(string: urlString), let host = url.host else { return }
        // 加载内置规则
        guard let builtinPath = Bundle.main.path(forResource: "BuiltinSources", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: builtinPath)),
              let builtin = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        var ruleJSON: [String: Any]? = nil
        for (domain, rule) in builtin {
            if host.contains(domain) || domain.contains(host) {
                ruleJSON = rule as? [String: Any]
                break
            }
        }
        guard let rule = ruleJSON else {
            // 简单提示，实际可以增加 Alert
            print("未找到匹配规则")
            return
        }
        let newSource = Source(context: viewContext)
        newSource.name = rule["name"] as? String ?? host
        newSource.type = rule["type"] as? String ?? "novel"
        if let ruleData = try? JSONSerialization.data(withJSONObject: rule) {
            newSource.ruleData = ruleData
        }
        try? viewContext.save()
    }
}