module TestExtras

export @constinferred
export TimedTestSet
export ConstInferred

include("constinferred.jl")
include("timedtest.jl")

using .ConstInferred: @constinferred
using .TimedTests: TimedTestSet

end
