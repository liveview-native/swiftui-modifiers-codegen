import Foundation
import SwiftSyntax
import SwiftParser

/// Parses protocol extensions to extract static style members.
///
/// This parser identifies patterns like:
/// ```swift
/// extension ProgressViewStyle where Self == LinearProgressViewStyle {
///     static var linear: Self { ... }
/// }
/// ```
/// to build type eraser enums with all available style cases.
public struct ProtocolStyleParser: Sendable {
    
    /// Represents a style case extracted from a protocol extension.
    public struct StyleCase: Equatable, Sendable, Hashable {
        /// The name of the static member (e.g., "linear", "circular").
        public let name: String
        
        /// The concrete type that conforms to the protocol (e.g., "LinearProgressViewStyle").
        public let concreteType: String
        
        /// Creates a new style case.
        public init(name: String, concreteType: String) {
            self.name = name
            self.concreteType = concreteType
        }
    }
    
    /// Creates a new protocol style parser.
    public init() {}
    
    /// Parses Swift source and extracts style cases for protocol extensions.
    ///
    /// - Parameter source: The Swift source code to parse.
    /// - Returns: A dictionary mapping protocol names to their discovered style cases.
    public func parse(source: String) -> [String: Set<StyleCase>] {
        let sourceFile = Parser.parse(source: source)
        
        var stylesByProtocol: [String: Set<StyleCase>] = [:]
        
        for statement in sourceFile.statements {
            if let extensionDecl = statement.item.as(ExtensionDeclSyntax.self) {
                if let (protocolName, styleCase) = parseStyleExtension(extensionDecl) {
                    stylesByProtocol[protocolName, default: []].insert(styleCase)
                }
            }
        }
        
        return stylesByProtocol
    }
    
    /// Parses a file and extracts style cases.
    ///
    /// - Parameter filePath: The path to the file to parse.
    /// - Returns: A dictionary mapping protocol names to their discovered style cases.
    public func parse(filePath: String) throws -> [String: Set<StyleCase>] {
        guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return [:]
        }
        return parse(source: source)
    }
    
    // MARK: - Private Methods
    
    /// Parses an extension declaration to extract style information.
    ///
    /// Looks for patterns like:
    /// ```swift
    /// extension ProgressViewStyle where Self == LinearProgressViewStyle {
    ///     static var linear: Self { ... }
    /// }
    /// ```
    private func parseStyleExtension(_ ext: ExtensionDeclSyntax) -> (protocolName: String, styleCase: StyleCase)? {
        // Get the protocol name from the extended type
        let protocolName = ext.extendedType.description.trimmingCharacters(in: .whitespaces)
        
        // Must have a where clause with "Self == ConcreteType"
        guard let whereClause = ext.genericWhereClause else {
            return nil
        }
        
        // Find the concrete type from "Self == ConcreteType"
        var concreteType: String? = nil
        for requirement in whereClause.requirements {
            if let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self) {
                let leftType = sameType.leftType.description.trimmingCharacters(in: .whitespaces)
                if leftType == "Self" {
                    concreteType = sameType.rightType.description.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        
        guard let concreteType = concreteType else {
            return nil
        }
        
        // Find static var/func that returns Self
        for member in ext.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                if let styleName = extractStaticStyleName(from: varDecl) {
                    return (protocolName, StyleCase(name: styleName, concreteType: concreteType))
                }
            }
        }
        
        return nil
    }
    
    /// Extracts the style name from a static variable declaration.
    private func extractStaticStyleName(from varDecl: VariableDeclSyntax) -> String? {
        // Must be static
        var isStatic = false
        for modifier in varDecl.modifiers {
            if modifier.name.text == "static" {
                isStatic = true
                break
            }
        }
        
        guard isStatic else {
            return nil
        }
        
        // Get the variable name
        guard let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return nil
        }
        
        // Check return type is Self (optional)
        if let typeAnnotation = binding.typeAnnotation {
            let returnType = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
            guard returnType == "Self" || returnType.hasSuffix(".Self") else {
                return nil
            }
        }
        
        return identifier.identifier.text
    }
}
