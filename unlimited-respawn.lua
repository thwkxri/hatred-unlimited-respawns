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
local useLastLocation = native(gameClass, "EnforceOldCrapRespawnLogicWhichMeansUseLastRespawnPoint")
local playerPawn = native(gameStatics, "GetPlayerPawn")
local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
local worldAddress, anchor, respawning

local function usablePoint(transform)
    local p = transform.Translation
    if p.X == 0 and p.Y == 0 and p.Z == 0 then return nil end
    return {X = p.X, Y = p.Y, Z = p.Z}
end

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
    local address = gi:GetWorld():GetAddress()
    if address ~= worldAddress then
        worldAddress, anchor = address, nil
    end

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
    if not anchor and not respawning then
        anchor = usablePoint(gi.PlayerTransformAtLastFinishedSideQuest)
    end

    if gi.CampaignRespawnBalance ~= 1 then
        gi.CampaignRespawnBalance = 1
    end
    return true
end

local lastError
local function refresh(gi)
    if not gi or not gi:IsValid() then return end
    local ok, problem = pcall(keepOne, gi)
    if not ok and problem ~= lastError then
        lastError = problem
        print("[Campaign respawn] " .. tostring(problem) .. "\n")
    end
    return ok and problem
end

local function fromHook(context)
    refresh(context:get())
end

RegisterHook(gameClass .. ":ShowPauseMenu", fromHook)
local previousLocationPolicy
RegisterHook(gameClass .. ":RespawnPlayer", function(context)
    local gi = context:get()
    if refresh(gi) then
        respawning = true
        previousLocationPolicy = gi.bEnforceLastRespawnPoint
        useLastLocation(gi, true)
    end
end, function(context)
    local gi = context:get()
    if previousLocationPolicy ~= nil then
        useLastLocation(gi, previousLocationPolicy)
        previousLocationPolicy = nil
    end
    if respawning and anchor and gi:GetWorld():GetAddress() == worldAddress then
        -- RestartPlayer can replace the native location array while it creates
        -- the new pawn. Keep the last earned checkpoint if it is still clear.
        local pawn = playerPawn(statics, gi, 0)
        if pawn and pawn:IsValid() and pawn:IsA("/Script/Hatred.HeroCharacterController") and pawn.Health > 0 then
            pawn:K2_TeleportTo(anchor, pawn:K2_GetActorRotation())
            -- Keep the engine's adjusted position, or its native spawn if the
            -- old point is now blocked.
            local p = pawn:K2_GetActorLocation()
            anchor = {X = p.X, Y = p.Y, Z = p.Z}
        end
    end
    respawning = false
    refresh(gi)
end)

local function trackReward(name, explicit)
    local count
    RegisterHook(gameClass .. ":" .. name, function(context)
        count = context:get().CampaignRespawnLocations
    end, function(context, _, transform)
        local gi = context:get()
        local added = count and gi.CampaignRespawnLocations > count
        count = nil
        if refresh(gi) and added and not respawning then
            local saved = explicit and transform:get() or gi.PlayerTransformAtLastFinishedSideQuest
            anchor = usablePoint(saved) or anchor
        end
    end)
end

trackReward("AddRespawn", false)
trackReward("AddRespawnWithTransform", true)
LoopInGameThreadWithDelay(250, function() refresh(game()) end)

print("[Campaign respawn] Ready\n")
