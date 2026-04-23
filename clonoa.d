#!/bin/env rdmd

/// A tool that generates D bindings from C files using ImportC.
module clonoa;

version (ClonoaLibrary) {
} else {
    int main(string[] args) {
        return clonoaMain(args);
    }
}

void printHelp(bool canSkipEmptyLine = false) {
    if (!canSkipEmptyLine) writeln();
    writeln("Usage: clonoa <compiler> <file.c|file.h> [options]");
    writeln("Options:");
    writeln("  -M=<name>   Module name");
    writeln("  -I=<path>   Header include path");
    writeln("  -P=<prefix> Header prefix(es) (e.g. SDL:KMOD:AUDIO:DUMMY:WindowShapeMode:ShapeMode)");
    writeln("  -S=<name>   Opaque struct(s) to add (e.g. rAudioBuffer:rAudioProcessor)");
    writeln("  -X=<name>   Exclude type(s) (e.g. Vector2:Vector3:Vector4)");
    writeln("  -E          Remove repeated enums (e.g. alias thing = Enum.thing;)");
}

void printInvalidOption(string option) {
    writeln("Invalid option: `", option, '`');
}

int clonoaMain(string[] cliArgs...) {
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
    clonoaArgs.useDefaults();
    clonoaArgs.compiler = cliArgs[1];
    clonoaArgs.headerPath = cliArgs[2];
    clonoaArgs.moduleName = clonoaArgs.headerPath.baseName.stripExtension().toLower();
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
                clonoaArgs.appendHeaderInclude(value);
                break;
            case 'P':
                foreach (part; value.splitter(':')) clonoaArgs.appendHeaderPrefix(part);
                break;
            case 'S':
                foreach (part; value.splitter(':')) clonoaArgs.opaqueStructs ~= part;
                break;
            case 'X':
                foreach (part; value.splitter(':')) clonoaArgs.typeSkipList ~= part;
                break;
            case 'E':
                clonoaArgs.removeRepeatedEnums = true;
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
    string[] definedStructs;
    string[] definedEnumMembers;
    for (auto i = diFistLine; i < diLines.length - diLastLineOffset; i += 1) {
        auto diLine = diLines[i].strip();
        auto hasBlock = i + 1 < diLines.length && diLines[i + 1].strip() == "{";
        if (!hasBlock) continue;

        if (diLine.startsWith("struct")) {
            auto structParts = diLine.split();
            auto structName = structParts[1].strip();
            definedStructs ~= structName;
        } else if (clonoaArgs.removeRepeatedEnums ? diLine.startsWith("enum") : diLine == "enum") {
            foreach (blockLine; BlockLineRange(diLines, i)) {
                auto memberParts = blockLine.split(" = ");
                auto memberName = memberParts[0].strip().strip(",");
                definedEnumMembers ~= memberName;
            }
        }
    }

    // Write module header.
    output.echo("module ", clonoaArgs.moduleName, ";\n");
    output.echo(clonoaArgs.moduleSymbolHeader, "\n");
    foreach (name; clonoaArgs.opaqueStructs) output.echo("struct " ~ name ~ ";");
    if (clonoaArgs.opaqueStructs.length) output.echo();

    for (auto i = diFistLine; i < diLines.length - diLastLineOffset; i += 1) {
        auto diLine = diLines[i].strip();
        // Normalize.
        if (diLine.startsWith("extern")) diLine = diLine["extern".length + 1 .. $];
        if (diLine.startsWith("static") || diLine.startsWith("/+") || diLine.length == 0) continue; /++/
        if (diLine.startsWith("auto")) {
            skipBlock(diLines, i);
            continue;
        }
        foreach (line; clonoaArgs.lineSkipList) if (diLine == line) continue;
        // Dispatch.
        if (diLine.startsWith("alias")) {
            processAlias(clonoaArgs, output, diLine, definedEnumMembers);
        } else if (diLine.startsWith("struct") || diLine.startsWith("union") || diLine.startsWith("enum")) {
            processBlock(clonoaArgs, output, diLines, i, definedEnumMembers, definedStructs);
        } else {
            processFunc(clonoaArgs, output, diLine);
        }
    }

    remove(diPath);
    return ClonoaResult();
}

// TODO: WAS HERE
string safeTypeMapReplace(string line, string[string] typeMap) {
    string result;
    string token;
    foreach (c; line) {
        if (c.isAlphaNum || c == '_') {
            token ~= c;
        } else {
            if (auto target = token in typeMap) {
                result ~= *target;
            } else {
                result ~= token;
            }
            token = "";
            result ~= c;
        }
    }
    if (auto target = token in typeMap) result ~= *target;
    else result ~= token;
    return result;
}

void processAlias(ref ClonoaArgs clonoaArgs, ref Array!char output, string line, string[] definedEnumMembers) {
    // Fix old-style functions: alias void foo(...) -> alias foo = void function(...)
    if (line.canFind("(") && !line.canFind("=")) {
        auto parenIndex = line.indexOf("(");
        auto afterParen = line[parenIndex + 1 .. $];
        auto beforeParen = line[0 .. parenIndex].strip();
        auto beforeParenParts = beforeParen.split();
        auto returnType = beforeParenParts[1 .. $ - 1].join(" ");
        auto funcName = beforeParenParts[$ - 1];
        line = "alias " ~ funcName ~ " = " ~ returnType ~ " function(" ~ afterParen;
    }

    auto parts = line.split();
    auto name = parts[1];
    auto value = parts[3];

    if (name.isSkipped(clonoaArgs.typeSkipList, clonoaArgs.headerPrefixes)) return;
    line = line.replace("alias " ~ name, "alias " ~ name.escapeKeyword());

    if (value.canFind(".")) {
        auto dotIndex = value.indexOf(".");
        auto enumType = value[0 .. dotIndex];
        auto enumMember = value[dotIndex + 1 .. $ - 1];
        if (enumType.isSkipped(clonoaArgs.typeSkipList, clonoaArgs.headerPrefixes)) return;
        foreach (defined; definedEnumMembers) if (enumMember == defined) return;
        line = line.replace(enumType ~ ".", enumType.escapeKeyword() ~ ".");
        line = line.replace("." ~ enumMember, "." ~ enumMember.escapeKeyword());
    } else if (line.canFind("function(")) {
        line = fixFuncLine(line);
        line = safeTypeMapReplace(line, clonoaArgs.typeMap);
    } else {
        line = safeTypeMapReplace(line, clonoaArgs.typeMap);
    }
    output.echo(line);
}

void processBlock(ref ClonoaArgs clonoaArgs, ref Array!char output, string[] lines, ref size_t i, string[] definedEnumMembers, string[] definedStructs) {
    auto line = lines[i].strip();
    auto parts = line.split();
    auto keyword = parts[0];
    auto isEnum = keyword == "enum";
    auto isStruct = keyword == "struct";
    auto isUnion = keyword == "union";
    auto name = parts.length > 1 ? parts[1].stripRight(";") : "";
    if (isEnum && parts.length == 5) name = parts[2];

    if (line.endsWith(";")) {
        if (isStruct) {
            foreach (defined; definedStructs) if (name == defined) return;
        }
        if (name.isSkipped(clonoaArgs.typeSkipList, clonoaArgs.headerPrefixes)) return;

        auto nameIndex = line.indexOf(name);
        if (nameIndex != -1) {
            line = line[0 .. nameIndex] ~ name.escapeKeyword() ~ line[nameIndex + name.length .. $];
        }
        line = safeTypeMapReplace(line, clonoaArgs.typeMap);
        output.echo(line);
        return;
    }
    if (name.isSkipped(clonoaArgs.typeSkipList, clonoaArgs.headerPrefixes)) {
        skipBlock(lines, i);
        return;
    }

    output.echo(keyword, name.length ? " " ~ name.escapeKeyword() : "", " {");
    foreach (memberLine; BlockLineRange(lines, i)) {
        if (memberLine.length == 0) continue;
        if (memberLine.startsWith("align ")) memberLine = memberLine["align ".length .. $];
        memberLine = memberLine.replace(" = void;", ";");
        if (isEnum) {
            auto equalIndex = memberLine.indexOf(" = ");
            auto commaIndex = memberLine.indexOf(",");
            auto endIndex = equalIndex != -1 ? equalIndex : (commaIndex != -1 ? commaIndex : memberLine.length);
            auto memberName = memberLine[0 .. endIndex];
            memberLine = memberName.escapeKeyword() ~ memberLine[memberName.length .. $];
        } else {
            auto memberParts = memberLine.split();
            auto memberName = memberParts[$ - 1][0 .. $ - 1];
            auto escapedName = memberName.escapeKeyword();
            memberLine = memberLine[0 .. $ - memberName.length - 1] ~ escapedName ~ ";";
        }
        memberLine = safeTypeMapReplace(memberLine, clonoaArgs.typeMap);
        output.echo(clonoaArgs.indentation, memberLine);
    }
    output.echo("}\n");
}

void processFunc(ref ClonoaArgs clonoaArgs, ref Array!char output, string line) {
    auto parts = line.split();
    auto parenIndex = parts.length > 1 ? parts[1].indexOf("(") : -1;
    auto name = parenIndex != -1 ? parts[1][0 .. parenIndex] : "";

    if (name.isSkipped(clonoaArgs.funcSkipList, clonoaArgs.headerPrefixes)) return;
    foreach (part; parts) if (part.startsWith("__")) return; // Libc leak heuristic.

    line = fixFuncLine(line);
    line = safeTypeMapReplace(line, clonoaArgs.typeMap);
    output.echo(line);
}

bool isInSkipList(string name, string[] skipList) {
    foreach (skip; skipList) if (name == skip) return true;
    return false;
}

bool startsWithPrefixes(string name, string[] prefixes) {
    if (prefixes.length == 0) return true;
    foreach (prefix; prefixes) if (name.startsWith(prefix)) return true;
    return false;
}

bool isSkipped(string name, string[] skipList, string[] prefixes) {
    if (name.length == 0) return false;
    if (name.isInSkipList(skipList)) return true;
    if (name.startsWith("__tag")) return false;
    if (prefixes.length) {
        if (!name.startsWithPrefixes(prefixes)) return true;
    } else {
        if (name.startsWith("_")) return true;
    }
    return false;
}

void skipBlock(string[] lines, ref size_t i) {
    foreach (blockLine; BlockLineRange(lines, i)) {}
}

string fixVarargsInFuncLineParams(string line) {
    if (line.canFind("__builtin_va_list") || line.canFind("va_list") || line.canFind("__va_list_tag")) {
        auto lastCommaIndex = line.lastIndexOf(",");
        if (lastCommaIndex != -1) {
            line = line[0 .. lastCommaIndex] ~ ", ...);";
        } else {
            line = line[0 .. line.indexOf("(")] ~ "(...);";
        }
    }
    return line;
}

string fixKeywordsInFuncLineParams(string line) {
    static string[4][] funcKeywordReplacements;

    if (funcKeywordReplacements.length == 0) {
        foreach (keyword; keywords) {
            funcKeywordReplacements ~= [
                " " ~ keyword ~ ",",
                " " ~ keyword ~ "_,",
                " " ~ keyword ~ ")",
                " " ~ keyword ~ "_)",
            ];
        }
    }

    foreach (replacement; funcKeywordReplacements) {
        line = line.replace(replacement[0], replacement[1]);
        line = line.replace(replacement[2], replacement[3]);
    }
    return line;
}

string fixFuncLine(string line) {
    return line.fixVarargsInFuncLineParams().fixKeywordsInFuncLineParams();
}

string escapeKeyword(string name) {
    foreach (keyword; keywords) if (keyword == name) return name ~ "_";
    return name;
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

enum defaultCompiler           = "ldc2";
enum defaultModuleSymbolHeader = "extern(C) nothrow @nogc:";
enum defaultIndentation        = "    ";

string[] defaultLineSkipList = [];

string[] defaultTypeSkipList = [
    "true",
    "false",
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
    "fpos_t",
    "wint_t",
    "ssize_t",
    "time_t",
    "clock_t",
    "va_list",
    "max_align_t",
    "_IO_lock_t",
    "FILE",
];

string[] defaultFuncSkipList = [
    "erf",
    "erff",
    "erfl",
    "erfc",
    "erfcf",
    "erfcl",
    "lgamma",
    "lgammaf",
    "lgammal",
    "tgamma",
    "tgammaf",
    "tgammal",
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
    "double_t"       : "double",

    "intptr_t"       : "long",
    "uintptr_t"      : "ulong",
    "intmax_t"       : "long",
    "uintmax_t"      : "ulong",
    "wchar_t"        : "int",
    "__u_char"       : "ubyte",
    "_IO_lock_t"     : "void", // HACK? TODO: Think about it later.
    "FILE"           : "void", // HACK? TODO: Think about it later.
];

string[] keywords = [
    "true",
    "false",
    "null",
    "real",
    "abstract",
    "final",
    "interface",
    "delegate",
    "function",
    "import",
    "module",
    "version",
    "scope",
    "ref",
    "out",
    "in",
    "alias",
    "debug",
    "is",
];

struct ClonoaResult {
    int fault;
    string faultMessage;
    alias fault this;
}

struct ClonoaArgs {
    string compiler = defaultCompiler;
    string headerPath;
    string moduleName;
    string[] headerIncludes;
    string[] headerPrefixes;
    string[] opaqueStructs;
    bool removeRepeatedEnums;

    string moduleSymbolHeader = defaultModuleSymbolHeader;
    string indentation = defaultIndentation;
    string[string] typeMap;
    string[] typeSkipList;
    string[] funcSkipList;
    string[] lineSkipList;

    void useDefaults() {
        typeMap = defaultTypeMap;
        typeSkipList = defaultTypeSkipList;
        funcSkipList = defaultFuncSkipList;
        lineSkipList = defaultLineSkipList;
    }

    void appendHeaderInclude(string path) {
        auto prefix = "-P=-I"; // NOTE: The default is DMD.
        if (compiler.endsWith("ldc2")) prefix = "-P -I";
        if (compiler.endsWith("gdc"))  prefix = "-Xpreprocessor -I";
        headerIncludes ~= prefix ~ path;
    }

    void appendHeaderPrefix(string prefix) {
        headerPrefixes ~= prefix;
        headerPrefixes ~= "_" ~ prefix;
        if (prefix[0].isUpper) headerPrefixes ~= prefix.toLower();
        if (prefix[0].isLower) headerPrefixes ~= prefix.toUpper();
    }
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

import std.ascii, std.string, std.path;
import std.algorithm, std.array, std.container.array;
import std.stdio, std.process, std.file;

// ---
// Copyright 2026 Alexandros F. G. Kapretsos
// SPDX-License-Identifier: MIT
// Email: alexandroskapretsos@gmail.com
// Project: https://github.com/Kapendev/clonoa
// ---
