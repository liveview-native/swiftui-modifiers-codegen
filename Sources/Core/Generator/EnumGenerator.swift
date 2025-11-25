import Foundation
import SwiftSyntaxBuilder
import SwiftSyntax

/// Generates type-safe Swift enum code for modifiers.
///
/// This generator creates enum cases for each modifier variant,
/// conforming to RuntimeViewModifier protocol for runtime parsing.
public struct EnumGenerator: Sendable {
    /// Errors that can occur during code generation.
    public enum GenerationError: Error, Equatable {
        case invalidModifierInfo(String)
        case unsupportedType(String)
        case codeGenerationFailed(String)
    }
    
    /// Creates a new enum generator.
    public init() {}
    
    /// Generates an enum definition for a group of related modifiers.
    ///
    /// - Parameters:
    ///   - enumName: The name of the enum to generate.
    ///   - modifiers: The modifiers to include in the enum.
    /// - Returns: A GeneratedCode instance containing the generated enum.
    /// - Throws: GenerationError if the code cannot be generated.
    public func generate(enumName: String, modifiers: [ModifierInfo]) throws -> GeneratedCode {
        guard !modifiers.isEmpty else {
            throw GenerationError.invalidModifierInfo("Cannot generate enum with no modifiers")
        }
        
        let warnings: [String] = []
        
        // Transform modifiers to use type erasers for generic parameters
        let transformedModifiers = modifiers.map { transformModifierForTypeErasure($0) }
        
        // Generate unique case names for each modifier variant
        let caseNames = generateUniqueCaseNames(for: transformedModifiers)
        
        // Generate enum cases
        var generatedCases: [String] = []
        for (modifier, caseName) in zip(transformedModifiers, caseNames) {
            let enumCase = try generateEnumCase(for: modifier, caseName: caseName)
            generatedCases.append(enumCase)
        }
        
        // Build complete enum
        let sourceCode = buildEnumSource(
            enumName: enumName,
            cases: generatedCases,
            modifiers: transformedModifiers,
            caseNames: caseNames,
            originalModifiers: modifiers
        )
        
        return GeneratedCode(
            sourceCode: sourceCode,
            fileName: "\(enumName).swift",
            modifierCount: modifiers.count,
            warnings: warnings
        )
    }
    
    // MARK: - Type Erasure Transformation
    
    /// Transforms a modifier to use type erasers for generic parameters.
    private func transformModifierForTypeErasure(_ modifier: ModifierInfo) -> ModifierInfo {
        guard modifier.isGeneric else {
            return modifier
        }
        
        // Build a map of generic parameter names to their erased types
        var genericErasures: [String: String] = [:]
        for genericParam in modifier.genericParameters {
            if let constraint = genericParam.constraint,
               let eraser = TypeEraserMapping.eraser(for: constraint) {
                genericErasures[genericParam.name] = eraser
            }
        }
        
        // Transform parameters that use generic types
        let transformedParams = modifier.parameters.map { param -> ModifierInfo.Parameter in
            let newType = replaceGenericTypes(in: param.type, with: genericErasures)
            return ModifierInfo.Parameter(
                label: param.label,
                name: param.name,
                type: newType,
                hasDefaultValue: param.hasDefaultValue,
                defaultValue: param.defaultValue
            )
        }
        
        return ModifierInfo(
            name: modifier.name,
            parameters: transformedParams,
            returnType: modifier.returnType,
            availability: modifier.availability,
            documentation: modifier.documentation,
            isGeneric: modifier.isGeneric,
            genericConstraints: modifier.genericConstraints,
            genericParameters: modifier.genericParameters
        )
    }
    
    /// Replaces generic type names with their erased counterparts.
    private func replaceGenericTypes(in type: String, with erasures: [String: String]) -> String {
        var result = type
        for (genericName, erasedType) in erasures {
            // Replace standalone generic type names
            // Be careful not to replace partial matches (e.g., "Label" in "LabelStyle")
            let pattern = "\\b\(genericName)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: erasedType
                )
            }
        }
        return result
    }
    
    // MARK: - Private Generation Methods
    
    /// Generates unique case names for all modifier variants.
    /// If there's only one variant, uses the simple name.
    /// If there are multiple variants, adds a suffix based on parameter types.
    private func generateUniqueCaseNames(for modifiers: [ModifierInfo]) -> [String] {
        let baseName = modifiers.first.map { makeCaseName(from: $0.name) } ?? "modifier"
        
        // If only one variant, use the simple name
        if modifiers.count == 1 {
            return [baseName]
        }
        
        // Multiple variants - need to make them unique
        var caseNames: [String] = []
        var usedNames: Set<String> = []
        
        for modifier in modifiers {
            var candidateName = baseName
            
            // Add parameter type information to make it unique
            if !modifier.parameters.isEmpty {
                let typeSignature = modifier.parameters.map { param -> String in
                    sanitizeTypeForCaseName(param.type)
                }.joined()
                
                candidateName = baseName + "With" + typeSignature
            }
            
            // Ensure the candidate name is a valid Swift identifier
            candidateName = sanitizeCaseName(candidateName)
            
            // If still not unique, add a numeric suffix
            var finalName = candidateName
            var counter = 1
            while usedNames.contains(finalName) {
                finalName = "\(candidateName)\(counter)"
                counter += 1
            }
            
            usedNames.insert(finalName)
            caseNames.append(finalName)
        }
        
        return caseNames
    }
    
    /// Sanitizes a type string for use in a case name.
    /// Extracts the simple type name and removes invalid characters.
    private func sanitizeTypeForCaseName(_ type: String) -> String {
        // Extract simple type name (e.g., "CGFloat" from "CoreFoundation.CGFloat")
        let components = type.split(separator: ".")
        var simpleType = components.last.map(String.init) ?? type
        
        // Handle closure types - extract a meaningful name
        if simpleType.contains("->") {
            // For closures like "() -> Void", extract return type
            if let arrowIndex = simpleType.range(of: "->") {
                let returnPart = simpleType[arrowIndex.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                simpleType = "Closure" + sanitizeTypeForCaseName(returnPart)
            } else {
                simpleType = "Closure"
            }
        }
        
        // Remove/replace invalid characters
        var cleanType = simpleType
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "?", with: "Optional")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "@escaping", with: "")
            .replacingOccurrences(of: "@Sendable", with: "")
            .replacingOccurrences(of: "@autoclosure", with: "")
            .replacingOccurrences(of: "->", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "[", with: "Array")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "&", with: "And")
        
        // Remove any remaining non-alphanumeric characters
        cleanType = cleanType.filter { $0.isLetter || $0.isNumber }
        
        return cleanType
    }
    
    /// Ensures a case name is a valid Swift identifier.
    private func sanitizeCaseName(_ name: String) -> String {
        var result = name
        
        // Remove any invalid characters that might have slipped through
        result = result.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        
        // Ensure it doesn't start with a number
        if let first = result.first, first.isNumber {
            result = "_" + result
        }
        
        // Ensure it's not empty
        if result.isEmpty {
            result = "unknown"
        }
        
        return result
    }
    
    /// Generates an enum case for a single modifier.
    private func generateEnumCase(for modifier: ModifierInfo, caseName: String) throws -> String {
        if modifier.parameters.isEmpty {
            // Simple case with no associated values
            return "case \(caseName)"
        }
        
        // Case with associated values - filter out closure types for enum cases
        let filteredParams = modifier.parameters.filter { !isClosure($0.type) }
        
        if filteredParams.isEmpty {
            return "case \(caseName)"
        }
        
        let params = filteredParams.map { param -> String in
            let type = cleanTypeForEnumCase(param.type)
            if let label = param.label {
                return "\(label): \(type)"
            } else {
                return type
            }
        }.joined(separator: ", ")
        
        return "case \(caseName)(\(params))"
    }
    
    /// Checks if a type string represents a closure.
    private func isClosure(_ type: String) -> Bool {
        type.contains("->")
    }
    
    /// Cleans a type for use in an enum case (removes attributes, simplifies).
    private func cleanTypeForEnumCase(_ type: String) -> String {
        type
            .replacingOccurrences(of: "@escaping ", with: "")
            .replacingOccurrences(of: "@Sendable ", with: "")
            .replacingOccurrences(of: "@autoclosure ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// Builds the complete enum source code.
    private func buildEnumSource(
        enumName: String,
        cases: [String],
        modifiers: [ModifierInfo],
        caseNames: [String],
        originalModifiers: [ModifierInfo]
    ) -> String {
        var lines: [String] = []
        
        // Import statements
        lines.append("import SwiftUI")
        lines.append("import SwiftSyntax")
        lines.append("")
        
        // Header comment
        lines.append("/// Generated modifier enum for \(enumName) modifiers.")
        lines.append("///")
        lines.append("/// This enum provides type-safe access to SwiftUI view modifiers.")
        lines.append("/// Generated by ModifierSwift.")
        
        // Get the base name for the modifier
        let baseName = originalModifiers.first?.name ?? "modifier"
        
        // Enum declaration
        lines.append("public enum \(enumName): Equatable, Sendable {")
        
        // Add cases
        for caseStr in cases {
            lines.append("    \(caseStr)")
        }
        
        lines.append("}")
        lines.append("")
        
        // RuntimeViewModifier conformance
        lines.append("extension \(enumName): RuntimeViewModifier {")
        lines.append("    public static var baseName: String { \"\(baseName)\" }")
        lines.append("")
        
        // Init from FunctionCallExprSyntax
        lines.append("    public init(syntax: FunctionCallExprSyntax) throws {")
        lines.append("        switch syntax.arguments.count {")
        
        // Group modifiers by argument count
        var modifiersByArgCount: [Int: [(ModifierInfo, String)]] = [:]
        for (modifier, caseName) in zip(modifiers, caseNames) {
            let argCount = modifier.parameters.filter { !isClosure($0.type) }.count
            modifiersByArgCount[argCount, default: []].append((modifier, caseName))
        }
        
        // Generate switch cases for each argument count
        for argCount in modifiersByArgCount.keys.sorted() {
            let variants = modifiersByArgCount[argCount]!
            lines.append("        case \(argCount):")
            
            if variants.count == 1 {
                let (modifier, caseName) = variants[0]
                lines.append(contentsOf: generateInitCase(for: modifier, caseName: caseName, indent: "            "))
            } else {
                // Multiple variants with same arg count - need to disambiguate
                // For now, just use the first one and add a TODO
                let (modifier, caseName) = variants[0]
                lines.append("            // TODO: Disambiguate between multiple variants")
                lines.append(contentsOf: generateInitCase(for: modifier, caseName: caseName, indent: "            "))
            }
        }
        
        lines.append("        default:")
        lines.append("            throw ModifierError()")
        lines.append("        }")
        lines.append("    }")
        lines.append("")
        
        // Body method (ViewModifier conformance)
        lines.append("    public func body(content: Content) -> some View {")
        lines.append("        switch self {")
        
        for (modifier, caseName) in zip(modifiers, caseNames) {
            let switchCase = generateBodyCase(for: modifier, caseName: caseName)
            lines.append("        \(switchCase)")
        }
        
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        
        return lines.joined(separator: "\n")
    }
    
    /// Generates the init case parsing code for a modifier variant.
    private func generateInitCase(for modifier: ModifierInfo, caseName: String, indent: String) -> [String] {
        var lines: [String] = []
        
        let nonClosureParams = modifier.parameters.filter { !isClosure($0.type) }
        
        if nonClosureParams.isEmpty {
            lines.append("\(indent)self = .\(caseName)")
            return lines
        }
        
        // Generate parsing for each parameter
        var guardConditions: [String] = []
        var paramValues: [String] = []
        
        for (index, param) in nonClosureParams.enumerated() {
            let varName = param.label ?? "value\(index)"
            let type = cleanTypeForEnumCase(param.type)
            
            // Generate the parsing expression
            let parseExpr: String
            if type.hasSuffix("?") {
                // Optional type - use optional init
                let baseType = String(type.dropLast())
                parseExpr = "\(baseType)(syntax: syntax.arguments[\(index)].expression)"
            } else {
                parseExpr = "\(type)(syntax: syntax.arguments[\(index)].expression)"
                guardConditions.append("let \(varName) = \(parseExpr)")
            }
            
            if type.hasSuffix("?") {
                paramValues.append("\(varName): \(type.dropLast())(syntax: syntax.arguments[\(index)].expression)")
            } else {
                paramValues.append(param.label != nil ? "\(param.label!): \(varName)" : varName)
            }
        }
        
        if !guardConditions.isEmpty {
            lines.append("\(indent)guard \(guardConditions.joined(separator: ",")) else {")
            lines.append("\(indent)    throw ModifierError()")
            lines.append("\(indent)}")
        }
        
        let caseParams = nonClosureParams.enumerated().map { index, param -> String in
            let varName = param.label ?? "value\(index)"
            return param.label != nil ? "\(param.label!): \(varName)" : varName
        }.joined(separator: ", ")
        
        lines.append("\(indent)self = .\(caseName)(\(caseParams))")
        
        return lines
    }
    
    /// Generates a switch case for the body method.
    private func generateBodyCase(for modifier: ModifierInfo, caseName: String) -> String {
        let nonClosureParams = modifier.parameters.filter { !isClosure($0.type) }
        
        if nonClosureParams.isEmpty {
            return "case .\(caseName):\n            content.\(modifier.name)()"
        }
        
        // Build pattern and call
        let pattern = nonClosureParams.enumerated().map { index, param -> String in
            if let label = param.label {
                return "let \(label)"
            } else {
                return "let value\(index)"
            }
        }.joined(separator: ", ")
        
        let call = nonClosureParams.enumerated().map { index, param -> String in
            let varName = param.label ?? "value\(index)"
            if let paramLabel = param.label {
                return "\(paramLabel): \(varName)"
            } else {
                return varName
            }
        }.joined(separator: ", ")
        
        return "case .\(caseName)(\(pattern)):\n            content.\(modifier.name)(\(call))"
    }
    
    /// Creates a valid Swift enum case name from a modifier name.
    private func makeCaseName(from modifierName: String) -> String {
        // Remove special characters and convert to camelCase
        var name = modifierName
        
        // Handle leading underscores
        if name.hasPrefix("_") {
            name = "underscore" + name.dropFirst()
        }
        
        // Ensure first character is lowercase
        if let first = name.first {
            name = first.lowercased() + name.dropFirst()
        }
        
        return name
    }
}
