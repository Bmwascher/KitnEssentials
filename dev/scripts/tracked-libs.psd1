# Libraries shipped from their tracked copy under Libs/ instead of a .pkgmeta
# external, because the copy carries a local fix. check-lib-updates.ps1 reads
# this file: it reports when upstream HEAD moves past Base, fails when File
# no longer holds the Fix line, and refuses -Update for these names.
@{
    'LibRangeCheck-3.0' = @{
        Path   = 'Libs/LibRangeCheck-3.0'
        Url    = 'https://github.com/WeakAuras/LibRangeCheck-3.0.git/LibRangeCheck-3.0'
        Base   = '95a6313a44f615738d216bd79cf132dc6f243284'
        File   = 'LibRangeCheck-3.0.lua'
        Fix    = 'local cacheKey = (issecretvalue and issecretvalue(guid) and unit or guid) .. (noItems and "-1" or "-0")'
        Update = 'Copy the file at the new upstream commit over the tracked one and re-apply Fix in getCachedRange; when the upstream test is already client-neutral, drop the fix, restore the .pkgmeta external and remove this entry. Set Base to the new commit, then /reload and check Range Display.'
    }
}
