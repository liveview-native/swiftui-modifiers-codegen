import XCTest
@testable import Core

final class FileOutputManagerTests: XCTestCase {
    var sut: FileOutputManager!
    var tempDirectory: String!
    
    override func setUp() {
        super.setUp()
        sut = FileOutputManager()
        
        // Create a temporary directory for testing
        tempDirectory = NSTemporaryDirectory()
            .appending("ModifierSwiftTests_\(UUID().uuidString)")
    }
    
    override func tearDown() {
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        tempDirectory = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Write Single File Tests
    
    func test_write_createsDirectory() throws {
        // Arrange
        let code = GeneratedCode(
            sourceCode: "enum Test {}",
            fileName: "Test.swift"
        )
        
        // Act
        try sut.write(code, to: tempDirectory)
        
        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory))
    }
    
    func test_write_createsFile() throws {
        // Arrange
        let code = GeneratedCode(
            sourceCode: "enum Test {}",
            fileName: "Test.swift"
        )
        
        // Act
        try sut.write(code, to: tempDirectory)
        
        // Assert
        let filePath = (tempDirectory as NSString).appendingPathComponent("Test.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
    }
    
    func test_write_writesCorrectContent() throws {
        // Arrange
        let sourceCode = "public enum TestModifier {\n    case test\n}"
        let code = GeneratedCode(
            sourceCode: sourceCode,
            fileName: "Test.swift"
        )
        
        // Act
        try sut.write(code, to: tempDirectory)
        
        // Assert
        let filePath = (tempDirectory as NSString).appendingPathComponent("Test.swift")
        let writtenContent = try String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, sourceCode)
    }
    
    func test_write_withNestedDirectory_createsIntermediateDirectories() throws {
        // Arrange
        let nestedPath = (tempDirectory as NSString)
            .appendingPathComponent("Generated")
            .appending("/Modifiers")
        let code = GeneratedCode(
            sourceCode: "enum Test {}",
            fileName: "Test.swift"
        )
        
        // Act
        try sut.write(code, to: nestedPath)
        
        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedPath))
    }
    
    // MARK: - Write Multiple Files Tests
    
    func test_writeAll_createsAllFiles() throws {
        // Arrange
        let codes = [
            GeneratedCode(sourceCode: "enum Test1 {}", fileName: "Test1.swift"),
            GeneratedCode(sourceCode: "enum Test2 {}", fileName: "Test2.swift"),
            GeneratedCode(sourceCode: "enum Test3 {}", fileName: "Test3.swift")
        ]
        
        // Act
        try sut.writeAll(codes, to: tempDirectory)
        
        // Assert
        let file1 = (tempDirectory as NSString).appendingPathComponent("Test1.swift")
        let file2 = (tempDirectory as NSString).appendingPathComponent("Test2.swift")
        let file3 = (tempDirectory as NSString).appendingPathComponent("Test3.swift")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file3))
    }
    
    // MARK: - Write By Category Tests
    
    func test_writeByCategory_createsSubdirectories() throws {
        // Arrange
        let codesByCategory: [String: [GeneratedCode]] = [
            "Layout": [
                GeneratedCode(sourceCode: "enum Layout {}", fileName: "Layout.swift")
            ],
            "Appearance": [
                GeneratedCode(sourceCode: "enum Appearance {}", fileName: "Appearance.swift")
            ]
        ]
        
        // Act
        try sut.writeByCategory(codesByCategory, to: tempDirectory)
        
        // Assert
        let layoutDir = (tempDirectory as NSString).appendingPathComponent("Layout")
        let appearanceDir = (tempDirectory as NSString).appendingPathComponent("Appearance")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: layoutDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appearanceDir))
    }
    
    func test_writeByCategory_createsFilesInCorrectDirectories() throws {
        // Arrange
        let codesByCategory: [String: [GeneratedCode]] = [
            "Layout": [
                GeneratedCode(sourceCode: "enum Layout {}", fileName: "Layout.swift")
            ],
            "Appearance": [
                GeneratedCode(sourceCode: "enum Appearance {}", fileName: "Appearance.swift")
            ]
        ]
        
        // Act
        try sut.writeByCategory(codesByCategory, to: tempDirectory)
        
        // Assert
        let layoutFile = (tempDirectory as NSString)
            .appendingPathComponent("Layout")
            .appending("/Layout.swift")
        let appearanceFile = (tempDirectory as NSString)
            .appendingPathComponent("Appearance")
            .appending("/Appearance.swift")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: layoutFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appearanceFile))
    }
    
    // MARK: - Clean Directory Tests
    
    func test_cleanOutputDirectory_removesExistingFiles() throws {
        // Arrange
        try FileManager.default.createDirectory(
            atPath: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        let file1 = (tempDirectory as NSString).appendingPathComponent("Test1.swift")
        let file2 = (tempDirectory as NSString).appendingPathComponent("Test2.swift")
        
        try "content".write(toFile: file1, atomically: true, encoding: .utf8)
        try "content".write(toFile: file2, atomically: true, encoding: .utf8)
        
        // Act
        try sut.cleanOutputDirectory(tempDirectory)
        
        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2))
        
        // Directory should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory))
    }
    
    func test_cleanOutputDirectory_withNonexistentDirectory_doesNotThrow() throws {
        // Arrange
        let nonexistentPath = "/tmp/nonexistent_\(UUID().uuidString)"
        
        // Act & Assert
        XCTAssertNoThrow(try sut.cleanOutputDirectory(nonexistentPath))
    }
    
    // MARK: - Error Cases Tests
    
    func test_write_withFileInsteadOfDirectory_throwsError() throws {
        // Arrange
        try FileManager.default.createDirectory(
            atPath: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        let filePath = (tempDirectory as NSString).appendingPathComponent("notADirectory")
        try "content".write(toFile: filePath, atomically: true, encoding: .utf8)
        
        let code = GeneratedCode(
            sourceCode: "enum Test {}",
            fileName: "Test.swift"
        )
        
        // Act & Assert
        XCTAssertThrowsError(try sut.write(code, to: filePath)) { error in
            if case FileOutputManager.OutputError.invalidPath = error {
                // Expected error
            } else {
                XCTFail("Expected invalidPath error, got \(error)")
            }
        }
    }
}
