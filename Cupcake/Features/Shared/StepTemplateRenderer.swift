import CupcakeModels
import Foundation

enum StepTemplateRenderer {
    static func render(stepDescription: String, reagents: [(stepReagent: CachedStepReagent, reagent: CachedReagent)]) -> String {
        var result = stepDescription
        for entry in reagents {
            guard let id = entry.stepReagent.serverID else { continue }
            let scaledQuantity = entry.stepReagent.scalable
                ? entry.stepReagent.quantity * entry.stepReagent.scalableFactor
                : entry.stepReagent.quantity
            result = result.replacingOccurrences(of: "%\(id).quantity%", with: "\(entry.stepReagent.quantity)")
            result = result.replacingOccurrences(of: "%\(id).scaled_quantity%", with: "\(scaledQuantity)")
            result = result.replacingOccurrences(of: "%\(id).name%", with: entry.reagent.name)
            result = result.replacingOccurrences(of: "%\(id).unit%", with: entry.reagent.unit)
        }
        return result
    }
}
