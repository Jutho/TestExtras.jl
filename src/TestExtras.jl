module TestExtras

export @constinferred, @constinferred_broken
export @timedtestset
export ConstInferred

include("constinferred.jl")
include("timedtest.jl")

using .ConstInferred: @constinferred, @constinferred_broken
using .TimedTests: @timedtestset

end
