-- _forever_kicks_rules.lua — the rules of derive-forever-kicks.lua that choose
-- or refuse, kept apart so a spec can load them with dofile. Pure: no file
-- reads, no exits; the script fails on their answers.

local R = {}

-- Rule 9: the index in families (row order) of the row's tracked kick, or nil
-- when no `tracked` line prints. The first trained or talent kick prints when
-- it is not the first kick or the first has ranks; with none, rule 6: the
-- first kick, when it has ranks.
function R.TrackedIndex(families)
    local at = 1
    for i, family in ipairs(families) do
        if family.trained or family.talent then
            at = i
            break
        end
    end
    if at > 1 or #families[1].ranks > 1 then return at end
    return nil
end

-- Rule 10: the first of a kick's forms that given (the forms its class's
-- spells give) lacks, or nil.
function R.MissingForm(forms, given)
    if not forms then return nil end
    for _, form in ipairs(forms) do
        if not (given and given[form]) then return form end
    end
    return nil
end

-- Rule 10: FOREVER_FORMS rows by spell id, each { id, form, fixed }; or nil
-- and the first spell, by id, whose form has no SpellShapeshiftForm row.
function R.FormRows(formSpells, formKnown, formFixed)
    local ids = {}
    for id in pairs(formSpells) do ids[#ids + 1] = id end
    table.sort(ids)
    local rows = {}
    for _, id in ipairs(ids) do
        local form = formSpells[id]
        if not formKnown[form] then return nil, id end
        rows[#rows + 1] = { id = id, form = form, fixed = formFixed[form] == true }
    end
    return rows
end

return R
