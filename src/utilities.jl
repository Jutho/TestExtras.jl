module Utilities

args_and_call((args..., f)...; kwargs...) = (args, kwargs, f(args...; kwargs...))

materialize_broadcasted(f, args...) = Broadcast.materialize(Broadcast.broadcasted(f, args...))

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
        return only(inftypes)
    end
end

end