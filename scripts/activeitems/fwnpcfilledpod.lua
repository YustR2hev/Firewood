function init()
  self.cooldown = 0
  self.lastFireMode = nil
  self.params = getParams()
end

function update(dt, fireMode, shiftHeld)
  self.cooldown = math.max(0, self.cooldown - dt)
  activeItem.setHoldingItem(true)

  local params = self.params or getParams()

  if fireMode ~= "primary" and params.suppressPrimary then
    setInstanceParam("suppressPrimary", false)
  end

  local primaryPressed = fireMode == "primary" and self.lastFireMode ~= "primary" and not params.suppressPrimary

  if primaryPressed and self.cooldown == 0 then
    self.cooldown = 0.5
    setInstanceParam("suppressPrimary", true)
    usePod()
  end

  self.lastFireMode = fireMode
end

function usePod()
  local params = self.params or getParams()

  if params.released then
    recallLinkedNpc(params)
  else
    releaseLinkedNpc(params)
  end
end

function releaseLinkedNpc(params)
  local data = params.npcData or params.originalNpcData
  if not data then return end

  if not hasValidNpcSnapshot(data) then
    sb.logWarn("[FW NPC Pods] Refusing release: pod has incomplete NPC data, so appearance would be random: %s", sb.printJson(data, 1))
    setInstanceParam("description", "This pod has incomplete NPC data and cannot safely release the original NPC.")
    setReleasedState(false, "")
    return
  end

  if not params.originalNpcData then
    setInstanceParam("originalNpcData", copyTable(data))
  end

  local linkId = params.linkId
  if not linkId or linkId == "" then
    linkId = "fwnpc_" .. sb.makeUuid()
    setInstanceParam("linkId", linkId)
  end

  local existingNpc = findLinkedNpc(linkId)
  if existingNpc then
    setReleasedState(true, linkId)
    setInstanceParam("releasedEntityId", existingNpc)
    return
  end

  local aim = activeItem.ownerAimPosition()
  local spawnPos = { aim[1], aim[2] + 1 }
  local spawnParams = buildSpawnParams(data, linkId)

  sb.logInfo("[FW NPC Pods] Releasing NPC data: %s", sb.printJson(data, 1))
  sb.logInfo("[FW NPC Pods] Spawn params: %s", sb.printJson(spawnParams, 1))

  local npcId = world.spawnNpc(
    spawnPos,
    data.species,
    data.npcType,
    data.level or world.threatLevel() or 1,
    data.seed,
    spawnParams
  )

  if npcId then
    world.sendEntityMessage(npcId, "fwnpcpods_setUniqueId", linkId)
    world.sendEntityMessage(npcId, "fwnpcpods_restoreSnapshot", data, linkId)

    setReleasedRecord(linkId, npcId)
    setReleasedState(true, linkId)
    setInstanceParam("releasedEntityId", npcId)
    setInstanceParam("npcData", data)
    setInstanceParam("shortdescription", "Released NPC Pod: " .. (data.name or "Unknown"))
    setInstanceParam("description", "Linked to " .. (data.name or "an NPC") .. ". Click again to recall.")
  else
    clearReleasedRecord(linkId)
    setReleasedState(false, "")
    setInstanceParam("description", "Failed to release NPC.")
  end
end

function recallLinkedNpc(params)
  local linkId = params.releasedUniqueId or params.linkId
  if not linkId or linkId == "" then
    setReleasedState(false, "")
    return
  end

  local npcId = nil
  if params.releasedEntityId and world.entityExists(params.releasedEntityId) then
    npcId = params.releasedEntityId
  else
    npcId = findLinkedNpc(linkId)
  end

  if not npcId then
    return
  end

  local data = params.npcData or params.originalNpcData
  if not hasValidNpcSnapshot(data) then
    sb.logWarn("[FW NPC Pods] Refusing recall: stored NPC data is invalid: %s", sb.printJson(data, 1))
    return
  end

  removeOriginalNpc(npcId)

  clearReleasedRecord(linkId)
  setInstanceParam("npcData", data)
  setInstanceParam("originalNpcData", params.originalNpcData or copyTable(data))
  setReleasedState(false, "")
  setInstanceParam("releasedEntityId", false)
  setInstanceParam("shortdescription", "Filled NPC Pod: " .. (data.name or "Unknown"))
  setInstanceParam("description", "Contains " .. (data.name or "an NPC") .. ".")
end

function findLinkedNpc(linkId)
  -- First try the unique entity lookup.
  local loadedId = nil
  local ok, result = pcall(world.loadUniqueEntity, linkId)

  if ok and result and result ~= 0 and world.entityExists(result) then
    return result
  end

  -- Fallback: search near cursor.
  local aim = activeItem.ownerAimPosition()
  local nearCursor = world.npcQuery(aim, 6, {
    order = "nearest"
  })

  for _, npcId in ipairs(nearCursor) do
    if world.entityUniqueId(npcId) == linkId then
      return npcId
    end
  end

  -- Fallback: search near player.
  local owner = activeItem.ownerEntityId()
  local ownerPos = world.entityPosition(owner)

  if ownerPos then
    local nearPlayer = world.npcQuery(ownerPos, 12, {
      order = "nearest"
    })

    for _, npcId in ipairs(nearPlayer) do
      if world.entityUniqueId(npcId) == linkId then
        return npcId
      end
    end
  end

  return nil
end

function setLinkedUniqueId(npcId, linkId)
  safeCall(npcId, "fwnpcpods_setUniqueId", linkId)

  safeCall(npcId, "npc.setPersistent", true)
end

function buildNpcData(npcId)
  if not safeCall(npcId, "fwnpcpods_helperLoaded") then
    sb.logWarn("[FW NPC Pods] Released NPC %s has no helper; refusing recall because identity would be lost", npcId)
    return nil
  end

  local data = safeCall(npcId, "fwnpcpods_captureData")
  if not hasValidNpcSnapshot(data) then
    sb.logWarn("[FW NPC Pods] Released NPC %s returned incomplete data; refusing recall: %s", npcId, sb.printJson(data, 1))
    return nil
  end

  return data
end

function hasValidNpcSnapshot(data)
  return type(data) == "table"
    and type(data.species) == "string"
    and type(data.npcType) == "string"
    and data.seed ~= nil
    and type(data.identity) == "table"
end

function mergeStoredNpcData(storedData, liveData)
  if not storedData then
    return liveData
  end

  return {
    name = storedData.name,
    species = storedData.species,
    gender = storedData.gender,
    npcType = storedData.npcType,
    level = liveData.level or storedData.level,
    seed = storedData.seed,
    identity = storedData.identity,
    personality = storedData.personality,
    storage = liveData.storage or storedData.storage,
    equipment = liveData.equipment or storedData.equipment,
    health = liveData.health or storedData.health,
    maxHealth = liveData.maxHealth or storedData.maxHealth,
    parameters = mergeSpawnParameters(storedData.parameters, liveData)
  }
end

function buildSpawnParams(data, linkId)
  local spawnParams = copyTable(data.parameters or {})

  spawnParams.persistent = true
  spawnParams.level = data.level
  spawnParams.identity = normalizedIdentity(data)

  spawnParams.scriptConfig = spawnParams.scriptConfig or {}
  spawnParams.scriptConfig.personality = copyTable(data.personality)

  spawnParams.scriptConfig.initialStorage = copyTable(data.storage or {})
  spawnParams.scriptConfig.initialStorage.itemSlots =
    spawnParams.scriptConfig.initialStorage.itemSlots or copyTable(data.equipment or {})

  spawnParams.scriptConfig.uniqueId = linkId

  return spawnParams
end

function normalizedIdentity(data)
  if not data.identity then return nil end

  local identity = copyTable(data.identity)
  identity.name = identity.name or data.name
  identity.gender = identity.gender or data.gender
  identity.species = identity.species or data.species

  return identity
end

function mergeSpawnParameters(storedParameters, liveData)
  local parameters = copyTable(storedParameters or liveData.parameters or {})
  parameters.level = liveData.level or parameters.level
  parameters.scriptConfig = parameters.scriptConfig or {}
  parameters.scriptConfig.initialStorage = copyTable(liveData.storage or parameters.scriptConfig.initialStorage)
  return parameters
end

function normalizedIdentity(data)
  if not data.identity then
    return nil
  end

  local identity = copyTable(data.identity)
  identity.name = identity.name or data.name
  identity.gender = identity.gender or data.gender
  identity.species = identity.species or data.species
  return identity
end

function copyTable(value)
  if type(value) ~= "table" then
    return value
  end

  local result = {}
  for k, v in pairs(value) do
    result[k] = copyTable(v)
  end
  return result
end

function restoreEquipment(npcId, equipment)
  for slot, itemDesc in pairs(equipment) do
    if itemDesc then
      safeCall(npcId, "fwnpcpods_setItemSlot", slot, itemDesc)
    end
  end
end

function removeOriginalNpc(npcId)
  if not world.entityExists(npcId) then
    return
  end

  local pos = world.entityPosition(npcId)
  if not pos then
    return
  end

  world.spawnProjectile(
    "fwnpccapturekill",
    pos,
    activeItem.ownerEntityId(),
    {1, 0},
    false,
    {
      power = 1,
      damageTeam = {
        type = "indiscriminate",
        team = 0
      }
    }
  )
end

function getParams()
  local desc = item.descriptor()
  return desc.parameters or {}
end

function setReleasedState(released, uniqueId)
  setInstanceParam("released", released)
  setInstanceParam("releasedUniqueId", uniqueId or "")
end

function setInstanceParam(name, value)
  if not self.params then
    self.params = getParams()
  end

  self.params[name] = value
  activeItem.setInstanceValue(name, value)
end

function getReleasedRecord(linkId)
  local ok, record = pcall(world.getProperty, releasedRecordKey(linkId))
  if ok then
    return record
  end

  return nil
end

function setReleasedRecord(linkId, entityId)
  local record = {
    released = true,
    entityId = entityId ~= true and entityId or nil
  }

  pcall(world.setProperty, releasedRecordKey(linkId), record)
end

function clearReleasedRecord(linkId)
  pcall(world.setProperty, releasedRecordKey(linkId), nil)
end

function releasedRecordKey(linkId)
  return "fwnpcpods_released_" .. linkId
end

function safeCall(entityId, functionName, ...)
  if not world.entityExists(entityId) then
    sb.logWarn("[FW NPC Pods] Cannot call %s; entity %s does not exist", functionName, entityId)
    return nil
  end

  local ok, result = pcall(world.callScriptedEntity, entityId, functionName, ...)
  if ok then
    return result
  end

  sb.logWarn("[FW NPC Pods] callScriptedEntity(%s, %s) failed: %s", entityId, functionName, result)
  return nil
end