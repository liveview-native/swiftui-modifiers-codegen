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
    
    /// Generates the global ModifierParseError type.
    ///
    /// This should be called once and the result included in the output.
    /// - Returns: A GeneratedCode instance containing the error type.
    public func generateParseErrorType() -> GeneratedCode {
        let sourceCode = """
        import Foundation
        
        /// Errors that can occur when parsing modifiers from syntax.
        public enum ModifierParseError: Error, CustomStringConvertible {
            /// The number of arguments doesn't match any known variant.
            case unexpectedArgumentCount(modifier: String, expected: [Int], found: Int)
            /// The arguments could not be parsed for the specified variant.
            case invalidArguments(modifier: String, variant: String, expectedTypes: String)
            /// Multiple variants match the argument count but labels don't match.
            case ambiguousVariant(modifier: String, expectedLabels: [String])
        
            public var description: String {
                switch self {
                case .unexpectedArgumentCount(let modifier, let expected, let found):
                    return "\\(modifier): unexpected argument count \\(found), expected one of \\(expected)"
                case .invalidArguments(let modifier, let variant, let expectedTypes):
                    return "\\(modifier): invalid arguments for '\\(variant)', expected types: \\(expectedTypes)"
                case .ambiguousVariant(let modifier, let expectedLabels):
                    return "\\(modifier): ambiguous variant, expected first argument label to be one of \\(expectedLabels)"
                }
            }
        }
        """
        
        return GeneratedCode(
            sourceCode: sourceCode,
            fileName: "ModifierParseError.swift",
            modifierCount: 0,
            warnings: []
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
        lines.append("public enum \(enumName): Sendable {")
        
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
                lines.append(contentsOf: generateInitCase(for: modifier, caseName: caseName, enumName: enumName, indent: "            "))
            } else {
                // Multiple variants with same arg count - disambiguate by argument labels
                lines.append(contentsOf: generateDisambiguatedInitCases(for: variants, enumName: enumName, indent: "            "))
            }
        }
        
        lines.append("        default:")
        lines.append("            throw ModifierParseError.unexpectedArgumentCount(modifier: \"\(enumName)\", expected: [\(modifiersByArgCount.keys.sorted().map { String($0) }.joined(separator: ", "))], found: syntax.arguments.count)")
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
    
    /// Generates the init case parsing code for a modifier variant using guard statements.
    /// This is used when there's only one variant for a given argument count.
    private func generateInitCase(for modifier: ModifierInfo, caseName: String, enumName: String, indent: String) -> [String] {
        var lines: [String] = []
        
        let nonClosureParams = modifier.parameters.filter { !isClosure($0.type) }
        
        if nonClosureParams.isEmpty {
            lines.append("\(indent)self = .\(caseName)")
            return lines
        }
        
        // Generate parsing statements for each parameter (positional or labeled, defaults supported)
        for (index, param) in nonClosureParams.enumerated() {
            let varName = param.label ?? "value\(index)"
            let type = cleanTypeForEnumCase(param.type)
            let hasDefault = param.hasDefaultValue
            let defaultVal = param.defaultValue ?? "nil"

            // Build an argument expression accessor that returns an ExprSyntax?.
            // Use labeled lookup when present; otherwise use positional lookup guarded by count.
            let argAccessor: String
            if let label = param.label {
                // Use the faster helper available in another package
                argAccessor = "syntax.argument(named: \"\(label)\")?.expression"
            } else {
                argAccessor = "(syntax.arguments.count > \(index) ? syntax.arguments[\(index)].expression : nil)"
            }

            if type.hasSuffix("?") {
                // Optional type - parse when argument is present, otherwise use default or nil
                let baseType = String(type.dropLast())

                if hasDefault {
                    // If default exists, perform a parsed-or-default assignment using if-expression
                    lines.append("\(indent)let \(varName) = if let expr = \(argAccessor), let parsed = \(baseType)(syntax: expr) { parsed } else { \(defaultVal) }")
                } else {
                    // No default, just try to parse the argument (may be nil)
                    lines.append("\(indent)let \(varName) = if let expr = \(argAccessor) { \(baseType)(syntax: expr) } else { nil }")
                }
            } else {
                // Non-optional (required) type
                if hasDefault {
                    // Use argument if present and parsable, otherwise fall back to the default value
                    lines.append("\(indent)let \(varName): \(type) = if let expr = \(argAccessor), let parsed = \(type)(syntax: expr) { parsed } else { \(defaultVal) }")
                } else {
                    // Required type - use guard with labeled/positional lookup
                    if let label = param.label {
                        lines.append("\(indent)guard let expr_\(varName) = syntax.argument(named: \"\(label)\")?.expression, let \(varName) = \(type)(syntax: expr_\(varName)) else {")
                    } else {
                        lines.append("\(indent)guard let expr_\(varName) = (syntax.arguments.count > \(index) ? syntax.arguments[\(index)].expression : nil), let \(varName) = \(type)(syntax: expr_\(varName)) else {")
                    }
                    let expectedTypes = nonClosureParams.map { cleanTypeForEnumCase($0.type) }.joined(separator: ", ")
                    lines.append("\(indent)    throw ModifierParseError.invalidArguments(modifier: \"\(enumName)\", variant: \"\(caseName)\", expectedTypes: \"\(expectedTypes)\")")
                    lines.append("\(indent)}")
                }
            }
        }
        
        let caseParams = nonClosureParams.enumerated().map { index, param -> String in
            let varName = param.label ?? "value\(index)"
            return param.label != nil ? "\(param.label!): \(varName)" : varName
        }.joined(separator: ", ")
        
        lines.append("\(indent)self = .\(caseName)(\(caseParams))")
        
        return lines
    }
    
    /// Generates an if-let condition for trying to parse a single variant.
    /// Returns the condition string and the variable bindings.
    private func generateIfLetCondition(for modifier: ModifierInfo, caseName: String) -> (condition: String, bindings: [(name: String, index: Int)]) {
        let nonClosureParams = modifier.parameters.filter { !isClosure($0.type) }
        var conditions: [String] = []
        var bindings: [(name: String, index: Int)] = []
        
        for (index, param) in nonClosureParams.enumerated() {
            let varName = param.label ?? "value\(index)"
            let type = cleanTypeForEnumCase(param.type)
            
            // If the parameter is optional or has a default value, it should not be required for the condition.
            if type.hasSuffix("?") || param.hasDefaultValue {
                // Optional parameters don't contribute to the condition
                // They'll be parsed separately
            } else {
                // Use labeled lookup when available, else positional
                if let label = param.label {
                    // We'll bind the expression first, then parse it
                    let exprName = "expr_\(varName)"
                    let exprBind = "let \(exprName) = syntax.argument(named: \"\(label)\")?.expression"
                    let parseBind = "let \(varName) = \(type)(syntax: \(exprName))"
                    conditions.append(exprBind + ", " + parseBind)
                } else {
                    let parseExpr = "\(type)(syntax: syntax.arguments[\(index)].expression)"
                    conditions.append("let \(varName) = \(parseExpr)")
                }
                bindings.append((name: varName, index: index))
            }
        }
        
        return (conditions.joined(separator: ", "), bindings)
    }
    
    /// Generates disambiguation logic for multiple variants with the same argument count.
    /// Uses if/else if chains to try each variant by type.
    private func generateDisambiguatedInitCases(for variants: [(ModifierInfo, String)], enumName: String, indent: String) -> [String] {
        var lines: [String] = []
        
        // Build a mapping of argument labels to variants
        // Use the first argument's label as the primary discriminator
        var variantsByFirstLabel: [String?: [(ModifierInfo, String)]] = [:]
        for (modifier, caseName) in variants {
            let nonClosureParams = modifier.parameters.filter { !isClosure($0.type) }
            let firstLabel = nonClosureParams.first?.label
            variantsByFirstLabel[firstLabel, default: []].append((modifier, caseName))
        }
        
        // If we can disambiguate by first argument label
        if variantsByFirstLabel.count > 1 {
            lines.append("\(indent)let firstLabel = syntax.arguments.first?.label?.text")
            lines.append("\(indent)switch firstLabel {")
            
            for (label, labelVariants) in variantsByFirstLabel.sorted(by: { ($0.key ?? "") < ($1.key ?? "") }) {
                if let label = label {
                    lines.append("\(indent)case \"\(label)\":")
                } else {
                    lines.append("\(indent)case nil:")
                }
                
                if labelVariants.count == 1 {
                    let (modifier, caseName) = labelVariants[0]
                    lines.append(contentsOf: generateInitCase(for: modifier, caseName: caseName, enumName: enumName, indent: indent + "    "))
                } else {
                    // Multiple variants with same label - try each by type
                    lines.append(contentsOf: generateTypeBasedDisambiguation(for: labelVariants, enumName: enumName, indent: indent + "    "))
                }
            }
            
            // Add default case for unexpected labels
            let expectedLabels = variantsByFirstLabel.keys.compactMap { $0 }.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("\(indent)default:")
            lines.append("\(indent)    throw ModifierParseError.ambiguousVariant(modifier: \"\(enumName)\", expectedLabels: [\(expectedLabels)])")
            lines.append("\(indent)}")
        } else {
            // Cannot disambiguate by label - try each variant by type
            lines.append(contentsOf: generateTypeBasedDisambiguation(for: variants, enumName: enumName, indent: indent))
        }
        
        return lines
    }
    
    /// Generates if/else if chain to try each variant by parsing their types.
    private func generateTypeBasedDisambiguation(for variants: [(ModifierInfo, String)], enumName: String, indent: String) -> [String] {
        var lines: [String] = []
        
        for (index, (modifier, caseName)) in variants.enumerated() {
            let nonClosureParams = modifier.parameters.filter { !isClosure($0.type) }
            
            // Build the if condition
            var conditions: [String] = []
            var optionalParams: [(varName: String, type: String, index: Int)] = []
            
            for (paramIndex, param) in nonClosureParams.enumerated() {
                let varName = param.label ?? "value\(paramIndex)"
                let type = cleanTypeForEnumCase(param.type)
                let hasDefault = param.hasDefaultValue

                // Build argument accessor for this parameter
                let argAccessor: String
                if let label = param.label {
                    argAccessor = "syntax.argument(named: \"\(label)\")?.expression"
                } else {
                    argAccessor = "(syntax.arguments.count > \(paramIndex) ? syntax.arguments[\(paramIndex)].expression : nil)"
                }

                if type.hasSuffix("?") {
                    // Track optional params to parse after the condition
                    let baseType = String(type.dropLast())
                    optionalParams.append((varName: varName, type: baseType, index: paramIndex))
                } else if hasDefault {
                    // Parameters with defaults are not required for the condition; parse in block
                    optionalParams.append((varName: varName, type: type, index: paramIndex))
                } else {
                    if let label = param.label {
                        let exprName = "expr_\(varName)"
                        let exprBind = "let \(exprName) = syntax.argument(named: \"\(label)\")?.expression"
                        let parseBind = "let \(varName) = \(type)(syntax: \(exprName))"
                        conditions.append(exprBind + ", " + parseBind)
                    } else {
                        let parseExpr = "\(type)(syntax: \(argAccessor)!)"
                        conditions.append("let \(varName) = \(parseExpr)")
                    }
                }
            }
            
            let keyword = index == 0 ? "if" : "} else if"
            
            if conditions.isEmpty {
                // All parameters are optional - this variant always matches
                if index == 0 {
                    // Just use this variant directly
                    for opt in optionalParams {
                        // Build an accessor for optional param
                        let argAccessor: String
                        if let label = nonClosureParams[opt.index].label {
                            argAccessor = "syntax.argument(named: \"\(label)\")?.expression"
                        } else {
                            argAccessor = "(syntax.arguments.count > \(opt.index) ? syntax.arguments[\(opt.index)].expression : nil)"
                        }
                        
                        // If parameter is optional (opt.type is base type without ?), parse into optional value
                        // Here opt.type is the base type for optional entries.
                        lines.append("\(indent)let \(opt.varName) = if let expr = \(argAccessor) { \(opt.type)(syntax: expr) } else { nil }")
                    }
                    let caseParams = nonClosureParams.enumerated().map { idx, param -> String in
                        let varName = param.label ?? "value\(idx)"
                        return param.label != nil ? "\(param.label!): \(varName)" : varName
                    }.joined(separator: ", ")
                    lines.append("\(indent)self = .\(caseName)(\(caseParams))")
                    return lines
                } else {
                    lines.append("\(indent)\(keyword) true {")
                }
            } else {
                lines.append("\(indent)\(keyword) \(conditions.joined(separator: ", ")) {")
            }
            
            // Parse optional and defaulted parameters inside the if block
            for opt in optionalParams {
                let label = nonClosureParams[opt.index].label
                let argAccessor: String
                if let label = label {
                    argAccessor = "syntax.argument(named: \"\(label)\")?.expression"
                } else {
                    argAccessor = "(syntax.arguments.count > \(opt.index) ? syntax.arguments[\(opt.index)].expression : nil)"
                }

                // If this param has a default value, we should fall back to it when parse fails.
                let hasDefault = nonClosureParams[opt.index].hasDefaultValue
                let defaultVal = nonClosureParams[opt.index].defaultValue ?? "nil"

                if hasDefault {
                    lines.append("\(indent)    let \(opt.varName) = { if let expr = \(argAccessor), let parsed = \(opt.type)(syntax: expr) { return parsed } else { return \(defaultVal) } }()")
                } else {
                    // No default - just try to parse (optional result)
                    lines.append("\(indent)    let \(opt.varName) = { if let expr = \(argAccessor) { return \(opt.type)(syntax: expr) } else { return nil } }()")
                }
            }
            
            // Build case parameters
            let caseParams = nonClosureParams.enumerated().map { idx, param -> String in
                let varName = param.label ?? "value\(idx)"
                return param.label != nil ? "\(param.label!): \(varName)" : varName
            }.joined(separator: ", ")
            
            lines.append("\(indent)    self = .\(caseName)(\(caseParams))")
        }
        
        // Add else clause with error
        let allExpectedTypes = variants.map { modifier, _ in
            let nonClosureParams = modifier.parameters.filter { !isClosure($0.type) }
            return nonClosureParams.map { cleanTypeForEnumCase($0.type) }.joined(separator: ", ")
        }.joined(separator: " or ")
        
        lines.append("\(indent)} else {")
        lines.append("\(indent)    throw ModifierParseError.invalidArguments(modifier: \"\(enumName)\", variant: \"multiple variants\", expectedTypes: \"\(allExpectedTypes)\")")
        lines.append("\(indent)}")
        
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
