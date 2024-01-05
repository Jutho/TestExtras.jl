module TimedTests
export @timedtestset, TimedTestSet

using Test

const var"@timedtestset" = Test.var"@testset"
const TimedTestSet = Test.DefaultTestSet

end
