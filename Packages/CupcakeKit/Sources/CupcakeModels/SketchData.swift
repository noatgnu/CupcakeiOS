import Foundation

public struct SketchPoint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SketchStroke: Codable, Sendable, Hashable {
    public var points: [SketchPoint]
    public var color: String
    public var width: Double

    public init(points: [SketchPoint], color: String, width: Double) {
        self.points = points
        self.color = color
        self.width = width
    }
}

public struct SketchData: Codable, Sendable {
    public var width: Double
    public var height: Double
    public var strokes: [SketchStroke]
    public var backgroundColor: String
    public var timestamp: Double

    public init(width: Double, height: Double, strokes: [SketchStroke], backgroundColor: String, timestamp: Double) {
        self.width = width
        self.height = height
        self.strokes = strokes
        self.backgroundColor = backgroundColor
        self.timestamp = timestamp
    }
}
