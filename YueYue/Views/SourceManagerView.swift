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
    @State private var showLogView = false
    
    @ObservedObject private var logManager = LogManager.shared
    
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
                    Button("查看日志") { showLogView = true }
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
        .sheet(isPresented: $showLogView) {
            LogView()
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
                let rule = try await detectSearchForm(from: url)
                let ruleData = try JSONEncoder().encode(rule)
                await MainActor.run {
                    let newSource = Source(context: viewContext)
                    newSource.name = url.host ?? "未知源"
                    newSource.type = rule.type
                    newSource.ruleData = ruleData
                    
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
                    alertMessage = "自动探测失败：\(error.localizedDescription)\n请查看日志获取详情"
                }
            }
        }
    }
    
    private func detectSearchForm(from url: URL) async throws -> Rule {
    await MainActor.run { LogManager.shared.add("🔍 开始爬虫探测: \(url.absoluteString)", level: .info) }
    
    // 1. 下载首页 HTML
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "Detect", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
    }
    await MainActor.run { LogManager.shared.add("响应状态码: \(httpResponse.statusCode)", level: .info) }
    
    guard let html = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "Detect", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法解析HTML"])
    }
    
    // 2. 解析 HTML
    let doc = try SwiftSoup.parse(html)
    let forms = try doc.select("form")
    await MainActor.run { LogManager.shared.add("找到 \(forms.count) 个表单", level: .info) }
    
    // 3. 遍历所有表单，找到包含文本输入框的
    for (index, form) in forms.enumerated() {
        let textInputs = try form.select("input[type=text], input[type=search], textarea")
        guard let firstTextInput = textInputs.first() else {
            await MainActor.run { LogManager.shared.add("表单 \(index+1) 无文本输入框，跳过", level: .warning) }
            continue
        }
        
        // 4. 提取表单信息
        let action = try form.attr("action")
        let method = try form.attr("method").uppercased() == "POST" ? "POST" : "GET"
        
        // 关键词字段名
        var keywordName = try firstTextInput.attr("name")
        if keywordName.isEmpty {
            keywordName = try firstTextInput.attr("id")
        }
        
        // 构建完整的搜索 URL
        var searchURL = action
        if !action.hasPrefix("http") {
            if action.hasPrefix("/") {
                searchURL = (url.scheme ?? "https") + "://" + (url.host ?? "") + action
            } else {
                let base = url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/"
                searchURL = base + action
            }
        }
        
        // 5. 提取所有表单字段
        var fields: [String: String] = [:]
        let allInputs = try form.select("input, textarea, select")
        for input in allInputs {
            var name = try input.attr("name")
            if name.isEmpty {
                name = try input.attr("id")
            }
            if name.isEmpty { continue }
            
            var value = try input.attr("value")
            if value.isEmpty && input.tagName() == "select" {
                let options = try input.select("option")
                if let firstOption = options.first() {
                    value = try firstOption.attr("value")
                }
            }
            fields[name] = value
        }
        
        // 6. 记录调试信息
        await MainActor.run {
            LogManager.shared.add("✅ 成功爬取表单 \(index+1):", level: .success)
            LogManager.shared.add("  方法: \(method)", level: .debug)
            LogManager.shared.add("  搜索URL: \(searchURL)", level: .debug)
            LogManager.shared.add("  关键词字段: \(keywordName)", level: .debug)
            LogManager.shared.add("  所有字段: \(fields)", level: .debug)
        }
        
        // 7. 构建 POST body 模板
        var bodyTemplate: String? = nil
        if method == "POST" && !fields.isEmpty {
            var params: [String] = []
            for (name, value) in fields {
                if name == keywordName {
                    params.append("\(name)=%@")  // 用 %@ 占位
                } else {
                    params.append("\(name)=\(value)")
                }
            }
            bodyTemplate = params.joined(separator: "&")
        }
        
        // 8. 构建规则
        let rule = Rule(
            name: url.host ?? "未知",
            type: "novel",
            baseURL: url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/",
            searchRule: SearchRule(
                url: searchURL,
                method: method,
                body: bodyTemplate,
                list: ".result-list .item, .search-list .item, ul.list li, .book-list li, #searchlist li",
                title: "h3 a, .book-title a, .name a, a.title, a.bookname",
                urlAttr: "a@href"
            ),
            chapterRule: ChapterRule(
                list: "#list dd a, .chapter-list a",
                title: "a",
                urlAttr: "a@href"
            ),
            contentRule: ContentRule(
                selector: "#content, .article-content",
                text: "text"
            ),
            discover: nil
        )
        
        // 9. 测试搜索（可选）
        await MainActor.run { LogManager.shared.add("测试搜索...", level: .info) }
        let testResult = try await testSearch(rule: rule, keyword: "test")
        if testResult {
            await MainActor.run { LogManager.shared.add("✅ 搜索测试成功！", level: .success) }
        } else {
            await MainActor.run { LogManager.shared.add("⚠️ 搜索测试无结果，可能需要调整选择器", level: .warning) }
        }
        
        return rule
    }
    
    throw NSError(domain: "Detect", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到搜索表单"])
}

// 测试搜索功能
private func testSearch(rule: Rule, keyword: String) async throws -> Bool {
    let (results, _) = try await SearchService.searchWithHtml(keyword: keyword, rule: rule)
    return !results.isEmpty
}

// 日志查看视图
struct LogView: View {
    @ObservedObject private var logManager = LogManager.shared
    @State private var exportText = ""
    @State private var showExportSheet = false
    
    var body: some View {
        NavigationView {
            List(logManager.logs) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.message)
                        .font(.system(.body, design: .monospaced))
                    Text(entry.timestamp.formatted())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .padding(.vertical, 2)
                )
            }
            .navigationTitle("日志")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清除") {
                        logManager.clear()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("导出") {
                        exportText = logManager.export()
                        showExportSheet = true
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                NavigationView {
                    TextEditor(text: .constant(exportText))
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .navigationTitle("日志导出")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showExportSheet = false }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("复制") {
                                    UIPasteboard.general.string = exportText
                                }
                            }
                        }
                }
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}