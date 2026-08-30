-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Sound.lua                     ║
-- ║  Purpose: the aura-sound registry as a desired-state      ║
-- ║  condition rather than a procedure.                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local table_concat = table.concat

local Sound = {}
KE.AuraSound = Sound

local Registry = {}
Registry.__index = Registry

function Sound.New(opts)
    opts = opts or {}
    return setmetatable({
        api          = opts.api,
        resolveMedia = opts.resolveMedia,
        isHidden     = opts.isHidden or function() return false end,
        onDiagnostic = opts.onDiagnostic,
        ids          = {},
        currentPath  = nil,
        currentIDs   = nil,
        pending      = false,
    }, Registry)
end

function Registry:Count()
    return #self.ids
end

function Registry:IsPending()
    return self.pending == true
end

-- Removal is the unrestricted half, so it always works and always runs first.
-- A stale sound is worse than silence.
function Registry:RetireAll()
    for i = 1, #self.ids do
        self.api.Remove(self.ids[i])
    end
    self.ids    = {}
    self.pending = false
end

-- The desired registry: every spell registered when ALL of the module's
-- Enabled setting, SoundEnabled, a real SoundName, and a resolvable media
-- path hold. Vehicle suspension is deliberately NOT one of the inputs — the
-- sound announces an external landing on you and is worth hearing while the
-- icons are off screen.
-- A declaration either names a fixed list or builds one from the settings.
-- The built form is what lets the sound follow a user-editable allowlist
-- instead of a list frozen at file scope.
local function desiredSpellIDs(declaration, settings)
    if not declaration then return {} end
    if declaration.buildSpellIDs then
        return declaration.buildSpellIDs(settings) or {}
    end
    return declaration.spellIDs or {}
end

local function desiredPath(declaration, settings, moduleEnabled, resolveMedia)
    if not declaration then return nil end
    if not moduleEnabled then return nil end

    local keys = declaration.settingKeys or {}
    if not settings[keys.enabled] then return nil end

    local name = settings[keys.name]
    if not name or name == "None" then return nil end

    return resolveMedia(name)
end

function Registry:Sync(declaration, settings, moduleEnabled)
    settings = settings or {}

    local path = desiredPath(declaration, settings, moduleEnabled, self.resolveMedia)
    local spellIDs = desiredSpellIDs(declaration, settings)

    -- The SET of ids is half the desired state, not just the sound file. A
    -- user switching an allowlist row on changes nothing about the path, so
    -- comparing the path alone would leave the old registrations standing and
    -- the new row silent.
    local idKey = table_concat(spellIDs, ",")

    -- NOTHING TO DO. Every settings change routes through here — icon size,
    -- fonts, growth direction — and almost none of them touch the sound. An
    -- unconditional retire-and-rebuild would tear down a valid registration on
    -- every one of those, and inside a keystone the rebuild half is not
    -- allowed: the user would lose their sound for the rest of the key by
    -- nudging a font slider. Registrations exist whenever the four inputs
    -- hold, and only registrations which no longer MATCH are retired.
    if path and path == self.currentPath and idKey == self.currentIDs
        and not self.pending and #self.ids > 0 then
        return
    end

    -- Past this point the desired state genuinely differs.
    self:RetireAll()
    self.currentPath = nil
    self.currentIDs  = nil

    if not path then
        -- The desired state IS silence, so it is already reached. Nothing to
        -- wait for and nothing to pend.
        return
    end

    if self.isHidden() then
        -- Cannot add while restricted. Leave the registry empty rather than
        -- partial, and rebuild from the LATEST settings on release.
        self.pending = true
        return
    end

    local created = {}
    for i = 1, #spellIDs do
        local id = self.api.Add(Enum.UnitAuraSoundTrigger.Added, {
            unitToken     = declaration.unit,
            spellID       = spellIDs[i],
            soundFileName = path,
            outputChannel = "Master",
        })

        if id == nil then
            -- Undocumented and possibly unreachable, but nilable. Roll back to
            -- empty and CLEAR pending: there is no restriction release coming
            -- to retry on. The next ordinary sync retries.
            for j = 1, #created do
                self.api.Remove(created[j])
            end
            self.ids     = {}
            self.pending = false
            if self.onDiagnostic then
                self.onDiagnostic("aura sound registration returned no id; registry left empty")
            end
            return
        end

        created[#created + 1] = id
    end

    self.ids         = created
    self.currentPath = path
    self.currentIDs  = idKey
    self.pending     = false
end
