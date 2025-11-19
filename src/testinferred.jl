module TestInferred

export @testinferred

using InteractiveUtils: gen_call_with_extracted_types
using Test: @test
using ..Utilities: args_and_call, materialize_broadcasted, typesplit, infer_return_type
using InteractiveUtils: gen_call_with_extracted_types

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

function _inferred(ex, mod, allow = :(Union{}))
    if Meta.isexpr(ex, :ref)
        ex = Expr(:call, :getindex, ex.args...)
    end
    Meta.isexpr(ex, :call)|| error("@testinferred requires a call expression")

    # handle broadcasting expressions
    farg = ex.args[1]
    if isa(farg, Symbol) && farg !== :.. && first(string(farg)) == '.'
        farg = Symbol(string(farg)[2:end])
        ex = Expr(:call, GlobalRef(@__MODULE__, :materialize_broadcasted), farg, ex.args[2:end]...)
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
                            args, kwargs, result = $(esc(Expr(:call, args_and_call, ex.args[2:end]..., ex.args[1])))
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
