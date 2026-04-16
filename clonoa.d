#!/bin/env rdmd

/// A tool that generates D bindings from C files using ImportC.

// NOTE: Add library-specific symbols here.
string defaultSymbolHeader = ``;
string[] defaultFunctionSkipList = [];

string[string] defaultTypeMap = [
    // --- NOTE: Add library-specific type replacements here.
    // "currentName" : "newName",
    // ---

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

    "intptr_t"       : "long",
    "uintptr_t"      : "ulong",
    "intmax_t"       : "long",
    "uintmax_t"      : "ulong",
    "wchar_t"        : "int",
    "__u_char"       : "ubyte",
];

string[] defaultSkipList = [
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

version (ClonoaLibrary) {
} else {
    int main(string[] args) {
        version (OSX) {
            enum compiler = "ldc2";
        } else {
            enum compiler = "dmd";
        }

        if (args.length < 2) {
            writeln(i"Usage: $(args[0].baseName) <source.c|source.h>");
            return 1;
        }

        auto output = clonoaMain(compiler, true, args);
        if (output.length == 0) {
            writeln("Compiler error:");
            write(__clonoaLastErrorOutput);
            return 1;
        }
        write(output);
        return 0;
    }
}

string clonoaMain(
    string compiler,
    bool canEmitTagStructs,
    string[] args,
    string symbolHeader = defaultSymbolHeader,
    string[string] typeMap = defaultTypeMap,
    string[] skipList = defaultSkipList,
    string[] functionSkipList = defaultFunctionSkipList,
    string attributes = "extern(C) nothrow @nogc",
) {
    auto result = appender!string();
    auto cPath  = args[1];
    auto cLines = File(cPath).byLine.map!(line => line.idup).array;

    auto dPath = cPath.baseName.stripExtension ~ ".di";
    auto dResult = execute([compiler, "-o-", "-H", cPath]);
    if (dResult.status != 0) {
        __clonoaLastErrorOutput = dResult.output;
        return "";
    }
    auto dLines = File(dPath).byLine.map!(line => line.idup).array;

    auto allowedFunctionNames = extractFunctionsFromHeaderFile(cLines, functionSkipList);
    auto moduleName = dPath.baseName.stripExtension;
    auto headerName = cPath.baseName.stripExtension; // Probably the same thing as `moduleName`, but it's night and I can't think.

    result.clonoaWriteln("module ", moduleName, ";\n");
    if (symbolHeader.length) result.clonoaWriteln(symbolHeader, "\n");
    result.clonoaWriteln(attributes, ":\n");
    result.insertSymbolsBasedOnHeaderName(headerName);

    auto i = 2UL;
    auto previousWasFunctionOrAlias = false;
    for (; i < dLines.length; i += 1) {
        auto line = dLines[i];
        auto cleanLine = line.strip();

        // Drop single-line enums because they are always junk.
        if (cleanLine.startsWith("enum ") && !cleanLine.endsWith("{")) {
            if (i + 1 >= dLines.length || dLines[i + 1].strip() != "{") continue;
        }

        // Drop macro templates.
        if (cleanLine.startsWith("auto ")) {
            if (i + 1 < dLines.length && dLines[i + 1].strip() == "{") {
                i += 1;
                while (i < dLines.length) {
                    if (dLines[i].strip() == "}") break;
                    i += 1;
                }
            }
            continue;
        }

        // Blocks: struct, enum, union.
        if (cleanLine.startsWith("struct ") || cleanLine.startsWith("enum ") || cleanLine.startsWith("union ") || cleanLine == "enum") {
            auto parts = cleanLine.split();
            auto name = parts.length > 1 ? parts[1] : ""; // Empty string for an anonymous enum.
            if (skipList.canFind(name)) continue;

            // NOTE: D creates `__tag` structs sometimes for macros.
            if (!name.startsWith("_") || (canEmitTagStructs && name.startsWith("__tag"))) {
                string[] block;
                block ~= cleanLine;
                i += 1;
                while (i < dLines.length) {
                    auto blockLine = dLines[i].strip();
                    block ~= blockLine;
                    if (blockLine == "}") break;
                    i += 1;
                }

                if (previousWasFunctionOrAlias) {
                    previousWasFunctionOrAlias = false;
                    result.clonoaWriteln("");
                }
                foreach (blockLineIndex, blockLine; block) {
                    auto outLine = blockLine;
                    foreach (cType, dType; typeMap) {
                        outLine = outLine.replace(cType, dType);
                    }

                    enum indentation = "    ";
                    auto isInsideBlock = blockLineIndex != 0 && blockLineIndex != 1 && blockLineIndex != block.length - 1;
                    result.clonoaWriteln(isInsideBlock ? indentation : "", outLine);
                }
                result.clonoaWriteln("");
            } else {
                i += 1;
            }
            continue;
        }

        // Functions.
        foreach (name; allowedFunctionNames) {
            if (!cleanLine.canFind(name ~ "(")) continue;
            auto outLine = cleanLine;
            foreach (cType, dType; typeMap) outLine = outLine.replace(cType, dType);
            outLine = outLine
                .replace("alias,", "alias_,")
                .replace("alias)", "alias_)");

            // TODO: CHANGE THIS 100%! (when you get time)
            outLine = outLine.replace(", __builtin_va_list args)", ", ...)"); // Hack.
            outLine = outLine.replace(", va_list argp)", ", ...)");           // Hack.
            outLine = outLine.replace(", va_list args)", ", ...)");           // Hack.

            result.clonoaWriteln(outLine);
            previousWasFunctionOrAlias = true;
        }

        // Aliases.
        if (cleanLine.startsWith("alias")) {
            if (cleanLine.canFind("__builtin_va_list") && !cleanLine.canFind("function(")) continue;
            auto lhs = cleanLine.split("=")[0].replace("alias", "").strip();
            if (lhs.startsWith("_") || skipList.canFind(lhs)) continue;
            auto parts = cleanLine.split("=");
            if (parts.length == 2) {
                auto rhs = parts[1].strip().stripRight(";").strip();
                if (rhs.startsWith("_")) continue;
                // TODO: CHANGE THIS 100%! (when you get time, same thing as the function code)
                auto outLine = cleanLine.replace(", __builtin_va_list args)", ", ...)");
                result.clonoaWriteln(outLine);
                previousWasFunctionOrAlias = true;
            }
        }
    }

    remove(dPath);
    return result.data;
}

string[] extractFunctionsFromHeaderFile(string[] lines, string[] functionSkipList) {
    string[] result;
    auto funcRegex = regex(`\b(\w+)\s*\)\s*\(|(\w+)\s*\(`);
    foreach (line; lines) {
        auto matches = line.matchAll(funcRegex).array;
        if (!matches.empty) {
            auto match = matches[$ - 1];
            auto name = match[1].length ? match[1] : match[2];
            auto isMacro = name[0].isUpper && name[1 .. $].all!(c => c.isUpper || c.isDigit || c == '_');
            if (!isMacro && !line.startsWith("static ") && !line.startsWith("__") && !functionSkipList.canFind(name)) {
                result ~= name;
            }
        }
    }
    return result.sort.uniq.array;
}

import std.ascii, std.string, std.path;
import std.algorithm, std.array, std.container.array;
import std.stdio, std.process, std.file;
import std.regex, std.format;

string __clonoaLastErrorOutput;

immutable dPrimitives = [
    "byte", "ubyte", "short", "ushort", "int", "uint",
    "long", "ulong", "float", "double", "real",
    "char", "wchar", "dchar", "bool", "void",
];

void clonoaAppend(A, T)(ref A array, T[] args...) {
    foreach (ref arg; args) array.put(arg);
}

alias clonaWrite = clonoaAppend;

void clonoaWriteln(A, T)(ref A array, T[] args...) {
    array.clonaWrite(args);
    array.clonaWrite("\n");
}

void insertSymbolsBasedOnHeaderName(A)(ref A array, string name) {
    switch (name) {
        case "raylib":
            array.clonoaWriteln("struct rAudioBuffer;");
            array.clonoaWriteln("struct rAudioProcessor;");
            break;
        case "clay":
            array.clonoaWriteln("struct Clay_Context;");
            break;
        default:
    }
    array.clonoaWriteln("");
}
