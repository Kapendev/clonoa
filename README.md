
# Clonoa

A tool that generates D bindings from C files using [ImportC](https://dlang.org/spec/importc.html).

[![dw](https://media1.tenor.com/m/Un16sFcZfdIAAAAC/cat-fish.gif)](https://youtu.be/DbV8gy__qS0)

## Usage

Clonoa is a single D file: [`clonoa.d`](source/clonoa.d).
By default, it takes a C file and prints the generated bindings to stdout.
The CLI follows this structure:

```
Usage: clonoa <compiler> <file.c|file.h> [options]
Options:
  -M=<name>   Module name
  -I=<path>   Header include path
  -P=<prefix> Header prefix(es) (e.g. SDL:KMOD:AUDIO:DUMMY:WindowShapeMode:ShapeMode)
  -S=<name>   Opaque struct(s) to add (e.g. rAudioBuffer:rAudioProcessor)
  -X=<name>   Exclude type(s) (e.g. Vector2:Vector3:Vector4)
  -E          Remove repeated enums (e.g. alias thing = Enum.thing;)
```

To run Clonoa from any folder via DUB, use:

```
dub run clonoa -- <compiler> <file.c> [options]
```

## SIMD Guards

Some files fail to parse with ImportC due to unsupported SIMD symbols.
This can be fixed by adding the following at the top of the file:

```c
#if __IMPORTC__
    #include "../clonoa_simd_guards.h"
#endif
```

The [included header](clonoa_simd_guards.h) and an example of an [`__IMPORTC__`](./headers/clay.h) block can be found in this repository.
Note that some files may also need additional stub definitions for missing builtins.
They can be added inside the `__IMPORTC__` block manually as needed.

## Example

Below is an example using the [`SDL2/SDL.h`](headers/SDL2/SDL.h) header on Linux:

```sh
# Filtering with prefixes and creating opaque structs that got skipped by ImportC.
rdmd clonoa.d dmd headers/SDL2/SDL.h \
  -P=SDL:KMOD:AUDIO:DUMMY:WindowShapeMode:ShapeMode \
  -S=SDL_Window:SDL_Cursor:SDL_BlitMap:_SDL_iconv_t \
  > sdl.d
```

To test the bindings, create an `app.d` file in the same folder:

```d
import sdl;

void main() {
    SDL_Init(SDL_INIT_VIDEO);
    auto running = true;
    auto window = SDL_CreateWindow("Hello", 100, 100, 800, 600, 0);
    auto renderer = SDL_CreateRenderer(window, -1, 0);
    auto event = SDL_Event();
    while (running) {
        while (SDL_PollEvent(&event)) if (event.type == SDL_QUIT) running = false;
        SDL_SetRenderDrawColor(renderer, 107, 122, 85, 255);
        SDL_RenderClear(renderer);
        SDL_RenderPresent(renderer);
    }
    SDL_DestroyWindow(window);
    SDL_Quit();
}
```

Compile and run with:

```sh
rdmd -L=-lSDL2 app.d
```

## Library

Clonoa can be used as a library by defining the `ClonoaLibrary` version flag.
This is defined by default when using Clonoa as a DUB dependency.
The main entry points are:

```d
int clonoaMain(string[] cliArgs...);
ClonoaResult clonoaRun(ref ClonoaArgs clonoaArgs, ref Array!char output);

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
```

## What is a Clonoa?

It's a play on the names C and Klonoa, with Klonoa being a character from a game.

[![dw](https://media1.tenor.com/m/TjmvhWaDkugAAAAC/klonoa-klonoa-heroes.gif)](https://youtu.be/7zmtw_miD9I)
