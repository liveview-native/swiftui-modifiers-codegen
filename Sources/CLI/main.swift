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
    
    @Option(name: .shortAndLong, help: "Path to the .swiftinterface file to parse")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output directory for generated Swift files")
    var output: String = "./Generated"
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Clean output directory before generating")
    var clean: Bool = false
    
    @Flag(name: .long, inversion: .prefixedNo, help: "Organize output files by category (default: true)")
    var categorize: Bool = true
    
    func run() throws {
        if verbose {
            print("ModifierSwift v0.1.0")
            print("Input: \(input)")
            print("Output: \(output)")
            print()
        }
        
        // Step 1: Parse the interface file
        if verbose {
            print("📖 Parsing interface file...")
        }
        
        let parser = InterfaceParser()
        let modifiers = try parser.parse(filePath: input)
        
        if verbose {
            print("✓ Found \(modifiers.count) modifiers")
            print()
        }
        
        guard !modifiers.isEmpty else {
            print("⚠️  No modifiers found in input file")
            return
        }
        
        // Step 2: Group modifiers by name (all overloads together)
        var modifiersByName: [String: [ModifierInfo]] = [:]
        for modifier in modifiers {
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
        
        // Step 3: Generate one file per modifier name
        if verbose {
            print("🔨 Generating code...")
        }
        
        let generator = EnumGenerator()
        var generatedCodes: [GeneratedCode] = []
        var totalGenerated = 0
        
        for (name, variants) in modifiersByName.sorted(by: { $0.key < $1.key }) {
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
        
        // Step 4: Write output files
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
        
        // Write all files to output directory
        try outputManager.writeAll(generatedCodes, to: output)
        
        if verbose {
            print()
        }
        
        // Step 5: Summary
        if verbose {
            print()
        }
        print("✅ Successfully generated \(totalGenerated) enum file(s) for \(modifiers.count) total modifier variants")
        print("📁 Output: \(output)")
    }
}
