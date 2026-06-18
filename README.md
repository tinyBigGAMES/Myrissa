<div align="center">

![Myrissa](media/myrissa.png)

[![Discord](https://img.shields.io/discord/1457450179254026250?style=for-the-badge&logo=discord&label=Discord)](https://discord.gg/Wb6z8Wam7p) [![Follow on Bluesky](https://img.shields.io/badge/Bluesky-tinyBigGAMES-blue?style=for-the-badge&logo=bluesky)](https://bsky.app/profile/tinybiggames.com)

</div>

## What is Myrissa?

**A zero-dependency native compiler for Windows x64.** Write clean, statically-typed `.myr` source code and get standalone PE executables, DLLs, or static libraries -- no MSVC, no MinGW, no external linker, no runtime to ship.

```myrissa
module exe hello;

begin
  println("Hello from Myrissa!");
end.
```

Compile and run:

```bash
myrc -s hello.myr -r
```

Myrissa compiles ahead-of-time through a complete in-process pipeline: lexer, parser, AST, semantic analysis, SSA-based IR with optimization passes, x64 register allocation and instruction encoding, and PE linking with sections, imports, exports, and relocations. The entire toolchain runs in a single invocation. There is nothing to install, configure, or depend on.

The language takes its syntax philosophy from Pascal and Oberon: `begin..end` blocks, `:=` assignment, strong static typing, and a module system that keeps code organized. Case-sensitive, semicolon-delimited, and designed to be readable at a glance.

Myrissa also ships as an embeddable DLL. Host applications can compile and execute Myrissa source at runtime through a flat C-compatible API, with pre-built bindings for C/C++ and Delphi/Free Pascal.

## Who is Myrissa For?

Myrissa is for developers who want native Win64 output without fighting the toolchain:

- **Game developers**: Scripting-language convenience with native compilation. Myrissa's `subsystem.routine` API style pairs naturally with the PIXELS 2D engine. Import C libraries like raylib and SDL via the built-in CImporter.
- **Tool builders**: Ship `Myrissa.dll` and give your application native-code compilation at runtime. The flat C-compatible API supports compiler, debugger, CImporter, LSP, and test runner subsystems. C/C++ and Delphi/Free Pascal bindings are included.
- **Language enthusiasts**: Study a complete native compiler stack from parsing and SSA IR through register allocation and PE linking -- all in one Delphi codebase with no third-party dependencies.
- **Windows developers**: Produce standalone Win64 binaries without shipping .NET, JVM, Python, or a pile of runtime DLLs alongside your application.


## Key Features

- **Zero dependencies**: The full compiler pipeline runs in one invocation. No build system, no toolchain installation, no PATH configuration. One tool produces standalone native binaries.
- **Native x64 output**: Ahead-of-time compiled to x86-64 machine code. No interpreter, no VM, no bytecode layer. The output runs bare metal.
- **Multiple output targets**: Compile the same source to EXE, DLL, static library (standard Win64 `.lib`, linkable by any compiler), or in-memory executable. The `module` declaration drives the output.
- **Pascal/Oberon syntax**: Case-sensitive, `begin..end` blocks, `:=` assignment, strong static typing. Records with inheritance, packed layout, and bit fields. Objects with methods, `self`/`parent`, and create/destroy lifecycle.
- **Routine overloading**: Use `cpplink` for Itanium ABI name mangling. Overloaded routines can be exported from and imported into `.dll` and `.lib` files.
- **Structured exception handling**: `guard/except/finally` with `throw` and `throwcode`. Full exception context via `exccode()` and `excmsg()` intrinsics.
- **Managed strings**: UTF-8 `string` and UTF-16 `wstring` types with automatic lifecycle management.
- **Variadic routines**: Define your own variadic routines with `...`. Access arguments via `varargs.count`, `varargs.next(T)`, and `varargs.copy()`.
- **Built-in debugger**: Debug Adapter Protocol (DAP) support provides breakpoints, stepping, call stacks, and variable inspection. Works with VS Code and other DAP-capable editors. The `@breakpoint` directive marks source locations.
- **Language Server Protocol**: Real-time diagnostics, completion, hover, go-to-definition, references, document symbols, rename, semantic tokens, and formatting. In-process or out-of-process modes.
- **CImporter**: Parse C headers and generate Myrissa bindings for foreign function interfaces. Handles structs, unions, enums, typedefs, function declarations, preprocessor constants, and calling conventions.
- **Embeddable API**: `Myrissa.dll` exposes a flat C-callable API for embedding the compiler, debugger, CImporter, LSP, console, utilities, menu, and test runner subsystems. Pre-built bindings at `lib/c/include/Myrissa.h` and `lib/pascal/Myrissa.pas`.
- **Built-in unit testing**: `test "name" begin ... end;` blocks with typed assertions (`assert`, `asserteq`, `assertnil`, `assertfail`, and more). The compiler replaces the entry point with the test runner automatically.
- **Conditional compilation**: `@define`, `@ifdef`, `@ifndef`, `@elseif`, `@else`, `@endif` with predefined platform and module-kind symbols.
- **Version info and icons**: Embed Windows version information and application icons into executables via directives. No post-build steps or resource compilers required.
- **SSA optimization**: Mem2Reg, constant folding, and dead code elimination passes on the intermediate representation.

## Getting Started

Every Myrissa program is a **module**. The module kind (`exe`, `dll`, `lib`, `unit`, or `mem`) is declared at the top of the file and determines what artifact gets built. An executable module has a `begin..end.` body that serves as the program entry point.

```myrissa
module exe hello;

@optimize debug

routine greet(const name: string; const times: int32);
var
  i: int32;
begin
  for i := 1 to times do
    println("Hello, %s! (%d)", name, i);
  end;
end;

begin
  greet("Myrissa", 3);
end.
```

Compile and run:

```bash
myrc -s hello.myr -r
```

Output:

```
Hello, Myrissa! (1)
Hello, Myrissa! (2)
Hello, Myrissa! (3)
```

The output type is determined by the `module` declaration, not by CLI flags:

| Module Declaration | Output | Description |
|-------------------|--------|-------------|
| `module exe name` | `name.exe` | Native Win64 executable |
| `module dll name` | `name.dll` | Dynamic link library with exported routines |
| `module lib name` | `name.lib` | Standard Win64 static library, linkable by Myrissa or other compilers |
| `module mem name` | (in memory) | Compile to memory and execute via the API (requires a host application) |
| `module unit name` | (none) | Reusable module compiled inline into the importing module |


## Documentation

The full language reference, BNF grammar, toolchain guide, API reference, and how-to recipes are in a single document:

| Document | Description |
|----------|-------------|
| **[Myrissa Language Reference](https://github.com/tinyBigGAMES/Myrissa/blob/main/docs/Myrissa.md)** | Complete language tour with examples: types, routines, records, objects, choices, sets, overlays, arrays, strings, control flow, exceptions, memory management, pointers, variadics, modules, external declarations, DLL loading, conditional compilation, unit testing, directives, the full BNF grammar, toolchain usage, and the embeddable API reference. |


## Getting Myrissa

### Download the Latest Release

**[Download the latest release](https://github.com/tinyBigGAMES/Myrissa/releases/latest)**

The release package contains the compiler (`myrc.exe`), the embeddable DLL (`Myrissa.dll`), pre-built API bindings, and the standard library. No external toolchain is required.

### CLI Reference

```bash
myrc -s <source.myr> [options]
```

| Flag | Description |
|------|-------------|
| `-s <file>` | Source file to compile |
| `-o <dir>` | Output directory (default: `output`) |
| `-r` | Compile and run the resulting executable |
| `-d` | Compile and launch the debugger |
| `-h` | Show help |

```bash
myrc -s hello.myr              # compile
myrc -s hello.myr -o build     # compile to specific output directory
myrc -s hello.myr -r           # compile and run
myrc -s hello.myr -d           # compile and launch debugger
```

### System Requirements

| | Requirement |
|---|---|
| **Host OS** | Windows 10/11 x64 |
| **Runtime dependencies** | None |
| **External toolchain** | None |


## Building the Compiler from Source

This section is for contributors who want to modify the Myrissa compiler itself. If you just want to write Myrissa programs, use the release download above.

### Prerequisites

| | Requirement |
|---|---|
| **Host OS** | Windows 10/11 x64 |
| **Compiler** | Delphi 12.x or higher |

### Get the Source

```bash
git clone https://github.com/tinyBigGAMES/Myrissa.git
```

### Compile

1. Open `projects\Myrissa Programming Language.groupproj` in the Delphi IDE
2. Build all projects in the group
3. The tester project compiles and executes every test case/demos and reports results


## Contributing

Myrissa is an open project and contributions are welcome at every level:

- **Report bugs**: Open an issue on GitHub with a minimal `.myr` reproduction case.
- **Suggest features**: Describe the use case first, then the syntax you have in mind.
- **Submit pull requests**: Bug fixes, documentation improvements, new test cases, and well-scoped features.
- **Review and discuss**: Reviewing open pull requests and issues helps move the project forward.

Join our [Discord](https://discord.gg/Wb6z8Wam7p) to discuss development, ask questions, or share what you are building with Myrissa.


## Support the Project

If Myrissa saves you time, sparks an idea, or becomes part of something you ship:

- **Star the repo** -- helps others find the project
- **Spread the word** -- write a post, mention it on social media
- **Join us on [Discord](https://discord.gg/Wb6z8Wam7p)** -- share what you are building
- **Become a sponsor** via [GitHub Sponsors](https://github.com/sponsors/tinyBigGAMES) -- directly funds development


## License

Myrissa is licensed under the **Apache License 2.0**. See [LICENSE](https://github.com/tinyBigGAMES/Myrissa?tab=Apache-2.0-1-ov-file) for details.


## Links

- [Website](https://myrissa.org)
- [Discord](https://discord.gg/Wb6z8Wam7p)
- [Bluesky](https://bsky.app/profile/tinybiggames.com)
- [tinyBigGAMES](https://tinybiggames.com)

<div align="center">

**Myrissa**&#8482; Programming Language

Copyright &copy; 2026-present tinyBigGAMES&#8482; LLC
All Rights Reserved.

</div>
