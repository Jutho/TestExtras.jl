module TestExtras

export @constinferred, @constinferred_broken
export @timedtestset
export @include
export @testinferred
export ConstInferred

include("utilities.jl")
include("constinferred.jl")
include("testinferred.jl")
include("includemacro.jl")

if VERSION >= v"1.8"
    include("timedtest_new.jl")
else
    include("timedtest.jl")
end

using .ConstInferred: @constinferred, @constinferred_broken
using .TestInferred: @testinferred
using .TimedTests: @timedtestset

end
