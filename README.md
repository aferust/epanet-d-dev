# epanet-d dev
The d code was ported from [the original C++ implementation](https://github.com/OpenWaterAnalytics/epanet-dev) which is WIP too.
 * Why dlang? Because to better achieve the goals defined as"the code to be more modular, extensible, and easier to maintain", I think dlang is superior to C++ in many ways.
 * I would happily transfer the ownership of the repo to OpenWaterAnalytics on request.
 * The example inp [files](https://github.com/OpenWaterAnalytics/EPANET/blob/dev/example-networks/) were successfully tested
 * The output binary file generation must be tested. It is probably buggy.

## Dependencies
 * only the d standard library phobos.

## How to buiild
You need any d compiler and dub (the D language's official package manager) which is usually shipped with the compilers.

for command line executable:
```
dub build --config=cli
```

for dynamic library:
```
dub build --config=dynamicLibrary
```