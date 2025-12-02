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
    public func generate(enumName: String, modifiers: [ModifierInfo]) throws -> GeneratedCode {
        guard !modifiers.isEmpty else {
            throw GenerationError.invalidModifierInfo("Cannot generate enum with no modifiers")
        }
        
        // 1. Transform generics to type erasers
        let erasedModifiers = modifiers.map { transformModifierForTypeErasure($0) }
        
        // 2. Transform View-returning closures to ViewReference
        let transformedModifiers = erasedModifiers.map { transformClosuresToViewReference($0) }
        
        // 3. Generate unique case names
        let caseNames = generateUniqueCaseNames(for: transformedModifiers)
        
        // 4. Generate enum cases
        var generatedCases: [String] = []
        for (modifier, caseName) in zip(transformedModifiers, caseNames) {
            let enumCase = try generateEnumCase(for: modifier, caseName: caseName)
            generatedCases.append(enumCase)
        }
        
        // 5. Build complete enum source
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
            modifierCount: modifiers.count
        )
    }
    
    /// Generates the global ModifierParseError type.
    public func generateParseErrorType() -> GeneratedCode {
        let sourceCode = """
        import Foundation
        
        /// Errors that can occur when parsing modifiers from syntax.
        public enum ModifierParseError: Error, CustomStringConvertible {
            case unexpectedArgumentCount(modifier: String, expected: [Int], found: Int)
            case invalidArguments(modifier: String, variant: String, expectedTypes: String)
            case ambiguousVariant(modifier: String, expectedLabels: [String])
            case noMatchingVariant(modifier: String, found: Int)
        
            public var description: String {
                switch self {
                case .unexpectedArgumentCount(let modifier, let expected, let found):
                    return "\\(modifier): unexpected argument count \\(found), expected one of \\(expected)"
                case .invalidArguments(let modifier, let variant, let expectedTypes):
                    return "\\(modifier): invalid arguments for '\\(variant)', expected types: \\(expectedTypes)"
                case .ambiguousVariant(let modifier, let expectedLabels):
                    return "\\(modifier): ambiguous variant, expected first argument label to be one of \\(expectedLabels)"
                case .noMatchingVariant(let modifier, let found):
                    return "\\(modifier): no matching variant found for argument count \\(found)"
                }
            }
        }
        """
        
        return GeneratedCode(
            sourceCode: sourceCode,
            fileName: "ModifierParseError.swift",
            modifierCount: 0
        )
    }
    
    // MARK: - Transformations
    
    /// Transforms a modifier to use type erasers for generic parameters.
    private func transformModifierForTypeErasure(_ modifier: ModifierInfo) -> ModifierInfo {
        guard modifier.isGeneric else { return modifier }
        
        var genericErasures: [String: String] = [:]
        for genericParam in modifier.genericParameters {
            if let constraint = genericParam.constraint,
               let eraser = TypeEraserMapping.eraser(for: constraint) {
                genericErasures[genericParam.name] = eraser
            }
        }
        
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
        
        return ModifierInfo(name: modifier.name, parameters: transformedParams, returnType: modifier.returnType, availability: modifier.availability, documentation: modifier.documentation, isGeneric: modifier.isGeneric, genericConstraints: modifier.genericConstraints, genericParameters: modifier.genericParameters)
    }
    
    /// Transforms closures returning View to `ViewReference` struct.
    private func transformClosuresToViewReference(_ modifier: ModifierInfo) -> ModifierInfo {
        let newParams = modifier.parameters.map { param -> ModifierInfo.Parameter in
            if isViewReturningClosure(param.type, genericParams: modifier.genericParameters) {
                return ModifierInfo.Parameter(
                    label: param.label,
                    name: param.name,
                    type: "ViewReference",
                    hasDefaultValue: param.hasDefaultValue,
                    defaultValue: param.defaultValue
                )
            }
            return param
        }
        
        return ModifierInfo(name: modifier.name, parameters: newParams, returnType: modifier.returnType, availability: modifier.availability, documentation: modifier.documentation, isGeneric: modifier.isGeneric, genericConstraints: modifier.genericConstraints, genericParameters: modifier.genericParameters)
    }
    
    private func replaceGenericTypes(in type: String, with erasures: [String: String]) -> String {
        var result = type
        for (genericName, erasedType) in erasures {
            let pattern = "\\b\(genericName)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: erasedType)
            }
        }
        return result
    }
    
    private func isViewReturningClosure(_ type: String, genericParams: [ModifierInfo.GenericParameter]) -> Bool {
        guard type.contains("->") else { return false }
        
        let cleaned = type.replacingOccurrences(of: "@escaping", with: "")
                          .replacingOccurrences(of: "@ViewBuilder", with: "")
                          .trimmingCharacters(in: .whitespaces)
        
        let components = cleaned.components(separatedBy: "->")
        guard let returnType = components.last?.trimmingCharacters(in: .whitespaces) else { return false }
        
        // Check explicit View types
        if returnType == "some View" || returnType == "View" || returnType == "SwiftUI.View" || returnType == "AnyView" {
            return true
        }
        
        // Check generic parameters constrained to View
        for param in genericParams {
            if returnType == param.name, let constraint = param.constraint, constraint.contains("View") {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Code Generation
    
    private func buildEnumSource(enumName: String, cases: [String], modifiers: [ModifierInfo], caseNames: [String], originalModifiers: [ModifierInfo]) -> String {
        var lines: [String] = []
        
        lines.append("import SwiftUI")
        lines.append("import SwiftSyntax")
        lines.append("")
        lines.append("/// Generated modifier enum for \(enumName) modifiers.")
        lines.append("/// Generated by ModifierSwift.")
        lines.append("public enum \(enumName): Sendable {")
        for caseStr in cases {
            lines.append("    \(caseStr)")
        }
        lines.append("}")
        lines.append("")
        
        lines.append("extension \(enumName): RuntimeViewModifier {")
        lines.append("    public static var baseName: String { \"\(originalModifiers.first?.name ?? "modifier")\" }")
        lines.append("")
        lines.append("    public init(syntax: FunctionCallExprSyntax) throws {")
        
        let zipped = zip(modifiers, caseNames).map { ($0.0, $0.1) }
        
        // Classification: Strict vs Flexible.
        // Modifiers with ViewReference are treated as Flexible to handle trailing closures gracefully.
        let strictVariants = zipped.filter { mod, _ in
            !mod.parameters.contains { $0.hasDefaultValue || $0.type == "ViewReference" }
        }
        let flexibleVariants = zipped.filter { mod, _ in
            mod.parameters.contains { $0.hasDefaultValue || $0.type == "ViewReference" }
        }
        
        // Phase 1: Strict Matches (Grouped by argument count)
        let strictByCount = Dictionary(grouping: strictVariants, by: { $0.0.parameters.count })
        
        for count in strictByCount.keys.sorted() {
            let variants = strictByCount[count]!
            lines.append("        if syntax.arguments.count == \(count) {")
            
            if variants.count == 1 {
                lines.append(contentsOf: generateStrictMatch(variants[0].0, caseName: variants[0].1, indent: "            "))
            } else {
                // Disambiguate strict variants (usually by argument labels)
                lines.append(contentsOf: generateDisambiguatedStrictMatches(variants, indent: "            "))
            }
            lines.append("        }")
        }
        
        // Phase 2: Flexible Matches (Fallback for defaults/trailing closures)
        for (index, (modifier, caseName)) in flexibleVariants.enumerated() {
            let isLast = index == flexibleVariants.count - 1
            
            // Build disambiguation condition based on unique labels
            let labels = modifier.parameters
                .compactMap { $0.label }
                .filter { !isClosure($0) } // Don't use closures as discriminators
            
            let conditions = labels.map { "syntax.argument(named: \"\($0)\") != nil" }
            let conditionStr = conditions.joined(separator: " || ")
            
            if !conditions.isEmpty && !isLast {
                lines.append("        if \(conditionStr) {")
                lines.append(contentsOf: generateFlexibleMatchBody(modifier, caseName: caseName, indent: "            "))
                lines.append("            return")
                lines.append("        }")
            } else {
                // Catch-all or last variant
                lines.append(contentsOf: generateFlexibleMatchBody(modifier, caseName: caseName, indent: "        "))
                lines.append("        return")
            }
        }
        
        lines.append("        throw ModifierParseError.noMatchingVariant(modifier: \"\(enumName)\", found: syntax.arguments.count)")
        lines.append("    }")
        
        // Body implementation with new signature
        lines.append("    public func body<Library: ElementLibrary>(content: Content, library: Library.Type) -> some View {")
        lines.append("        switch self {")
        for (modifier, caseName) in zip(modifiers, caseNames) {
            lines.append("        \(generateBodyCase(for: modifier, caseName: caseName))")
        }
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        
        return lines.joined(separator: "\n")
    }
    
    private func generateStrictMatch(_ modifier: ModifierInfo, caseName: String, indent: String) -> [String] {
        var lines: [String] = []
        var conditions: [String] = []
        
        for (index, param) in modifier.parameters.enumerated() {
            let varName = param.label ?? "value\(index)"
            let cleanType = cleanTypeForEnumCase(param.type)
            let isOptional = cleanType.hasSuffix("?")
            let typeToParse = isOptional ? String(cleanType.dropLast()) : cleanType
            
            let accessor = param.label.map { "syntax.argument(named: \"\($0)\")?.expression" } 
                ?? "(syntax.arguments.count > \(index) ? syntax.arguments[\(index)].expression : nil)"
            
            if param.type == "ViewReference" {
                 conditions.append("let \(varName) = ViewReference(syntax: \(accessor)!)")
            } else {
                 conditions.append("let \(varName) = \(typeToParse)(syntax: \(accessor)!)")
            }
        }
        
        if conditions.isEmpty {
            lines.append("\(indent)self = .\(caseName)")
            lines.append("\(indent)return")
        } else {
            lines.append("\(indent)if \(conditions.joined(separator: ", ")) {")
            let args = modifier.parameters.enumerated().map { i, p in 
                let name = p.label ?? "value\(i)"
                return p.label != nil ? "\(p.label!): \(name)" : name 
            }.joined(separator: ", ")
            lines.append("\(indent)    self = .\(caseName)(\(args))")
            lines.append("\(indent)    return")
            lines.append("\(indent)}")
        }
        return lines
    }
    
    private func generateDisambiguatedStrictMatches(_ variants: [(ModifierInfo, String)], indent: String) -> [String] {
        var lines: [String] = []
        for (modifier, caseName) in variants {
            lines.append(contentsOf: generateStrictMatch(modifier, caseName: caseName, indent: indent))
        }
        return lines
    }

    private func generateFlexibleMatchBody(_ modifier: ModifierInfo, caseName: String, indent: String) -> [String] {
        var lines: [String] = []
        
        for (index, param) in modifier.parameters.enumerated() {
            let varName = param.label ?? "value\(index)"
            let type = cleanTypeForEnumCase(param.type)
            let isOptional = type.hasSuffix("?")
            let baseType = isOptional ? String(type.dropLast()) : type
            
            let accessor = param.label.map { "syntax.argument(named: \"\($0)\")?.expression" }
                ?? "(syntax.arguments.count > \(index) ? syntax.arguments[\(index)].expression : nil)"
            
            if param.type == "ViewReference" {
                let isLast = index == modifier.parameters.count - 1
                let defaultVal = param.defaultValue ?? "ViewReference(reference: nil)"
                
                let extractExpr: String
                if isLast {
                    extractExpr = "(\(accessor) ?? syntax.trailingClosure.map { ExprSyntax($0) })"
                } else {
                    extractExpr = accessor
                }
                
                lines.append("\(indent)let \(varName): \(type) = \(extractExpr).flatMap { ViewReference(syntax: $0) } ?? \(defaultVal)")
                
            } else {
                let defaultVal = param.defaultValue ?? (isOptional ? "nil" : nil)
                var extraction = "\(accessor).flatMap { \(baseType)(syntax: $0) }"
                if let def = defaultVal {
                    extraction += " ?? \(def)"
                }
                lines.append("\(indent)let \(varName): \(type) = \(extraction)")
            }
        }
        
        let args = modifier.parameters.enumerated().map { i, p in 
            let name = p.label ?? "value\(i)"
            return p.label != nil ? "\(p.label!): \(name)" : name 
        }.joined(separator: ", ")
        
        lines.append("\(indent)self = .\(caseName)(\(args))")
        return lines
    }

    // MARK: - Helpers
    
    private func generateUniqueCaseNames(for modifiers: [ModifierInfo]) -> [String] {
        let baseName = modifiers.first.map { makeCaseName(from: $0.name) } ?? "modifier"
        if modifiers.count == 1 { return [baseName] }
        
        var names: [String] = []
        var used: Set<String> = []
        
        for mod in modifiers {
            var name = baseName
            if !mod.parameters.isEmpty {
                name += "With" + mod.parameters.map { sanitizeTypeForCaseName($0.type) }.joined()
            }
            name = sanitizeCaseName(name)
            var unique = name
            var count = 1
            while used.contains(unique) {
                unique = "\(name)\(count)"
                count += 1
            }
            used.insert(unique)
            names.append(unique)
        }
        return names
    }
    
    private func makeCaseName(from name: String) -> String {
        var res = name
        if res.hasPrefix("_") { res = "underscore" + res.dropFirst() }
        if let f = res.first { res = f.lowercased() + res.dropFirst() }
        return res
    }
    
    private func sanitizeCaseName(_ name: String) -> String {
        let filtered = name.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return filtered.isEmpty ? "unknown" : (filtered.first!.isNumber ? "_" + filtered : filtered)
    }
    
    private func sanitizeTypeForCaseName(_ type: String) -> String {
        if type == "ViewReference" { return "View" }
        return type.replacingOccurrences(of: "[", with: "Array")
                   .replacingOccurrences(of: "]", with: "")
                   .replacingOccurrences(of: "?", with: "Optional")
                   .filter { $0.isLetter || $0.isNumber }
    }
    
    private func generateEnumCase(for modifier: ModifierInfo, caseName: String) throws -> String {
        if modifier.parameters.isEmpty { return "case \(caseName)" }
        let params = modifier.parameters.map { p in
            let t = cleanTypeForEnumCase(p.type)
            return p.label != nil ? "\(p.label!): \(t)" : t
        }.joined(separator: ", ")
        return "case \(caseName)(\(params))"
    }
    
    private func generateBodyCase(for modifier: ModifierInfo, caseName: String) -> String {
        if modifier.parameters.isEmpty { return "case .\(caseName):\n            content.\(modifier.name)()" }
        
        let patterns = modifier.parameters.enumerated().map { i, p in
            p.label.map { "let \($0)" } ?? "let value\(i)"
        }.joined(separator: ", ")
        
        let calls = modifier.parameters.enumerated().map { i, p in
            let val = p.label ?? "value\(i)"
            
            if p.type == "ViewReference" {
                 if p.label != nil {
                     return "\(p.label!): { \(val) }"
                 } else {
                     return "{ \(val) }"
                 }
            }
            
            return p.label != nil ? "\(p.label!): \(val)" : val
        }.joined(separator: ", ")
        
        return "case .\(caseName)(\(patterns)):\n            content.\(modifier.name)(\(calls))"
    }
    
    private func isClosure(_ type: String) -> Bool {
        return type.contains("->") && !type.contains("ViewReference")
    }
    
    private func cleanTypeForEnumCase(_ type: String) -> String {
        type.replacingOccurrences(of: "@escaping", with: "")
            .replacingOccurrences(of: "@ViewBuilder", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}