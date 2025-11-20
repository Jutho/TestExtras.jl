module TestExtras

export @testinferred, @testinferred_broken
export @constinferred, @constinferred_broken
export @timedtestset
export @include
export ConstInferred

include("testinferred.jl")
include("includemacro.jl")

if VERSION >= v"1.8"
    include("timedtest_new.jl")
else
    include("timedtest.jl")
end

using .TestInferred: @constinferred, @constinferred_broken, @testinferred, @testinferred_broken
using .TimedTests: @timedtestset

end
