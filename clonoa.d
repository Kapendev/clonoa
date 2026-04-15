#!/bin/env rdmd

/// A tool that generates D bindings from C files using ImportC.

immutable defaultTypeMap = [
    "__int8_t"   : "byte",
    "__int16_t"  : "short",
    "__int32_t"  : "int",
    "__int64_t"  : "long",
    "__uint8_t"  : "ubyte",
    "__uint16_t" : "ushort",
    "__uint32_t" : "uint",
    "__uint64_t" : "ulong",
    "wchar_t"    : "int",

    // Add library-specific type replacements here:
    "rAudioBuffer*"    : "void*",
    "rAudioProcessor*" : "void*",
];

immutable defaultSkipList = [
    "div_t", "ldiv_t", "lldiv_t",
    "FILE", "fpos_t",
    "wchar_t", "wint_t", "size_t", "ssize_t",
    "time_t", "clock_t",
    "va_list",
];

version (ClonoaLibrary) {
} else {
    int main(string[] args) {
        version (OSX) {
            enum compiler = "ldc2";
        } else {
            enum compiler = "dmd";
        }
        return clonoaMain(compiler, true, args);
    }
}

int clonoaMain(string compiler, bool canEmitTagStructs, string[] args, const(string[string]) typeMap = defaultTypeMap, const(string[]) skipList = defaultSkipList) {
    if (args.length < 2) {
        writeln(i"Usage: $(args[0].baseName) <source.c|source.h>");
        return 1;
    }

    auto cPath  = args[1];
    auto cLines = File(cPath).byLine.map!(line => line.idup).array;
    auto dPath  = cPath.stripExtension ~ ".di"; // args[2];
    auto dResult = execute([compiler, "-o-", "-H", cPath]);
    if (dResult.status != 0) {
        writeln(i"$(compiler) failed:\n", dResult.output);
        return 1;
    }
    auto dLines = File(dPath).byLine.map!(line => line.idup).array;
    auto allowedNames = extractNamesFromHeaderFile(cLines);
    auto moduleName   = dPath.baseName.stripExtension;

    writeln(i"module $(moduleName);\n");
    writeln("extern(C):\n");
    size_t i = 2;
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
                i++;
                while (i < dLines.length) {
                    if (dLines[i].strip() == "}") break;
                    i++;
                }
            }
            continue;
        }

        // Blocks: struct, enum, union.
        if (cleanLine.startsWith("struct ") || cleanLine.startsWith("enum ") || cleanLine.startsWith("union ") || cleanLine == "enum") {
            auto parts = cleanLine.split();
            auto name = parts.length > 1 ? parts[1] : ""; // Empty string for an anonymous enum.
            if (skipList.canFind(name)) continue;
            if (!name.startsWith("_") || (canEmitTagStructs && name.startsWith("__tag"))) { // NOTE: D creates `__tag` structs sometimes for macros.
                string[] block;
                block ~= cleanLine;
                i++;
                while (i < dLines.length) {
                    auto blockLine = dLines[i].strip();
                    block ~= blockLine;
                    if (blockLine == "}") break;
                    i++;
                }

                if (previousWasFunctionOrAlias) {
                    previousWasFunctionOrAlias = false;
                    writeln();
                }
                foreach (blockLineIndex, blockLine; block) {
                    auto outLine = blockLine;
                    foreach (cType, dType; typeMap) {
                        outLine = outLine.replace(cType, dType);
                    }
                    enum indentation = "    ";
                    auto isInsideBlock = blockLineIndex != 0 && blockLineIndex != 1 && blockLineIndex != block.length - 1;
                    writeln(isInsideBlock ? indentation : "", outLine);
                }
                writeln();
            } else {
                i++;
            }
            continue;
        }

        // Functions.
        foreach (allowedName; allowedNames) {
            if (!cleanLine.canFind(allowedName ~ "(")) continue;
            auto outLine = cleanLine;
            foreach (cType, dType; typeMap) {
                outLine = outLine.replace(cType, dType);
            }
            outLine = outLine
                .replace("alias,", "alias_,")
                .replace("alias)", "alias_)");

            outLine = outLine.replace(", __builtin_va_list args)", ", ...)"); // Hack.
            writeln(outLine);
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
                auto outLine = cleanLine.replace(", __builtin_va_list args)", ", ...)");
                writeln(outLine);
                previousWasFunctionOrAlias = true;
            }
        }
    }

    remove(dPath);
    return 0;
}

string[] extractNamesFromHeaderFile(string[] lines) {
    string[] result;
    auto funcRegex = regex(`\b(\w+)\s*\(`);
    foreach (line; lines) {
        auto match = line.matchFirst(funcRegex);
        if (!match.empty) {
            auto name = match[1];
            auto isMacro = name[0].isUpper && name[1 .. $].all!(c => c.isUpper || c.isDigit || c == '_');
            if (!isMacro) {
                result ~= name;
            }
        }
    }
    return result;
}

import std.ascii, std.string, std.path;
import std.algorithm, std.array;
import std.stdio, std.process, std.file;
import std.regex;

immutable dPrimitives = [
    "byte", "ubyte", "short", "ushort", "int", "uint",
    "long", "ulong", "float", "double", "real",
    "char", "wchar", "dchar", "bool", "void",
];
