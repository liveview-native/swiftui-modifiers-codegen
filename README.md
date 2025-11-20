# ModifierSwift

A Swift tool for generating type-safe SwiftUI modifier enums from `.swiftinterface` files.

## Overview

ModifierSwift parses SwiftUI's `.swiftinterface` files and generates type-safe enum representations of view modifiers. This enables:

- **Type-safe modifier composition** - Catch invalid modifier combinations at compile time
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
```

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

**Key Feature:** When multiple interface files define the same modifier, they are automatically merged into a single enum file with all variants.

### Code Formatting

This project uses SwiftFormat. Format all code before committing:

```bash
swiftformat Sources/ Tests/
```

## Generated Code Example

Given a SwiftUI modifier like:

```swift
extension View {
    func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View
}
```

ModifierSwift generates:

```swift
public enum PaddingModifier {
    case edges(Edge.Set, CGFloat?)
    case all
    case length(CGFloat)
}

extension View {
    func modifier(_ modifier: PaddingModifier) -> some View {
        switch modifier {
        case .edges(let edges, let length):
            self.padding(edges, length)
        case .all:
            self.padding()
        case .length(let length):
            self.padding(length)
        }
    }
}
```

## Architecture

### 1. Parser Phase

The `InterfaceParser` reads `.swiftinterface` files and extracts:
- View extension methods
- Method signatures and parameters
- Availability constraints
- Documentation comments

### 2. Analysis Phase

The `TypeAnalyzer` processes extracted methods:
- Resolves type information
- Groups related modifiers
- Identifies parameter patterns
- Categorizes by functionality

### 3. Generation Phase

The `EnumGenerator` produces Swift code:
- Enum cases for each modifier variant
- SyntaxConvertible extensions
- Helper methods for applying modifiers
- Documentation comments

### 4. Output Phase

The `FileOutputManager` writes generated files:
- Organizes by category
- Applies code formatting
- Generates imports and headers

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Status

✅ **All Core Phases Complete!**

Completed Phases:
- ✅ Phase 1: Project Structure & Foundation
- ✅ Phase 2: SwiftInterface Parser
- ✅ Phase 3: Type System Analysis
- ✅ Phase 4: Code Generator - Modifier Enums
- ✅ Phase 5: Code Generator - SyntaxConvertible Extensions (merged with Phase 4)
- ✅ Phase 6: File Output Manager
- ✅ Phase 7: CLI Interface
- ✅ Phase 8: Testing & Validation

**Test Coverage:** 78 tests passing across all components
