using TestExtras
using Test

@timedtestset "TestExtras.jl" begin

    mysqrt(x; complex = true) = x >= 0 ? sqrt(x) : (complex ? im*sqrt(-x) : throw(DomainError(x, "Enable complex return values to take square roots of negative numbers")))

    @constinferred mysqrt(+3)
    @constinferred mysqrt(-3)
    for x = -1.5:0.5:+1.5
        @constinferred mysqrt($x)
    end

    @constinferred Nothing iterate(1:5)
    @constinferred Nothing iterate(1:-1)
    @constinferred Tuple{Int,Int} iterate(1:-1)

    x = 3.
    @constinferred mysqrt(x; complex = false)
end
