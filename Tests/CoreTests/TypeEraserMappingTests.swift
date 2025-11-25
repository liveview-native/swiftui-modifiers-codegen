import XCTest
@testable import Core

final class TypeEraserMappingTests: XCTestCase {
    
    // MARK: - Built-in Eraser Tests
    
    func test_eraser_forView_returnsAnyView() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "View"), "AnyView")
        XCTAssertEqual(TypeEraserMapping.eraser(for: "SwiftUI.View"), "AnyView")
        XCTAssertEqual(TypeEraserMapping.eraser(for: "SwiftUICore.View"), "AnyView")
    }
    
    func test_eraser_forStringProtocol_returnsString() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "StringProtocol"), "String")
        XCTAssertEqual(TypeEraserMapping.eraser(for: "Swift.StringProtocol"), "String")
    }
    
    func test_eraser_forHashable_returnsAnyHashable() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "Hashable"), "AnyHashable")
        XCTAssertEqual(TypeEraserMapping.eraser(for: "Swift.Hashable"), "AnyHashable")
    }
    
    func test_eraser_forShape_returnsAnyShape() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "Shape"), "AnyShape")
        XCTAssertEqual(TypeEraserMapping.eraser(for: "SwiftUI.Shape"), "AnyShape")
        XCTAssertEqual(TypeEraserMapping.eraser(for: "InsettableShape"), "AnyShape")
    }
    
    func test_eraser_forShapeStyle_returnsAnyShapeStyle() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "ShapeStyle"), "AnyShapeStyle")
        XCTAssertEqual(TypeEraserMapping.eraser(for: "SwiftUI.ShapeStyle"), "AnyShapeStyle")
    }
    
    func test_eraser_forTransition_returnsAnyTransition() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "Transition"), "AnyTransition")
    }
    
    func test_eraser_forLayout_returnsAnyLayout() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "Layout"), "AnyLayout")
    }
    
    // MARK: - Custom Eraser Tests
    
    func test_eraser_forButtonStyle_returnsAnyButtonStyle() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "ButtonStyle"), "AnyButtonStyle")
    }
    
    func test_eraser_forProgressViewStyle_returnsAnyProgressViewStyle() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "ProgressViewStyle"), "AnyProgressViewStyle")
    }
    
    func test_eraser_forToggleStyle_returnsAnyToggleStyle() {
        XCTAssertEqual(TypeEraserMapping.eraser(for: "ToggleStyle"), "AnyToggleStyle")
    }
    
    func test_eraser_forUnknownType_returnsNil() {
        XCTAssertNil(TypeEraserMapping.eraser(for: "UnknownProtocol"))
        XCTAssertNil(TypeEraserMapping.eraser(for: "SomeRandomType"))
    }
    
    // MARK: - Custom Eraser Detection Tests
    
    func test_needsCustomEraser_forButtonStyle_returnsTrue() {
        XCTAssertTrue(TypeEraserMapping.needsCustomEraser(for: "ButtonStyle"))
    }
    
    func test_needsCustomEraser_forView_returnsFalse() {
        XCTAssertFalse(TypeEraserMapping.needsCustomEraser(for: "View"))
    }
    
    func test_needsCustomEraser_forUnknown_returnsFalse() {
        XCTAssertFalse(TypeEraserMapping.needsCustomEraser(for: "Unknown"))
    }
    
    // MARK: - Custom Eraser Name Tests
    
    func test_customEraserName_forButtonStyle_returnsAnyButtonStyle() {
        XCTAssertEqual(TypeEraserMapping.customEraserName(for: "ButtonStyle"), "AnyButtonStyle")
    }
    
    func test_customEraserName_forView_returnsNil() {
        XCTAssertNil(TypeEraserMapping.customEraserName(for: "View"))
    }
}
