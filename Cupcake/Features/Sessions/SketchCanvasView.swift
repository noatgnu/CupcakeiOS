import CupcakeModels
import SwiftUI

@Observable
final class SketchEditorModel {
    private(set) var strokes: [SketchStroke] = []
    private(set) var currentPoints: [SketchPoint] = []
    var selectedColor = "#000000"
    var selectedWidth: Double = 4
    var isErasing = false

    var isEmpty: Bool { strokes.isEmpty }

    func appendPoint(_ point: CGPoint) {
        currentPoints.append(SketchPoint(x: point.x, y: point.y))
    }

    func endStroke() {
        if currentPoints.count > 1 {
            strokes.append(SketchStroke(points: currentPoints, color: isErasing ? "eraser" : selectedColor, width: selectedWidth))
        }
        currentPoints = []
    }

    func selectColor(_ hex: String) {
        selectedColor = hex
        isErasing = false
    }

    func toggleEraser() {
        isErasing.toggle()
    }

    func clear() {
        strokes = []
    }

    func undo() {
        _ = strokes.popLast()
    }

    func buildSketchData(size: CGSize) -> SketchData {
        SketchData(
            width: size.width,
            height: size.height,
            strokes: strokes,
            backgroundColor: "#ffffff",
            timestamp: Date().timeIntervalSince1970 * 1000
        )
    }

    func encode(size: CGSize) -> Data? {
        try? JSONEncoder().encode(buildSketchData(size: size))
    }
}

struct SketchCanvasView: View {
    let onSave: (Data) -> Void
    let onCancel: () -> Void

    @State private var model = SketchEditorModel()
    @State private var canvasSize: CGSize = .zero

    private let colors = ["#000000", "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF", "#FFFFFF"]
    private let widths: [Double] = [1, 2, 4, 8, 12]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                        SketchRenderer.draw(strokes: model.strokes, eraserColor: .white, in: context)
                        if model.currentPoints.count > 1 {
                            let liveStroke = SketchStroke(points: model.currentPoints, color: model.isErasing ? "eraser" : model.selectedColor, width: model.selectedWidth)
                            SketchRenderer.draw(strokes: [liveStroke], eraserColor: .white, in: context)
                        }
                    }
                    .background(Color.white)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in model.appendPoint(value.location) }
                            .onEnded { _ in model.endStroke() }
                    )
                    .onAppear { canvasSize = geometry.size }
                    .onChange(of: geometry.size) { _, newValue in canvasSize = newValue }
                    .accessibilityIdentifier("sketchCanvas")
                }
                controls
            }
            .navigationTitle("Sketch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(model.isEmpty)
                        .accessibilityIdentifier("saveSketchButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 480)
        #endif
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(.secondary, lineWidth: model.selectedColor == hex && !model.isErasing ? 2 : 0.5))
                        .onTapGesture {
                            model.selectColor(hex)
                        }
                        .accessibilityIdentifier("sketchColor_\(hex)")
                }
                Spacer()
                Button {
                    model.toggleEraser()
                } label: {
                    Image(systemName: model.isErasing ? "eraser.fill" : "eraser")
                }
                .accessibilityIdentifier("sketchEraserButton")
                .help("Eraser")
            }
            HStack {
                Picker("Width", selection: $model.selectedWidth) {
                    ForEach(widths, id: \.self) { width in
                        Text("\(Int(width))pt").tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button("Clear") {
                    model.clear()
                }
                .accessibilityIdentifier("sketchClearButton")
                Button("Undo") {
                    model.undo()
                }
                .disabled(model.isEmpty)
                .accessibilityIdentifier("sketchUndoButton")
            }
        }
        .padding()
    }

    private func save() {
        guard let data = model.encode(size: canvasSize) else { return }
        onSave(data)
    }
}

enum SketchRenderer {
    static func draw(strokes: [SketchStroke], eraserColor: Color, in context: GraphicsContext) {
        for stroke in strokes {
            guard stroke.points.count > 1 else { continue }
            var path = Path()
            path.move(to: CGPoint(x: stroke.points[0].x, y: stroke.points[0].y))
            for point in stroke.points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            let color: Color = stroke.color == "eraser" ? eraserColor : Color(hex: stroke.color)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
        }
    }
}

extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
