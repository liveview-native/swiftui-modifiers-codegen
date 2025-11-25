import XCTest
@testable import Core

final class ProtocolStyleParserTests: XCTestCase {
    var sut: ProtocolStyleParser!
    
    override func setUp() {
        super.setUp()
        sut = ProtocolStyleParser()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Basic Parsing Tests
    
    func test_parse_withStaticStyleProperty_extractsStyleCase() {
        // Arrange
        let source = """
        extension ProgressViewStyle where Self == LinearProgressViewStyle {
            static var linear: Self { get }
        }
        """
        
        // Act
        let result = sut.parse(source: source)
        
        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.keys.contains("ProgressViewStyle"))
        
        let cases = result["ProgressViewStyle"]!
        XCTAssertEqual(cases.count, 1)
        XCTAssertTrue(cases.contains(ProtocolStyleParser.StyleCase(name: "linear", concreteType: "LinearProgressViewStyle")))
    }
    
    func test_parse_withMultipleStyles_extractsAllCases() {
        // Arrange
        let source = """
        extension ProgressViewStyle where Self == LinearProgressViewStyle {
            static var linear: Self { get }
        }
        
        extension ProgressViewStyle where Self == CircularProgressViewStyle {
            static var circular: Self { get }
        }
        """
        
        // Act
        let result = sut.parse(source: source)
        
        // Assert
        let cases = result["ProgressViewStyle"]!
        XCTAssertEqual(cases.count, 2)
        XCTAssertTrue(cases.contains(ProtocolStyleParser.StyleCase(name: "linear", concreteType: "LinearProgressViewStyle")))
        XCTAssertTrue(cases.contains(ProtocolStyleParser.StyleCase(name: "circular", concreteType: "CircularProgressViewStyle")))
    }
    
    func test_parse_withDifferentProtocols_groupsByProtocol() {
        // Arrange
        let source = """
        extension ProgressViewStyle where Self == LinearProgressViewStyle {
            static var linear: Self { get }
        }
        
        extension ButtonStyle where Self == BorderedButtonStyle {
            static var bordered: Self { get }
        }
        """
        
        // Act
        let result = sut.parse(source: source)
        
        // Assert
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.keys.contains("ProgressViewStyle"))
        XCTAssertTrue(result.keys.contains("ButtonStyle"))
    }
    
    // MARK: - Edge Cases
    
    func test_parse_withNoWhereClause_returnsEmpty() {
        // Arrange
        let source = """
        extension ProgressViewStyle {
            static var linear: Self { get }
        }
        """
        
        // Act
        let result = sut.parse(source: source)
        
        // Assert
        XCTAssertTrue(result.isEmpty)
    }
    
    func test_parse_withNonStaticProperty_returnsEmpty() {
        // Arrange
        let source = """
        extension ProgressViewStyle where Self == LinearProgressViewStyle {
            var linear: Self { get }
        }
        """
        
        // Act
        let result = sut.parse(source: source)
        
        // Assert
        XCTAssertTrue(result.isEmpty)
    }
    
    func test_parse_withEmptySource_returnsEmpty() {
        // Arrange
        let source = ""
        
        // Act
        let result = sut.parse(source: source)
        
        // Assert
        XCTAssertTrue(result.isEmpty)
    }
}
