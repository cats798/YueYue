import Foundation
import CoreData

@objc(Source)
public class Source: NSManagedObject {
    @NSManaged public var name: String?
    @NSManaged public var type: String?
    @NSManaged public var ruleData: Data?
}