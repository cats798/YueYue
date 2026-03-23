import SwiftUI
import CoreData

struct BookshelfView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.title, ascending: true)],
        animation: .default)
    private var books: FetchedResults<Book>
    
    @State private var showSourcePicker = false
    @State private var selectedSource: Source? = nil
    @State private var navigationPath = NavigationPath()
    
    let columns = [GridItem(.adaptive(minimum: 120), spacing: 20)]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(books) { book in
                        NavigationLink(value: book) {
                            GlassCard {
                                VStack {
                                    if let cover = book.cover, let uiImage = UIImage(data: cover) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 160)
                                            .cornerRadius(12)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(height: 160)
                                    }
                                    Text(book.title ?? "未知")
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .background(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.2)], startPoint: .top, endPoint: .bottom))
            .navigationTitle("已阅")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        NavigationLink(destination: SourceManagerView()) {
                            Label("管理源", systemImage: "gear")
                        }
                        Button("搜索书籍") {
                            showSourcePicker = true
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
            }
            .sheet(isPresented: $showSourcePicker) {
                SourcePickerView { source in
                    selectedSource = source
                    navigationPath.append(source)
                }
            }
            .navigationDestination(for: Source.self) { source in
                SearchView(source: source)
            }
        }
    }
}

// 源选择器
struct SourcePickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Source.name, ascending: true)],
        animation: .default)
    private var sources: FetchedResults<Source>
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Source) -> Void
    
    var body: some View {
        NavigationView {
            List(sources) { source in
                Button(source.name ?? "未命名") {
                    onSelect(source)
                    dismiss()
                }
            }
            .navigationTitle("选择源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}