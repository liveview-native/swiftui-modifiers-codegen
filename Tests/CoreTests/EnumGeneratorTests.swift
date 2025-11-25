import XCTest
@testable import Core

final class EnumGeneratorTests: XCTestCase {
    var sut: EnumGenerator!
    
    override func setUp() {
        super.setUp()
        sut = EnumGenerator()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Basic Generation Tests
    
    func test_generate_withSimpleModifier_generatesEnum() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(result.modifierCount, 1)
        XCTAssertTrue(result.sourceCode.contains("public enum PaddingModifier"))
        XCTAssertTrue(result.sourceCode.contains("case padding"))
        XCTAssertTrue(result.sourceCode.contains("content.padding()"))
    }
    
    func test_generate_withParameterizedModifier_generatesEnumWithAssociatedValues() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "padding",
                parameters: [
                    .init(label: nil, name: "edges", type: "Edge.Set"),
                    .init(label: nil, name: "length", type: "CGFloat?")
                ],
                returnType: "some View"
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("case padding(Edge.Set, CGFloat?)"))
    }
    
    func test_generate_withLabeledParameters_usesLabels() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "background",
                parameters: [
                    .init(label: "alignment", name: "alignment", type: "Alignment")
                ],
                returnType: "some View"
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "BackgroundModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("case background(alignment: Alignment)"))
        XCTAssertTrue(result.sourceCode.contains("content.background(alignment: alignment)"))
    }
    
    // MARK: - Multiple Modifiers Tests
    
    func test_generate_withMultipleVariants_generatesAllCases() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View"),
            ModifierInfo(
                name: "padding",
                parameters: [.init(label: nil, name: "length", type: "CGFloat")],
                returnType: "some View"
            ),
            ModifierInfo(
                name: "padding",
                parameters: [.init(label: nil, name: "insets", type: "EdgeInsets")],
                returnType: "some View"
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertEqual(result.modifierCount, 3)
        XCTAssertTrue(result.sourceCode.contains("case padding"))
        XCTAssertTrue(result.sourceCode.contains("case paddingWithCGFloat"))
        XCTAssertTrue(result.sourceCode.contains("case paddingWithEdgeInsets"))
    }
    
    // MARK: - RuntimeViewModifier Conformance Tests
    
    func test_generate_includesRuntimeViewModifierConformance() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("RuntimeViewModifier"))
        XCTAssertTrue(result.sourceCode.contains("static var baseName: String"))
        XCTAssertTrue(result.sourceCode.contains("\"padding\""))
    }
    
    func test_generate_includesInitFromSyntax() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("init(syntax: FunctionCallExprSyntax)"))
        XCTAssertTrue(result.sourceCode.contains("switch syntax.arguments.count"))
    }
    
    func test_generate_includesBodyMethod() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("func body(content: Content) -> some View"))
        XCTAssertTrue(result.sourceCode.contains("switch self"))
    }
    
    func test_generate_withParameters_generatesBodyWithBindings() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "frame",
                parameters: [
                    .init(label: "width", name: "w", type: "CGFloat?"),
                    .init(label: "height", name: "h", type: "CGFloat?")
                ],
                returnType: "some View"
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "FrameModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("case .frame(let width, let height):"))
        XCTAssertTrue(result.sourceCode.contains("content.frame(width: width, height: height)"))
    }
    
    // MARK: - Documentation Tests
    
    func test_generate_includesDocumentation() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("/// Generated modifier enum"))
        XCTAssertTrue(result.sourceCode.contains("/// This enum provides type-safe access"))
    }
    
    // MARK: - Import Tests
    
    func test_generate_includesImports() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("import SwiftUI"))
        XCTAssertTrue(result.sourceCode.contains("import SwiftSyntax"))
    }
    
    // MARK: - File Name Tests
    
    func test_generate_setsCorrectFileName() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertEqual(result.fileName, "PaddingModifier.swift")
    }
    
    // MARK: - Error Cases Tests
    
    func test_generate_withEmptyModifiers_throwsError() {
        // Arrange
        let modifiers: [ModifierInfo] = []
        
        // Act & Assert
        XCTAssertThrowsError(try sut.generate(enumName: "Empty", modifiers: modifiers)) { error in
            if case EnumGenerator.GenerationError.invalidModifierInfo(let message) = error {
                XCTAssertTrue(message.contains("no modifiers"))
            } else {
                XCTFail("Expected invalidModifierInfo error")
            }
        }
    }
    
    // MARK: - Conformance Tests
    
    func test_generate_enumConformsToEquatable() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("Equatable"))
    }
    
    func test_generate_enumConformsToSendable() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "padding", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "PaddingModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("Sendable"))
    }
    
    // MARK: - Closure Handling Tests
    
    func test_generate_withClosureParameter_excludesClosureFromEnumCase() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "onTapGesture",
                parameters: [
                    .init(label: "count", name: "count", type: "Int"),
                    .init(label: "perform", name: "action", type: "@escaping () -> Void")
                ],
                returnType: "some View"
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "OnTapGestureModifier", modifiers: modifiers)
        
        // Assert
        // Closure should be excluded from enum case
        XCTAssertTrue(result.sourceCode.contains("case onTapGesture(count: Int)"))
        XCTAssertFalse(result.sourceCode.contains("@escaping"))
    }
    
    // MARK: - Type Erasure Tests
    
    func test_generate_withGenericViewParameter_usesAnyView() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "overlay",
                parameters: [
                    .init(label: nil, name: "overlay", type: "Content")
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "Content", constraint: "View")
                ]
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "OverlayModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("AnyView"))
    }
    
    func test_generate_withGenericStringParameter_usesString() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "accessibilityLabel",
                parameters: [
                    .init(label: nil, name: "label", type: "S")
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "S", constraint: "StringProtocol")
                ]
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "AccessibilityLabelModifier", modifiers: modifiers)
        
        // Assert
        XCTAssertTrue(result.sourceCode.contains("String"))
    }
    
    // MARK: - Case Name Sanitization Tests
    
    func test_generate_withUnderscorePrefix_generatesValidCaseName() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "_makeView", parameters: [], returnType: "some View")
        ]
        
        // Act
        let result = try sut.generate(enumName: "InternalModifier", modifiers: modifiers)
        
        // Assert
        // Should convert _makeView to underscoreMakeView or similar valid case name
        XCTAssertTrue(result.sourceCode.contains("case underscore"))
    }
    
    func test_generate_withSpecialCharactersInType_sanitizesCaseName() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "action",
                parameters: [
                    .init(label: nil, name: "action", type: "@escaping () -> Void"),
                    .init(label: nil, name: "label", type: "() -> Label")
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "Label", constraint: "View")
                ]
            )
        ]
        
        // Act
        let result = try sut.generate(enumName: "ActionModifier", modifiers: modifiers)
        
        // Assert
        // Case name should not contain special characters
        XCTAssertFalse(result.sourceCode.contains("case action("))
        // Should be a simple case since all params are closures
        XCTAssertTrue(result.sourceCode.contains("case action"))
    }
}
