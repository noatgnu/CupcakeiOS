import Foundation
import SwiftData

@Model
public final class CachedColumnTemplate {
    @Attribute(.unique) public var serverID: Int64
    public var name: String?
    public var columnName: String?
    public var columnType: String?
    public var defaultValue: String?
    public var ontologyType: String?
    public var ontologyOptions: String?
    public var customOntologyFilters: String?
    public var inputType: String?
    public var units: String?
    public var possibleDefaultValues: String?

    public init(
        serverID: Int64,
        name: String? = nil,
        columnName: String? = nil,
        columnType: String? = nil,
        defaultValue: String? = nil,
        ontologyType: String? = nil,
        ontologyOptions: String? = nil,
        customOntologyFilters: String? = nil,
        inputType: String? = nil,
        units: String? = nil,
        possibleDefaultValues: String? = nil
    ) {
        self.serverID = serverID
        self.name = name
        self.columnName = columnName
        self.columnType = columnType
        self.defaultValue = defaultValue
        self.ontologyType = ontologyType
        self.ontologyOptions = ontologyOptions
        self.customOntologyFilters = customOntologyFilters
        self.inputType = inputType
        self.units = units
        self.possibleDefaultValues = possibleDefaultValues
    }
}

extension CachedColumnTemplate: OntologyRowDecodable {
    public static let typeKey = "system"
    public static let sqlTableName = "column_template"
    public convenience init?(row: [String: String?]) {
        guard let idString = row["id"] ?? nil, let id = Int64(idString) else { return nil }
        self.init(
            serverID: id,
            name: row["name"] ?? nil,
            columnName: row["column_name"] ?? nil,
            columnType: row["column_type"] ?? nil,
            defaultValue: row["default_value"] ?? nil,
            ontologyType: row["ontology_type"] ?? nil,
            ontologyOptions: row["ontology_options"] ?? nil,
            customOntologyFilters: row["custom_ontology_filters"] ?? nil,
            inputType: row["input_type"] ?? nil,
            units: row["units"] ?? nil,
            possibleDefaultValues: row["possible_default_values"] ?? nil
        )
    }
}

@Model
public final class CachedSDRFSchema {
    @Attribute(.unique) public var name: String
    public var displayName: String?
    public var schemaDescription: String?
    public var version: String?
    public var extendsSchema: String?
    public var usableAlone: Bool
    public var layer: String?
    public var columnsJSON: String?

    public init(
        name: String,
        displayName: String? = nil,
        schemaDescription: String? = nil,
        version: String? = nil,
        extendsSchema: String? = nil,
        usableAlone: Bool = true,
        layer: String? = nil,
        columnsJSON: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.schemaDescription = schemaDescription
        self.version = version
        self.extendsSchema = extendsSchema
        self.usableAlone = usableAlone
        self.layer = layer
        self.columnsJSON = columnsJSON
    }
}

extension CachedSDRFSchema: OntologyRowDecodable {
    public static let typeKey = "sdrf"
    public static let sqlTableName = "schema"
    public convenience init?(row: [String: String?]) {
        guard let name = row["name"] ?? nil else { return nil }
        self.init(
            name: name,
            displayName: row["display_name"] ?? nil,
            schemaDescription: row["description"] ?? nil,
            version: row["version"] ?? nil,
            extendsSchema: row["extends"] ?? nil,
            usableAlone: (row["usable_alone"] ?? nil).flatMap { $0 == "1" } ?? true,
            layer: row["layer"] ?? nil,
            columnsJSON: row["columns_json"] ?? nil
        )
    }
}
