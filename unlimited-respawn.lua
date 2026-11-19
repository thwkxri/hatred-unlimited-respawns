-- Campaign-only respawns for the Windows Hatred build 1232203 and Hatred 1.333.
local gameClass = "/Script/Hatred.HatredGameInstance"
local modeName = "BP_HatredGameInstance_C"
local gameStatics = "/Script/Engine.GameplayStatics"

local function native(class, name)
    local func = StaticFindObject(class .. ":" .. name)
    assert(func:IsValid(), "Missing " .. class .. ":" .. name)
    return func
end

local function field(name, offset, type)
    RegisterCustomProperty({
        Name = name,
        Type = type,
        BelongsToClass = gameClass,
        OffsetInternal = offset,
    })
end

local instance
local function game()
    if not instance or not instance:IsValid() then
        instance = FindFirstOf(modeName)
    end
    return instance and instance:IsValid() and instance or nil
end

field("CampaignRespawnBalance", 0x134, PropertyTypes.IntProperty)
field("CampaignRespawnLocations", 0x360, PropertyTypes.IntProperty)
field("CampaignDifficultyRaw", 0x170, PropertyTypes.IntProperty)

local currentMap = native(gameClass, "GetCurrentMapName")
local changeLocation = native(gameClass, "SilentChangeRespawnLocation")
local playerPawn = native(gameStatics, "GetPlayerPawn")
local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")

local function keepOne(gi)
    local map = currentMap(gi):ToString():lower()
    if not map:match("^lvl_0[1-7]_.+_p$") then return end
    local difficulty = gi.CampaignDifficultyRaw & 0xff
    if difficulty == 4 then
        -- Native Hatred never awards a point at this difficulty. Drop any
        -- point carried over if a different difficulty was just played.
        if gi.CampaignRespawnBalance ~= 0 then gi.CampaignRespawnBalance = 0 end
        return
    end
    if difficulty > 3 then return end

    if gi.CampaignRespawnLocations == 0 then
        local pawn = playerPawn(statics, gi, 0)
        if not pawn or not pawn:IsValid() then return end
        local pawnClass = pawn:GetClass():GetFullName()
        if not (pawnClass:match("%.MyCharacter_C$") or pawnClass:match("%.MyCharacterTps_C$") or
                pawn:IsA("/Script/Hatred.HatredBaseVehicle")) then return end

        -- Until a side objective provides a point, use the first player spawn.
        changeLocation(gi, false)
        if gi.CampaignRespawnLocations == 0 then return end
    end

    if gi.CampaignRespawnBalance ~= 1 then
        gi.CampaignRespawnBalance = 1
    end
end

local lastError
local function refresh(gi)
    if not gi or not gi:IsValid() then return end
    local ok, problem = pcall(keepOne, gi)
    if not ok and problem ~= lastError then
        lastError = problem
        print("[Campaign respawn] " .. tostring(problem) .. "\n")
    end
end

local function fromHook(context)
    refresh(context:get())
end

RegisterHook(gameClass .. ":ShowPauseMenu", fromHook)
RegisterHook(gameClass .. ":RespawnPlayer", fromHook, fromHook)
RegisterHook(gameClass .. ":AddRespawn", function() end, fromHook)
RegisterHook(gameClass .. ":AddRespawnWithTransform", function() end, fromHook)
LoopInGameThreadWithDelay(250, function() refresh(game()) end)

print("[Campaign respawn] Ready\n")
