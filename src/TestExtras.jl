module TestExtras

export @constinferred
export @timedtestset
export ConstInferred

include("constinferred.jl")
include("timedtest.jl")

using .ConstInferred: @constinferred
using .TimedTests: @timedtestset

end
