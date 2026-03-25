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
        await MainActor.run { LogManager.shared.add("开始探测源: \(url.absoluteString)", level: .info) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            await MainActor.run { LogManager.shared.add("无效的HTTP响应", level: .error) }
            throw NSError(domain: "Detect", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
        }
        await MainActor.run { LogManager.shared.add("响应状态码: \(httpResponse.statusCode)", level: .info) }
        
        guard let html = String(data: data, encoding: .utf8) else {
            await MainActor.run { LogManager.shared.add("网页编码不是UTF-8", level: .error) }
            throw NSError(domain: "Detect", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法解析HTML"])
        }
        await MainActor.run { LogManager.shared.add("HTML长度: \(html.count) 字符", level: .debug) }
        
        let doc = try SwiftSoup.parse(html)
        let forms = try doc.select("form")
        await MainActor.run { LogManager.shared.add("找到 \(forms.count) 个表单", level: .info) }
        
        for (index, form) in forms.enumerated() {
            // 查找所有文本输入框
            let textInputs = try form.select("input[type=text], input[type=search], textarea")
            guard let firstTextInput = textInputs.first() else {
                await MainActor.run { LogManager.shared.add("表单 \(index+1) 没有文本输入框，跳过", level: .warning) }
                continue
            }
            
            // 获取关键词字段名（优先 name，其次 id）
            var keywordName = try firstTextInput.attr("name")
            if keywordName.isEmpty {
                keywordName = try firstTextInput.attr("id")
            }
            guard !keywordName.isEmpty else {
                await MainActor.run { LogManager.shared.add("表单 \(index+1) 文本输入框无 name 或 id，跳过", level: .warning) }
                continue
            }
            
            let action = try form.attr("action")
            let method = try form.attr("method").uppercased() == "POST" ? "POST" : "GET"
            
            // 构建完整 action URL
            var fullAction = action
            if !action.hasPrefix("http") {
                if action.hasPrefix("/") {
                    fullAction = (url.scheme ?? "https") + "://" + (url.host ?? "") + action
                } else {
                    let base = url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/"
                    fullAction = base + action
                }
            }
            
            // 构建 body 模板
            var bodyTemplate: String? = nil
            if method == "POST" {
                var params: [String] = []
                let allInputs = try form.select("input, textarea, select")
                for input in allInputs {
                    let tagName = input.tagName()
                    var name = try input.attr("name")
                    if name.isEmpty && (tagName == "input" || tagName == "textarea") {
                        name = try input.attr("id")
                    }
                    guard !name.isEmpty else { continue }
                    
                    var value = try input.attr("value")
                    if value.isEmpty && tagName == "select" {
                        let options = try input.select("option")
                        if let firstOption = options.first() {
                            value = try firstOption.attr("value")
                        }
                    }
                    
                    if input == firstTextInput {
                        params.append("\(name)=%@")   // 关键词字段用 %@ 占位
                    } else {
                        params.append("\(name)=\(value)")
                    }
                }
                bodyTemplate = params.joined(separator: "&")
            } else {
                bodyTemplate = keywordName
            }
            
            await MainActor.run {
                LogManager.shared.add("✅ 成功探测表单 \(index+1): 方法=\(method), 关键词字段=\(keywordName)", level: .success)
                LogManager.shared.add("Action URL: \(fullAction)", level: .debug)
                LogManager.shared.add("Body模板: \(bodyTemplate ?? "")", level: .debug)
            }
            
            let rule = Rule(
                name: url.host ?? "未知",
                type: "novel",
                baseURL: url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/",
                searchRule: SearchRule(
                    url: fullAction,
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
            return rule
        }
        
        await MainActor.run { LogManager.shared.add("未找到任何可用的搜索表单", level: .error) }
        throw NSError(domain: "Detect", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到搜索表单"])
    }
    
    private func testLatency(for source: Source) {
        guard let ruleData = source.ruleData,
              let rule = try? JSONDecoder().decode(Rule.self, from: ruleData),
              let url = URL(string: rule.baseURL) else {
            alertMessage = "无法获取源地址"
            return
        }
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