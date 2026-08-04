import CupcakeOntology
import SwiftData
import SwiftUI

struct MetadataSettingsView: View {
    @Environment(AppSession.self) private var appSession
    @AppStorage("defaultSDRFSchema") private var defaultSchemaName: String = ""
    @Query(sort: \CachedSDRFSchema.name) private var schemas: [CachedSDRFSchema]

    private var isOverridingForInstance: Bool {
        appSession.defaultSDRFSchemaOverride != nil
    }

    private var instanceOverride: Binding<String> {
        Binding(
            get: { appSession.defaultSDRFSchemaOverride ?? defaultSchemaName },
            set: { appSession.setDefaultSDRFSchemaOverride($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Default Schema", selection: $defaultSchemaName) {
                    Text("None (show all schemas)").tag("")
                    ForEach(schemas) { schema in
                        Text(schema.displayName ?? schema.name).tag(schema.name)
                    }
                }
                .accessibilityIdentifier("defaultSchemaPicker")
            } footer: {
                Text("When adding a metadata field, template search prefers this schema. The same column can exist in several schemas, pick a default here, or switch schemas per-search.")
            }

            if appSession.activeInstance != nil {
                Section("This Instance") {
                    Toggle(
                        "Override for This Instance",
                        isOn: Binding(
                            get: { isOverridingForInstance },
                            set: { isOn in appSession.setDefaultSDRFSchemaOverride(isOn ? (appSession.defaultSDRFSchemaOverride ?? defaultSchemaName) : nil) }
                        )
                    )
                    .accessibilityIdentifier("defaultSchemaOverrideToggle")
                    if isOverridingForInstance {
                        Picker("Default Schema Override", selection: instanceOverride) {
                            Text("None (show all schemas)").tag("")
                            ForEach(schemas) { schema in
                                Text(schema.displayName ?? schema.name).tag(schema.name)
                            }
                        }
                        .accessibilityIdentifier("defaultSchemaOverridePicker")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Metadata")
    }
}
