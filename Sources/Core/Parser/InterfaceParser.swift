import Foundation
import SwiftSyntax
import SwiftParser

/// Parses SwiftUI .swiftinterface files to extract modifier methods.
public struct InterfaceParser: Sendable {
    public enum ParsingError: Error, Equatable {
        case fileNotFound(String)
        case invalidSyntax(String)
        case unsupportedConstruct(String)
    }
    
    public init() {}
    
    public func parse(filePath: String) throws -> [ModifierInfo] {
        guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            throw ParsingError.fileNotFound(filePath)
        }
        return try parse(source: source)
    }
    
    public func parse(source: String) throws -> [ModifierInfo] {
        let sourceFile = Parser.parse(source: source)
        var modifiers: [ModifierInfo] = []
        
        for statement in sourceFile.statements {
            if let extensionDecl = statement.item.as(ExtensionDeclSyntax.self) {
                modifiers.append(contentsOf: parseExtension(extensionDecl))
            }
        }
        
        return modifiers
    }
    
    // MARK: - Private Parsing Methods
    
    private func parseExtension(_ ext: ExtensionDeclSyntax) -> [ModifierInfo] {
        guard isViewExtension(ext) else { return [] }
        
        var modifiers: [ModifierInfo] = []
        
        for member in ext.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                if let modifier = parseFunction(funcDecl) {
                    modifiers.append(modifier)
                }
            } else if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                modifiers.append(contentsOf: parseFunctionsFromIfConfig(ifConfigDecl))
            }
        }
        
        return modifiers
    }
    
    private func parseFunctionsFromIfConfig(_ ifConfig: IfConfigDeclSyntax) -> [ModifierInfo] {
        var modifiers: [ModifierInfo] = []
        
        for clause in ifConfig.clauses {
            var clauseCondition: String? = nil
            if let cond = clause.condition {
                clauseCondition = sanitizeCondition(cond.description)
            }
            
            if let elements = clause.elements?.as(MemberBlockItemListSyntax.self) {
                for member in elements {
                    if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                        if let modifier = parseFunction(funcDecl, inheritedCondition: clauseCondition) {
                            modifiers.append(modifier)
                        }
                    } else if let nestedIfConfig = member.decl.as(IfConfigDeclSyntax.self) {
                        let nestedModifiers = parseFunctionsFromIfConfig(nestedIfConfig)
                        
                        if let parentCond = clauseCondition {
                            let merged = nestedModifiers.map { mod -> ModifierInfo in
                                let combinedCond: String
                                if let childCond = mod.buildCondition {
                                    combinedCond = "(\(parentCond)) && (\(childCond))"
                                } else {
                                    combinedCond = parentCond
                                }
                                return ModifierInfo(
                                    name: mod.name,
                                    parameters: mod.parameters,
                                    returnType: mod.returnType,
                                    availability: mod.availability,
                                    buildCondition: combinedCond,
                                    documentation: mod.documentation,
                                    isGeneric: mod.isGeneric,
                                    genericConstraints: mod.genericConstraints,
                                    genericParameters: mod.genericParameters
                                )
                            }
                            modifiers.append(contentsOf: merged)
                        } else {
                            modifiers.append(contentsOf: nestedModifiers)
                        }
                    }
                }
            }
        }
        return modifiers
    }
    
    private func sanitizeCondition(_ raw: String) -> String? {
        let range = NSRange(location: 0, length: raw.utf16.count)
        let regex = try? NSRegularExpression(pattern: "!?os\\([^)]+\\)")
        
        guard let matches = regex?.matches(in: raw, range: range), !matches.isEmpty else {
            return nil
        }
        
        let conditions = matches.map { match -> String in
            if let range = Range(match.range, in: raw) {
                return String(raw[range])
            }
            return ""
        }
        
        return conditions.joined(separator: " || ")
    }
    
    private func isViewExtension(_ ext: ExtensionDeclSyntax) -> Bool {
        let typeName = ext.extendedType.description.trimmingCharacters(in: .whitespaces)
        return typeName.contains("View") && 
               !typeName.contains("ViewModifier") &&
               !typeName.contains("ViewDimensions")
    }
    
    private func parseFunction(_ funcDecl: FunctionDeclSyntax, inheritedCondition: String? = nil) -> ModifierInfo? {
        guard isPublicFunction(funcDecl) else { return nil }
        
        let name = funcDecl.name.text
        let parameters = extractParameters(from: funcDecl.signature.parameterClause)
        let returnType = extractReturnType(from: funcDecl.signature.returnClause)
        
        let (availability, attrBuildCondition) = analyzeAttributes(funcDecl.attributes)
        
        var buildCondition = inheritedCondition
        if let attrCond = attrBuildCondition {
            if let existing = buildCondition {
                buildCondition = "(\(existing)) && (\(attrCond))"
            } else {
                buildCondition = attrCond
            }
        }
        
        let documentation = extractDocumentation(from: funcDecl.leadingTrivia)
        let isGeneric = funcDecl.genericParameterClause != nil
        let genericConstraints = extractGenericConstraints(from: funcDecl.genericWhereClause)
        let genericParameters = extractGenericParameters(from: funcDecl.genericParameterClause, whereClause: funcDecl.genericWhereClause)
        
        return ModifierInfo(
            name: name,
            parameters: parameters,
            returnType: returnType,
            availability: availability,
            buildCondition: buildCondition,
            documentation: documentation,
            isGeneric: isGeneric,
            genericConstraints: genericConstraints,
            genericParameters: genericParameters
        )
    }
    
    private func analyzeAttributes(_ attributes: AttributeListSyntax?) -> (availability: String?, buildCondition: String?) {
        guard let attributes = attributes else { return (nil, nil) }
        
        var availablePlatforms: [String] = []
        var unavailablePlatforms: [String] = []
        var availabilityEntries: [String] = []
        
        for element in attributes {
            guard let attr = element.as(AttributeSyntax.self),
                  let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
                  attrName == "available",
                  let arguments = attr.arguments?.as(AvailabilityArgumentListSyntax.self)
            else { continue }
            
            // Ignore swift language version checks
            if let firstArg = arguments.first?.argument.as(TokenSyntax.self), firstArg.text == "swift" {
                continue
            }
            
            // Check for unavailability
            var isUnavailable = false
            for arg in arguments {
                if let token = arg.argument.as(TokenSyntax.self), token.text == "unavailable" {
                    isUnavailable = true
                    break
                }
            }
            
            if isUnavailable {
                if let firstArg = arguments.first?.argument {
                    let platformText = firstArg.as(PlatformVersionSyntax.self)?.platform.text 
                                    ?? firstArg.as(TokenSyntax.self)?.text
                    if let platform = platformText {
                        unavailablePlatforms.append(platform)
                    }
                }
            } else {
                // Parse Availability entries statefully
                var currentPlatform: String? = nil
                
                for arg in arguments {
                    let description = arg.argument.description.trimmingCharacters(in: .whitespaces)
                    
                    // 1. Check for PlatformVersion syntax (e.g. "iOS 13.0")
                    if let platformVer = arg.argument.as(PlatformVersionSyntax.self) {
                        let versionStr = platformVer.version?.description ?? ""
                        let entry = "\(platformVer.platform.text) \(versionStr)".trimmingCharacters(in: .whitespaces)
                        
                        availabilityEntries.append(entry)
                        availablePlatforms.append(platformVer.platform.text)
                        currentPlatform = nil // Reset state
                    } 
                    // 2. Check for Token syntax (e.g. "iOS", "*", "deprecated")
                    else if let token = arg.argument.as(TokenSyntax.self) {
                        let text = token.text
                        
                        if ["iOS", "macOS", "tvOS", "watchOS", "visionOS"].contains(text) {
                            currentPlatform = text
                            availablePlatforms.append(text)
                        } else if text == "*" {
                            // We add * later manually to ensure it's at the end
                        }
                    }
                    // 3. Check for Labeled Syntax (e.g. "introduced: 13.0")
                    else if description.hasPrefix("introduced:") {
                        if let platform = currentPlatform {
                            // Extract version part
                            let version = description.replacingOccurrences(of: "introduced:", with: "").trimmingCharacters(in: .whitespaces)
                            availabilityEntries.append("\(platform) \(version)")
                            currentPlatform = nil
                        }
                    }
                }
            }
        }
        
        // Construct availability string
        var availabilityString: String? = nil
        if !availabilityEntries.isEmpty {
            // Deduplicate entries roughly
            let uniqueEntries = Array(Set(availabilityEntries)).sorted()
            availabilityString = uniqueEntries.joined(separator: ", ") + ", *"
        }
        
        // Construct Build Condition
        var buildCondition: String? = nil
        
        if !availablePlatforms.isEmpty && !unavailablePlatforms.isEmpty {
            let conditions = availablePlatforms.map { "os(\($0))" }
            buildCondition = conditions.joined(separator: " || ")
        } else if !unavailablePlatforms.isEmpty {
            let conditions = unavailablePlatforms.map { "!os(\($0))" }
            buildCondition = conditions.joined(separator: " && ")
        } else if !availablePlatforms.isEmpty {
            let conditions = availablePlatforms.map { "os(\($0))" }
            buildCondition = conditions.joined(separator: " || ")
        }
        
        return (availabilityString, buildCondition)
    }
    
    private func isPublicFunction(_ funcDecl: FunctionDeclSyntax) -> Bool {
        return funcDecl.modifiers.contains { $0.name.text == "public" }
    }
    
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
    
    private func extractReturnType(from clause: ReturnClauseSyntax?) -> String {
        guard let clause = clause else { return "Void" }
        return clause.type.description.trimmingCharacters(in: .whitespaces)
    }
    
    private func extractDocumentation(from trivia: Trivia?) -> String? {
        guard let trivia = trivia else { return nil }
        var docLines: [String] = []
        for piece in trivia {
            switch piece {
            case .docLineComment(let text): docLines.append(text)
            case .docBlockComment(let text): docLines.append(text)
            default: continue
            }
        }
        return docLines.isEmpty ? nil : docLines.joined(separator: "\n")
    }
    
    private func extractGenericConstraints(from clause: GenericWhereClauseSyntax?) -> [String] {
        guard let clause = clause else { return [] }
        return clause.requirements.map { $0.description.trimmingCharacters(in: .whitespaces) }
    }
    
    private func extractGenericParameters(from clause: GenericParameterClauseSyntax?, whereClause: GenericWhereClauseSyntax?) -> [ModifierInfo.GenericParameter] {
        guard let clause = clause else { return [] }
        
        var constraintMap: [String: String] = [:]
        if let whereClause = whereClause {
            for requirement in whereClause.requirements {
                if let conformance = requirement.requirement.as(ConformanceRequirementSyntax.self) {
                    constraintMap[conformance.leftType.description.trimmingCharacters(in: .whitespaces)] = conformance.rightType.description.trimmingCharacters(in: .whitespaces)
                } else if let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self) {
                    constraintMap[sameType.leftType.description.trimmingCharacters(in: .whitespaces)] = sameType.rightType.description.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return clause.parameters.map { param in
            let name = param.name.text
            var constraint: String? = param.inheritedType?.description.trimmingCharacters(in: .whitespaces)
            if let whereConstraint = constraintMap[name] {
                constraint = whereConstraint
            }
            return ModifierInfo.GenericParameter(name: name, constraint: constraint)
        }
    }
}