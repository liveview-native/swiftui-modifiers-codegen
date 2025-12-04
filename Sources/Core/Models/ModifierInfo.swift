/// Represents a SwiftUI view modifier method extracted from the interface file.
///
/// This struct captures all relevant information about a modifier method,
/// including its name, parameters, return type, and documentation.
public struct ModifierInfo: Equatable, Sendable {
    /// The name of the modifier method (e.g., "padding", "background").
    public let name: String
    
    /// The parameters of the modifier method.
    public let parameters: [Parameter]
    
    /// The return type of the modifier (usually "some View").
    public let returnType: String
    
    /// The availability constraints (e.g., "iOS 13.0, *").
    /// Note: This is the raw string inside @available(...).
    public let availability: String?
    
    /// The build condition for conditional compilation (e.g., "os(iOS) || os(macOS)").
    /// Note: This is the raw string inside #if ...
    public let buildCondition: String?
    
    /// Documentation comments extracted from the interface.
    public let documentation: String?
    
    /// Whether this modifier is generic.
    public let isGeneric: Bool
    
    /// Generic constraints if applicable.
    public let genericConstraints: [String]
    
    /// Generic parameters with their constraints (e.g., ["Label": "View", "S": "StringProtocol"]).
    public let genericParameters: [GenericParameter]
    
    public init(
        name: String,
        parameters: [Parameter],
        returnType: String,
        availability: String? = nil,
        buildCondition: String? = nil,
        documentation: String? = nil,
        isGeneric: Bool = false,
        genericConstraints: [String] = [],
        genericParameters: [GenericParameter] = []
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.availability = availability
        self.buildCondition = buildCondition
        self.documentation = documentation
        self.isGeneric = isGeneric
        self.genericConstraints = genericConstraints
        self.genericParameters = genericParameters
    }
    
    /// Represents a generic parameter with its constraint.
    public struct GenericParameter: Equatable, Sendable {
        public let name: String
        public let constraint: String?
        
        public init(name: String, constraint: String? = nil) {
            self.name = name
            self.constraint = constraint
        }
    }
    
    /// Represents a parameter in a modifier method.
    public struct Parameter: Equatable, Sendable {
        public let label: String?
        public let name: String
        public let type: String
        public let hasDefaultValue: Bool
        public let defaultValue: String?
        
        public init(
            label: String?,
            name: String,
            type: String,
            hasDefaultValue: Bool = false,
            defaultValue: String? = nil
        ) {
            self.label = label
            self.name = name
            self.type = type
            self.hasDefaultValue = hasDefaultValue
            self.defaultValue = defaultValue
        }
    }
}