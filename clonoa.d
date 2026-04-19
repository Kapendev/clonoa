#!/bin/env rdmd

/// A tool that generates D bindings from C files using ImportC.
module clonoa;

version (ClonoaLibrary) {
} else {
    int main(string[] args) {
        return clonoaMain(args);
    }
}

int clonoaMain(string[] args) {
    if (args.length < 2) {
        writeln("Usage: ", args[0].baseName, " <source.c|source.h> [module name] [header prefix]");
        return 0;
    }

    auto clonoaArgs = ClonoaArgs(args[1]);
    clonoaArgs.moduleTargetName = args.length <= 2 ? "" : args[2];
    if (args.length > 3) {
        clonoaArgs.headerPrefix = args[3];
        clonoaArgs.strictPrefix = true;
    }

    if (clonoaArgs.autoPopulateByName && clonoaArgs.strictPrefix) { // TODO: REMOVE LATER. Just for testing.
        if (clonoaArgs.headerPrefix == "SDL") {
            clonoaArgs.headerPrefixExceptions ~= "WindowShapeMode";
            clonoaArgs.headerPrefixExceptions ~= "ShapeMode";
        }
    }

    auto result = clonoaRun(clonoaArgs);
    if (result.faultMessage.length) {
        if (args[1].endsWith(".h")) {
            writeln("Note:");
            writeln("  Files that end with `.h` require a newer DMD version.");
            writeln("  Try wrapping the include in a `.c` file.");
        }
        writeln("Compiler error:\n", result.faultMessage);
        return 1;
    }
    write(result.output);
    return 0;
}

ClonoaResult clonoaRun(in ClonoaArgs args) {
    // Create the main variables.
    auto output = appender!string();
    auto vaRegex = regex(`, \w+ \w+\)`);
    auto modulePath = args.headerPathBaseName ~ ".di";
    {
        auto executeResult = execute([args.compiler, "-o-", "-H", args.headerPath]);
        if (executeResult.status != 0) return ClonoaResult.none(executeResult.output);
    }
    auto moduleLines = File(modulePath).byLine().map!(line => line.idup).array;
    auto moduleName = args.moduleTargetName.length ? args.moduleTargetName : modulePath.baseName.stripExtension().toLower();

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
    if (args.autoPopulateByName) output.insertSymbolsBasedOnHeaderPathBaseName(args);

    // Create the module body.
    auto hadEmptyLoopOutputLine = true;
    moduleLoop: for (auto i = 3UL; i < moduleLines.length - 2; i += 1) {
        auto moduleLine = moduleLines[i].strip();
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
                if (outputLine.canFind("__builtin_va_list") || outputLine.canFind("va_list")) {
                    outputLine = outputLine.replaceAll(vaRegex, ", ...)");
                }
                foreach (keywordName; keywordNames) {
                    outputLine = outputLine
                        .replace(" " ~ keywordName ~ ",", " " ~ keywordName ~ "_,")
                        .replace(" " ~ keywordName ~ ")", " " ~ keywordName ~ "_)");
                }
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
            if (name.isPrivateName(args, headerPrefixExceptions, true)) {
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
            auto nameIndex = (moduleLine.startsWith("export ") || moduleLine.startsWith("extern ")) ? 2 : (parts.length > 1 ? 1 : -1);
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
    return ClonoaResult.some(output.data);
}

void insertSymbolsBasedOnHeaderPathBaseName(ref Appender!string output, in ClonoaArgs args) {
    auto hasInserted = true;
    switch (args.headerPathBaseName) {
        case "raylib":
            output.echo("struct rAudioBuffer;");
            output.echo("struct rAudioProcessor;");
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

bool isPrivateName(string name, in ClonoaArgs args, string[] headerPrefixExceptions, bool isNameAndNotValue = false) {
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

string replaceTypeWithTypeFromTypeMap(string line, string name, in ClonoaArgs args) {
    auto cleanName = name;
    while (cleanName.endsWith("*")) cleanName = cleanName[0 .. $ - 1];
    if (auto targetName = cleanName in args.typeMap) {
        return line.replace(cleanName, *targetName);
    }
    return line;
}

void echon(ref Appender!string output, string[] args...) {
    foreach (ref arg; args) output.put(arg);
}

void echo(ref Appender!string output, string[] args...) {
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
];

string[] keywordNames = [
    "true", "false", "null", "real",
    "abstract", "final", "interface", "delegate", "function",
    "module", "import", "version",
    "scope", "ref", "out", "in",
    "alias", "is", "debug",
];

struct ClonoaResult {
    string faultMessage;
    string output;

    alias Self = typeof(this);

    static
    Self none(string faultMessage) {
        return Self(faultMessage, "");
    }

    static
    Self some(string output) {
        return Self("", output);
    }
}

struct ClonoaArgs {
    string headerPath;
    string headerPathBaseName;
    string headerPrefix;
    string[] headerPrefixExceptions;
    string compiler;
    string[string] typeMap;
    string[] typeSkipList;
    string[] funcSkipList;
    string[] lineSkipList;
    string moduleSymbolHeader;
    string moduleAttributes;
    string moduleTargetName;
    bool strictPrefix;
    bool autoPopulateByName = true;

    this(string headerPath, bool autoPopulateByName = true) {
        this.headerPath = headerPath;
        this.headerPathBaseName = headerPath.baseName.stripExtension();
        this.autoPopulateByName = autoPopulateByName;
        readyWithDefaults();
    }

    void readyWithDefaults() {
        compiler = defaultCompiler;
        typeMap = defaultTypeMap;
        typeSkipList = defaultTypeSkipList;
        funcSkipList = defaultFuncSkipList;
        lineSkipList = defaultLineSkipList;
        moduleSymbolHeader = defaultModuleSymbolHeader;
        moduleAttributes = defaultModuleAttributes;
    }
}

import std.ascii, std.string, std.path;
import std.algorithm, std.array, std.container.array;
import std.stdio, std.process, std.file;
import std.regex, std.format;
