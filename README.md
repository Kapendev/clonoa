# Clonoa

A tool that generates D bindings from C files using [ImportC](https://dlang.org/spec/importc.html).

![dw](https://media0.giphy.com/media/v1.Y2lkPTc5MGI3NjExMGI3MmR6NzJwcDNvOGt5N2g5cDdwNW9pbDRrMjBtM29sZDMwZGV2MyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/IjPLlyNa8ajCLfIsA6/giphy.gif)

## Usage

Clonoa is a single D file: [`clonoa.d`](./clonoa.d).
By default, it accepts a C file and prints the bindings to stdout:

```sh
rdmd clonoa.d header.h > bindings.d
# Or: ./clonoa.d header.h > bindings.d
```

The CLI follows this structure:

```
clonoa <source.c|source.h> [module name] [header prefix]
```

## SIMD Guards

Some files fail to parse with ImportC due to unsupported SIMD symbols.
This can be fixed by adding the following at the top of the file:

```c
#if __IMPORTC__
    #include "../clonoa_simd_guards.h"
#endif
```

The [included header](./clonoa_simd_guards.h) and an example of the [`__IMPORTC__`](./headers/clay.h) block above can be found in this repository.
Note that some files may also need additional stub definitions for missing builtins.
They can be added inside the `__IMPORTC__` block manually as needed.

## Example

Below is an example using the [`SDL2/SDL.h`](./headers/SDL2/SDL.h) header from the headers folder:

```sh
rdmd clonoa.d headers/SDL2/SDL.h sdl SDL > sdl.d
```

Create an `app.d` file next to the bindings that looks like this:

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
The function that creates the bindings is called `clonoaRun` and looks like this:

```d
ClonoaResult clonoaRun(ref ClonoaArgs args, ref Array!char output);

struct ClonoaResult {
    int fault;
    string faultMessage;

    alias fault this;
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
    string moduleName;
    bool strictPrefix;
    bool autoPopulateByName;

    this(string headerPath, string moduleName, string headerPrefix, bool autoPopulateByName = true);
}
```
