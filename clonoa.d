#!/bin/env rdmd

// TODO: Can parse the test header. I was about to use the `typeMap` in the new main function when I stopped.

/// A tool that generates D bindings from C files using ImportC.

// NOTE: Add library-specific symbols here.
string defaultModuleSymbolHeader = ``;
string[] defaultLineSkipList = [];
string[] defaultFuncSkipList = [];
enum indentation = "    ";

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
        if (args.length < 2) {
            writeln(i"Usage: $(args[0].baseName) <source.c|source.h>");
            return 1;
        }

        version (OSX) {
            enum compiler = "ldc2";
        } else {
            enum compiler = "dmd";
        }
        auto result = clonoaMain(compiler, args[1], "");
        if (result.fault) {
            writeln(i"Compiler error:\n$(result.faultMessage)");
            return 1;
        }
        write(result.output);
        return 0;
    }
}

struct ClonoaResult {
    bool fault;
    string faultMessage;
    string output;

    this(bool fault, string faultMessage) {
        this.fault = fault;
        this.faultMessage = faultMessage;
    }

    this(string output) {
        this.output = output;
    }
}

ClonoaResult clonoaMain(
    string compiler,
    string headerPath,
    string headerPrefix,
    string[string] typeMap = null,
    string[] typeSkipList = defaultTypeSkipList,
    string[] funcSkipList = defaultFuncSkipList,
    string[] lineSkipList = defaultLineSkipList,
    string moduleSymbolHeader = defaultModuleSymbolHeader,
    string moduleAttributes = "extern(C) nothrow @nogc",
) {
    // Create the main variables.
    auto output = appender!string();
    auto headerLines = File(headerPath).byLine().map!(line => line.idup).array;
    auto headerPathBaseName = headerPath.baseName.stripExtension();
    auto modulePath = headerPath.baseName.stripExtension() ~ ".di";
    {
        auto executeResult = execute([compiler, "-o-", "-H", headerPath]);
        if (executeResult.status != 0) return ClonoaResult(true, executeResult.output);
    }
    auto moduleLines = File(modulePath).byLine().map!(line => line.idup).array;
    auto moduleName = modulePath.baseName.stripExtension().toLower();
    if (headerPrefix.length == 0) headerPrefix = moduleName;

    // Create the module header.
    output.echo("module ", moduleName, ";\n");
    output.echo(moduleAttributes, ":\n");
    output.echon(moduleSymbolHeader, moduleSymbolHeader.length ? "\n" : "");
    output.insertSymbolsBasedOnHeaderPathBaseName(headerPathBaseName);
    insertSkipNamesBasedOnHeaderPathBaseName(headerPathBaseName, typeSkipList, funcSkipList, lineSkipList);

    // Create the module symbols.
    auto hadEmptyLoopOutputLine = true;
    auto i = 3UL;
    moduleLoop: for (; i < moduleLines.length - 2; i += 1) {
        auto moduleLine = moduleLines[i].strip();
        if (moduleLine.length == 0 || moduleLine.startsWith("static") || moduleLine.startsWith("/+")) continue moduleLoop;
        foreach (line; lineSkipList) if (moduleLine.startsWith(line)) continue moduleLoop;

        if (moduleLine.startsWith("alias")) {
            auto parts = moduleLine.split(" ");
            auto name = parts[1];
            auto value = parts[3];
            if (name.isPrivateName(typeSkipList)) continue;

            auto outputLine = moduleLine.replace("alias " ~ name, "alias " ~ name.escapeKeyword());
            if (value.canFind(".")) {
                // NOTE: Enum values can have keywords and ignored names in them.
                auto valueParts = value.split(".");
                if (valueParts[0].isPrivateName(typeSkipList)) continue;
                outputLine = outputLine.replace(valueParts[1], valueParts[1][0 .. $ - 1].escapeKeyword() ~ ";");
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
            auto name = parts.length == 1 ? "" : (parts.length == 5 ? parts[2] : parts[1]);
            if (name.isPrivateName(typeSkipList)) {
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
                auto outputLine = moduleLine.replace(keyword ~ " " ~ name, keyword ~ " " ~ name.escapeKeyword());
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
                        output.echo(indentation, outputLine2);
                    }
                }
                continue;
            }
        }

        // Handle functions.
        {
            auto parts = moduleLine.split(" ");
            auto name = moduleLine.startsWith("export") ? parts[2] : (parts.length > 1 ? parts[1] : "");
            if (name.isPrivateName(funcSkipList)) {
                if (i + 1 < moduleLines.length && moduleLines[i + 1].strip() == "{") {
                    i += 1;
                    while (i < moduleLines.length) {
                        if (moduleLines[i].strip() == "}") break;
                        i += 1;
                    }
                }
                continue;
            }
        }

        output.echo(moduleLine);
    }

    remove(modulePath);
    return ClonoaResult(output.data);
}

bool isPrivateName(string name, string[] typeSkipList) {
    return name.startsWith("_") || typeSkipList.canFind(name);
}

string escapeKeyword(string name) {
    static immutable keywords = [
        "alias", "version", "module", "import",
        "scope", "ref", "out", "in", "function",
        "delegate", "interface", "debug",
    ];
    return keywords.canFind(name) ? name ~ "_" : name;
}

string clonoaMainOld(
    string compiler,
    bool canEmitTagStructs,
    string[] args,
    string symbolHeader = defaultModuleSymbolHeader,
    string[string] typeMap = defaultTypeMap,
    string[] typeSkipList = defaultTypeSkipList,
    string[] functionSkipList = defaultFuncSkipList,
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

    result.echo("module ", moduleName, ";\n");
    if (symbolHeader.length) result.echo(symbolHeader, "\n");
    result.echo(attributes, ":\n");
    result.insertSymbolsBasedOnHeaderPathBaseName(headerName);      string[] __temp;
    insertSkipNamesBasedOnHeaderPathBaseName(headerName, typeSkipList, functionSkipList, __temp);

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
                    result.echo(outLine);
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
                result.echo(cleanLine);
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
                result.echo("");
            }
            foreach (blockLineIndex, blockLine; block) {
                auto outLine = blockLine;
                foreach (cType, dType; typeMap) outLine = outLine.replace(cType, dType);
                outLine = outLine
                    .replace("alias ", "alias_ ")
                    .replace("function ", "function_ ")
                    .replace("version ", "version_ ");
                auto isInsideBlock = blockLineIndex != 0 && blockLineIndex != 1 && blockLineIndex != block.length - 1;
                result.echo(isInsideBlock ? indentation : "", outLine);
            }
            result.echo("");
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
                result.echo(outLine);
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
            result.echo(outLine);
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

void echon(ref Appender!string output, string[] args...) {
    foreach (ref arg; args) output.put(arg);
}

void echo(ref Appender!string output, string[] args...) {
    output.echon(args);
    output.echon("\n");
}

void insertSymbolsBasedOnHeaderPathBaseName(ref Appender!string output, string name) {
    auto hasInserted = true;
    switch (name) {
        case "raylib":
            output.echo("struct rAudioBuffer;");
            output.echo("struct rAudioProcessor;");
            break;
        case "clay":
            output.echo("struct Clay_Context;");
            break;
        case "SDL":
            output.echo("struct SDL_BlitMap;");
            output.echo("struct SDL_Window;");
            break;
        default:
            hasInserted = false;
            break;
    }
    if (hasInserted) output.echo();
}

void insertSkipNamesBasedOnHeaderPathBaseName(string name, ref string[] typeSkipList, ref string[] funcSkipList, ref string[] lineSkipList) {
    switch (name) {
        case "SDL":
            lineSkipList ~= "struct SDL_AudioCVT;";
            break;
        default:
            break;
    }
}
