import CupcakeOntology
import SwiftData
import SwiftUI

struct MetadataSettingsView: View {
    @AppStorage("defaultSDRFSchema") private var defaultSchemaName: String = ""
    @Query(sort: \CachedSDRFSchema.name) private var schemas: [CachedSDRFSchema]

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
                Text("When adding a metadata field, template search prefers this schema. The same column can exist in several schemas — pick a default here, or switch schemas per-search.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Metadata")
    }
}
