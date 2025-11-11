module TestInferred

export @testinferred

using InteractiveUtils: gen_call_with_extracted_types
using Test: @test

"""
    @testinferred [AllowedType] f(x)

Tests that the call expression `f(x)` returns a value of the same type inferred by the compiler.
It is useful to check for type stability.
This is similar to `Test.@inferred`, but instead of throwing an error, a `@test` is added.

Optionally, `AllowedType` relaxes the test, by making it pass when either the type of `f(x)` matches the inferred type modulo `AllowedType`, or when the return type is a subtype of `AllowedType`.
This is useful when testing type stability of functions returning a small union such as `Union{Nothing, T}` or `Union{Missing, T}`.
"""
macro testinferred(ex)
    return _inferred(ex, __module__)
end

macro testinferred(allow, ex)
    return _inferred(ex, __module__, allow)
end

# helper functions
_args_and_call((args..., f)...; kwargs...) = (args, kwargs, f(args...; kwargs...))
_materialize_broadcasted(f, args...) = Broadcast.materialize(Broadcast.broadcasted(f, args...))
@static if isdefined(Base, :typesplit)
    const typesplit = Base.typesplit
else
    Base.@pure function typesplit(@nospecialize(a), @nospecialize(b))
        a <: b && return Base.Bottom
        isa(a, Union) && return Union{typesplit(a.a, b), typesplit(a.b, b)}
        return a
    end
end

# ensure backwards compatibility - have to use `return_types` which can return a vector of types
@static if isdefined(Base, :infer_return_type)
    infer_return_type(args...) = Base.infer_return_type(args...)
else
    function infer_return_type(args...)
        inftypes = Base.return_types(args...)
        @assert length(inftypes) == 1
        return only(inftypes)
    end
end

function _inferred(ex, mod, allow = :(Union{}))
    if Meta.isexpr(ex, :ref)
        ex = Expr(:call, :getindex, ex.args...)
    end
    Meta.isexpr(ex, :call)|| error("@testinferred requires a call expression")

    # handle broadcasting expressions
    farg = ex.args[1]
    if isa(farg, Symbol) && farg !== :.. && first(string(farg)) == '.'
        farg = Symbol(string(farg)[2:end])
        ex = Expr(:call, GlobalRef(@__MODULE__, :_materialize_broadcasted), farg, ex.args[2:end]...)
    end

    result = let ex = ex
        quote
            let allow = $(esc(allow))
                allow isa Type || throw(ArgumentError("@testinferred requires a type as second argument"))
                $(
                    if any(@nospecialize(a) -> (Meta.isexpr(a, :kw) || Meta.isexpr(a, :parameters)), ex.args)
                        # Has keywords
                        # Create the call expression with escaped user expressions
                        call_expr = :($(esc(ex.args[1]))(args...; kwargs...))
                        quote
                            args, kwargs, result = $(esc(Expr(:call, _args_and_call, ex.args[2:end]..., ex.args[1])))
                            # wrap in dummy hygienic-scope to work around scoping issues with `call_expr` already having `esc` on the necessary parts
                            inftype = $(Expr(:var"hygienic-scope", gen_call_with_extracted_types(mod, infer_return_type, call_expr), @__MODULE__))
                        end
                    else
                        # No keywords
                        quote
                            args = ($([esc(ex.args[i]) for i in 2:length(ex.args)]...),)
                            result = $(esc(ex.args[1]))(args...)
                            inftype = $(GlobalRef(@__MODULE__, :infer_return_type))($(esc(ex.args[1])), Base.typesof(args...))
                        end
                    end
                )
                rettype = result isa Type ? Type{result} : typeof(result)
                @test (rettype <: allow || rettype == typesplit(inftype, allow))
                result
            end
        end
    end

    return Base.remove_linenums!(result)
end

end
