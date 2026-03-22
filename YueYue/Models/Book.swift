import Foundation
import CoreData

@objc(Book)
public class Book: NSManagedObject {
    @NSManaged public var title: String?
    @NSManaged public var cover: Data?
    @NSManaged public var type: String?
    @NSManaged public var currentChapter: Int32
    @NSManaged public var progress: Double
    @NSManaged public var source: Source?
}