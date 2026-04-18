# Clonoa

A tool that generates D bindings from C files using [ImportC](https://dlang.org/spec/importc.html).

## Usage

The tool is just one D file: [`clonoa.d`](./clonoa.d).
By default, Clonoa accepts a C file and prints the bindings to stdout:

```sh
rdmd clonoa.d header.h > bindings.d
# Or: ./clonoa.d header.h > bindings.d
```

### Example

Below is an example using the `SDL2/SDL.h` header from the [headers](./headers) folder:

```sh
rdmd clonoa.d headers/SDL2/SDL.h > sdl.d
# Or: ./clonoa.d headers/SDL2/SDL.h > sdl.d
```

Create an `app.d` file next to the bindings that looks like this:

```d
import sdl;
pragma(lib, "SDL2");

void main() {
    SDL_Init(SDL_INIT_VIDEO);
    auto window = SDL_CreateWindow("Hello", 100, 100, 800, 600, 0);
    auto renderer = SDL_CreateRenderer(window, -1, 0);
    auto running = true;
    SDL_Event e;
    while (running) {
        while (SDL_PollEvent(&e)) if (e.type == SDL_QUIT) running = false;
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
rdmd app.d
```

### Library

Clonoa can be used as a library by defining the `ClonoaLibrary` version flag.
The function that creates the bindings is called `clonoaRun` and looks like this:

```d
ClonoaResult clonoaRun(in ClonoaArgs args);

struct ClonoaResult {
    string faultMessage;
    string output;
}

struct ClonoaArgs {
    string headerPath;
    string headerPathBaseName;
    string headerPrefix;
    string compiler;
    string[string] typeMap;
    string[] typeSkipList;
    string[] funcSkipList;
    string[] lineSkipList;
    string moduleSymbolHeader;
    string moduleAttributes;
    string moduleTargetName;
    bool autoPopulateByName;

    this(string headerPath, bool autoPopulateByName = true);
}
```

### SIMD Guards

Some headers fail to parse with ImportC due to unsupported SIMD symbols.
This can be fixed by adding the following at the top of the target header:

```c
#if __IMPORTC__
    #include "../clonoa_simd_guards.h"
#endif
```

Note that some headers may also need additional stub definitions for missing builtins.
They can be added inside the `__IMPORTC__` block manually as needed.
