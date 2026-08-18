-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Sound.lua                     ║
-- ║  Purpose: the aura-sound registry as a desired-state      ║
-- ║  condition rather than a procedure.                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

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

    -- NOTHING TO DO. Every settings change routes through here — icon size,
    -- fonts, growth direction — and almost none of them touch the sound. An
    -- unconditional retire-and-rebuild would tear down a valid registration on
    -- every one of those, and inside a keystone the rebuild half is not
    -- allowed: the user would lose their sound for the rest of the key by
    -- nudging a font slider. Registrations exist whenever the four inputs
    -- hold, and only registrations which no longer MATCH are retired.
    if path and path == self.currentPath and not self.pending and #self.ids > 0 then
        return
    end

    -- Past this point the desired state genuinely differs. Retire first:
    -- removal is never restricted, and a stale sound is worse than silence.
    self:RetireAll()
    self.currentPath = nil

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
    for i = 1, #declaration.spellIDs do
        local id = self.api.Add(Enum.UnitAuraSoundTrigger.Added, {
            unitToken     = declaration.unit,
            spellID       = declaration.spellIDs[i],
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
    self.pending     = false
end
