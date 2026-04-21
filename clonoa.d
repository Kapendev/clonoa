#!/bin/env rdmd

// NOTE: Was about to write the new main loop code.
// TODO: The replacing of names is so bad... Fix in thrid refactor now that you know more about ImportC.

/// A tool that generates D bindings from C files using ImportC.
module clonoa;

version (ClonoaLibrary) {
} else {
    int main(string[] args) {
        return clonoaMain(args);
    }
}

int clonoaMain(string[] cliArgs) {
    if (cliArgs.length < 3) {
        printHelp(true);
        return cliArgs.length == 1 ? 0 : 1;
    }
    if (!cliArgs[2].endsWith(".h") && !cliArgs[2].endsWith(".c")) {
        writeln("Error: The second argument must be a `.h` or `.c` file.");
        printHelp();
        return 1;
    }

    auto clonoaArgs = ClonoaArgs();
    clonoaArgs.compiler = cliArgs[1];
    clonoaArgs.headerPath = cliArgs[2];
    foreach (arg; cliArgs[3 .. $]) {
        if (!arg.startsWith('-') || arg.length == 1) {
            printInvalidOption(arg);
            printHelp();
            return 1;
        }
        auto option = arg[0 .. 2];
        auto key = arg[1];
        auto value = arg[(arg.length >= 3 && arg[2] == '=' ? 3 : 2) .. $];
        switch (key) {
            case 'M':
                clonoaArgs.moduleName = value;
                break;
            case 'I':
                auto prefix = "-P=-I"; // NOTE: The default compiler is DMD.
                if (clonoaArgs.compiler == "ldc2") prefix = "-P -I";
                if (clonoaArgs.compiler == "gdc")  prefix = "-Xpreprocessor -I";
                clonoaArgs.headerIncludes ~= prefix ~ value;
                break;
            case 'P':
                foreach (part; value.splitter(':')) clonoaArgs.headerPrefixes ~= part;
                break;
            case 'S':
                foreach (part; value.splitter(':')) clonoaArgs.opaqueStructs ~= part;
                break;
            default:
                printInvalidOption(option);
                printHelp();
                return 1;
        }
    }
    if (!clonoaArgs.headerPath.exists) {
        writeln("Error: The file doesn't exist.");
        printHelp();
        return 1;
    }

    auto output = Array!char();
    if (auto result = clonoaRun(clonoaArgs, output)) {
        if (clonoaArgs.headerPath.endsWith(".h")) {
            writeln("Note: Files that end with `.h` may not be supported by your compiler. Try wrapping the include in a `.c` file instead.");
        }
        writeln(result.faultMessage);
        return 1;
    }
    write(output.data);
    return 0;
}

ClonoaResult clonoaRun(ref ClonoaArgs clonoaArgs, ref Array!char output) {
    enum diFistLine = 3UL;
    enum diLastLineOffset = 2UL;

    if (clonoaArgs.compiler.length == 0) return ClonoaResult(1, "No compiler specified.");
    output.clear();
    output.reserve(1024 * 1024);
    auto diPath = clonoaArgs.headerPath.baseName.stripExtension() ~ ".di";
    auto executeArgs = [clonoaArgs.compiler, "-o-", "-H", clonoaArgs.headerPath] ~ clonoaArgs.headerIncludes;
    auto executeResult = execute(executeArgs);
    if (executeResult.status) return ClonoaResult(executeResult.status, executeResult.output);
    auto diLines = File(diPath).byLine().map!(line => line.idup).array;

    // Collect names that have full definitions before main loop.
    // Only names that start with `_` will be skipped here.
    string[] definedStructs;
    string[] definedEnumMembers;
    for (auto i = diFistLine; i < diLines.length - diLastLineOffset; i += 1) {
        auto diLine = diLines[i].strip();
        auto hasBlock = i + 1 < diLines.length && diLines[i + 1].strip() == "{";
        if (!hasBlock) continue;

        if ((diLine.startsWith("struct"))) {
            auto structParts = diLine.split();
            auto structName = structParts[1].strip();
            if (structName.startsWith("_")) continue;
            definedStructs ~= structName;
        } else if ((diLine.startsWith("enum"))) {
            foreach (blockLine; BlockLineRange(diLines, i)) {
                auto memberParts = blockLine.split(" = ");
                auto memberName = memberParts[0].strip().strip(",");
                if (memberName.startsWith("_")) continue;
                definedEnumMembers ~= memberName;
            }
        }
    }
    writeln(definedStructs);
    writeln();
    writeln(definedEnumMembers);
    // TODO: STOPPED HERE LAST TIME. Can parse the di file normally now.

    remove(diPath);
    return ClonoaResult();
}

struct BlockLineRange {
    string[] lines;
    size_t* i;

    pragma(inline, true):

    this(string[] lines, ref size_t i) {
        i += 1;
        if (lines[i].strip() == "{") i += 1;
        this.lines = lines;
        this.i = &i;
    }

    bool empty() {
        return *i >= lines.length || lines[*i].strip() == "}";
    }

    string front() {
        return lines[*i].strip();
    }

    void popFront() {
        *i += 1;
    }
}

void printHelp(bool canSkipEmptyLine = false) {
    if (!canSkipEmptyLine) writeln();
    writeln("Usage: clonoa <compiler> <file.c|file.h> [options]");
    writeln("Options:");
    writeln("  -M=<name>     Module name");
    writeln("  -I=<path>     Header include path");
    writeln("  -P=<prefix>   Header prefix(es), can be colon-separated (e.g. SDL:KMOD)");
    writeln("  -S=<name>     Opaque struct(s) to add, can be colon-separated (e.g. rAudioBuffer:rAudioProcessor)");
}

void printInvalidOption(string option) {
    writeln("Invalid option: `", option, '`');
}

ClonoaResult clonoaRunOld(ref ClonoaArgsOld args, ref Array!char output) {
    // Create the main variables.
    output.clear();
    output.reserve(1024 * 1024);
    auto vaRegex = regex(`, \w+ \w+\)`);
    auto modulePath = args.headerPathBaseName ~ ".di";
    {
        auto executeArgs = [args.compiler, "-o-", "-H", args.headerPath];
        if (args.headerIncludes.length) {
            foreach (include; args.headerIncludes) executeArgs ~= "-P=-I" ~ include;
        }
        auto executeResult = execute(executeArgs);
        if (executeResult.status != 0) return ClonoaResult(executeResult.status, executeResult.output);
    }
    auto moduleLines = File(modulePath).byLine().map!(line => line.idup).array;
    auto moduleName = args.moduleName.length ? args.moduleName : modulePath.baseName.stripExtension().toLower();

    auto headerPrefixExceptions_TempHeaderPrefix = args.headerPrefix.length ? args.headerPrefix : args.headerPathBaseName;
    string[] headerPrefixExceptions = args.headerPrefixExceptions ~ [
        "_" ~ headerPrefixExceptions_TempHeaderPrefix,
        "_" ~ headerPrefixExceptions_TempHeaderPrefix.toLower(),
        "_" ~ headerPrefixExceptions_TempHeaderPrefix.toUpper(),
    ];

    // Collect names that have full definitions before main loop.
    string[] definedEnumMembers;
    string[] definedStructNames;
    for (auto i = 3UL; i < moduleLines.length - 2; i += 1) {
        auto moduleLine = moduleLines[i].strip();
        auto hasBlock = i + 1 < moduleLines.length && moduleLines[i + 1].strip() == "{";
        if ((moduleLine.startsWith("struct ")) && hasBlock) {
            definedStructNames ~= moduleLine.split(" ")[1];
        }
        if ((moduleLine == "enum") && hasBlock) {
            i += 2;
            while (i < moduleLines.length) {
                auto member = moduleLines[i].strip();
                if (member == "}") break;
                auto memberName = member[0 .. $ - 1].split(" = ")[0].strip();
                definedEnumMembers ~= memberName;
                i += 1;
            }
        }
    }

    // Create the module header.
    output.echo("module ", moduleName, ";\n");
    output.echo(args.moduleAttributes, ":\n");
    output.echon(args.moduleSymbolHeader, args.moduleSymbolHeader.length ? "\n" : "");
    output.appendSymbolsByName(args);

    // Create the module body.
    auto hadEmptyLoopOutputLine = true;
    moduleLoop: for (auto i = 3UL; i < moduleLines.length - 2; i += 1) {
        auto moduleLine = moduleLines[i].strip();
        if (moduleLine.startsWith("extern ")) moduleLine = moduleLine["extern ".length .. $];
        if (moduleLine.length == 0 || moduleLine.startsWith("static") || moduleLine.startsWith("/+")) continue moduleLoop; /++/
        foreach (line; args.lineSkipList) if (moduleLine.startsWith(line)) continue moduleLoop;

        if (moduleLine.startsWith("alias")) {
            // Fix old-style function typedef: alias void foo(...) -> alias foo = void function(...)
            if (!moduleLine.canFind("=")) {
                auto parenIdx = moduleLine.indexOf("(");
                if (parenIdx != -1) {
                    auto beforeParen = moduleLine[0 .. parenIdx].strip();
                    auto afterParen = moduleLine[parenIdx .. $];
                    auto beforeParts = beforeParen.split(" ");
                    auto retType = beforeParts[1 .. $ - 1].join(" ");
                    auto funcName = beforeParts[$ - 1];
                    moduleLine = "alias " ~ funcName ~ " = " ~ retType ~ " function" ~ afterParen;
                }
            }

            auto parts = moduleLine.split(" ");
            auto name = parts[1];
            auto value = parts[3];
            if (name.isPrivateName(args, headerPrefixExceptions, true)) continue;
            if (value.isPrivateName(args, headerPrefixExceptions)) continue;

            auto outputLine = moduleLine.replace("alias " ~ name, "alias " ~ name.escapeKeyword());
            outputLine = outputLine.replaceTypeWithTypeFromTypeMap(value, args);
            foreach (line; args.lineSkipList) if (outputLine.startsWith(line)) continue moduleLoop; // NOTE: Skip again with new names. This does not avoid any bugs like the anon enum one, but might be useful.
            if (value.canFind(".")) {
                // NOTE: Enum values can have keywords and ignored names in them.
                auto valueParts = value.split(".");
                if (valueParts[0].isPrivateName(args, headerPrefixExceptions, true)) continue;
                outputLine = outputLine.replace(valueParts[1], valueParts[1][0 .. $ - 1].escapeKeyword() ~ ";");
            } else if (outputLine.canFind(" function")) { // NOTE: A hack that works.
                foreach (c, d; args.typeMap) outputLine = outputLine.replace(c, d);
                if (outputLine.canFind("__builtin_va_list") || outputLine.canFind("va_list")) {
                    outputLine = outputLine.replaceAll(vaRegex, ", ...)");
                }
                foreach (keywordName; keywordNames) {
                    outputLine = outputLine
                        .replace(" " ~ keywordName ~ ",", " " ~ keywordName ~ "_,")
                        .replace(" " ~ keywordName ~ ")", " " ~ keywordName ~ "_)");
                }
            } else {
                /* foreach (c, d; args.typeMap) outputLine = outputLine.replace(c, d); */
            }
            output.echo(outputLine);
            hadEmptyLoopOutputLine = false;
            continue;
        }

        auto isEnum = moduleLine.startsWith("enum");
        auto isStruct = moduleLine.startsWith("struct");
        auto isUnion = moduleLine.startsWith("union");
        if (isEnum || isStruct || isUnion) {
            auto parts = moduleLine.split(" ");
            auto keyword = parts[0];
            auto name = parts.length == 1 ? "" : (parts.length == 5 ? parts[2] : parts[1].stripRight(";"));
            if (name.isPrivateName(args, headerPrefixExceptions, true) && name.length > 0) { // NOTE: Enums might not have a name and that is why we check the length.
                if (i + 1 < moduleLines.length && moduleLines[i + 1].strip() == "{") {
                    i += 1;
                    while (i < moduleLines.length) {
                        if (moduleLines[i].strip() == "}") break;
                        i += 1;
                    }
                }
                continue;
            }

            if (moduleLine[$ - 1] == ';') {
                if (isEnum && definedEnumMembers.canFind(name)) continue moduleLoop;
                if (isStruct && definedStructNames.canFind(name)) continue moduleLoop;

                auto outputLine = moduleLine.replace(name ~ " =", name.escapeKeyword() ~ " =");
                if (parts.length == 5) outputLine = outputLine.replaceTypeWithTypeFromTypeMap(parts[1], args);
                foreach (line; args.lineSkipList) if (outputLine.startsWith(line)) continue moduleLoop; // NOTE: Skip again with new names. This avoids some anon enum bugs.
                output.echo(outputLine);
                hadEmptyLoopOutputLine = false;
                continue;
            } else {
                auto outputLine1 = name.length ? moduleLine.replace(keyword ~ " " ~ name, keyword ~ " " ~ name.escapeKeyword()) : moduleLine;
                output.echo(hadEmptyLoopOutputLine ? "" : "\n", outputLine1, " {");
                i += 1;
                while (i < moduleLines.length) {
                    i += 1;
                    moduleLine = moduleLines[i].strip();
                    if (moduleLine == "}") {
                        output.echo(moduleLine, "\n");
                        hadEmptyLoopOutputLine = true;
                        break;
                    } else {
                        auto hasCastOrArraySymbol = false;
                        if (moduleLine.startsWith("align ")) moduleLine = moduleLine["align ".length .. $];
                        if (moduleLine.canFind("cast(") || moduleLine.canFind("[")) {
                            foreach (c, d; args.typeMap) moduleLine = moduleLine.replace(c, d);
                            hasCastOrArraySymbol = true;
                        }

                        auto memberParts = moduleLine.split(" ");
                        auto memberName = moduleLine;
                        if (isEnum) {
                            memberName = memberParts[0][0 .. $ - 1];
                        } else if (isStruct || isUnion) {
                            memberName = memberParts[1];
                        }
                        auto memberEscapedName = memberName.escapeKeyword();
                        auto outputLine2 = moduleLine
                            .replace(memberName, memberEscapedName)
                            .replace(" = void;", ";");
                        if (isStruct || isUnion) {
                            auto memberType = memberParts[0];
                            outputLine2 = outputLine2.replaceTypeWithTypeFromTypeMap(memberType, args);

                            if (outputLine2.canFind(" function")) { // NOTE: A hack that works.
                                if (outputLine2.canFind("__builtin_va_list") || outputLine2.canFind("va_list")) {
                                    outputLine2 = outputLine2.replaceAll(vaRegex, ", ...)");
                                }
                                if (!hasCastOrArraySymbol) foreach (c, d; args.typeMap) outputLine2 = outputLine2.replace(c, d);
                            }
                        }
                        output.echo(indentation, outputLine2);
                    }
                }
                continue;
            }
        }

        // Handle functions.
        {
            auto parts = moduleLine.split(" ");
            auto nameIndex = moduleLine.startsWith("export ") ? 2 : (parts.length > 1 ? 1 : -1);
            auto name = nameIndex == -1 ? "" : parts[nameIndex].split("(")[0];
            if (args.funcSkipList.canFind(name)) continue moduleLoop;
            if (name.isPrivateName(args, headerPrefixExceptions, true) || moduleLine.startsWith("auto ")) {
                if (i + 1 < moduleLines.length && moduleLines[i + 1].strip() == "{") {
                    i += 1;
                    while (i < moduleLines.length) {
                        if (moduleLines[i].strip() == "}") break;
                        i += 1;
                    }
                }
                continue;
            }
            foreach (part; parts) if (part.startsWith("__")) continue moduleLoop;

            auto outputLine = moduleLine;
            foreach (c, d; args.typeMap) outputLine = outputLine.replace(c, d);
            if (outputLine.canFind("__builtin_va_list") || outputLine.canFind("va_list")) {
                outputLine = outputLine.replaceAll(vaRegex, ", ...)");
            }
            foreach (keywordName; keywordNames) {
                outputLine = outputLine
                    .replace(" " ~ keywordName ~ ",", " " ~ keywordName ~ "_,")
                    .replace(" " ~ keywordName ~ ")", " " ~ keywordName ~ "_)");
            }
            output.echo(outputLine);
            hadEmptyLoopOutputLine = false;
        }
    }

    remove(modulePath);
    return ClonoaResult();
}

void appendSymbolsByName(ref Array!char output, ref ClonoaArgsOld args) {
    if (!args.autoPopulateByName) return;
    auto hasInserted = true;
    switch (args.headerPathBaseName) {
        case "raylib":
            output.echo("struct rAudioBuffer;");
            output.echo("struct rAudioProcessor;");
            break;
        case "igraph":
            output.echo("struct igraph_safelocale_s;");
            break;
        case "clay":
            output.echo("struct Clay_Context;");
            break;
        case "SDL":
            if (args.headerPath.canFind("SDL2")) {
                output.echo("struct SDL_BlitMap;");
                output.echo("struct SDL_Cursor;");
                output.echo("struct SDL_Window;");
                output.echo("struct _SDL_iconv_t;");
            }
            break;
        default:
            hasInserted = false;
            break;
    }
    if (hasInserted) output.echo();
}

void appendExceptionsByName(ref ClonoaArgsOld args) {
    if (!args.autoPopulateByName) return;
    switch (args.headerPathBaseName) {
        default:
            break;
    }
}

bool isPrivateName(string name, ref ClonoaArgsOld args, string[] headerPrefixExceptions, bool isNameAndNotValue = false) {
    if (name.length == 0) return true;

    auto isPrivatePrivate = name.startsWith("_");
    foreach (exception; headerPrefixExceptions) {
        if (exception.length && name.startsWith(exception)) isPrivatePrivate = false;
    }
    if (isNameAndNotValue && args.strictPrefix) {
        isPrivatePrivate = true;
        string[3] headerStrictPrefixList = [args.headerPrefix, args.headerPrefix.toLower, args.headerPrefix.toUpper];
        foreach (strictPrefix; headerStrictPrefixList) if (name.startsWith(strictPrefix)) isPrivatePrivate = false;
        foreach (exception; headerPrefixExceptions) if (exception.length && name.startsWith(exception)) isPrivatePrivate = false;
    }
    if (name.startsWith("__tag")) isPrivatePrivate = false;
    return isPrivatePrivate || args.typeSkipList.canFind(name);
}

string escapeKeyword(string name) {
    return keywordNames.canFind(name) ? name ~ "_" : name;
}

string replaceTypeWithTypeFromTypeMap(string line, string name, ref ClonoaArgsOld args) {
    auto cleanName = name;
    while (cleanName.endsWith("*")) cleanName = cleanName[0 .. $ - 1];
    if (auto targetName = cleanName in args.typeMap) {
        return line.replace(cleanName, *targetName);
    }
    return line;
}

void echon(ref Array!char output, const(char)[][] args...) {
    foreach (arg; args) {
        foreach (c; arg) output.insertBack(c);
    }
}

void echo(ref Array!char output, const(char)[][] args...) {
    output.echon(args);
    output.echon("\n");
}

string[string] mergeMaps(string[string] lhs, string[string] rhs) {
    auto result = lhs.dup;
    foreach (k, v; rhs) result[k] = v;
    return result;
}

version (OSX) {
    enum defaultCompiler = "ldc2";
} else {
    enum defaultCompiler = "dmd";
}
enum indentation = "    ";
enum defaultModuleAttributes = "extern(C) nothrow @nogc";
enum defaultModuleSymbolHeader = "";

string[] defaultLineSkipList = [];

string[] defaultFuncSkipList = [
    "erf", "erff", "erfl",
    "erfc", "erfcf", "erfcl",
    "lgamma", "lgammaf", "lgammal",
    "tgamma", "tgammaf", "tgammal",
];

string[] defaultTypeSkipList = [
    "__int8_t",
    "__int16_t",
    "__int32_t",
    "__int64_t",
    "__uint8_t",
    "__uint16_t",
    "__uint32_t",
    "__uint64_t",
    "int8_t",
    "int16_t",
    "int32_t",
    "int64_t",
    "uint8_t",
    "uint16_t",
    "uint32_t",
    "uint64_t",
    "__byte",
    "__short",
    "__int",
    "__long",
    "__ubyte",
    "__ushort",
    "__uint",
    "__ulong",
    "Sint8",
    "Sint16",
    "Sint32",
    "Sint64",
    "Uint8",
    "Uint16",
    "Uint32",
    "Uint64",

    "int_least8_t",
    "int_least16_t",
    "int_least32_t",
    "int_least64_t",
    "uint_least8_t",
    "uint_least16_t",
    "uint_least32_t",
    "uint_least64_t",

    "int_fast8_t",
    "int_fast16_t",
    "int_fast32_t",
    "int_fast64_t",
    "uint_fast8_t",
    "uint_fast16_t",
    "uint_fast32_t",
    "uint_fast64_t",

    "intptr_t",
    "uintptr_t",
    "intmax_t",
    "uintmax_t",

    "wchar_t",
    "size_t",
    "ptrdiff_t",
    "div_t",
    "ldiv_t",
    "lldiv_t",
    "FILE",
    "fpos_t",
    "wint_t",
    "ssize_t",
    "time_t",
    "clock_t",
    "va_list",
    "max_align_t",
    "_IO_lock_t",
];

string[string] defaultTypeMap = [
    "__int8_t"       : "byte",
    "__int16_t"      : "short",
    "__int32_t"      : "int",
    "__int64_t"      : "long",
    "__uint8_t"      : "ubyte",
    "__uint16_t"     : "ushort",
    "__uint32_t"     : "uint",
    "__uint64_t"     : "ulong",
    "int8_t"         : "byte",
    "int16_t"        : "short",
    "int32_t"        : "int",
    "int64_t"        : "long",
    "uint8_t"        : "ubyte",
    "uint16_t"       : "ushort",
    "uint32_t"       : "uint",
    "uint64_t"       : "ulong",
    "__byte"         : "byte",
    "__short"        : "short",
    "__int"          : "int",
    "__long"         : "long",
    "__ubyte"        : "ubyte",
    "__ushort"       : "ushort",
    "__uint"         : "uint",
    "__ulong"        : "ulong",
    "Sint8"          : "byte",
    "Sint16"         : "short",
    "Sint32"         : "int",
    "Sint64"         : "long",
    "Uint8"          : "ubyte",
    "Uint16"         : "ushort",
    "Uint32"         : "uint",
    "Uint64"         : "ulong",

    "int_least8_t"   : "byte",
    "int_least16_t"  : "short",
    "int_least32_t"  : "int",
    "int_least64_t"  : "long",
    "uint_least8_t"  : "ubyte",
    "uint_least16_t" : "ushort",
    "uint_least32_t" : "uint",
    "uint_least64_t" : "ulong",

    "int_fast8_t"    : "byte",
    "int_fast16_t"   : "long",
    "int_fast32_t"   : "long",
    "int_fast64_t"   : "long",
    "uint_fast8_t"   : "ubyte",
    "uint_fast16_t"  : "ulong",
    "uint_fast32_t"  : "ulong",
    "uint_fast64_t"  : "ulong",

    "float_t"        : "float",
    "double_t"        : "double",

    "intptr_t"       : "long",
    "uintptr_t"      : "ulong",
    "intmax_t"       : "long",
    "uintmax_t"      : "ulong",
    "wchar_t"        : "int",
    "__u_char"       : "ubyte",
    "_IO_lock_t"     : "void",
    "FILE"           : "void", // HACK? TODO: Think about it later.
];

string[] defaultHeaderPrefixExceptions = [
    "s", "cs", "WindowShapeMode", "ShapeMode", "KMOD", "AUDIO", "DUMMY",
];

string[] keywordNames = [
    "true", "false", "null", "real",
    "abstract", "final", "interface", "delegate", "function",
    "module", "import", "version",
    "scope", "ref", "out", "in",
    "alias", "is", "debug",
];

struct ClonoaResult {
    int fault;
    string faultMessage;

    alias fault this;
}

struct ClonoaArgs {
    string headerPath;
    string moduleName;
    string[] headerIncludes;
    string[] headerPrefixes;
    string[] opaqueStructs;
    string compiler;

    string moduleSymbolHeader = "extern(C) nothrow @nogc:";
    string[string] typeMap;
    string[] typeSkipList;
    string[] funcSkipList;
    string[] lineSkipList;
}

struct ClonoaArgsOld {
    string headerPath;
    string headerPathBaseName;
    string headerPrefix;
    string[] headerPrefixExceptions;
    string[] headerIncludes;
    string compiler;
    string[string] typeMap;
    string[] typeSkipList;
    string[] funcSkipList;
    string[] lineSkipList;
    string moduleSymbolHeader;
    string moduleAttributes;
    string moduleName;
    bool strictPrefix;
    bool autoPopulateByName;

    this(string headerPath, string moduleName, string headerPrefix, string[] headerIncludes, bool autoPopulateByName = true) {
        this.headerPath = headerPath;
        this.headerPathBaseName = headerPath.baseName.stripExtension();
        this.moduleName = moduleName;
        this.autoPopulateByName = autoPopulateByName;
        setHeaderPrefix(headerPrefix);
        setHeaderIncludes(headerIncludes);
        readyWithDefaults();
        appendExceptionsByName(this);
    }

    void setHeaderPrefix(string newHeaderPrefix) {
        if (newHeaderPrefix == "_") newHeaderPrefix = "";
        headerPrefix = newHeaderPrefix;
        strictPrefix = newHeaderPrefix.length != 0;
    }

    void setHeaderIncludes(string[] newHeaderIncludes...) {
        headerIncludes = newHeaderIncludes;
        foreach (ref include; headerIncludes) {
            if (include.startsWith("-I")) include = include[2 .. $];
        }
    }

    void readyWithDefaults() {
        compiler = defaultCompiler;
        typeMap = defaultTypeMap;
        typeSkipList = defaultTypeSkipList;
        funcSkipList = defaultFuncSkipList;
        lineSkipList = defaultLineSkipList;
        moduleSymbolHeader = defaultModuleSymbolHeader;
        moduleAttributes = defaultModuleAttributes;
        headerPrefixExceptions = defaultHeaderPrefixExceptions;
    }
}

import std.ascii, std.string, std.path;
import std.algorithm, std.array, std.container.array;
import std.stdio, std.process, std.file;
import std.regex, std.format;

// ---
// Copyright 2025 Alexandros F. G. Kapretsos
// SPDX-License-Identifier: MIT
// Email: alexandroskapretsos@gmail.com
// Project: https://github.com/Kapendev/clonoa
// ---
