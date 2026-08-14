# Installation

*From a bare machine to a working `using Sturm`. Every Julia output and every
error message quoted here is real, captured from this machine; the CMake steps
are Orkan's own documented build.*

Sturm.jl is not a registered Julia package. You clone it, you clone the C
simulator it calls, you build that simulator, and then it works. There are four
steps and a check.

## 1. Julia 1.11 or newer

```console
$ julia --version
julia version 1.12.5
```

**1.11 is a hard floor, not a suggestion.** Sturm carries the current execution
context in a `ScopedValue` — a Base facility introduced in 1.11 that, unlike
task-local storage, is correctly inherited by tasks you spawn. It also uses the
1.11 `public` keyword to mark the kernel API as documented-but-not-exported.
Julia 1.10 and earlier have neither, and the package's own compatibility bound
declines to install there. Get Julia from
[julialang.org](https://julialang.org/downloads/) or via
[juliaup](https://github.com/JuliaLang/juliaup).

## 2. A C toolchain for the backend

Sturm does no linear algebra of its own. It calls **Orkan**, a C17 statevector
and density-matrix simulator, through `ccall`. You need:

- **CMake ≥ 3.27**
- **a C17 compiler** (gcc, clang, or Apple clang)
- **OpenMP** — optional but wanted for speed. A system package on Linux;
  Homebrew `libomp` on macOS.

## 3. Clone the repositories, side by side

Orkan is found by a *relative path* from the Sturm source tree, so the layout
matters:

```console
$ mkdir -p ~/Projects && cd ~/Projects
$ git clone https://github.com/tobiasosborne/Sturm.jl.git
$ git clone https://github.com/Timo59/orkan.git
```

leaving you with:

```
~/Projects/
  Sturm.jl/       # this package
  orkan/          # the C simulator — must sit beside Sturm.jl
  Bennett.jl/     # optional, see step 6
```

## 4. Build liborkan

```console
$ cd ~/Projects/orkan
$ cmake --preset release
$ cmake --build --preset release
```

That produces `~/Projects/orkan/cmake-build-release/src/liborkan.so`
(`.dylib` on macOS). **There is no install step.** Sturm looks for exactly that
path relative to its own source, so a freshly built sibling checkout works with
zero configuration — no environment variables, no `cmake --install`.

If you would rather keep the library somewhere else, set `LIBORKAN_PATH` to the
file itself (see [Troubleshooting](#Troubleshooting) below).

## 5. Check that it worked

```console
$ cd ~/Projects/Sturm.jl
$ julia --project -e 'using Sturm; println(Sturm.eager(1) do _; Bool(QBool(true)) end)'
true
```

That one line does more than it looks like. `using Sturm` loads the package,
resolves the shared library, and asserts the byte size of every C struct it
mirrors — so a layout drift between the two projects fails loudly at load time
rather than corrupting a state silently. Then
`Sturm.eager(1)` allocates a one-qubit simulator state, `QBool(true)` prepares
`|1⟩`, and `Bool(...)` measures it. Getting `true` means the whole stack — Julia
types, the FFI, the C kernel — is live.

The first call pays a compilation cost of roughly 40 seconds. Subsequent calls
in the same session are fast.

Want more assurance? Run the test suite. It takes a while.

```console
$ julia --project -e 'using Pkg; Pkg.test()'
```

Note that `Pkg.test()` requires the optional Bennett checkout from the next
step; plain `using Sturm` does not.

## 6. Optional: Bennett.jl, for `oracle`

One of the seven surface constructs, `oracle(f, x)`, takes an ordinary Julia
function and compiles it into a reversible quantum operation. That compiler is a
separate package, [Bennett.jl](https://github.com/tobiasosborne/Bennett.jl),
wired in as a *weak dependency*: Sturm works fine without it, and the bridge
activates the moment both packages are loaded in the same session.

Without Bennett, `oracle` fails loudly and tells you so:

```julia
using Sturm

Sturm.eager(20) do ctx
    x = QInt{3}(5)
    b = QInt{3}(0)
    b ⊻= oracle(v -> v + 0x01, x)
    Int(b)
end
# ERROR: oracle(f, x): the Bennett backend is not loaded — add `using Bennett`
#        alongside `using Sturm` to activate the `SturmBennettExt` extension
```

To get it, clone Bennett beside the other two and make a small environment that
develops both:

```console
$ cd ~/Projects
$ git clone https://github.com/tobiasosborne/Bennett.jl.git
$ mkdir quantum && cd quantum
$ julia --project=. -e 'using Pkg;
                        Pkg.develop(path="../Sturm.jl");
                        Pkg.develop(path="../Bennett.jl")'
```

Now, from `~/Projects/quantum`:

```julia
using Sturm, Bennett

inc(v) = v + 0x01                     # an ordinary Julia function

Sturm.eager(20) do ctx
    x = QInt{3}(5)                    # a 3-bit quantum integer holding 5
    b = QInt{3}(0)                    # somewhere to put the answer
    b ⊻= oracle(inc, x)               # b ← b ⊕ inc(x), reversibly
    (Int(x), Int(b))
end
# => (5, 6)
```

`x` survives the call — reversibility means the input is preserved — and `b`
picks up `0 ⊕ 6 = 6`. The capacity of `20` is not the register width; the
reversible compilation needs scratch wires, and it borrows them from the same
sandbox. See [writing oracles](../howto/write_oracles.md) for what `f` may
contain.

> **Why a separate environment?** Sturm's own project file lists Bennett only as
> a weak dependency and a test dependency, so `using Bennett` from inside
> `~/Projects/Sturm.jl` raises `ArgumentError: Package Bennett not found in
> current path`. A project of your own that develops both packages is the
> supported way to use them together — and it is where your own code should
> live anyway.

## Troubleshooting

### `could not load library "liborkan"`

```
ERROR: could not load library "liborkan"
liborkan.so: cannot open shared object file: No such file or directory
```

This is the common one, and note *when* it appears: `using Sturm` succeeds, and
the failure comes at the first operation that touches quantum state. Sturm looks
for the library in three places, in order — the `LIBORKAN_PATH` environment
variable, the sibling `../orkan/cmake-build-release/src/liborkan.so`, and
finally the bare name `liborkan`, handed to the system loader. Reaching the
third and failing means neither of the first two was there.

Fixes, in order of likelihood:

1. You have not built Orkan yet, or the build failed. Redo step 4 and confirm
   `ls ~/Projects/orkan/cmake-build-release/src/liborkan.so` finds a file.
2. Your checkouts are not siblings — `orkan/` must sit next to `Sturm.jl/`, not
   inside it or three directories away. Either move it, or set the environment
   variable:
   ```console
   $ export LIBORKAN_PATH=/absolute/path/to/liborkan.so
   ```

### `LIBORKAN_PATH=… is set but does not exist`

```
ERROR: InitError: LIBORKAN_PATH=/nonexistent/liborkan.so is set but does not exist. Fix it, unset it, or build:
  cd ../orkan && cmake --preset release && cmake --build cmake-build-release
```

The override is set but points at nothing. This one fires immediately at
`using Sturm`, not at first use — a stale variable is a mistake worth reporting
early. Point it at the real file, or unset it and let the sibling search work.

**A related trap:** the variable is read exactly once, when the package
initialises. Setting it *after* `using Sturm` in the same session does nothing
at all:

```julia
using Sturm
ENV["LIBORKAN_PATH"] = "/some/other/liborkan.so"
Sturm.LIBORKAN[]
# => "/home/you/Projects/Sturm.jl/src/orkan/../../../orkan/cmake-build-release/src/liborkan.so"
```

Set it in the shell, then start a fresh Julia process.

### Julia is older than 1.11

Check first, because the symptom is a load failure with no obvious connection to
the version:

```console
$ julia --version
```

Anything below 1.11 lacks both `ScopedValue` and the `public` keyword, and the
package's own compatibility bound rejects it. Install a newer Julia; there is no
workaround.

### `expected package Bennett … to exist at path …`

```
ERROR: expected package `Bennett [d4e5f6a7]` to exist at path `/home/you/Projects/Bennett.jl`
```

You ran `Pkg.test()` (or another operation that resolves the full test
environment) without the Bennett sibling checkout. Sturm's project file pins
Bennett by relative path, so the test target cannot resolve without it. Clone it
as in step 6. Ordinary use — `using Sturm`, running your own programs — is
unaffected.

### The library loads but everything is slow

Orkan parallelises with OpenMP. At load time Sturm sets `OMP_NUM_THREADS` for
you if you have not set it, choosing a quarter of your CPU count capped at 16 —
deliberately conservative, because oversubscribing threads on a small state
vector costs more than it buys. If you set the variable yourself, Sturm leaves
your value alone, including when it is a bad one.

## Next

[Write your first program](first_program.md).
