import XCTest

@testable import Core

final class VerifyFixesTests: XCTestCase {
    var sut: EnumGenerator!

    override func setUp() {
        super.setUp()
        sut = EnumGenerator()
    }

    func test_combinedFixes_generatesCorrectCode() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "overlay",
                parameters: [
                    .init(
                        label: "alignment", name: "alignment", type: "Alignment",
                        hasDefaultValue: true, defaultValue: ".center"),
                    .init(label: "content", name: "content", type: "V"),  // Generic that will become ViewReference
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "V", constraint: "View")
                ]
            )
        ]

        // Act
        let result = try sut.generate(enumName: "OverlayModifier", modifiers: modifiers)

        // Assert
        let code = result.sourceCode

        // 1. alignment should NOT be wrapped in eraser because Alignment is not erased
        XCTAssertTrue(code.contains("?? .center"), "Alignment should check default value")

        // 2. content should be handled as ViewReference<Library> and flatMap should NOT have `() ->`
        XCTAssertTrue(
            code.contains("flatMap({ ViewReference<Library>(syntax: $0.expression) })"),
            "Content parsing should be correct")
        XCTAssertFalse(
            code.contains("() -> ViewReference"), "Should not contain closure signature in flatMap")
    }

    func test_closureTransformation_worksForExplicitClosures() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "custom",
                parameters: [
                    .init(label: nil, name: "content", type: "() -> V")
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "V", constraint: "View")
                ]
            )
        ]

        // Act
        let result = try sut.generate(enumName: "CustomModifier", modifiers: modifiers)

        // Assert
        XCTAssertTrue(result.sourceCode.contains("case custom(ViewReference<Library>)"))
        XCTAssertTrue(
            result.sourceCode.contains("flatMap({ ViewReference<Library>(syntax: $0.expression) })")
        )
    }

    func test_valueTypeViewReference_isNotWrappedInClosure() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(
                name: "background",
                parameters: [
                    .init(label: nil, name: "view", type: "V")
                ],
                returnType: "some View",
                isGeneric: true,
                genericParameters: [
                    .init(name: "V", constraint: "View")
                ]
            )
        ]

        // Act
        let result = try sut.generate(enumName: "BackgroundModifier", modifiers: modifiers)

        // Assert
        // The type `V` becomes `ViewReference<Library>` via erasure.
        // It should NOT be wrapped in `{ }` when generating the body call.
        // Expected: content.background(view)
        // Incorrect: content.background({ view })
        XCTAssertTrue(
            result.sourceCode.contains("content.background(view)"),
            "Should pass ViewReference directly for value types")
        XCTAssertFalse(
            result.sourceCode.contains("background({ view })"),
            "Should not wrap ViewReference in closure for value types")
    }
    func test_noParameterModifier_generatesCorrectEnumInit() throws {
        // Arrange
        let modifiers = [
            ModifierInfo(name: "spacer", parameters: [], returnType: "some View")
        ]

        // Act
        let result = try sut.generate(enumName: "SpacerModifier", modifiers: modifiers)

        // Assert
        // Should be `self = .custom`, NOT `self = .custom()`
        XCTAssertTrue(result.sourceCode.contains("self = .spacer"), "Should init without parens")
        XCTAssertFalse(
            result.sourceCode.contains("self = .spacer()"), "Should not have empty parens")
    }
}
