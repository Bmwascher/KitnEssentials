-- Not a spec. Run it by hand:
--   busted dev/spec/chat_history_bench.lua
-- It reports microseconds per SaveChatHistory call at two caps, which is what
-- settles whether the trim needs a ring buffer.
local L = require("dev.spec._ke_loader")

local ITERATIONS = 20000
-- EVEN, so the counterbalance below actually balances. With an odd count one
-- cap runs first more often than the other, which is the bias the alternation
-- exists to cancel. Eight rather than four because the dispersion rule at the
-- bottom needs enough pairs to tell a noisy machine from a real difference.
local RUNS = 8

-- A realistic payload: seventeen positional arguments, as the covered events
-- actually deliver, with a body of roughly typical chat length.
local ARGS = { "a message of about forty characters in length", "Sender",
    "Common", "", "Sender", "", 0, 0, "General", "", 12345, "guid", 0,
    false, false, false, false }

local function once(cap)
    local CH, KE = L.loadChatHistory()
    KE.db.profile.Skinning.ChatHistory.Size = cap
    -- Garbage-collector state is a benchmark INPUT, not background noise: a
    -- measured loop that inherits the previous loop's garbage pays for
    -- collecting it. Blizzard's own benchmark utility collects and stops the
    -- collector before each measured iteration for the same reason. Collect
    -- first so both caps start clean, stop so no collection lands inside the
    -- timed window, restart afterwards so the next load is not measuring a
    -- heap this one abandoned.
    collectgarbage("collect")
    collectgarbage("stop")
    -- os.clock is CPU time for this process, which is what a per-call cost
    -- means here; wall time would include whatever else the machine is doing.
    local start = os.clock()
    for _ = 1, ITERATIONS do
        CH:SaveChatHistory("CHAT_MSG_SAY", unpack(ARGS))
    end
    local elapsed = os.clock() - start
    collectgarbage("restart")
    return elapsed / ITERATIONS * 1e6
end

-- Sorts a COPY: the run order in `results` is what the paired ratios below
-- depend on, and table.sort would destroy it.
--
-- For an even count this averages the two middle samples rather than taking the
-- lower-middle one. That is not tidiness. The two caps sit at different
-- positions in the schedule -- over the first four runs cap 100 lands at
-- 1,4,5,8 and cap 500 at 2,3,6,7, and the pattern repeats -- so
-- on a machine whose runtime drifts upward, picking the lower-middle sample
-- reports position 4 for one cap and position 3 for the other, and two
-- IDENTICAL implementations come out looking different.
local function median(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    local n = #c
    if n % 2 == 1 then return c[(n + 1) / 2] end
    return (c[n / 2] + c[n / 2 + 1]) / 2
end

-- COUNTERBALANCED, not merely interleaved: always running 100 before 500 pairs
-- every 500 with a machine that has been busy slightly longer, which is a
-- systematic bias, not noise. Alternating the order cancels it, but only over
-- an EVEN number of runs -- see RUNS above.
local results = { [100] = {}, [500] = {} }
for run = 1, RUNS do
    local order = (run % 2 == 1) and { 100, 500 } or { 500, 100 }
    for _, cap in ipairs(order) do
        results[cap][#results[cap] + 1] = once(cap)
    end
end

for _, cap in ipairs({ 100, 500 }) do
    print(string.format("cap %d: %.3f us/call (median of %d)", cap,
        median(results[cap]), RUNS))
end

-- The ACCEPTANCE ratio is taken pairwise, not from the two medians. Each run
-- produces one cap-100 sample and one cap-500 sample seconds apart, so drift
-- over the session cancels inside the pair. A ratio of two medians drawn from
-- different positions in the schedule does not have that property, whatever the
-- median function does.
--
-- GEOMETRIC mean, not arithmetic, and the difference is not cosmetic. The
-- order alternates, so if the second measurement of a pair runs a factor d
-- slower, the pairs come out as R*d and R/d around the true ratio R. Their
-- ARITHMETIC mean is R*(d + 1/d)/2, which is greater than R for every d other
-- than 1 -- the statistic inflates the very number the ring-buffer decision
-- turns on. The geometric mean of R*d and R/d is exactly R: the reciprocal
-- pair cancels, which is the whole point of alternating the order.
local ratios = {}
local logsum = 0
for i = 1, RUNS do
    ratios[i] = results[500][i] / results[100][i]
    logsum = logsum + math.log(ratios[i])
end
local geo = math.exp(logsum / RUNS)

local lo, hi = ratios[1], ratios[1]
for i = 2, RUNS do
    if ratios[i] < lo then lo = ratios[i] end
    if ratios[i] > hi then hi = ratios[i] end
end
local straddles = (lo < 1.5) and (hi > 1.5)

print(string.format("paired 500/100 ratio: %.3f (geometric mean of %d pairs)",
    geo, RUNS))
print(string.format("pair spread: %.3f to %.3f (hi/lo %.3f)%s", lo, hi, hi / lo,
    straddles and "  ** STRADDLES 1.5 -- run is VOID, retake **" or ""))
