-- ╔══════════════════════════════════════════════════════════╗
-- ║  ChatCopyText.lua                                        ║
-- ║  Purpose: Byte rules that keep one chat line safe for    ║
-- ║           the Chat Copy edit box.                        ║
-- ╚══════════════════════════════════════════════════════════╝

local KE = select(2, ...)

local strbyte = string.byte
local strfind = string.find
local strsub = string.sub
local tconcat = table.concat

-- Kept apart from ChatCopy.lua so a spec can load the rules without the chat
-- skin. One control byte or invalid UTF-8 byte makes the edit box drop its
-- whole text. The pipe byte is printable and passes, so colour codes and
-- escapes survive.

-- Reused across calls; the join reads only the first `count` entries.
local parts = {}

-- Length of the valid UTF-8 sequence led by byte b at i, or nil. Called only
-- for leads C2-F4; ranges per RFC 3629.
local function sequenceLength(text, i, b)
    local b2 = strbyte(text, i + 1)
    if not b2 then return nil end
    if b <= 0xDF then
        if b2 >= 0x80 and b2 <= 0xBF then return 2 end
        return nil
    end
    local lo, hi = 0x80, 0xBF
    if b == 0xE0 then
        lo = 0xA0
    elseif b == 0xED then
        hi = 0x9F
    elseif b == 0xF0 then
        lo = 0x90
    elseif b == 0xF4 then
        hi = 0x8F
    end
    if b2 < lo or b2 > hi then return nil end
    local b3 = strbyte(text, i + 2)
    if not b3 or b3 < 0x80 or b3 > 0xBF then return nil end
    if b <= 0xEF then return 3 end
    local b4 = strbyte(text, i + 3)
    if not b4 or b4 < 0x80 or b4 > 0xBF then return nil end
    return 4
end

-- Drops control bytes except LF, keeps valid UTF-8 whole, and writes one ?
-- for every byte that starts no valid sequence.
function KE.SanitizeCopyLine(text)
    if not strfind(text, "[%z\1-\9\11-\31\127-\255]") then return text end

    local count, runStart, i, len = 0, 1, 1, #text
    while i <= len do
        local b = strbyte(text, i)
        local width
        if b == 10 or (b >= 32 and b <= 126) then
            width = 1
        elseif b >= 0xC2 and b <= 0xF4 then
            width = sequenceLength(text, i, b)
        end
        if width then
            i = i + width
        else
            if i > runStart then
                count = count + 1
                parts[count] = strsub(text, runStart, i - 1)
            end
            if b >= 0x80 then
                count = count + 1
                parts[count] = "?"
            end
            i = i + 1
            runStart = i
        end
    end
    if runStart <= len then
        count = count + 1
        parts[count] = strsub(text, runStart, len)
    end
    return tconcat(parts, "", 1, count)
end
