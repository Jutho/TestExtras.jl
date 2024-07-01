# include file as-is in local scope
macro include(filename::String)
    dir = dirname(string(__source__.file))
    filepath = joinpath(dir, filename)
    source = "quote; " * read(filepath, String) * "; end"
    return esc(Meta.parse(source).args[1])
end
