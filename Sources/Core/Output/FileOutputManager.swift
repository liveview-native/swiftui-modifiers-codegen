import Foundation

/// Manages writing generated code to output files.
///
/// This manager handles file organization, directory creation,
/// and writing generated Swift code to the filesystem.
public struct FileOutputManager {
    /// Errors that can occur during file output.
    public enum OutputError: Error, Equatable {
        case directoryCreationFailed(String)
        case fileWriteFailed(String, Error?)
        case invalidPath(String)
        
        public static func == (lhs: OutputError, rhs: OutputError) -> Bool {
            switch (lhs, rhs) {
            case (.directoryCreationFailed(let l), .directoryCreationFailed(let r)):
                return l == r
            case (.invalidPath(let l), .invalidPath(let r)):
                return l == r
            case (.fileWriteFailed(let lPath, _), .fileWriteFailed(let rPath, _)):
                return lPath == rPath
            default:
                return false
            }
        }
    }
    
    private let fileManager: FileManager
    
    /// Creates a new file output manager.
    ///
    /// - Parameter fileManager: The file manager to use. Defaults to .default.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }
    
    /// Writes generated code to a file in the specified output directory.
    ///
    /// - Parameters:
    ///   - code: The generated code to write.
    ///   - outputDirectory: The directory to write the file to.
    /// - Throws: OutputError if the file cannot be written.
    public func write(_ code: GeneratedCode, to outputDirectory: String) throws {
        // Ensure output directory exists
        try ensureDirectoryExists(at: outputDirectory)
        
        // Construct full file path
        let filePath = (outputDirectory as NSString).appendingPathComponent(code.fileName)
        
        // Write the source code to file
        do {
            try code.sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            throw OutputError.fileWriteFailed(filePath, error)
        }
    }
    
    /// Writes multiple generated code files to the output directory.
    ///
    /// - Parameters:
    ///   - codes: The array of generated code to write.
    ///   - outputDirectory: The directory to write the files to.
    /// - Throws: OutputError if any file cannot be written.
    public func writeAll(_ codes: [GeneratedCode], to outputDirectory: String) throws {
        for code in codes {
            try write(code, to: outputDirectory)
        }
    }
    
    /// Writes generated code organized by category subdirectories.
    ///
    /// - Parameters:
    ///   - codesByCategory: Dictionary mapping category names to generated code.
    ///   - outputDirectory: The base output directory.
    /// - Throws: OutputError if any file cannot be written.
    public func writeByCategory(
        _ codesByCategory: [String: [GeneratedCode]],
        to outputDirectory: String
    ) throws {
        for (category, codes) in codesByCategory {
            let categoryPath = (outputDirectory as NSString).appendingPathComponent(category)
            try writeAll(codes, to: categoryPath)
        }
    }
    
    /// Ensures a directory exists at the given path, creating it if necessary.
    ///
    /// - Parameter path: The directory path.
    /// - Throws: OutputError if the directory cannot be created.
    private func ensureDirectoryExists(at path: String) throws {
        var isDirectory: ObjCBool = false
        
        // Check if path exists
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            // Path exists, verify it's a directory
            guard isDirectory.boolValue else {
                throw OutputError.invalidPath("Path exists but is not a directory: \(path)")
            }
            return
        }
        
        // Create directory
        do {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw OutputError.directoryCreationFailed(path)
        }
    }
    
    /// Cleans the output directory by removing all existing files.
    ///
    /// - Parameter outputDirectory: The directory to clean.
    /// - Throws: OutputError if the directory cannot be cleaned.
    public func cleanOutputDirectory(_ outputDirectory: String) throws {
        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: outputDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            // Directory doesn't exist, nothing to clean
            return
        }
        
        // Get all items in directory
        guard let items = try? fileManager.contentsOfDirectory(atPath: outputDirectory) else {
            return
        }
        
        // Remove each item
        for item in items {
            let itemPath = (outputDirectory as NSString).appendingPathComponent(item)
            try? fileManager.removeItem(atPath: itemPath)
        }
    }
}
