import Foundation
import SwiftSyntax
import SwiftParser

/// Parses SwiftUI .swiftinterface files to extract modifier methods.
///
/// This parser reads the Swift interface syntax and identifies View extension
/// methods that represent SwiftUI modifiers.
public struct InterfaceParser: Sendable {
    /// Errors that can occur during parsing.
    public enum ParsingError: Error, Equatable {
        case fileNotFound(String)
        case invalidSyntax(String)
        case unsupportedConstruct(String)
    }
    
    /// Creates a new interface parser.
    public init() {}
    
    /// Parses a .swiftinterface file and extracts modifier information.
    ///
    /// - Parameter filePath: The path to the .swiftinterface file.
    /// - Returns: An array of ModifierInfo instances extracted from the file.
    /// - Throws: ParsingError if the file cannot be read or parsed.
    public func parse(filePath: String) throws -> [ModifierInfo] {
        guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            throw ParsingError.fileNotFound(filePath)
        }
        return try parse(source: source)
    }
    
    /// Parses Swift source code and extracts modifier information.
    ///
    /// - Parameter source: The Swift source code to parse.
    /// - Returns: An array of ModifierInfo instances extracted from the source.
    /// - Throws: ParsingError if the source cannot be parsed.
    public func parse(source: String) throws -> [ModifierInfo] {
        // Parse the source code into a syntax tree
        let sourceFile = Parser.parse(source: source)
        
        var modifiers: [ModifierInfo] = []
        
        // Visit all extension declarations
        for statement in sourceFile.statements {
            if let extensionDecl = statement.item.as(ExtensionDeclSyntax.self) {
                modifiers.append(contentsOf: parseExtension(extensionDecl))
            }
        }
        
        return modifiers
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parses an extension declaration and extracts View modifier methods.
    private func parseExtension(_ ext: ExtensionDeclSyntax) -> [ModifierInfo] {
        // Check if this is a View extension
        guard isViewExtension(ext) else {
            return []
        }
        
        var modifiers: [ModifierInfo] = []
        
        // Extract all public functions from the extension
        for member in ext.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                if let modifier = parseFunction(funcDecl) {
                    modifiers.append(modifier)
                }
            }
            // Also handle functions inside #if blocks
            else if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                modifiers.append(contentsOf: parseFunctionsFromIfConfig(ifConfigDecl))
            }
        }
        
        return modifiers
    }
    
    /// Recursively extracts functions from #if/#elseif/#else blocks.
    private func parseFunctionsFromIfConfig(_ ifConfig: IfConfigDeclSyntax) -> [ModifierInfo] {
        var modifiers: [ModifierInfo] = []
        
        for clause in ifConfig.clauses {
            // Process all elements in this clause (whether #if, #elseif, or #else)
            if let elements = clause.elements {
                // The elements can be a MemberBlockItemListSyntax
                if let memberList = elements.as(MemberBlockItemListSyntax.self) {
                    for member in memberList {
                        if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                            if let modifier = parseFunction(funcDecl) {
                                modifiers.append(modifier)
                            }
                        }
                        // Handle nested #if blocks
                        else if let nestedIfConfig = member.decl.as(IfConfigDeclSyntax.self) {
                            modifiers.append(contentsOf: parseFunctionsFromIfConfig(nestedIfConfig))
                        }
                    }
                }
            }
        }
        
        return modifiers
    }
    
    /// Checks if an extension declaration is extending View.
    private func isViewExtension(_ ext: ExtensionDeclSyntax) -> Bool {
        let typeName = ext.extendedType.description.trimmingCharacters(in: .whitespaces)
        return typeName.contains("View") && 
               !typeName.contains("ViewModifier") &&
               !typeName.contains("ViewDimensions")
    }
    
    /// Parses a function declaration and creates a ModifierInfo if it's a valid modifier.
    private func parseFunction(_ funcDecl: FunctionDeclSyntax) -> ModifierInfo? {
        // Only extract public functions
        guard isPublicFunction(funcDecl) else {
            return nil
        }
        
        // Extract function name
        let name = funcDecl.name.text
        
        // Extract parameters
        let parameters = extractParameters(from: funcDecl.signature.parameterClause)
        
        // Extract return type (should be "some View" for modifiers)
        let returnType = extractReturnType(from: funcDecl.signature.returnClause)
        
        // Extract availability information
        let availability = extractAvailability(from: funcDecl.attributes)
        
        // Extract documentation comments
        let documentation = extractDocumentation(from: funcDecl.leadingTrivia)
        
        // Check if generic
        let isGeneric = funcDecl.genericParameterClause != nil
        
        // Extract generic constraints
        let genericConstraints = extractGenericConstraints(from: funcDecl.genericWhereClause)
        
        // Extract generic parameters with their constraints
        let genericParameters = extractGenericParameters(from: funcDecl.genericParameterClause, whereClause: funcDecl.genericWhereClause)
        
        return ModifierInfo(
            name: name,
            parameters: parameters,
            returnType: returnType,
            availability: availability,
            documentation: documentation,
            isGeneric: isGeneric,
            genericConstraints: genericConstraints,
            genericParameters: genericParameters
        )
    }
    
    /// Checks if a function is public.
    private func isPublicFunction(_ funcDecl: FunctionDeclSyntax) -> Bool {
        for modifier in funcDecl.modifiers {
            if modifier.name.text == "public" {
                return true
            }
        }
        return false
    }
    
    /// Extracts parameters from a parameter clause.
    private func extractParameters(from clause: FunctionParameterClauseSyntax) -> [ModifierInfo.Parameter] {
        clause.parameters.map { param in
            let label = param.firstName.text == "_" ? nil : param.firstName.text
            let name = param.secondName?.text ?? param.firstName.text
            let type = param.type.description.trimmingCharacters(in: .whitespaces)
            let hasDefaultValue = param.defaultValue != nil
            let defaultValue = param.defaultValue?.value.description.trimmingCharacters(in: .whitespaces)
            
            return ModifierInfo.Parameter(
                label: label,
                name: name,
                type: type,
                hasDefaultValue: hasDefaultValue,
                defaultValue: defaultValue
            )
        }
    }
    
    /// Extracts return type from a return clause.
    private func extractReturnType(from clause: ReturnClauseSyntax?) -> String {
        guard let clause = clause else {
            return "Void"
        }
        return clause.type.description.trimmingCharacters(in: .whitespaces)
    }
    
    /// Extracts availability information from attributes.
    private func extractAvailability(from attributes: AttributeListSyntax?) -> String? {
        guard let attributes = attributes else {
            return nil
        }
        
        for attribute in attributes {
            let attrText = attribute.description.trimmingCharacters(in: .whitespaces)
            if attrText.hasPrefix("@available") {
                return attrText
            }
        }
        
        return nil
    }
    
    /// Extracts documentation comments from trivia.
    private func extractDocumentation(from trivia: Trivia?) -> String? {
        guard let trivia = trivia else {
            return nil
        }
        
        var docLines: [String] = []
        
        for piece in trivia {
            switch piece {
            case .docLineComment(let text):
                docLines.append(text)
            case .docBlockComment(let text):
                docLines.append(text)
            default:
                continue
            }
        }
        
        if docLines.isEmpty {
            return nil
        }
        
        return docLines.joined(separator: "\n")
    }
    
    /// Extracts generic constraints from a where clause.
    private func extractGenericConstraints(from clause: GenericWhereClauseSyntax?) -> [String] {
        guard let clause = clause else {
            return []
        }
        
        return clause.requirements.map { req in
            req.description.trimmingCharacters(in: .whitespaces)
        }
    }
    
    /// Extracts generic parameters with their constraints.
    private func extractGenericParameters(from clause: GenericParameterClauseSyntax?, whereClause: GenericWhereClauseSyntax?) -> [ModifierInfo.GenericParameter] {
        guard let clause = clause else {
            return []
        }
        
        // Build a map of constraints from the where clause
        var constraintMap: [String: String] = [:]
        if let whereClause = whereClause {
            for requirement in whereClause.requirements {
                // Handle conformance requirements like "Label: View"
                if let conformance = requirement.requirement.as(ConformanceRequirementSyntax.self) {
                    let leftType = conformance.leftType.description.trimmingCharacters(in: .whitespaces)
                    let rightType = conformance.rightType.description.trimmingCharacters(in: .whitespaces)
                    constraintMap[leftType] = rightType
                }
                // Handle same-type requirements like "Label == Text"
                else if let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self) {
                    let leftType = sameType.leftType.description.trimmingCharacters(in: .whitespaces)
                    let rightType = sameType.rightType.description.trimmingCharacters(in: .whitespaces)
                    constraintMap[leftType] = rightType
                }
            }
        }
        
        return clause.parameters.map { param in
            let name = param.name.text
            
            // First check for inherited type in the parameter declaration (e.g., <Label: View>)
            var constraint: String? = nil
            if let inheritedType = param.inheritedType {
                constraint = inheritedType.description.trimmingCharacters(in: .whitespaces)
            }
            
            // Override with where clause constraint if present
            if let whereConstraint = constraintMap[name] {
                constraint = whereConstraint
            }
            
            return ModifierInfo.GenericParameter(name: name, constraint: constraint)
        }
    }
}
