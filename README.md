
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
  -T=<name>   Exclude type(s) (e.g. Vector2:Vector3:Vector4)
  -F=<name>   Exclude function(s) (e.g. DrawText:DrawTextEx:DrawTextPro:MeasureText)
  -H=<path>   Module symbol header path (e.g. raylib_header.txt)
  -R=<path>   Type map path (e.g. raylib_types.ini)
  -X=<prefix> Exclude prefix(es) from function names (e.g. -X=SDL_ turns SDL_Init to Init)
  -L          Lower the first character of function names (e.g. turns InitWindow to initWindow)
  -E          Remove repeated enums (e.g. alias theThing = Enum.theThing;)
  -V          Print skipped symbols to stderr
```

To run Clonoa from any folder via DUB, use:

```
dub run clonoa -- <compiler> <file.c|file.h> [options]
```

Clonoa examples are in the [examples section](#examples) of this README.

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
    string[] excludePrefixes;
    bool lowerFirstChar;
    bool removeRepeatedEnums;
    bool verbose;

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

## Examples

### Hello

Below is an example using the [`hello.c`](hello.c) file on Linux:

```sh
rdmd source/clonoa.d dmd headers/hello.c
```

This will print:

```c
module hello;

extern(C) nothrow @nogc:

struct debug_ {
    int debug_;
}

enum Foo {
    FOO_1,
    FOO_2,
    function_,
}

alias FOO_1 = Foo.FOO_1;
alias FOO_2 = Foo.FOO_2;
alias function_ = Foo.function_;
int foo1();
long foo2();
```

### SDL2

Below is an example using the [`SDL2/SDL.h`](headers/SDL2/SDL.h) header (that needs an `__IMPORTC__` block) on Linux:

```sh
# Filtering with prefixes and creating opaque structs that got skipped by ImportC.
rdmd source/clonoa.d dmd headers/SDL2/SDL.h \
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
    auto window = SDL_CreateWindow("D + SDL", 100, 100, 800, 600, 0);
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

The `SDL_` prefix can be removed from functions by passing the `-X=SDL_` flag.
With this enabled, the code becomes:

```d
import sdl;

void main() {
    Init(SDL_INIT_VIDEO);
    auto running = true;
    auto window = CreateWindow("D + SDL", 100, 100, 800, 600, 0);
    auto renderer = CreateRenderer(window, -1, 0);
    auto event = SDL_Event();
    while (running) {
        while (PollEvent(&event)) if (event.type == SDL_QUIT) running = false;
        SetRenderDrawColor(renderer, 107, 122, 85, 255);
        RenderClear(renderer);
        RenderPresent(renderer);
    }
    DestroyWindow(window);
    Quit();
}
```

### raylib

Below is an example using the [`raylib.h`](headers/raylib.h) header on Linux:

```sh
# Creating opaque structs that got skipped by ImportC.
rdmd source/clonoa.d dmd headers/raylib.h \
    -S=rAudioBuffer:rAudioProcessor \
    > raylib.d
```

To test the bindings, create an `app.d` file in the same folder:

```d
import raylib;

void main() {
    InitWindow(800, 450, "D + raylib");
    while (!WindowShouldClose) {
        BeginDrawing();
        ClearBackground(Color(40, 40, 40, 255));
        DrawText("Hello, World!", 16, 16, 20, Color(200, 200, 200, 255));
        EndDrawing();
    }
    CloseWindow();
}
```

Compile and run with:

```sh
rdmd -L=-lraylib -L=-lX11 app.d
```

The PascalCase can be changed to camelCase for function names by passing the `-L` flag.
With this enabled, the code becomes:

```d
import raylib;

void main() {
    initWindow(800, 450, "D + raylib");
    while (!windowShouldClose) {
        beginDrawing();
        clearBackground(Color(40, 40, 40, 255));
        drawText("Hello, World!", 16, 16, 20, Color(200, 200, 200, 255));
        endDrawing();
    }
    closeWindow();
}
```

## What is a Clonoa?

It's a play on the names C and Klonoa, with Klonoa being a character from a game.

[![dw](https://media1.tenor.com/m/TjmvhWaDkugAAAAC/klonoa-klonoa-heroes.gif)](https://youtu.be/7zmtw_miD9I)
