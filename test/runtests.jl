using TestExtras
using Test

@timedtestset "tests part 1" begin

    mysqrt(x; complex = true) = x >= 0 ? sqrt(x) : (complex ? im*sqrt(-x) : throw(DomainError(x, "Enable complex return values to take square roots of negative numbers")))

    @constinferred mysqrt(+3)
    @constinferred mysqrt(-3)
    for x = -1.5:0.5:+1.5
        @constinferred mysqrt($x)
    end

    @constinferred Nothing iterate(1:5)
    @constinferred Nothing iterate(1:-1)
    @constinferred Tuple{Int,Int} iterate(1:-1)

    @constinferred (1:3)[2]
    a = (0.1, 0.2, 0.3)
    b = (3, 2, 1)
    @constinferred a .+ b

    x = 3.
    @constinferred mysqrt(x; complex = false)
end

# ensure constinferred only evaluates argument once
inferred_test_global = 0
function inferred_test_function()
    global inferred_test_global
    inferred_test_global += 1
    true
end
@constinferred inferred_test_function()
@test inferred_test_global == 1



f25835(;x=nothing) = _f25835(x)
_f25835(::Nothing) = ()
_f25835(x) = (x,)
# A keyword function that is never type stable
g25835(;x=1) = rand(Bool) ? 1.0 : 1
# A keyword function that is sometimes type stable
h25835(;x=1,y=1) = x isa Int ? x*y : (rand(Bool) ? 1.0 : 1)

@timedtestset begin
    @test @constinferred(f25835()) == ()
    @test @constinferred(f25835(x=nothing)) == ()
    @test @constinferred(f25835(x=1)) == (1,)

    @test @constinferred(h25835()) == 1
    @test @constinferred(h25835(x=2,y=3)) == 6
    @test @constinferred(Union{Float64,Int64}, h25835(x=1.0,y=1.0)) == 1
end
