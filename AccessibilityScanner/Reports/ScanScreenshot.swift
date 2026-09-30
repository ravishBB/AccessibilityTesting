import Foundation

struct ScanScreenshot: Codable {
    let imageData: Data
    let annotatedImageData: Data?
    let width: Double
    let height: Double
    let hierarchyWidth: Double
    let hierarchyHeight: Double

    init(
        imageData: Data,
        annotatedImageData: Data? = nil,
        width: Double,
        height: Double,
        hierarchyWidth: Double,
        hierarchyHeight: Double
    ) {
        self.imageData = imageData
        self.annotatedImageData = annotatedImageData
        self.width = width
        self.height = height
        self.hierarchyWidth = hierarchyWidth
        self.hierarchyHeight = hierarchyHeight
    }
}
