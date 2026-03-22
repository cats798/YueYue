import SwiftUI
import CoreData

struct BookshelfView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.title, ascending: true)],
        animation: .default)
    private var books: FetchedResults<Book>
    
    let columns = [GridItem(.adaptive(minimum: 120), spacing: 20)]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(books) { book in
                        NavigationLink(destination: ReaderView(book: book)) {
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
                    NavigationLink(destination: SourceManagerView()) {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
    }
}