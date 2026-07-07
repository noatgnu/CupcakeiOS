import CupcakeModels
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A standard/scientific calculator that logs every operation as a `CalculatorHistoryEntry`.
struct CalculatorAnnotationView: View {
    let onSave: (Data) -> Void
    let onCancel: () -> Void

    private enum ExecutionMode { case initial, second }
    private enum CalculatorMode { case standard, scientific }
    private enum AngleMode { case deg, rad }

    @State private var executionMode: ExecutionMode = .initial
    @State private var operation: String?
    @State private var calculatorMode: CalculatorMode = .standard
    @State private var angleMode: AngleMode = .deg
    @State private var firstValue = "0"
    @State private var secondValue = ""
    @State private var memoryValue: Double = 0
    @State private var history: [CalculatorHistoryEntry] = []
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var currentDisplay: String { executionMode == .second ? secondValue : firstValue }
    private var displayExpression: String {
        guard executionMode == .second, let operation else { return "" }
        return "\(firstValue) \(Self.symbol(for: operation))"
    }
    private var hasMemory: Bool { memoryValue != 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                displayArea
                buttonGrid
                if !history.isEmpty {
                    historyList
                }
            }
            .padding()
            .navigationTitle(calculatorMode == .scientific ? "Scientific Calculator" : "Calculator")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(history.isEmpty)
                        .accessibilityIdentifier("saveCalculatorButton")
                }
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button(calculatorMode == .standard ? "Standard ✓" : "Standard") { calculatorMode = .standard }
                        Button(calculatorMode == .scientific ? "Scientific ✓" : "Scientific") { calculatorMode = .scientific }
                        if calculatorMode == .scientific {
                            Button(angleMode == .deg ? "Degrees ✓" : "Degrees") { angleMode = .deg }
                            Button(angleMode == .rad ? "Radians ✓" : "Radians") { angleMode = .rad }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("calculatorModeMenu")
                }
            }
            .alert("Calculator error", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 360, minHeight: 560)
    }

    private var displayArea: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if !displayExpression.isEmpty {
                Text(displayExpression)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(currentDisplay)
                .font(.system(.largeTitle, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("calculatorDisplay")
            if hasMemory {
                Text("M: \(Self.formatNumber(memoryValue))")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(Color.calculatorDisplayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var buttonGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return LazyVGrid(columns: columns, spacing: 6) {
            calcButton("MC", disabled: !hasMemory) { memoryOperation(.clear) }
            calcButton("MR", disabled: !hasMemory) { memoryOperation(.recall) }
            calcButton("M+") { memoryOperation(.add) }
            calcButton("M−") { memoryOperation(.subtract) }

            calcButton("MS") { memoryOperation(.store) }
            calcButton("log₂", disabled: executionMode == .second) { scientificOperation("log2") }
            calcButton("log", disabled: executionMode == .second) { scientificOperation("log10") }
            calcButton("√", disabled: executionMode == .second) { scientificOperation("sqrt") }

            if calculatorMode == .scientific {
                calcButton("sin", disabled: executionMode == .second) { scientificOperation("sin") }
                calcButton("cos", disabled: executionMode == .second) { scientificOperation("cos") }
                calcButton("tan", disabled: executionMode == .second) { scientificOperation("tan") }
                calcButton("ln", disabled: executionMode == .second) { scientificOperation("ln") }

                calcButton("sin⁻¹", disabled: executionMode == .second) { scientificOperation("asin") }
                calcButton("cos⁻¹", disabled: executionMode == .second) { scientificOperation("acos") }
                calcButton("tan⁻¹", disabled: executionMode == .second) { scientificOperation("atan") }
                calcButton("eˣ", disabled: executionMode == .second) { scientificOperation("exp") }

                calcButton("π", disabled: executionMode == .second) { insertConstant(.pi) }
                calcButton("x!", disabled: executionMode == .second) { scientificOperation("factorial") }
                calcButton("|x|", disabled: executionMode == .second) { scientificOperation("abs") }
                calcButton("1/x", disabled: executionMode == .second) { scientificOperation("reciprocal") }
            } else {
                calcButton("|x|", disabled: executionMode == .second) { scientificOperation("abs") }
                calcButton("1/x", disabled: executionMode == .second) { scientificOperation("reciprocal") }
                calcButton("xʸ") { formOperation("^") }
                calcButton("x²", disabled: executionMode == .second) { scientificOperation("square") }
            }

            calcButton("C", tint: .red) { clearAll() }
            calcButton("CE", tint: .orange) { clearEntry() }
            calcButton("⌫") { formDelete() }
            calcButton("÷", tint: .blue) { formOperation("/") }

            calcButton("7") { formNumber(7) }
            calcButton("8") { formNumber(8) }
            calcButton("9") { formNumber(9) }
            calcButton("×", tint: .blue) { formOperation("*") }

            calcButton("4") { formNumber(4) }
            calcButton("5") { formNumber(5) }
            calcButton("6") { formNumber(6) }
            calcButton("−", tint: .blue) { formOperation("-") }

            calcButton("1") { formNumber(1) }
            calcButton("2") { formNumber(2) }
            calcButton("3") { formNumber(3) }
            calcButton("+", tint: .blue) { formOperation("+") }

            calcButton("0") { formNumber(0) }
            calcButton(".") { formDecimal() }
            calcButton("=", tint: .green) { formOperation("=") }
        }
    }

    private func calcButton(_ label: String, tint: Color = .primary, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(disabled)
        .accessibilityIdentifier("calcButton_\(label)")
    }

    private var historyList: some View {
        List {
            Section("History (\(history.count))") {
                ForEach(history.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.formatExpression(entry))
                            .font(.system(.footnote, design: .monospaced))
                        Text("= \(Self.formatNumber(entry.result))")
                            .font(.subheadline.bold())
                    }
                    .opacity(entry.scratched == true ? 0.5 : 1)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            history.removeAll { $0.id == entry.id }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 220)
    }

    // MARK: - Calculator logic (mirrors calculator-annotation.ts)

    private func formNumber(_ digit: Int) {
        if executionMode == .initial {
            firstValue = Self.appendDigit(digit, to: firstValue)
        } else {
            secondValue = Self.appendDigit(digit, to: secondValue)
        }
    }

    private func formDecimal() {
        if executionMode == .initial {
            if !firstValue.contains(".") { firstValue += "." }
        } else {
            if !secondValue.contains(".") { secondValue += "." }
        }
    }

    private func formOperation(_ op: String) {
        if op == "=" && executionMode == .second {
            executeBinaryOperation()
            executionMode = .initial
            operation = nil
            return
        }
        if executionMode == .initial {
            guard firstValue != "", firstValue != "0" else { return }
            executionMode = .second
            if op != "=" { operation = op }
        } else {
            if secondValue.isEmpty {
                if op != "=" { operation = op }
                return
            }
            executeBinaryOperation()
            if op != "=" {
                operation = op
            } else {
                executionMode = .initial
                operation = nil
            }
        }
    }

    private func executeBinaryOperation() {
        guard let first = Double(firstValue), let second = Double(secondValue), let op = operation else { return }
        var result = 0.0
        switch op {
        case "+": result = first + second
        case "-": result = first - second
        case "*": result = first * second
        case "/":
            guard second != 0 else { showError("Cannot divide by zero"); return }
            result = first / second
        case "^": result = pow(first, second)
        default: return
        }
        guard result.isFinite else { showError("Result is not a finite number"); return }
        history.append(CalculatorHistoryEntry(inputPromptFirstValue: first, inputPromptSecondValue: second, operation: op, result: result))
        firstValue = Self.trim(result)
        secondValue = ""
    }

    private func scientificOperation(_ op: String) {
        guard executionMode == .initial else { return }
        let value = Double(firstValue) ?? 0
        var result = 0.0
        var isValid = true
        switch op {
        case "log2": result = log2(value)
        case "log10": result = log10(value)
        case "ln": result = log(value)
        case "sqrt": result = value.squareRoot()
        case "abs": result = abs(value)
        case "sin": result = angleMode == .deg ? sin(value * .pi / 180) : sin(value)
        case "cos": result = angleMode == .deg ? cos(value * .pi / 180) : cos(value)
        case "tan": result = angleMode == .deg ? tan(value * .pi / 180) : tan(value)
        case "asin": result = angleMode == .deg ? asin(value) * 180 / .pi : asin(value)
        case "acos": result = angleMode == .deg ? acos(value) * 180 / .pi : acos(value)
        case "atan": result = angleMode == .deg ? atan(value) * 180 / .pi : atan(value)
        case "exp": result = Foundation.exp(value)
        case "factorial":
            if value < 0 || value.truncatingRemainder(dividingBy: 1) != 0 || value > 170 {
                isValid = false
            } else {
                result = Self.factorial(value)
            }
        case "square": result = value * value
        case "cube": result = value * value * value
        case "reciprocal":
            if value == 0 { isValid = false } else { result = 1 / value }
        default: return
        }
        guard isValid, result.isFinite else { showError("Invalid operation or result"); return }
        history.append(CalculatorHistoryEntry(inputPromptFirstValue: value, inputPromptSecondValue: 0, operation: op, result: result))
        firstValue = Self.trim(result)
    }

    private func insertConstant(_ constant: MathConstant) {
        guard executionMode == .initial else { return }
        firstValue = Self.trim(constant == .pi ? Double.pi : M_E)
    }

    private enum MathConstant { case pi, e }
    private enum MemoryOp { case clear, recall, add, subtract, store }

    private func memoryOperation(_ op: MemoryOp) {
        let currentValue = Double(executionMode == .second ? secondValue : firstValue) ?? 0
        switch op {
        case .clear: memoryValue = 0
        case .recall: firstValue = Self.trim(memoryValue); executionMode = .initial
        case .add: memoryValue += currentValue
        case .subtract: memoryValue -= currentValue
        case .store: memoryValue = currentValue
        }
    }

    private func clearAll() {
        firstValue = "0"
        secondValue = ""
        executionMode = .initial
        operation = nil
    }

    private func clearEntry() {
        if executionMode == .initial { firstValue = "0" } else { secondValue = "0" }
    }

    private func formDelete() {
        if executionMode == .initial {
            guard firstValue != "", firstValue != "0" else { return }
            firstValue = String(firstValue.dropLast())
            if firstValue.isEmpty { firstValue = "0" }
        } else {
            guard !secondValue.isEmpty else { return }
            secondValue = String(secondValue.dropLast())
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            onSave(data)
        }
    }

    // MARK: - Formatting helpers

    /// Plain string append, preserving the decimal point correctly for any input.
    private static func appendDigit(_ digit: Int, to current: String) -> String {
        if current == "0" || current.isEmpty {
            return "\(digit)"
        } else {
            return current + "\(digit)"
        }
    }

    private static func trim(_ value: Double) -> String {
        formatNumber(value)
    }

    private static func factorial(_ n: Double) -> Double {
        n <= 1 ? 1 : n * factorial(n - 1)
    }

    private static func symbol(for operation: String) -> String {
        switch operation {
        case "+": return "+"
        case "-": return "−"
        case "*": return "×"
        case "/": return "÷"
        case "^": return "^"
        default: return operation
        }
    }

    static func formatNumber(_ value: Double) -> String {
        if abs(value) < 1e-10 && value != 0 {
            return String(format: "%.6e", value)
        }
        if abs(value) > 1e12 {
            return String(format: "%.6e", value)
        }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    static func formatExpression(_ entry: CalculatorHistoryEntry) -> String {
        if entry.inputPromptSecondValue != 0 {
            return "\(formatNumber(entry.inputPromptFirstValue)) \(symbol(for: entry.operation)) \(formatNumber(entry.inputPromptSecondValue))"
        } else {
            return "\(entry.operation)(\(formatNumber(entry.inputPromptFirstValue)))"
        }
    }
}

extension Color {
    static var calculatorDisplayBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
