import SwiftUI
import CoreData

struct AddSourceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var type = "novel"
    @State private var jsonText = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("源名称", text: $name)
                    Picker("类型", selection: $type) {
                        Text("小说").tag("novel")
                        Text("漫画").tag("comic")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("规则 JSON") {
                    TextEditor(text: $jsonText)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                    Text("请输入符合格式的 JSON 规则")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("添加") {
                    addSource()
                }
                .disabled(name.isEmpty || jsonText.isEmpty)
            }
            .navigationTitle("添加源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
    
    private func addSource() {
        let newSource = Source(context: viewContext)
        newSource.name = name
        newSource.type = type
        newSource.ruleData = jsonText.data(using: .utf8)
        try? viewContext.save()
        dismiss()
    }
}