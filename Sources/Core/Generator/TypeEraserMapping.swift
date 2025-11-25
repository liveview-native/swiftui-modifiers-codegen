import Foundation

/// Maps generic type constraints to their corresponding type erasers.
///
/// This struct provides mappings from protocol constraints to concrete type erasers,
/// enabling the generator to convert generic modifiers to concrete ones.
public struct TypeEraserMapping: Sendable {
    
    /// Known mappings from protocol constraints to type erasers.
    /// These are built-in SwiftUI/Swift type erasers.
    public static let builtInErasers: [String: String] = [
        // View-related
        "View": "AnyView",
        "SwiftUI.View": "AnyView",
        "SwiftUICore.View": "AnyView",
        
        // String-related
        "StringProtocol": "String",
        "Swift.StringProtocol": "String",
        
        // Hashable/Equatable
        "Hashable": "AnyHashable",
        "Swift.Hashable": "AnyHashable",
        
        // Shape-related
        "Shape": "AnyShape",
        "SwiftUI.Shape": "AnyShape",
        "InsettableShape": "AnyShape",
        "SwiftUI.InsettableShape": "AnyShape",
        
        // ShapeStyle
        "ShapeStyle": "AnyShapeStyle",
        "SwiftUI.ShapeStyle": "AnyShapeStyle",
        
        // Gesture
        "Gesture": "AnyGesture<Any>",
        "SwiftUI.Gesture": "AnyGesture<Any>",
        
        // Transition
        "Transition": "AnyTransition",
        "SwiftUI.Transition": "AnyTransition",
        
        // Layout
        "Layout": "AnyLayout",
        "SwiftUI.Layout": "AnyLayout",
    ]
    
    /// Protocol types that need custom type eraser enums to be generated.
    /// Maps protocol name to the eraser enum name to generate.
    public static let customEraserProtocols: [String: String] = [
        // Button styles
        "ButtonStyle": "AnyButtonStyle",
        "PrimitiveButtonStyle": "AnyPrimitiveButtonStyle",
        
        // Progress styles
        "ProgressViewStyle": "AnyProgressViewStyle",
        
        // Picker styles
        "PickerStyle": "AnyPickerStyle",
        "DatePickerStyle": "AnyDatePickerStyle",
        
        // Toggle styles
        "ToggleStyle": "AnyToggleStyle",
        
        // List styles
        "ListStyle": "AnyListStyle",
        
        // Navigation styles
        "NavigationViewStyle": "AnyNavigationViewStyle",
        
        // Tab styles
        "TabViewStyle": "AnyTabViewStyle",
        
        // Text field styles
        "TextFieldStyle": "AnyTextFieldStyle",
        
        // Label styles
        "LabelStyle": "AnyLabelStyle",
        
        // Menu styles
        "MenuStyle": "AnyMenuStyle",
        
        // Gauge styles
        "GaugeStyle": "AnyGaugeStyle",
        
        // Group box styles
        "GroupBoxStyle": "AnyGroupBoxStyle",
        
        // Index view styles
        "IndexViewStyle": "AnyIndexViewStyle",
        
        // Control group styles
        "ControlGroupStyle": "AnyControlGroupStyle",
        
        // Form styles
        "FormStyle": "AnyFormStyle",
        
        // Disclosure group styles
        "DisclosureGroupStyle": "AnyDisclosureGroupStyle",
    ]
    
    /// Returns the type eraser for a given constraint, if one exists.
    ///
    /// - Parameter constraint: The protocol constraint (e.g., "View", "StringProtocol").
    /// - Returns: The corresponding type eraser, or nil if none exists.
    public static func eraser(for constraint: String) -> String? {
        // Clean up the constraint (remove module prefixes for matching)
        let cleanConstraint = constraint
            .replacingOccurrences(of: "SwiftUI.", with: "")
            .replacingOccurrences(of: "SwiftUICore.", with: "")
            .replacingOccurrences(of: "Swift.", with: "")
        
        // Check built-in erasers first
        if let eraser = builtInErasers[constraint] ?? builtInErasers[cleanConstraint] {
            return eraser
        }
        
        // Check custom eraser protocols
        if let eraser = customEraserProtocols[constraint] ?? customEraserProtocols[cleanConstraint] {
            return eraser
        }
        
        return nil
    }
    
    /// Returns whether a constraint requires a custom type eraser enum to be generated.
    ///
    /// - Parameter constraint: The protocol constraint.
    /// - Returns: True if a custom eraser enum needs to be generated.
    public static func needsCustomEraser(for constraint: String) -> Bool {
        let cleanConstraint = constraint
            .replacingOccurrences(of: "SwiftUI.", with: "")
            .replacingOccurrences(of: "SwiftUICore.", with: "")
            .replacingOccurrences(of: "Swift.", with: "")
        
        return customEraserProtocols[constraint] != nil || customEraserProtocols[cleanConstraint] != nil
    }
    
    /// Returns the custom eraser enum name for a protocol, if one needs to be generated.
    ///
    /// - Parameter constraint: The protocol constraint.
    /// - Returns: The name of the eraser enum to generate, or nil if not needed.
    public static func customEraserName(for constraint: String) -> String? {
        let cleanConstraint = constraint
            .replacingOccurrences(of: "SwiftUI.", with: "")
            .replacingOccurrences(of: "SwiftUICore.", with: "")
            .replacingOccurrences(of: "Swift.", with: "")
        
        return customEraserProtocols[constraint] ?? customEraserProtocols[cleanConstraint]
    }
}
