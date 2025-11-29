# TestExtras

[![Build Status](https://github.com/Jutho/TestExtras.jl/workflows/CI/badge.svg)](https://github.com/Jutho/TestExtras.jl/actions)
[![Coverage](https://codecov.io/gh/Jutho/TestExtras.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/Jutho/TestExtras.jl)

This package adds useful additions to the functionality provided by `Test`, the Julia
standard library for writing tests.

# What's new in version 0.3.3

* Introduction of a `@testinferred` macro, that unlike `@constinferred` can be used inside
  functions, but does not apply constant propagation. However, unlike `Test.@inferred`, it
  does contribute to the test results.

# Short description of the package

The first feature of TestExtras.jl are the macros `@testinferred` and `@constinferred`, 
which are a replacement of `Test.@inferred` but with two major differences.

1.  Unlike `Test.@inferred`, the comparison between the actual and inferred runtype is a
    proper test which contributes to the total number of passed or failed tests.

2.  Unlike `Test.@inferred`, `@constinferred` will test whether the return value of a
    function call can be inferred in combination with constant propagation. For `@inferred`,
    both `@inferred f(3, ...)` and `x=3; @inferred f(x, ...)` will yield the same result,
    based on probing `Base.return_types(f,(Int,...))`. In contrast `@constinferred f(3,...)`
    will wrap the function call in a new function in which the value `3` is hard-coded, and
    test whether the return type of this wrapper function can be inferred, so as to let
    constant propagation do its work. This is true for all arguments (positional and
    keyword) whose value is a literal constants of type `Integer`, `Char` or `Symbol`.
    Generic arguments will instead also be arguments to the wrapper function and will thus
    not trigger constant propagation. However, sometimes it is useful to test for successful
    constant propagation of a certain variable, even though you want to keep it as a symbol
    in the test, for example because you want to loop over possible values. In that case,
    you can interpolate the value into the `@constinferred` expression.

    However, because this macro works by defining a new function, it cannot be used inside
    other functions. Therefore, `@testinferred` is provided as a variant that works inside
    functions, but without constant propagation. In fact, `@constinferred f(args...)` is
    equivalent to `@testinferred f(args...) constprop=true`, where the optional keyword argument
    `constprop` (default `false`) controls whether constant propagation is applied.

Some example is probably more insightful. We define a new function `mysqrt` that is
type-unstable with respect to real values of the argument `x`, at least if the keyword
argument `complex = true`.

```julia
julia> using Test, TestExtras

julia> mysqrt(x; complex = true) = x >= 0 ? sqrt(x) : (complex ? im*sqrt(-x) : throw(DomainError(x, "Enable complex return values to take square roots of negative numbers")))
mysqrt (generic function with 1 method)

julia> x = 3.
3.0

julia> @inferred mysqrt(x)
ERROR: return type Float64 does not match inferred return type Union{Complex{Float64}, Float64}
Stacktrace:
 [1] error(::String) at ./error.jl:33
 [2] top-level scope at REPL[5]:1

julia> @inferred mysqrt(3.)
ERROR: return type Float64 does not match inferred return type Union{Complex{Float64}, Float64}
Stacktrace:
 [1] error(::String) at ./error.jl:33
 [2] top-level scope at REPL[6]:1

julia> @inferred mysqrt(-3.)
ERROR: return type Complex{Float64} does not match inferred return type Union{Complex{Float64}, Float64}
Stacktrace:
 [1] error(::String) at ./error.jl:33
 [2] top-level scope at REPL[7]:1

julia> @inferred mysqrt(x; complex = false)
ERROR: return type Float64 does not match inferred return type Union{Complex{Float64}, Float64}
Stacktrace:
 [1] error(::String) at ./error.jl:33
 [2] top-level scope at REPL[8]:1

julia> @constinferred mysqrt(x)
Test Failed at REPL[10]:1
  Expression: @constinferred mysqrt(x)
   Evaluated: Float64 != Union{Complex{Float64}, Float64}
ERROR: There was an error during testing

julia> @constinferred mysqrt($x)
1.7320508075688772

julia> @constinferred mysqrt(3.)
1.7320508075688772

julia> @constinferred mysqrt(-3.)
0.0 + 1.7320508075688772im

julia> @constinferred mysqrt(x; complex = false)
1.7320508075688772
```
Note, firstly, that the case where `@constinferred` detects that the return type cannot be
inferred for a general argument of type `Float64`, it reports the error as an actual test
failure rather than a generic error. Secondly, note that while the `@constinferred` macro
seems to work for all versions of Julia from version 1 onwards, the result can depend on the
specific Julia version, as changes in the compiler affect constant propagation. In
particular, the constant propagation for the keyword argument in the last test only leads to
an inferred return type on Julia 1.5 (and beyond?).

The second feature of TestExtras.jl is a new type of `TestSet`, namely `TimedTestSet`, which
is essentially a backport of the the `Test.DefaultTestSet` of Julia v1.8 (but it dates back
to before it existed in the `Test` standard library). In particular, the difference with the
`Test.DefaultTestSet` on older Julia versions is that it also prints the total time it took
to execute the test set, together with the number of passed, failed and broken tests. While
this service should not be used as a finetuned performance regression detection mechanism,
it can provide a first hint of possible regressions in case there is a significant
discrepancy in the time of a testset in comparison to previous runs. There is a simple macro
`@timedtestset` to facilitate using this testset. The name `TimedTestSet` is itself not
exported, so one either does
```julia
using Test, TestExtras
@timedtestset "some optional name" begin
    ...
end
```
or
```julia
using Test, TestExtras
using TestExtras: TimedTestSet
@testset TimedTestSet "some optional name" begin
    ...
end
```
