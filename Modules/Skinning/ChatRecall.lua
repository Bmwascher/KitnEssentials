local KE = select(2, ...)

-- Rules for the Up/Down typing-history recall, kept apart from Chat.lua so a
-- spec can load them without the chat skin. Recall plants the line with
-- SetText, and addon-planted edit-box text makes the send a tainted caller.

-- Secure slash commands (/ping, /cast, ...) never enter the history: their
-- re-send is a protected call and a planted line cannot make it.
function KE.ChatRecallStores(text)
    if type(text) ~= "string" or text == "" then return false end
    local cmd = text:match("^%s*(/%S+)")
    if cmd and IsSecureCmd and IsSecureCmd(cmd) then return false end
    return true
end

-- A hyperlink is protected content while chat is restricted, so a planted
-- line carrying one is refused there. Plain lines still recall; Alt+Up is the
-- engine's own recall and is never affected.
function KE.ChatRecallRefused(text, restricted)
    if not restricted then return false end
    return type(text) == "string" and text:find("|H", 1, true) ~= nil
end
