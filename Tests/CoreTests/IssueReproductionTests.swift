import XCTest

@testable import Core

final class IssueReproductionTests: XCTestCase {
    var sut: EnumGenerator!

    override func setUp() {
        super.setUp()
        sut = EnumGenerator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func test_generate_withErasableTypeAndDefaultValue_wrapsDefaultValue() throws {
        // Arrange
        // glassEffect(_ glass: SwiftUICore.Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())
        let modifiers = [
            ModifierInfo(
                name: "glassEffect",
                parameters: [
                    .init(
                        label: "in", name: "shape", type: "some Shape", hasDefaultValue: true,
                        defaultValue: "DefaultGlassEffectShape()")
                ],
                returnType: "some View"
            )
        ]

        // Act
        let result = try sut.generate(enumName: "GlassModifier", modifiers: modifiers)

        // Assert
        // Should contain AnyShape(DefaultGlassEffectShape())
        // Currently expected to FAIL (it will contain "?? DefaultGlassEffectShape()")
        XCTAssertTrue(
            result.sourceCode.contains("?? AnyShape(DefaultGlassEffectShape())"),
            "Default value should be wrapped in type eraser")
    }

    func test_generate_withGenericErasureAndDefaultValue_wrapsDefaultValue() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "generic",
                parameters: [
                    .init(
                        label: nil, name: "view", type: "V", hasDefaultValue: true,
                        defaultValue: "EmptyView()")
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "V", constraint: "View")
                ]
            )
        ]

        // Act
        let result = try sut.generate(enumName: "GenericModifier", modifiers: modifiers)

        // Assert
        // Should contain ViewReference<Library>(EmptyView())
        XCTAssertTrue(
            result.sourceCode.contains("?? ViewReference<Library>(EmptyView())"),
            "Default value should be wrapped in ViewReference<Library>")
    }

    func test_generate_withOptionalGenericAndDefaultValue_wrapsDefaultValue() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "genericOptional",
                parameters: [
                    .init(
                        label: nil, name: "view", type: "V?", hasDefaultValue: true,
                        defaultValue: "EmptyView()")
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "V", constraint: "View")
                ]
            )
        ]

        // Act
        let result = try sut.generate(enumName: "GenericOptionalModifier", modifiers: modifiers)

        // Assert
        // Should contain ViewReference<Library>(EmptyView()) - promoted to ViewReference<Library>?
        XCTAssertTrue(
            result.sourceCode.contains("?? ViewReference<Library>(EmptyView())"),
            "Default value should be wrapped in ViewReference<Library>")
    }
}
