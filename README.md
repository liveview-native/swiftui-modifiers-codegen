# ModifierSwift

A Swift tool for generating type-safe SwiftUI modifier enums from `.swiftinterface` files.

## Overview

ModifierSwift parses SwiftUI's `.swiftinterface` files and generates type-safe enum representations of view modifiers with unique case names for each variant. This enables:

- **Type-safe modifier composition** - Catch invalid modifier combinations at compile time
- **Automatic variant merging** - Modifiers from multiple files merged into single enums
- **Unique case naming** - Each modifier overload gets a distinct, descriptive case name
- **Better autocomplete** - IDE suggestions for valid modifier variants
- **Easier refactoring** - Modifiers represented as data structures
- **Testing support** - Assert on modifier values in UI tests

## Installation

### Requirements

- macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

### Building from Source

```bash
git clone <repository-url>
cd modifierSwift
swift build -c release
```

The executable will be available at `.build/release/modifier-swift`.

## Usage

### Basic Usage

```bash
modifier-swift --input /path/to/SwiftUICore.swiftinterface --output ./Generated
```

### Options

- `-i, --input <path>` - Path to a `.swiftinterface` file **or directory** to parse (required)
  - If a file: processes that file
  - If a directory: recursively finds and processes all `.swiftinterface` files
- `-o, --output <path>` - Output directory for generated Swift files (default: `./Generated`)
- `-v, --verbose` - Enable verbose output
- `--clean` - Clean output directory before generating
- `--version` - Show version information
- `-h, --help` - Show help information

## Project Structure

```
Sources/
├── Core/               # Core library components
│   ├── Models/         # Data models (ModifierInfo, TypeInfo, etc.)
│   ├── Parser/         # SwiftInterface parsing logic
│   ├── Analyzer/       # Type analysis and categorization
│   └── Generator/      # Code generation for enums
└── CLI/                # Command-line interface

Tests/
├── CoreTests/          # Unit tests for Core library
└── IntegrationTests/   # End-to-end integration tests

Generated/              # ✨ Generated modifier enums (tracked in git)
├── PaddingModifier.swift
├── BackgroundModifier.swift
├── FrameModifier.swift
└── ... 465 more files (468 total)
```

**Note:** The `Generated/` directory contains real SwiftUI modifier enums extracted from Apple's interface files. These files are tracked in version control to serve as:
- **Reference documentation** for SwiftUI modifiers
- **Examples** of the tool's output
- **Validation** that all generated code compiles successfully

## Development

### Running Tests

```bash
swift test
```

### Running the CLI in Development

```bash
# Process a single file
swift run modifier-swift --input arm64e-apple-ios.swiftinterface --output ./Generated

# Process all .swiftinterface files in a directory
swift run modifier-swift --input /path/to/interfaces --output ./Generated

# With verbose output
swift run modifier-swift --input arm64e-apple-ios.swiftinterface --output ./Generated --verbose

# Clean output directory before generating
swift run modifier-swift --input /path/to/interfaces --output ./Generated --clean
```

### Real-World Examples

**Processing a single interface file:**

```bash
$ modifier-swift --input arm64e-apple-ios.swiftinterface --output ./Generated --clean

✅ Successfully generated 134 enum file(s) for 199 total modifier variants
📁 Output: ./Generated
```

**Processing multiple interface files from a directory:**

```bash
$ modifier-swift --input /path/to/swiftinterfaces --output ./Generated --verbose --clean

ModifierSwift v0.1.0
Input: /path/to/swiftinterfaces
Output: ./Generated

📖 Parsing 2 interface files...
  • arm64e-apple-ios-alt.swiftinterface
  • arm64e-apple-ios.swiftinterface

  ✓ arm64e-apple-ios-alt.swiftinterface: 595 modifiers
  ✓ arm64e-apple-ios.swiftinterface: 199 modifiers

✓ Total modifiers found: 794

📊 Grouped into 468 unique modifiers:
  • _makeView: 11 variants (merged from both files)
  • background: 8 variants
  • padding: 2 variants
  ... and 465 more

🔨 Generating code...
  ✓ Generated _makeViewModifier.swift (11 variants)
  ... and 467 more files

✅ Successfully generated 468 enum file(s) for 794 total modifier variants
📚 Processed 2 interface files
📁 Output: ./Generated
```

**Key Features:** 
- When multiple interface files define the same modifier, they are **automatically merged** into a single enum file
- Each variant gets a **unique case name** based on its parameter types to avoid compilation errors
- Example: `padding` from SwiftUICore + SwiftUI → `PaddingModifier` with `paddingWithEdgeInsets` and `paddingWithCGFloat` cases

### Code Formatting

This project uses SwiftFormat. Format all code before committing:

```bash
swiftformat Sources/ Tests/
```

## Generated Code Example

Given SwiftUI modifiers from different interfaces:

```swift
// From SwiftUICore.swiftinterface
extension View {
    func padding(_ insets: EdgeInsets) -> some View
    func padding(_ length: CGFloat) -> some View
}

// From SwiftUI.swiftinterface  
extension View {
    func padding(_ edges: Edge.Set, _ length: CGFloat?) -> some View
}
```

ModifierSwift **automatically merges** them into a single enum with **unique case names**:

```swift
/// Generated modifier enum for PaddingModifier modifiers.
///
/// This enum provides type-safe access to SwiftUI view modifiers.
/// Generated by ModifierSwift.
public enum PaddingModifier: Equatable, Sendable {
    case paddingWithEdgeInsets(SwiftUICore.EdgeInsets)
    case paddingWithCGFloat(CoreFoundation.CGFloat)
    case paddingWithEdgeSetCGFloatOptional(SwiftUICore.Edge.Set, CoreFoundation.CGFloat?)
}

extension View {
    /// Applies a PaddingModifier modifier to this view.
    ///
    /// - Parameter modifier: The modifier to apply.
    /// - Returns: A modified view.
    @inlinable
    public func modifier(_ modifier: PaddingModifier) -> some View {
        switch modifier {
        case .paddingWithEdgeInsets(let param0):
            self.padding(param0)
        case .paddingWithCGFloat(let param0):
            self.padding(param0)
        case .paddingWithEdgeSetCGFloatOptional(let param0, let param1):
            self.padding(param0, param1)
        }
    }
}
```

### Key Features

**🔀 Automatic Merging**: All variants of the same modifier name from any `.swiftinterface` file are merged into a single enum.

**✨ Unique Case Names**: Each overload gets a descriptive case name based on its parameter types:
- Single variant: Simple name (e.g., `opacity`)
- Multiple variants: Type-based names (e.g., `paddingWithCGFloat`, `paddingWithEdgeInsets`)
- Name collisions: Numeric suffixes (e.g., `backgroundWithCGFloat1`, `backgroundWithCGFloat2`)

**📦 Production Ready**: All 468 generated enums compile successfully and are included in version control for reference.

## Architecture

### 1. Parser Phase

The `InterfaceParser` reads `.swiftinterface` files and extracts:
- View extension methods from multiple files
- Method signatures and parameters
- Availability constraints
- Documentation comments

### 2. Merging Phase

The CLI groups modifiers by name:
- Collects all variants of each modifier across all input files
- Creates a single modifier group per unique name
- Example: 11 `_makeView` variants from 2 files → 1 `_makeViewModifier` enum

### 3. Generation Phase

The `EnumGenerator` produces Swift code with unique case names:
- Generates descriptive case names based on parameter types
- Creates enum cases for each modifier variant
- Builds switch statements with proper pattern matching
- Adds inline documentation comments

### 4. Output Phase

The `FileOutputManager` writes generated files:
- One file per unique modifier name
- Clean output directory structure
- All files ready for compilation

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Current Status

✅ **Production Ready!**

**Latest Updates:**
- ✅ **Unique case naming** - Each modifier overload gets a distinct case name
- ✅ **Automatic merging** - Modifiers from multiple files merged into single enums
- ✅ **468 generated files** - All compile successfully and included in git
- ✅ **794 modifier variants** - From real SwiftUI interface files

**Completed Phases:**
- ✅ Phase 1: Project Structure & Foundation
- ✅ Phase 2: SwiftInterface Parser
- ✅ Phase 3: Type System Analysis
- ✅ Phase 4: Code Generator - Modifier Enums with Unique Naming
- ✅ Phase 5: Code Generator - SyntaxConvertible Extensions (merged with Phase 4)
- ✅ Phase 6: File Output Manager
- ✅ Phase 7: CLI Interface with Directory Support
- ✅ Phase 8: Testing & Validation

**Generated Files:** The `Generated/` directory contains 468 real-world modifier enums extracted from SwiftUI, serving as both examples and reference documentation.

**Test Coverage:** 78 tests passing across all components
