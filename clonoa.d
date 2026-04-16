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

    "intptr_t"       : "long",
    "uintptr_t"      : "ulong",
    "intmax_t"       : "long",
    "uintmax_t"      : "ulong",
    "wchar_t"        : "int",
    "__u_char"       : "ubyte",
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
    string[] typeSkipList = defaultTypeSkipList,
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
    auto moduleName = dPath.baseName.stripExtension.toLower;
    auto headerName = cPath.baseName.stripExtension; // Probably the same thing as `moduleName`, but it's night and I can't think.
    auto headerNameUpper = headerName.toUpper();
    auto headerNameLower = headerName.toLower();

    result.clonoaWriteln("module ", moduleName, ";\n");
    if (symbolHeader.length) result.clonoaWriteln(symbolHeader, "\n");
    result.clonoaWriteln(attributes, ":\n");
    result.insertSymbolsBasedOnHeaderName(headerName);
    insertSkipNamesBasedOnHeaderName(typeSkipList, functionSkipList, headerName);

    auto i = 2UL;
    auto previousWasFunctionOrAlias = false;
    for (; i < dLines.length; i += 1) {
        auto line = dLines[i];
        auto cleanLine = line.strip();

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
        auto isBlock = cleanLine.startsWith("struct ")
            || cleanLine.startsWith("union ")
            || cleanLine.startsWith("enum ")
            || cleanLine == "enum";
        if (isBlock) {
            auto parts = cleanLine.split();
            auto name = parts.length > 1 ? parts[1] : "";

            // Drop single-line enums (junk) but not block enums.
            auto nextLine = i + 1 < dLines.length ? dLines[i + 1].strip() : "";
            if (cleanLine.startsWith("enum ") && nextLine != "{") {
                // TODO: Hack. Will clean stuff later.
                auto realNameIndex = parts.length > 1 ? 1 : -1;
                if (parts.length > 2) realNameIndex = 2;
                if (realNameIndex != -1 && (parts[realNameIndex].startsWith(headerNameLower) || parts[realNameIndex].startsWith(headerNameUpper))) {
                    auto outLine = cleanLine;
                    foreach (cType, dType; typeMap) outLine = outLine.replace(cType, dType);
                    result.clonoaWriteln(outLine);
                }
                continue;
            }

            // Somtimes ImportC will do the C thing and have the same struct 2 times.
            bool isForwardStruct = cleanLine.endsWith(";") && cleanLine.startsWith("struct ");
            if (isForwardStruct && typeSkipList.canFind(cleanLine)) continue;

            if (typeSkipList.canFind(name)) continue;
            if (cleanLine[$ - 1] == ';' && typeSkipList.canFind(cleanLine)) continue;
            if (name.startsWith("_") && !(canEmitTagStructs && name.startsWith("__tag"))) {
                i += 1;
                continue;
            }

            // Forward declaration — no body.
            if (nextLine != "{") {
                result.clonoaWriteln(cleanLine);
                continue;
            }

            // Full block.
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
                foreach (cType, dType; typeMap) outLine = outLine.replace(cType, dType);
                outLine = outLine
                    .replace("alias ", "alias_ ")
                    .replace("function ", "function_ ")
                    .replace("version ", "version_ ");
                enum indentation = "    ";
                auto isInsideBlock = blockLineIndex != 0 && blockLineIndex != 1 && blockLineIndex != block.length - 1;
                result.clonoaWriteln(isInsideBlock ? indentation : "", outLine);
            }
            result.clonoaWriteln("");
            continue;
        }

        // Aliases.
        if (cleanLine.startsWith("alias")) {
            if (cleanLine.canFind("__builtin_va_list") && !cleanLine.canFind("function(")) continue;
            auto lhs = cleanLine.split("=")[0].replace("alias", "").strip();
            if (lhs.startsWith("_") || typeSkipList.canFind(lhs)) continue;
            auto parts = cleanLine.split("=");
            if (parts.length == 2) {
                auto rhs = parts[1].strip().stripRight(";").strip();
                if (rhs.startsWith("_")) continue;
                auto outLine = cleanLine.replace(", __builtin_va_list args)", ", ...)");
                result.clonoaWriteln(outLine);
                previousWasFunctionOrAlias = true;
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
                .replace("alias)", "alias_)")
                .replace("function,", "function_,")
                .replace("function)", "function_)");
            outLine = outLine.replace(", __builtin_va_list args)", ", ...");
            outLine = outLine.replace(", va_list argp)", ", ...)");
            outLine = outLine.replace(", va_list args)", ", ...)");
            result.clonoaWriteln(outLine);
            previousWasFunctionOrAlias = true;
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
            if (!isMacro && !line.startsWith("static ") && !name.startsWith("__") && !functionSkipList.canFind(name)) {
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
    auto hasInserted = true;
    switch (name) {
        case "raylib":
            array.clonoaWriteln("struct rAudioBuffer;");
            array.clonoaWriteln("struct rAudioProcessor;");
            break;
        case "clay":
            array.clonoaWriteln("struct Clay_Context;");
            break;
        case "SDL":
            array.clonoaWriteln("struct SDL_BlitMap;");
            array.clonoaWriteln("struct SDL_Window;");
            break;
        default:
            hasInserted = false;
            break;
    }
    if (hasInserted) array.clonoaWriteln("");
}

void insertSkipNamesBasedOnHeaderName(T)(ref T typeSkipList, ref T functionSkipList, string name) {
    switch (name) {
        case "SDL":
            typeSkipList ~= "struct SDL_AudioCVT;";
            break;
        default:
            break;
    }
}
