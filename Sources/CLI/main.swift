import ArgumentParser
import Foundation
import Core

/// CLI tool for generating type-safe SwiftUI modifier enums.
@main
struct ModifierSwiftCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "modifier-swift",
        abstract: "Generate type-safe SwiftUI modifier enums from .swiftinterface files",
        version: "0.1.0"
    )
    
    @Option(name: .shortAndLong, help: "Path to the .swiftinterface file or directory to parse")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output directory for generated Swift files")
    var output: String = "./Generated"
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Clean output directory before generating")
    var clean: Bool = false
    
    func run() throws {
        if verbose {
            print("ModifierSwift v0.1.0")
            print("Input: \(input)")
            print("Output: \(output)")
            print()
        }
        
        // Step 1: Find all swiftinterface files
        let interfaceFiles = try findSwiftInterfaceFiles(at: input)
        
        if verbose {
            if interfaceFiles.count == 1 {
                print("📖 Parsing 1 interface file...")
            } else {
                print("📖 Parsing \(interfaceFiles.count) interface files...")
                for file in interfaceFiles {
                    print("  • \(URL(fileURLWithPath: file).lastPathComponent)")
                }
                print()
            }
        }
        
        guard !interfaceFiles.isEmpty else {
            print("⚠️  No .swiftinterface files found in \(input)")
            return
        }
        
        // Step 2: Parse all interface files and collect modifiers
        let parser = InterfaceParser()
        var allModifiers: [ModifierInfo] = []
        
        for file in interfaceFiles {
            do {
                let modifiers = try parser.parse(filePath: file)
                allModifiers.append(contentsOf: modifiers)
                if verbose {
                    print("  ✓ \(URL(fileURLWithPath: file).lastPathComponent): \(modifiers.count) modifiers")
                }
            } catch {
                print("  ⚠️  Failed to parse \(URL(fileURLWithPath: file).lastPathComponent): \(error)")
            }
        }
        
        if verbose {
            print()
            print("✓ Total modifiers found: \(allModifiers.count)")
            print()
        }
        
        guard !allModifiers.isEmpty else {
            print("⚠️  No modifiers found in input files")
            return
        }
        
        // Step 3: Group modifiers by name (all overloads together)
        // This will automatically merge modifiers from multiple files
        var modifiersByName: [String: [ModifierInfo]] = [:]
        for modifier in allModifiers {
            modifiersByName[modifier.name, default: []].append(modifier)
        }
        
        if verbose {
            print("📊 Grouped into \(modifiersByName.count) unique modifiers:")
            let sortedNames = modifiersByName.keys.sorted()
            for name in sortedNames.prefix(20) {
                let count = modifiersByName[name]!.count
                print("  • \(name): \(count) variant\(count == 1 ? "" : "s")")
            }
            if modifiersByName.count > 20 {
                print("  ... and \(modifiersByName.count - 20) more")
            }
            print()
        }
        
        // Step 4: Filter out underscore-prefixed modifiers
        let filteredModifiersByName = modifiersByName.filter { name, _ in
            !name.hasPrefix("_")
        }
        
        if verbose && filteredModifiersByName.count < modifiersByName.count {
            let skipped = modifiersByName.count - filteredModifiersByName.count
            print("⏭️  Skipping \(skipped) underscore-prefixed modifier(s)")
            print()
        }
        
        // Step 5: Parse protocol styles for type erasers
        let styleParser = ProtocolStyleParser()
        var allStyles: [String: Set<ProtocolStyleParser.StyleCase>] = [:]
        
        for file in interfaceFiles {
            do {
                let styles = try styleParser.parse(filePath: file)
                for (protocol_, cases) in styles {
                    allStyles[protocol_, default: []].formUnion(cases)
                }
            } catch {
                // Silently skip files that fail to parse for styles
            }
        }
        
        if verbose && !allStyles.isEmpty {
            print("🎨 Found \(allStyles.count) protocol style(s) for type erasers")
            print()
        }
        
        // Step 6: Generate type eraser enums
        let typeEraserGenerator = TypeEraserGenerator()
        var typeEraserCodes: [GeneratedCode] = []
        
        for (protocolName, cases) in allStyles.sorted(by: { $0.key < $1.key }) {
            if let eraserName = TypeEraserMapping.customEraserName(for: protocolName) {
                let code = typeEraserGenerator.generate(
                    protocolName: protocolName,
                    eraserName: eraserName,
                    styleCases: cases
                )
                typeEraserCodes.append(code)
                
                if verbose {
                    print("  ✓ Generated \(eraserName).swift (\(cases.count) style case\(cases.count == 1 ? "" : "s"))")
                }
            }
        }
        
        if verbose && !typeEraserCodes.isEmpty {
            print()
        }
        
        // Step 7: Generate one file per modifier name
        if verbose {
            print("🔨 Generating modifier code...")
        }
        
        let generator = EnumGenerator()
        var generatedCodes: [GeneratedCode] = []
        var totalGenerated = 0
        
        for (name, variants) in filteredModifiersByName.sorted(by: { $0.key < $1.key }) {
            guard !variants.isEmpty else { continue }
            
            // Create enum name from modifier name
            let enumName = name.prefix(1).uppercased() + name.dropFirst() + "Modifier"
            
            do {
                let code = try generator.generate(enumName: enumName, modifiers: variants)
                generatedCodes.append(code)
                totalGenerated += 1
                
                if verbose && totalGenerated <= 20 {
                    print("  ✓ Generated \(enumName).swift (\(code.modifierCount) variant\(code.modifierCount == 1 ? "" : "s"))")
                }
            } catch {
                print("  ⚠️  Failed to generate \(enumName): \(error)")
            }
        }
        
        if verbose && totalGenerated > 20 {
            print("  ... and \(totalGenerated - 20) more files")
        }
        
        if verbose {
            print()
        }
        
        // Step 8: Write output files
        if verbose {
            print()
            print("💾 Writing files to \(output)...")
        }
        
        let outputManager = FileOutputManager()
        
        // Clean if requested
        if clean {
            try outputManager.cleanOutputDirectory(output)
            if verbose {
                print("  ✓ Cleaned output directory")
            }
        }
        
        // Generate the global parse error type
        let parseErrorCode = generator.generateParseErrorType()
        
        // Write all files to output directory (parse error + type erasers + modifiers)
        let allCodes = [parseErrorCode] + typeEraserCodes + generatedCodes
        try outputManager.writeAll(allCodes, to: output)
        
        if verbose {
            print()
        }
        
        // Step 9: Summary
        if verbose {
            print()
        }
        let totalFiles = totalGenerated + typeEraserCodes.count
        print("✅ Successfully generated \(totalFiles) file(s):")
        print("   • \(totalGenerated) modifier enum(s)")
        if !typeEraserCodes.isEmpty {
            print("   • \(typeEraserCodes.count) type eraser(s)")
        }
        print("   • \(allModifiers.count) total modifier variants")
        if interfaceFiles.count > 1 {
            print("📚 Processed \(interfaceFiles.count) interface files")
        }
        print("📁 Output: \(output)")
    }
    
    // MARK: - Helper Methods
    
    /// Finds all .swiftinterface files at the given path.
    /// If path is a file, returns it. If path is a directory, searches recursively.
    private func findSwiftInterfaceFiles(at path: String) throws -> [String] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(path)")
        }
        
        // If it's a file, check if it's a swiftinterface file
        if !isDirectory.boolValue {
            if path.hasSuffix(".swiftinterface") {
                return [path]
            } else {
                throw ValidationError("File is not a .swiftinterface file: \(path)")
            }
        }
        
        // It's a directory - search for all .swiftinterface files
        var interfaceFiles: [String] = []
        
        if let enumerator = fileManager.enumerator(atPath: path) {
            for case let file as String in enumerator {
                if file.hasSuffix(".swiftinterface") {
                    let fullPath = (path as NSString).appendingPathComponent(file)
                    interfaceFiles.append(fullPath)
                }
            }
        }
        
        return interfaceFiles.sorted()
    }
}
