import SwiftUI
import CoreData

struct BookshelfView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.title, ascending: true)],
        animation: .default)
    private var books: FetchedResults<Book>
    
    @State private var showSourcePicker = false
    @State private var navigationPath = NavigationPath()
    
    let columns = [GridItem(.adaptive(minimum: 120), spacing: 20)]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("书架空空如也")
                            .font(.title2)
                        Text("点击右上角 + → 聚合搜索，添加小说或漫画")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
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
                        NavigationLink(destination: AggregateSearchView()) {
                            Label("聚合搜索", systemImage: "magnifyingglass")
                        }
                        Button("单源搜索") {
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
                    navigationPath.append(source)
                }
            }
            .navigationDestination(for: Source.self) { source in
                SearchView(source: source)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sourceAdded)) { notification in
                if let source = notification.object as? Source {
                    navigationPath.append(source)
                }
            }
        }
    }
}

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
            if sources.isEmpty {
                Text("请先在源管理中添加快捷源")
                    .foregroundColor(.secondary)
                    .navigationTitle("选择源")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { dismiss() }
                        }
                    }
            } else {
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
}