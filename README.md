# Clonoa (WIP)

A tool that generates D bindings from C files using [ImportC](https://dlang.org/spec/importc.html).

## Usage

The tool is just one D file: [`clonoa.d`](./clonoa.d).
Compile and run with:

```sh
rdmd clonoa.d
# Or: ./clonoa.d
```

### CLI

By default, Clonoa accepts one C file and prints the bindings to stdout:

```sh
rdmd clonoa.d header.h > bindings.d
# Or: ./clonoa.d header.h > bindings.d
```

### Library

Clonoa can be used as a library by defining the `ClonoaLibrary` version flag.
The function that creates the bindings is called `clonoaMain` and looks like this:

```d
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
);
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
