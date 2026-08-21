-- Not a spec. Run it by hand:
--   busted dev/spec/chat_history_bench.lua
-- It reports microseconds per SaveChatHistory call at two caps, which is what
-- settles whether the trim needs a ring buffer.
local L = require("dev.spec._ke_loader")

local ITERATIONS = 20000
-- EVEN, so the counterbalance below actually balances. With an odd count one
-- cap runs first more often than the other, which is the bias the alternation
-- exists to cancel.
--
-- THIRTY-TWO because the acceptance has to be able to ANSWER. The measured
-- ratio sits only a few percent under the threshold, and at eight pairs the
-- band below is wider than that gap, so the run voids however clean the machine
-- is -- a rule that can only ever say "retake" is not an acceptance. The band
-- narrows with the square root of the count; thirty-two brings it inside the
-- gap, and the whole script still runs in about seven seconds.
local RUNS = 32

-- The two caps compared: the shipped default and the slider's maximum.
local CAP_DEFAULT = 100
local CAP_MAX = 500

-- The line at which the trim stops being merely cap-proportional and becomes
-- the DOMINANT cost -- the ratio at which the trim is exactly half the call at
-- the maximum cap. Derived rather than chosen, and written as the formula so it
-- recomputes if the slider range ever changes.
--
-- 2.0 is NOT the half-way point, though it reads like one: at a ratio of 2.0
-- the trim is already about 62% of the call.
--
-- The margin is THIN and is recorded as thin rather than rounded away: measured
-- ratios run 1.54 to 1.62, which is three to eight percent under this line
-- rather than comfortably clear of it, and the closest single run cleared it by
-- 0.002. A change to the store's hot path can cross it. Trust the band this
-- script prints over this range, which is a record of past runs and will age.
local THRESHOLD = 2 * CAP_MAX / (CAP_MAX + CAP_DEFAULT)

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
local results = { [CAP_DEFAULT] = {}, [CAP_MAX] = {} }
for run = 1, RUNS do
    local order = (run % 2 == 1) and { CAP_DEFAULT, CAP_MAX } or { CAP_MAX, CAP_DEFAULT }
    for _, cap in ipairs(order) do
        results[cap][#results[cap] + 1] = once(cap)
    end
end

for _, cap in ipairs({ CAP_DEFAULT, CAP_MAX }) do
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
    ratios[i] = results[CAP_MAX][i] / results[CAP_DEFAULT][i]
    logsum = logsum + math.log(ratios[i])
end
local geo = math.exp(logsum / RUNS)

local lo, hi = ratios[1], ratios[1]
for i = 2, RUNS do
    if ratios[i] < lo then lo = ratios[i] end
    if ratios[i] > hi then hi = ratios[i] end
end
-- The decision rests on the geometric MEAN, so the retake rule has to be about
-- that mean's own uncertainty -- not about how far apart two individual pairs
-- landed. A rule that voids whenever any single pair falls on the far side of
-- the threshold voids nearly every run, because ordinary pair-level noise
-- reaches that far while the mean stays well clear of the line. The spread of
-- single samples is not the error bar of their average, and treating it as one
-- makes the acceptance unsatisfiable rather than strict.
--
-- The samples are ratios, so the arithmetic stays in log space for the same
-- reason the mean is geometric. Inside the bar below, this run genuinely cannot
-- say which side of the threshold the mean falls on, which is the one thing the
-- rule it replaced was right about.
--
-- Student's t at RUNS-1 degrees of freedom, NOT the normal multiplier of 2: a
-- bar of 2 falls short of 95% at these counts and so errs toward calling a run
-- decisive, which is the wrong way to err when the measured ratio sits only a
-- few percent from the threshold. The value below is t for RUNS = 32. Change
-- the two together or the bar quietly stops meaning what it says.
local logmean = logsum / RUNS
local sumsq = 0
for i = 1, RUNS do
    local d = math.log(ratios[i]) - logmean
    sumsq = sumsq + d * d
end
-- Sample standard deviation (RUNS - 1), then the standard error of the mean.
local stderr = math.sqrt(sumsq / (RUNS - 1)) / math.sqrt(RUNS)
local T_95 = 2.040
local indecisive = math.abs(logmean - math.log(THRESHOLD)) < T_95 * stderr

print(string.format("paired %d/%d ratio: %.3f (geometric mean of %d pairs), threshold %.3f%s",
    CAP_MAX, CAP_DEFAULT, geo, RUNS, THRESHOLD,
    indecisive and "  ** THE 95% BAND COVERS THE THRESHOLD -- run is VOID, retake **"
        or (geo > THRESHOLD and "  ** OVER THRESHOLD -- the trim is dominant **" or "")))
-- Spread is REPORTED, never a verdict. A fixed hi/lo limit is the same crude
-- proxy for noise as the boundary rule it used to sit beside, and it rejected
-- runs the standard error had already found decisive. A noisy machine widens
-- the error bar, which voids the run on its own; a second rule reading the same
-- noise a cruder way only throws away answers.
--
-- The one acceptance condition left is printed with the verdict above, and the
-- band is printed here beside the spread it is easy to confuse with, so the
-- difference between the two is visible rather than asserted.
print(string.format("pair spread: %.3f to %.3f (hi/lo %.3f); mean 95%% band = %.3f to %.3f",
    lo, hi, hi / lo, geo * math.exp(-T_95 * stderr), geo * math.exp(T_95 * stderr)))
