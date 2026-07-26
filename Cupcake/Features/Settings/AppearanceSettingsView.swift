import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appearanceRawValue: String = AppAppearance.system.rawValue
    @AppStorage("stepDetailUseCustomFontSize") private var useCustomStepFontSize = false
    @AppStorage("stepDetailFontSize") private var stepFontSize: Double = Double(HTMLText.defaultBodyPointSize)

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("appearancePicker")
            }

            Section("Step Text Size") {
                Toggle("Use Fixed Text Size", isOn: $useCustomStepFontSize)
                    .accessibilityIdentifier("useCustomStepFontSizeToggle")
                if useCustomStepFontSize {
                    Slider(value: $stepFontSize, in: 12...28, step: 1) {
                        Text("Text Size")
                    } minimumValueLabel: {
                        Text("A").font(.caption)
                    } maximumValueLabel: {
                        Text("A").font(.title3)
                    }
                    .accessibilityIdentifier("stepFontSizeSlider")
                    Text("Using a 200 µL pipette tip, remove one colony and transfer it into 300 mL broth.")
                        .font(.system(size: stepFontSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}
