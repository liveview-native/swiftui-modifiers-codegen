import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

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
    public func generate(enumName: String, modifiers: [ModifierInfo]) throws -> GeneratedCode {
        guard !modifiers.isEmpty else {
            throw GenerationError.invalidModifierInfo("Cannot generate enum with no modifiers")
        }

        // 1. Transform generics to type erasers
        let erasedModifiers = modifiers.map { transformModifierForTypeErasure($0) }

        // 2. Transform View-returning closures to ViewReference<Library>
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
            originalModifiers: modifiers,
            erasedModifiers: erasedModifiers
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
                case noMatchingVariant(modifier: String, errors: [Error])
                case missingRequiredArgument(modifier: String, argument: String)

                public var description: String {
                    switch self {
                    case .unexpectedArgumentCount(let modifier, let expected, let found):
                        return "\\(modifier): unexpected argument count \\(found), expected one of \\(expected)"
                    case .invalidArguments(let modifier, let variant, let expectedTypes):
                        return "\\(modifier): invalid arguments for '\\(variant)', expected types: \\(expectedTypes)"
                    case .ambiguousVariant(let modifier, let expectedLabels):
                        return "\\(modifier): ambiguous variant, expected first argument label to be one of \\(expectedLabels)"
                    case .noMatchingVariant(let modifier, let errors):
                        return "\\(modifier): no matching variant found. Errors: \\(errors)"
                    case .missingRequiredArgument(let modifier, let argument):
                        return "\\(modifier): missing required argument '\\(argument)'"
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

    private func transformModifierForTypeErasure(_ modifier: ModifierInfo) -> ModifierInfo {
        // Build a map of generic parameter names to their erased types
        var genericErasures: [String: String] = [:]
        if modifier.isGeneric {
            for genericParam in modifier.genericParameters {
                if let constraint = genericParam.constraint,
                    var eraser = TypeEraserMapping.eraser(for: constraint)
                {
                    if eraser == "AnyView" {
                        eraser = "ViewReference<Library>"
                    }
                    genericErasures[genericParam.name] = eraser
                }
            }
        }

        let transformedParams = modifier.parameters.map { param -> ModifierInfo.Parameter in
            var newType = replaceGenericTypes(in: param.type, with: genericErasures)
            var newDefaultValue = param.defaultValue

            // Check if we are applying an eraser to this type (either via generics or direct mapping)
            // We strip '?' to handle optional types like `V?` -> `AnyView?`
            let typeClean = param.type.trimmingCharacters(in: .whitespaces).replacingOccurrences(
                of: "?", with: "")
            var appliedEraser: String?

            // 1. Check if it matches a generic we are erasing (e.g. V -> AnyView)
            if let eraser = genericErasures[typeClean] {
                appliedEraser = eraser
            }
            // 2. Check if the type itself is erasable (e.g. some Shape -> AnyShape)
            // Note: We check `newType` here because it might have been modified by replaceGenericTypes,
            // but for "some Shape" it remains "some Shape" until the next block.
            // We use `typeClean` to check the original type structure.
            else if var eraser = TypeEraserMapping.eraser(for: typeClean) {
                if eraser == "AnyView" {
                    eraser = "ViewReference<Library>"
                }
                appliedEraser = eraser
            }

            // Check if the type itself (even if not generic) needs erasure (e.g. "some Shape")
            if var eraser = TypeEraserMapping.eraser(for: newType) {
                if eraser == "AnyView" {
                    eraser = "ViewReference<Library>"
                }
                newType = eraser
                // Ensure we capture this eraser if we haven't already
                if appliedEraser == nil {
                    appliedEraser = eraser
                }
            }

            // If we have an eraser and a default value (that isn't nil), wrap it
            if let eraser = appliedEraser,
                let val = newDefaultValue,
                val != "nil"
            {
                newDefaultValue = "\(eraser)(\(val))"
            }

            return ModifierInfo.Parameter(
                label: param.label,
                name: param.name,
                type: newType,
                hasDefaultValue: param.hasDefaultValue,
                defaultValue: newDefaultValue
            )
        }

        return ModifierInfo(
            name: modifier.name,
            parameters: transformedParams,
            returnType: modifier.returnType,
            availability: modifier.availability,
            buildCondition: modifier.buildCondition,
            documentation: modifier.documentation,
            isGeneric: modifier.isGeneric,
            genericConstraints: modifier.genericConstraints,
            genericParameters: modifier.genericParameters
        )
    }

    private func transformClosuresToViewReference(_ modifier: ModifierInfo) -> ModifierInfo {
        let newParams = modifier.parameters.map { param -> ModifierInfo.Parameter in
            if isViewReturningClosure(param.type, genericParams: modifier.genericParameters) {
                return ModifierInfo.Parameter(
                    label: param.label,
                    name: param.name,
                    type: "ViewReference<Library>",
                    hasDefaultValue: param.hasDefaultValue,
                    defaultValue: param.defaultValue
                )
            }
            return param
        }

        return ModifierInfo(
            name: modifier.name,
            parameters: newParams,
            returnType: modifier.returnType,
            availability: modifier.availability,
            buildCondition: modifier.buildCondition,
            documentation: modifier.documentation,
            isGeneric: modifier.isGeneric,
            genericConstraints: modifier.genericConstraints,
            genericParameters: modifier.genericParameters
        )
    }

    private func replaceGenericTypes(in type: String, with erasures: [String: String]) -> String {
        var result = type
        for (genericName, erasedType) in erasures {
            let pattern = "\\b\(genericName)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result, options: [], range: NSRange(result.startIndex..., in: result),
                    withTemplate: erasedType)
            }
        }
        return result
    }

    private func isViewReturningClosure(
        _ type: String, genericParams: [ModifierInfo.GenericParameter]
    ) -> Bool {
        guard type.contains("->") else { return false }

        let cleaned = type.replacingOccurrences(of: "@escaping", with: "")
            .replacingOccurrences(of: "@ViewBuilder", with: "")
            .trimmingCharacters(in: .whitespaces)

        let components = cleaned.components(separatedBy: "->")
        guard let returnType = components.last?.trimmingCharacters(in: .whitespaces) else {
            return false
        }

        if returnType == "some View" || returnType == "View" || returnType == "SwiftUI.View"
            || returnType == "AnyView" || returnType.hasPrefix("ViewReference")
        {
            return true
        }

        for param in genericParams {
            if returnType == param.name, let constraint = param.constraint,
                constraint.contains("View")
            {
                return true
            }
        }

        return false
    }

    // MARK: - Code Generation

    private func buildEnumSource(
        enumName: String, cases: [String], modifiers: [ModifierInfo], caseNames: [String],
        originalModifiers: [ModifierInfo], erasedModifiers: [ModifierInfo]
    ) -> String {
        var lines: [String] = []

        lines.append("import SwiftUI")
        lines.append("import SwiftSyntax")
        lines.append("")
        lines.append("/// Generated modifier enum for \(enumName) modifiers.")
        lines.append("/// Generated by ModifierSwift.")
        lines.append("public enum \(enumName)<Library: ElementLibrary>: @unchecked Sendable {")
        for caseStr in cases {
            lines.append("    \(caseStr)")
        }
        lines.append("}")
        lines.append("")

        lines.append("extension \(enumName): RuntimeViewModifier {")
        lines.append(
            "    public static var baseName: String { \"\(originalModifiers.first?.name ?? "modifier")\" }"
        )
        lines.append("")
        lines.append("    public init(syntax: FunctionCallExprSyntax) throws {")
        lines.append("        var errors: [Error] = []")

        let variants = zip(modifiers, caseNames).map { ($0, $1) }
        let sortedVariants = variants.sorted { (v1, v2) in
            let req1 = v1.0.parameters.filter { !$0.hasDefaultValue }.count
            let req2 = v2.0.parameters.filter { !$0.hasDefaultValue }.count
            if req1 != req2 { return req1 > req2 }
            return v1.0.parameters.count > v2.0.parameters.count
        }

        for (modifier, caseName) in sortedVariants {
            if let condition = modifier.buildCondition {
                lines.append("        #if \(condition)")
            }

            if let avail = modifier.availability {
                lines.append("        if #available(\(avail)) {")
                lines.append("            do {")
                lines.append(
                    contentsOf: generateVariantTryBlock(
                        modifier, caseName: caseName, enumName: enumName, indent: "                "
                    ))
                lines.append("                return")
                lines.append("            } catch {")
                lines.append("                errors.append(error)")
                lines.append("            }")
                lines.append("        }")
            } else {
                lines.append("        do {")
                lines.append(
                    contentsOf: generateVariantTryBlock(
                        modifier, caseName: caseName, enumName: enumName, indent: "            "))
                lines.append("            return")
                lines.append("        } catch {")
                lines.append("            errors.append(error)")
                lines.append("        }")
            }

            if modifier.buildCondition != nil {
                lines.append("        #endif")
            }
        }

        lines.append(
            "        throw ModifierParseError.noMatchingVariant(modifier: \"\(enumName)\", errors: errors)"
        )
        lines.append("    }")

        lines.append("    @ViewBuilder")
        lines.append("    public func body(content _content: Content) -> some View {")
        lines.append("        switch self {")
        for (i, (modifier, caseName)) in zip(modifiers, caseNames).enumerated() {
            let erasedModifier = erasedModifiers[i]
            if let condition = modifier.buildCondition {
                lines.append("        #if \(condition)")
            }

            lines.append(
                "        \(generateBodyCase(for: modifier, erasedModifier: erasedModifier, caseName: caseName))"
            )

            if modifier.buildCondition != nil {
                lines.append("        #endif")
            }
        }
        lines.append("        }")
        lines.append("    }")
        lines.append("}")

        return lines.joined(separator: "\n")
    }

    private func generateVariantTryBlock(
        _ modifier: ModifierInfo, caseName: String, enumName: String, indent: String
    ) -> [String] {
        var lines: [String] = []

        for (index, param) in modifier.parameters.enumerated() {
            let varName = escapeKeyword(param.label ?? "value\(index)")

            let type = cleanTypeForEnumCase(param.type)
            let isOptional = type.hasSuffix("?")
            let baseType = isOptional ? String(type.dropLast()) : type

            let accessor: String
            if let label = param.label {
                accessor = "syntax.argument(named: \"\(label)\")"
            } else {
                accessor = "(syntax.arguments.count > \(index) ? syntax.arguments[\(index)] : nil)"
            }

            let parseExpr: String
            if param.type.hasPrefix("ViewReference") {
                parseExpr = "\(accessor).flatMap({ ViewReference<Library>(syntax: $0.expression) })"
            } else {
                parseExpr = "\(accessor).flatMap({ \(baseType)(syntax: $0.expression) })"
            }

            if param.hasDefaultValue || isOptional {
                let defaultVal =
                    param.defaultValue ?? (isOptional ? "nil" : "/* error: no default */")
                lines.append("\(indent)let \(varName): \(type) = \(parseExpr) ?? \(defaultVal)")
            } else {
                lines.append("\(indent)guard let \(varName) = \(parseExpr) else {")
                lines.append(
                    "\(indent)    throw ModifierParseError.missingRequiredArgument(modifier: \"\(enumName)\", argument: \"\(param.name)\")"
                )
                lines.append("\(indent)}")
            }
        }

        let args = modifier.parameters.enumerated().map { i, p in
            let name = escapeKeyword(p.label ?? "value\(i)")
            return p.label != nil ? "\(p.label!): \(name)" : name
        }.joined(separator: ", ")

        if modifier.parameters.isEmpty {
            lines.append("\(indent)self = .\(caseName)")
        } else {
            lines.append("\(indent)self = .\(caseName)(\(args))")
        }
        return lines
    }

    // MARK: - Helpers

    private func escapeKeyword(_ name: String) -> String {
        let keywords = [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
            "import", "init", "inout", "internal", "let", "open", "operator", "private",
            "protocol", "public", "static", "struct", "subscript", "typealias", "var",
            "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
            "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
            "as", "Any", "catch", "false", "is", "nil", "rethrows", "super", "self", "Self",
            "throw", "throws", "true", "try",
        ]

        return keywords.contains(name) ? "`\(name)`" : name
    }

    private func generateEnumCase(for modifier: ModifierInfo, caseName: String) throws -> String {
        var caseLine = "case \(caseName)"

        if !modifier.parameters.isEmpty {
            let params = modifier.parameters.map { p in
                let t = cleanTypeForEnumCase(p.type)
                let typeStr = modifier.availability != nil ? "Any" : t

                if let label = p.label {
                    return "\(label): \(typeStr)"
                } else {
                    return typeStr
                }
            }.joined(separator: ", ")
            caseLine += "(\(params))"
        }

        if let condition = modifier.buildCondition {
            caseLine = "#if \(condition)\n    \(caseLine)\n    #endif"
        }

        return caseLine
    }

    private func generateBodyCase(
        for modifier: ModifierInfo, erasedModifier: ModifierInfo, caseName: String
    ) -> String {
        let patternParams = modifier.parameters.enumerated().map { i, p in
            let suffix = modifier.availability != nil ? "Any" : ""
            let rawName = p.label ?? "value\(i)"
            let escapedName = escapeKeyword(rawName + suffix)

            if let label = p.label {
                return "\(label): let \(escapedName)"
            } else {
                return "let \(escapedName)"
            }
        }.joined(separator: ", ")

        let pattern =
            modifier.parameters.isEmpty
            ? "case .\(caseName)" : "case .\(caseName)(\(patternParams))"

        var prepCalls: [String] = []
        var calls: [String] = []

        for (i, p) in modifier.parameters.enumerated() {
            let suffix = modifier.availability != nil ? "Any" : ""
            let sourceVarName = escapeKeyword((p.label ?? "value\(i)") + suffix)
            let usageVarName = escapeKeyword(p.label ?? "value\(i)")
            let type = cleanTypeForEnumCase(p.type)
            // Use erasedModifier to check the *erased* type before it was potentially flattened.
            // If the erased type was a closure (e.g. () -> ViewReference), we want to wrap it.
            // If it was just ViewReference, we pass it directly.
            let erasedParam = erasedModifier.parameters[i]

            if modifier.availability != nil {
                prepCalls.append("let \(usageVarName) = \(sourceVarName) as? \(type)")
            }

            // Check if we need to wrap in closure:
            // We use erasedParam.type because that preserves the `() -> ViewReference` vs `ViewReference` distinction.
            // isViewReturningClosure will be true for `() -> ViewReference` and false for `ViewReference`.
            if isViewReturningClosure(
                erasedParam.type, genericParams: erasedModifier.genericParameters)
            {
                let arg =
                    p.label != nil ? "\(p.label!): { \(usageVarName) }" : "{ \(usageVarName) }"
                calls.append(arg)
            } else {
                let arg = p.label != nil ? "\(p.label!): \(usageVarName)" : usageVarName
                calls.append(arg)
            }
        }

        let methodCall = "_content.\(modifier.name)(\(calls.joined(separator: ", ")))"

        if let avail = modifier.availability {
            let castLogic: String
            if !prepCalls.isEmpty {
                let conditions = prepCalls.joined(separator: ", ")
                castLogic = """
                    if \(conditions) {
                        \(methodCall)
                    } else {
                        _content
                    }
                    """
            } else {
                castLogic = methodCall
            }

            let indentedCastLogic = castLogic.split(separator: "\n").map { "    " + $0 }.joined(
                separator: "\n")

            let lines = [
                "if #available(\(avail)) {",
                indentedCastLogic,
                "} else {",
                "    _content",
                "}",
            ]

            let indentedBlock = lines.enumerated().map { i, line in
                if i == 0 { return line }
                return "            " + line
            }.joined(separator: "\n")

            return "\(pattern):\n            \(indentedBlock)"
        }

        return "\(pattern):\n            \(methodCall)"
    }

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
        if type.hasPrefix("ViewReference") { return "View" }
        return type.replacingOccurrences(of: "[", with: "Array")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "?", with: "Optional")
            .filter { $0.isLetter || $0.isNumber }
    }

    private func cleanTypeForEnumCase(_ type: String) -> String {
        type.replacingOccurrences(of: "@escaping", with: "")
            .replacingOccurrences(of: "@ViewBuilder", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
