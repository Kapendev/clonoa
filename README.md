# Clonoa (WIP)

A tool that generates D bindings from C files using [ImportC](https://dlang.org/spec/importc.html).

## Usage

The tool is just one D file: [`clonoa.d`](./clonoa.d).
Compile and run with:

```sh
rdmd clonoa.d
```

### CLI
By default, Clonoa accepts one C file and prints the bindings to stdout:

```sh
rdmd clonoa.d header.h > bindings.d
```

### Library

Clonoa can also be used it as a library by defining the `ClonoaLibrary` version flag.
The function that creates the bindings is called `clonoaMain`.

```d
string clonoaMain(
    string compiler,
    bool canEmitTagStructs,
    string[] args,
    string symbolHeader = defaultSymbolHeader,
    string[string] typeMap = defaultTypeMap,
    string[] skipList = defaultSkipList,
);
```
