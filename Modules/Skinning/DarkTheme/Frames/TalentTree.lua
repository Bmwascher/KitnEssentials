local KE = select(2, ...)
local S = KE.Skins

-- Same grouping as the client's state-border rule, which draws every
-- non-disabled state other than maxed with the spendable art.
function S._TalentStateColorKey(visualState, states)
    if visualState == nil or not states then return nil end
    if visualState == states.RefundInvalid or visualState == states.DisplayError then
        return "red"
    elseif visualState == states.Maxed then
        return "gold"
    elseif visualState == states.Gated or visualState == states.Disabled
        or visualState == states.Locked then
        return "gray"
    elseif visualState == states.Normal or visualState == states.Selectable
        or visualState == states.Invisible then
        return "green"
    end
    return nil
end
