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
    
    /// The availability constraints (e.g., "@available(iOS 13.0, *)").
    public let availability: String?
    
    /// Documentation comments extracted from the interface.
    public let documentation: String?
    
    /// Whether this modifier is generic.
    public let isGeneric: Bool
    
    /// Generic constraints if applicable.
    public let genericConstraints: [String]
    
    /// Generic parameters with their constraints (e.g., ["Label": "View", "S": "StringProtocol"]).
    public let genericParameters: [GenericParameter]
    
    /// Creates a new modifier info instance.
    ///
    /// - Parameters:
    ///   - name: The name of the modifier method.
    ///   - parameters: The parameters of the modifier method.
    ///   - returnType: The return type of the modifier.
    ///   - availability: Optional availability constraints.
    ///   - documentation: Optional documentation comments.
    ///   - isGeneric: Whether this modifier is generic. Defaults to false.
    ///   - genericConstraints: Generic constraints if applicable. Defaults to empty array.
    ///   - genericParameters: Generic parameters with constraints. Defaults to empty array.
    public init(
        name: String,
        parameters: [Parameter],
        returnType: String,
        availability: String? = nil,
        documentation: String? = nil,
        isGeneric: Bool = false,
        genericConstraints: [String] = [],
        genericParameters: [GenericParameter] = []
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.availability = availability
        self.documentation = documentation
        self.isGeneric = isGeneric
        self.genericConstraints = genericConstraints
        self.genericParameters = genericParameters
    }
    
    /// Represents a generic parameter with its constraint.
    public struct GenericParameter: Equatable, Sendable {
        /// The name of the generic parameter (e.g., "Label", "S", "Content").
        public let name: String
        
        /// The constraint type (e.g., "View", "StringProtocol", "Hashable").
        public let constraint: String?
        
        /// Creates a new generic parameter.
        ///
        /// - Parameters:
        ///   - name: The name of the generic parameter.
        ///   - constraint: The constraint type if any.
        public init(name: String, constraint: String? = nil) {
            self.name = name
            self.constraint = constraint
        }
    }
    
    /// Represents a parameter in a modifier method.
    public struct Parameter: Equatable, Sendable {
        /// The label of the parameter (for call sites).
        public let label: String?
        
        /// The internal name of the parameter.
        public let name: String
        
        /// The type of the parameter.
        public let type: String
        
        /// Whether the parameter has a default value.
        public let hasDefaultValue: Bool
        
        /// The default value if available.
        public let defaultValue: String?
        
        /// Creates a new parameter instance.
        ///
        /// - Parameters:
        ///   - label: The label of the parameter (for call sites).
        ///   - name: The internal name of the parameter.
        ///   - type: The type of the parameter.
        ///   - hasDefaultValue: Whether the parameter has a default value. Defaults to false.
        ///   - defaultValue: The default value if available. Defaults to nil.
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
