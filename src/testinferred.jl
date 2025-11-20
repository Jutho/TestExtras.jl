module TestInferred
export @testinferred, @testinferred_broken
export @constinferred, @constinferred_broken

const ConstantValue = Union{Number, Char, QuoteNode}

using Test
using Test: Returned, Threw, do_test, do_broken_test

using InteractiveUtils: gen_call_with_extracted_types

_enabled = Ref(true)
enable() = (_enabled[] = true; return nothing)
disable() = (_enabled[] = false; return nothing)

# Some utility functions
function materialize_broadcasted(f, args...)
    return Broadcast.materialize(Broadcast.broadcasted(f, args...))
end

# this function extracts the parts of a type `a` that are not subtypes of `b`,
# which makes sense only for `a` being a Union type.
@static if isdefined(Base, :typesplit)
    const typesplit = Base.typesplit
else
    Base.@pure function typesplit(@nospecialize(a), @nospecialize(b))
        a <: b && return Base.Bottom
        isa(a, Union) && return Union{typesplit(a.a, b),typesplit(a.b, b)}
        return a
    end
end

# ensure backwards compatibility - have to use `return_types` which can return a vector of types
@static if isdefined(Base, :infer_return_type)
    infer_return_type(args...) = Base.infer_return_type(args...)
else
    function infer_return_type(args...)
        inftypes = Base.return_types(args...)
        return only(inftypes)
    end
end

function parsekwargs(macroname, kwargexprs...)
    kwargs = Any[]
    for arg in kwargexprs
        if !Meta.isexpr(arg, :(=))
            error("$macroname: invalid expression for keyword argument $arg")
        end
        key = arg.args[1]
        if !(key ∈ (:broken, :constprop))
            error("$macroname: unknown keyword argument \"$(key)\"")
        end
        val = arg.args[2]
        if key == :constprop && !(val isa Bool)
            error("$macroname: only `true` or `false` allowed for value of keyword argument `constprop`")
        end
        push!(kwargs, key => val)
    end
    return kwargs
end

# macro definitions
"""
    @testinferred [AllowedType] f(x) [constprop=true|false] [broken=true|false]
    @testinferred_broken [AllowedType] f(x) [constprop=true|false]
    @constinferred [AllowedType] f(x) [broken=true|false]
    @constinferred_broken [AllowedType] f(x)

Tests that the call expression `f(x)` returns a value of the same type inferred by the
compiler. This is useful to test for type stability. It is similar to `Test.@inferred`,
but in contrast to `Test.@inferred` the result of `f(x)` is always returned and
the success or failure of type inference is reported to the passed and failed test count.

`f(x)` can be any call expression, including broadcasting expressions. 

Optionally, `AllowedType` relaxes the test, by making it pass when either the type of `f(x)`
matches the inferred type modulo `AllowedType`, or when the return type is a subtype of
`AllowedType`. This is useful when testing type stability of functions returning a small
union such as `Union{Nothing, T}` or `Union{Missing, T}`.

Furthermore, the keyword argument `constprop` can be used to enable constant propagation
while testing for type inferrability. Constant propagation is applied for all arguments
and keyword arguments that have a constant value (in the call expression) of type
`Union{Number,Char,Symbol}`. If you want to test for constant propagation in a variable
which is not hard-coded in the call expression, you can interpolate it into the expression.
Note that `constprop` is `false` by default, and can only have an explicit `true` or `false`
value.

!!! note 
    Interpolating values into the call expression is only possible with `constprop = true`.

!!! warning
    With `constprop = true`, a new temporary function is created, which is not possible
    within the scope of another function.

Finally, the keyword argument `broken` can be used to test that type inference fails. Here,
the value of `broken` can be a general expression that evaluates to `true` or `false`.

Alternatively to the keyword argument `constprop=true`, you can use the `@constinferred`
macro, which has constant propagation enabled by default. Similarly, you can use the
macros `@testinferred_broken` and `@constinferred_broken` to test for broken type inference.

```jldoctest
julia> f(a) = a < 10 ? missing : 1.0
f (generic function with 1 method)

julia> @testinferred f(2)
Test Failed at REPL[54]:1
  Expression: @testinferred f(2)
   Evaluated: Missing != Union{Missing, Float64}

ERROR: There was an error during testing

julia> @constinferred f(2) # with constant propagation enabled
missing

julia> x = 2; @testinferred f(x)
Test Failed at REPL[55]:1
  Expression: @testinferred f(x)
   Evaluated: Missing != Union{Missing, Float64}

ERROR: There was an error during testing

julia> x = 2; @constinferred f(x)
Test Failed at REPL[57]:1
  Expression: @constinferred f(x)
   Evaluated: Missing != Union{Missing, Float64}

ERROR: There was an error during testing

julia> x = 2; @constinferred f(\$x)
missing

julia> x = 2; @testinferred_broken f(x)
missing

julia> broken = true; @testinferred f(x) broken = broken
missing

julia> x = 2; @constinferred_broken f(x)
missing

julia> @testinferred Missing f(2)
missing

julia> h() = (@testinferred_broken f(2)); h()
missing

ERROR: There was an error during testing

julia> h() = (@constinferred_broken f(2)); h()
ERROR: syntax: World age increment not at top level
Stacktrace:
 [1] top-level scope
```
"""
macro testinferred(args...)
    orig_ex = Expr(:inert, Expr(:macrocall, Symbol("@testinferred"), nothing, args...))
    kwargstart = something(findfirst(x -> Meta.isexpr(x, :(=)), args), length(args) + 1)
    if kwargstart > 3
        error("@testinferred: invalid expression")
    end
    kwargs = parsekwargs("@testinferred", args[kwargstart:end]...)
    if kwargstart == 3
        allow = args[1]
        ex = args[2]
        return _testinferred(ex, orig_ex, __module__, __source__, allow; kwargs...)
    else
        ex = args[1]
        return _testinferred(ex, orig_ex, __module__, __source__; kwargs...)
    end
end
macro testinferred_broken(args...)
    orig_ex = Expr(:inert, Expr(:macrocall, Symbol("@testinferred_broken"), nothing, args...))
    kwargstart = something(findfirst(x -> Meta.isexpr(x, :(=)), args), length(args) + 1)
    if kwargstart > 3
        error("@testinferred_broken: invalid expression")
    end
    kwargs = parsekwargs("@testinferred_broken", Expr(:(=), :broken, true), args[kwargstart:end]...)
    if kwargstart == 3
        allow = args[1]
        ex = args[2]
        return _testinferred(ex, orig_ex, __module__, __source__, allow; kwargs...)
    else
        ex = args[1]
        return _testinferred(ex, orig_ex, __module__, __source__; kwargs...)
    end
end
macro constinferred(args...)
    orig_ex = Expr(:inert, Expr(:macrocall, Symbol("@constinferred"), nothing, args...))
    kwargstart = something(findfirst(x -> Meta.isexpr(x, :(=)), args), length(args) + 1)
    if kwargstart > 3
        error("@constinferred: invalid expression")
    end
    kwargs = parsekwargs("@constinferred", Expr(:(=), :constprop, true), args[kwargstart:end]...)
    if kwargstart == 3
        allow = args[1]
        ex = args[2]
        return _testinferred(ex, orig_ex, __module__, __source__, allow; kwargs...)
    else
        ex = args[1]
        return _testinferred(ex, orig_ex, __module__, __source__; kwargs...)
    end
end
macro constinferred_broken(args...)
    orig_ex = Expr(:inert, Expr(:macrocall, Symbol("@constinferred_broken"), nothing, args...))
    kwargstart = something(findfirst(x -> Meta.isexpr(x, :(=)), args), length(args) + 1)
    if kwargstart > 3
        error("@constinferred_broken: invalid expression")
    end
    kwargs = parsekwargs("@constinferred_broken", Expr(:(=), :broken, true), Expr(:(=), :constprop, true), args[kwargstart:end]...)
    if kwargstart == 3
        allow = args[1]
        ex = args[2]
        return _testinferred(ex, orig_ex, __module__, __source__, allow; kwargs...)
    else
        ex = args[1]
        return _testinferred(ex, orig_ex, __module__, __source__; kwargs...)
    end
end

function _testinferred(ex, orig_ex, mod, src, allow = :(Union{}); constprop = false, broken = false)
    if Meta.isexpr(ex, :ref)
        ex = Expr(:call, :getindex, ex.args...)
    end
    Meta.isexpr(ex, :call) || error("@constinferred requires a call expression")
    farg = ex.args[1]
    if isa(farg, Symbol) && first(string(farg)) == '.'
        farg = Symbol(string(farg)[2:end])
        ex = Expr(
            :call, GlobalRef(@__MODULE__, :materialize_broadcasted),
            farg, ex.args[2:end]...
        )
    end
    pre1 = quote
        $(esc(allow)) isa Type ||
            throw(ArgumentError("@constinferred requires a type as second argument"))
    end
    # extract args and kwargs
    if length(ex.args) > 1 && Meta.isexpr(ex.args[2], :parameters)
        kwargs = ex.args[2].args
        args = ex.args[3:end]
    elseif length(ex.args) > 1 && Meta.isexpr(ex.args[2], :kw)
        kwargs = ex.args[2:end]
        args = Any[]
    else
        kwargs = Any[]
        args = ex.args[2:end]
    end

    if constprop
        callexpr, pre2 = make_callexpr_constprop(ex.args[1], args, kwargs, mod)
    else
        callexpr, pre2 = make_callexpr(ex.args[1], args, kwargs, mod)
    end

    inftype = esc(gensym())
    rettype = esc(gensym())
    result = esc(gensym())
    main = quote
        $result = $callexpr
        if $(_enabled[])
            $inftype = $(
                Expr(
                    :var"hygienic-scope",
                    gen_call_with_extracted_types(
                        mod,
                        infer_return_type,
                        callexpr
                    ),
                    @__MODULE__
                )
            )
            $rettype = $result isa Type ? Type{$result} : typeof($result)
            v = $rettype <: $(esc(allow)) ||
                $rettype == typesplit($inftype, $(esc(allow)))
            testresult = Returned(
                v, Expr(:call, :!=, $rettype, $inftype),
                $(QuoteNode(src))
            )
            if $(esc(broken))
                $(Test.do_broken_test)(testresult, $orig_ex)
            else
                $(Test.do_test)(testresult, $orig_ex)
            end
        end
        $result
    end
    finalex = quote
        $pre1
        $pre2
        let
            $main
        end
    end
    return Base.remove_linenums!(finalex)
end

function make_callexpr_constprop(f, args, kwargs, mod)
    newf = gensym()
    rightargs = Any[]
    rightkwargs = Any[]
    leftargs = Any[]
    callargs = Any[]
    quoteargs = Any[]
    for x in args
        if x isa ConstantValue
            push!(rightargs, x)
        elseif Meta.isexpr(x, :$)
            s = gensym()
            push!(rightargs, s)
            push!(quoteargs, Expr(:(=), s, x))
        else
            s = gensym()
            push!(leftargs, s)
            if Meta.isexpr(x, :...)
                push!(rightargs, Expr(:..., s))
                push!(callargs, Expr(:tuple, esc(x)))
            else
                push!(rightargs, s)
                push!(callargs, esc(x))
            end
        end
    end
    for x in kwargs
        if x isa Expr && x.head == :kw
            xkey = x.args[1]
            xval = x.args[2]
        elseif x isa Symbol
            xkey = x
            xval = x
        else
            return Expr(
                :call, :error,
                "syntax: invalid keyword argument syntax \"$x\" at $src"
            )
        end
        if xval isa ConstantValue
            push!(rightkwargs, x)
        elseif Meta.isexpr(xval, :$)
            s = gensym()
            push!(rightkwargs, Expr(:kw, xkey, s))
            push!(quoteargs, Expr(:(=), s, xval))
        else
            s = gensym()
            push!(rightkwargs, Expr(:kw, xkey, s))
            push!(leftargs, s)
            push!(callargs, esc(xval))
        end
    end
    farg = Expr(:$, f)
    fundefhead = Expr(:tuple, leftargs...)
    fundefbody = Expr(
        :block, quoteargs...,
        isempty(kwargs) ?
            Expr(:call, farg, rightargs...) :
            Expr(:call, farg, Expr(:parameters, rightkwargs...), rightargs...)
    )
    fundefex = esc(Expr(:quote, Expr(:(=), newf, Expr(:->, fundefhead, fundefbody))))
    # call expression
    callex = Expr(:call, Expr(:., mod, QuoteNode(newf)), callargs...)
    latestworld = isdefined(Core, :var"@latestworld") ? :(Core.@latestworld) : nothing
    pre = quote
        Core.eval($mod, $fundefex)
        $latestworld
    end
    return callex, pre
end

function make_callexpr(f, args, kwargs, mod)
    callargs = Any[]
    callkwargs = Any[]
    preargs = Any[]
    for x in args
        if x isa ConstantValue
            push!(callargs, x)
        elseif x isa Symbol
            push!(callargs, esc(x))
        elseif Meta.isexpr(x, :$)
            error("value interpolation with `\$` is not supported in @constinferred without constant propagation")
        else
            s = gensym()
            if Meta.isexpr(x, :...)
                push!(callargs, Expr(:..., s))
                push!(preargs, Expr(:(=), s, Expr(:tuple, esc(x))))
            else
                push!(callargs, s)
                push!(preargs, Expr(:(=), s, esc(x)))
            end
        end
    end
    for x in kwargs
        if x isa Expr && x.head == :kw
            xkey = x.args[1]
            xval = x.args[2]
        elseif x isa Symbol
            xkey = x
            xval = x
        else
            error("syntax: invalid keyword argument syntax \"$x\" at $src")
        end
        if xval isa Symbol || xval isa ConstantValue
            push!(callkwargs, x)
        elseif Meta.isexpr(xval, :$)
            error("value interpolation with `\$` is not supported in @constinferred without constant propagation")
        else
            s = gensym()
            push!(callkwargs, Expr(:kw, xkey, s))
            push!(preargs, Expr(:(=), s, esc(xval)))
        end
    end
    pre = Expr(:block, preargs...)
    callexpr = isempty(kwargs) ?
        Expr(:call, esc(f), callargs...) :
        Expr(:call, esc(f), Expr(:parameters, callkwargs...), callargs...)
    return callexpr, pre
end

end
