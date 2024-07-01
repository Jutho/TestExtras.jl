module TestExtras

export @constinferred, @constinferred_broken
export @timedtestset
export @include
export ConstInferred

include("constinferred.jl")
include("includemacro.jl")

if VERSION >= v"1.8"
    include("timedtest_new.jl")
else
    include("timedtest.jl")
end

using .ConstInferred: @constinferred, @constinferred_broken
using .TimedTests: @timedtestset

end
