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
        
        // Step 2: Categorize modifiers
        let analyzer = TypeAnalyzer()
        let categories = categorize 
            ? analyzer.categorize(modifiers: modifiers)
            : ["All": modifiers]
        
        if verbose {
            print("📊 Categorized into \(categories.count) groups:")
            for (category, mods) in categories.sorted(by: { $0.key < $1.key }) {
                print("  • \(category): \(mods.count) modifiers")
            }
            print()
        }
        
        // Step 3: Generate code for each category
        if verbose {
            print("🔨 Generating code...")
        }
        
        let generator = EnumGenerator()
        var generatedCodesByCategory: [String: [GeneratedCode]] = [:]
        var totalGenerated = 0
        
        for (category, mods) in categories {
            guard !mods.isEmpty else { continue }
            
            let enumName = "\(category)Modifier"
            do {
                let code = try generator.generate(enumName: enumName, modifiers: mods)
                generatedCodesByCategory[category] = [code]
                totalGenerated += 1
                
                if verbose {
                    print("  ✓ Generated \(enumName).swift (\(code.modifierCount) modifiers)")
                }
            } catch {
                print("  ⚠️  Failed to generate \(enumName): \(error)")
            }
        }
        
        if verbose {
            print()
        }
        
        // Step 4: Write output files
        if verbose {
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
        
        // Write files
        if categorize {
            try outputManager.writeByCategory(generatedCodesByCategory, to: output)
        } else {
            let allCode = generatedCodesByCategory.values.flatMap { $0 }
            try outputManager.writeAll(allCode, to: output)
        }
        
        if verbose {
            print()
        }
        
        // Step 5: Summary
        print("✅ Successfully generated \(totalGenerated) enum(s) with \(modifiers.count) total modifiers")
        print("📁 Output: \(output)")
    }
}
