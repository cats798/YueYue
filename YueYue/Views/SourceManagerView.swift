import SwiftUI
import CoreData
import SwiftSoup

extension Notification.Name {
    static let sourceAdded = Notification.Name("sourceAdded")
}

struct SourceManagerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Source.name, ascending: true)],
        animation: .default)
    private var sources: FetchedResults<Source>
    
    @State private var showAddSource = false
    @State private var showQuickAdd = false
    @State private var quickURL = ""
    @State private var alertMessage: String? = nil
    @State private var testingSourceID: NSManagedObjectID? = nil
    
    var body: some View {
        List {
            if sources.isEmpty {
                Text("暂无源，点击右上角 + 添加")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sources) { source in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(source.name ?? "未命名")
                                .font(.headline)
                            Text(source.type ?? "未知类型")
                                .font(.caption)
                        }
                        Spacer()
                        Button {
                            testLatency(for: source)
                        } label: {
                            if testingSourceID == source.objectID {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
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
        .alert(item: $alertMessage) { message in
            Alert(title: Text("提示"), message: Text(message), dismissButton: .default(Text("确定")))
        }
    }
    
    private func deleteSources(offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(sources[index])
        }
        try? viewContext.save()
    }
    
    private func addSourceFromURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            alertMessage = "无效的网址"
            return
        }
        
        Task {
            do {
                let (searchInfo, html) = try await detectSearchForm(from: url)
                await MainActor.run {
                    let newSource = Source(context: viewContext)
                    newSource.name = url.host ?? "未知源"
                    newSource.type = "novel"
                    newSource.searchURL = searchInfo.url
                    newSource.searchMethod = searchInfo.method
                    newSource.searchBody = searchInfo.bodyTemplate
                    newSource.listSelector = searchInfo.listSelector
                    newSource.titleSelector = searchInfo.titleSelector
                    newSource.linkSelector = searchInfo.linkSelector
                    
                    do {
                        try viewContext.save()
                        NotificationCenter.default.post(name: .sourceAdded, object: newSource)
                        showQuickAdd = false
                    } catch {
                        alertMessage = "保存失败：\(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = "自动探测失败：\(error.localizedDescription)\n请稍后再试或联系开发者"
                }
            }
        }
    }
    
    // 探测搜索表单
    private func detectSearchForm(from url: URL) async throws -> (url: String, method: String, bodyTemplate: String?, listSelector: String, titleSelector: String, linkSelector: String) {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Detect", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法解析HTML"])
        }
        
        let doc = try SwiftSoup.parse(html)
        // 查找第一个包含文本输入框的 form 元素
        let forms = try doc.select("form")
        for form in forms {
            let inputs = try form.select("input[type=text], input[type=search]")
            if let firstInput = inputs.first() {
                let action = try form.attr("action")
                let method = try form.attr("method").uppercased() == "POST" ? "POST" : "GET"
                let inputName = try firstInput.attr("name")
                let baseURL = url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/"
                let fullAction = URL(string: action, relativeTo: url)?.absoluteString ?? action
                
                var bodyTemplate: String? = nil
                if method == "POST" {
                    var params: [String] = []
                    let allInputs = try form.select("input")
                    for input in allInputs {
                        let name = try input.attr("name")
                        let value = try input.attr("value")
                        if name == inputName {
                            params.append("\(name)=%@")
                        } else if !name.isEmpty {
                            params.append("\(name)=\(value)")
                        }
                    }
                    bodyTemplate = params.joined(separator: "&")
                } else {
                    // GET 请求，bodyTemplate 存储参数名
                    bodyTemplate = inputName
                }
                
                // 默认选择器（可后续手动编辑）
                let listSelector = ".result-list .item, .search-list .item"
                let titleSelector = "h3 a, .book-title a"
                let linkSelector = "a@href"
                
                return (fullAction, method, bodyTemplate, listSelector, titleSelector, linkSelector)
            }
        }
        throw NSError(domain: "Detect", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到搜索表单"])
    }
    
    private func testLatency(for source: Source) {
        guard let baseURL = source.searchURL else {
            alertMessage = "无法获取源地址"
            return
        }
        guard let url = URL(string: baseURL) else { return }
        testingSourceID = source.objectID
        
        Task {
            let start = Date()
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 5
                let (_, response) = try await URLSession.shared.data(for: request)
                let elapsed = Date().timeIntervalSince(start) * 1000
                let httpResponse = response as? HTTPURLResponse
                let status = httpResponse?.statusCode ?? 0
                await MainActor.run {
                    testingSourceID = nil
                    if status >= 200 && status < 400 {
                        alertMessage = String(format: "延迟：%.0f ms", elapsed)
                    } else {
                        alertMessage = "响应异常（HTTP \(status)）"
                    }
                }
            } catch {
                await MainActor.run {
                    testingSourceID = nil
                    alertMessage = "连接失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// 用于 Alert 的扩展
extension String: @retroactive Identifiable {
    public var id: String { self }
}