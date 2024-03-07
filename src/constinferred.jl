module ConstInferred
export @constinferred, @constinferred_broken

const ConstantValue = Union{Number,Char,QuoteNode}

using InteractiveUtils: gen_call_with_extracted_types
using Test
using Test: Returned, Threw

@static if isdefined(Base, :typesplit)
    const typesplit = Base.typesplit
else
    Base.@pure function typesplit(@nospecialize(a), @nospecialize(b))
        if a <: b
            return Base.Bottom
        end
        if isa(a, Union)
            return Union{typesplit(a.a, b),
                         typesplit(a.b, b)}
        end
        return a
    end
end

_enabled = Ref(true)
enable() = (_enabled[] = true; return nothing)
disable() = (_enabled[] = false; return nothing)

function _materialize_broadcasted(f, args...)
    return Broadcast.materialize(Broadcast.broadcasted(f, args...))
end

"""
    @constinferred [AllowedType] f(x)
Tests that the call expression `f(x)` returns a value of the same type inferred by the
compiler. It is useful to check for type stability. Similar to `Test.@inferred`, but
differs in two important ways.

Firstly, `@constinferred` tries to test type stability under constant propagation by
testing type stability of a new function, where all arguments or keyword arguments of
the original function `f` that have a constant value (in the call expression) of type
`Union{Number,Char,Symbol}` are hard coded.

If you want to test for constant propagation in a variable which is not hard-coded in 
the call expression, you can interpolate it into the expression.

Secondly, @constinferred returns the value if type inference succeeds, like `@inferred`,
but used the `Test.@test` mechanism and shows up as an actual test error when type
inference fails.
```
"""
macro constinferred(ex)
    return _constinferred(ex, __module__, __source__, Test.do_test)
end
macro constinferred(allow, ex)
    return _constinferred(ex, __module__, __source__, Test.do_test, allow)
end

macro constinferred_broken(ex)
    return _constinferred(ex, __module__, __source__, Test.do_broken_test)
end

macro constinferred_broken(allow, ex)
    return _constinferred(ex, __module__, __source__, Test.do_broken_test, allow)
end

function _constinferred(ex, mod, src, test_f, allow=:(Union{}))
    if Meta.isexpr(ex, :ref)
        ex = Expr(:call, :getindex, ex.args...)
    end
    Meta.isexpr(ex, :call) || error("@constinferred requires a call expression")
    farg = ex.args[1]
    if isa(farg, Symbol) && first(string(farg)) == '.'
        farg = Symbol(string(farg)[2:end])
        ex = Expr(:call, GlobalRef(Test, :_materialize_broadcasted),
                  farg, ex.args[2:end]...)
    end
    pre = quote
        $(esc(allow)) isa Type ||
            throw(ArgumentError("@constinferred requires a type as second argument"))
    end
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
            return Expr(:call, :error, "syntax: invalid keyword argument syntax \"$x\" at $src")
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
    f = Expr(:$, ex.args[1])

    fundefhead = Expr(:tuple, leftargs...)
    fundefbody = Expr(:block, quoteargs...,
                      isempty(kwargs) ?
                      Expr(:call, f, rightargs...) :
                      Expr(:call, f, Expr(:parameters, rightkwargs...), rightargs...))
    fundefex = esc(Expr(:quote, Expr(:(=), newf, Expr(:->, fundefhead, fundefbody))))

    inftypes = gensym()
    rettype = gensym()
    result = esc(gensym())
    newfcall = Expr(:., mod, QuoteNode(newf))
    main = quote
        callargs = ($(callargs...),)
        $result = $newfcall(callargs...)
        $(esc(inftypes)) = Base.return_types($newfcall, Base.typesof(callargs...))
        $(esc(rettype)) = $result isa Type ? Type{$result} : typeof($result)
    end
    orig_ex = Expr(:inert, Expr(:macrocall, Symbol("@constinferred"), nothing, ex))
    post = quote
        if $(_enabled[])
            if length($(esc(inftypes))) > 1
                testresult = Threw(ArgumentError("more than one inferred type"),
                                   Base.catch_stack(), $(QuoteNode(src)))
            else
                v = $(esc(rettype)) <: $(esc(allow)) ||
                    $(esc(rettype)) == typesplit($(esc(inftypes))[1], $(esc(allow)))
                testresult = Returned(v,
                                      Expr(:call, :!=, $(esc(rettype)),
                                           $(esc(inftypes))[1]), $(QuoteNode(src)))
            end

            $test_f(testresult, $orig_ex)
        end
        $result
    end
    finalex = Base.remove_linenums!(quote
                                        $pre
                                        Core.eval($mod, $fundefex)
                                        let
                                            $main
                                            $post
                                        end
                                    end)
    return finalex
end
end
