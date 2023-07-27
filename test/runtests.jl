using TestExtras
using Test

@timedtestset "constinferred tests" begin
    function mysqrt(x; complex=true)
        return x >= 0 ? sqrt(x) :
               (complex ? im * sqrt(-x) :
                throw(DomainError(x,
                                  "Enable complex return values to take square roots of negative numbers")))
    end

    @constinferred mysqrt(+3)
    @constinferred mysqrt(-3)
    for x in -1.5:0.5:+1.5
        @constinferred mysqrt($x)
        @constinferred mysqrt($(rand() < 0 ? x : -x))
    end

    @constinferred Nothing iterate(1:5)
    @constinferred Nothing iterate(1:-1)
    @constinferred Tuple{Int,Int} iterate(1:-1)

    x = (2, 3)
    @constinferred +(1, x...)

    @constinferred (1:3)[2]
    a = (0.1, 0.2, 0.3)
    b = (3, 2, 1)
    @constinferred a .+ b

    x = 3.0
    @constinferred mysqrt(x; complex=false)
    @constinferred_broken mysqrt(x; complex=true)
end

# ensure constinferred only evaluates argument once
inferred_test_global = 0
function inferred_test_function()
    global inferred_test_global
    inferred_test_global += 1
    return true
end
@constinferred inferred_test_function()
@test inferred_test_global == 1

f25835(; x=nothing) = _f25835(x)
_f25835(::Nothing) = ()
_f25835(x) = (x,)
# A keyword function that is never type stable
g25835(; x=1) = rand(Bool) ? 1.0 : 1
# A keyword function that is sometimes type stable
h25835(; x=1, y=1) = x isa Int ? x * y : (rand(Bool) ? 1.0 : 1)

@timedtestset begin
    @test @constinferred(f25835()) == ()
    @test @constinferred(f25835(x=nothing)) == ()
    @test @constinferred(f25835(x=$(rand() < 0 ? nothing : nothing))) == ()
    @test @constinferred(f25835(x=1)) == (1,)

    @test @constinferred(h25835()) == 1
    @test @constinferred(h25835(x=2, y=3)) == 6
    @test @constinferred(Union{Float64,Int64}, h25835(x=1.0, y=1.0)) == 1
end

@timedtestset "@test" begin
    @test true
    @test 1 == 1
    @test 1 != 2
    @test ==(1, 1)
    @test ==((1, 1)...)
    @test 1 ≈ 2 atol = 1
    @test strip("\t  hi   \n") == "hi"
    @test strip("\t  this should fail   \n") != "hi"
    @test isequal(1, 1)
    @test isapprox(1, 1, atol=0.1)
    @test isapprox(1, 1; atol=0.1)
    @test isapprox(1, 1; [(:atol, 0)]...)
end
@timedtestset "@test keyword precedence" begin
    # post-semicolon keyword, suffix keyword, pre-semicolon keyword
    @test isapprox(1, 2, atol=0) atol = 1
    @test isapprox(1, 3, atol=0; atol=2) atol = 1
end
@timedtestset "@test should only evaluate the arguments once" begin
    g = Int[]
    f = (x) -> (push!(g, x); x)
    @test f(1) == 1
    @test g == [1]

    empty!(g)
    @test isequal(f(2), 2)
    @test g == [2]
end

@timedtestset "@test_broken with fail" begin
    @test_broken false
    @test_broken 1 == 2
    @test_broken 1 != 1
    @test_broken strip("\t  hi   \n") != "hi"
    @test_broken strip("\t  this should fail   \n") == "hi"
end
@timedtestset "@test_broken with errors" begin
    @test_broken error()
    @test_broken absolute_nonsense
end
@timedtestset "@test_skip" begin
    @test_skip error()
    @test_skip true
    @test_skip false
    @test_skip gobbeldygook
end
@timedtestset "@test_warn" begin
    @test 1234 === @test_nowarn(1234)
    @test 5678 === @test_warn("WARNING: foo", begin
                                  println(stderr, "WARNING: foo")
                                  5678
                              end)
    let a
        @test_throws UndefVarError(:a) a
        @test_nowarn a = 1
        @test a === 1
    end
end
