local readableSlots = {
  "head", "headCosmetic",
  "chest", "chestCosmetic",
  "legs", "legsCosmetic",
  "back", "backCosmetic",
  "primary", "alt",
  "sheathedprimary", "sheathedalt"
}

local settableSlots = {
  head = true,
  headCosmetic = true,
  chest = true,
  chestCosmetic = true,
  legs = true,
  legsCosmetic = true,
  back = true,
  backCosmetic = true,
  primary = true,
  alt = true
}

local fwnpcpods_oldInit = init

function init(...)
  if fwnpcpods_oldInit then
    fwnpcpods_oldInit(...)
  end

  message.setHandler("fwnpcpods_helperLoaded", function()
    return true
  end)

  message.setHandler("fwnpcpods_captureData", function()
    return fwnpcpods_captureData()
  end)

  message.setHandler("fwnpcpods_restoreSnapshot", function(_, _, data, uniqueId)
    fwnpcpods_restoreSnapshot(data, uniqueId)
    return true
  end)

  message.setHandler("fwnpcpods_setUniqueId", function(_, _, uniqueId)
    fwnpcpods_setUniqueId(uniqueId)
    return true
  end)

  message.setHandler("fwnpcpods_setItemSlot", function(_, _, slotName, item)
    fwnpcpods_setItemSlot(slotName, item)
    return true
  end)
end

function fwnpcpods_captureData()
  local identity = copyJson(npc.humanoidIdentity() or {})

  identity.name = identity.name or world.entityName(entity.id())
  identity.species = identity.species or npc.species()
  identity.gender = identity.gender or world.entityGender(entity.id())

  local itemSlots = {}
  for _, slotName in ipairs(readableSlots) do
    itemSlots[slotName] = npc.getItemSlot(slotName)
  end

  local storageData = copyJson(storage) or {}
  storageData.itemSlots = storageData.itemSlots or {}

  for slotName, item in pairs(itemSlots) do
    if storageData.itemSlots[slotName] == nil then
      storageData.itemSlots[slotName] = item
    end
  end

  local resources = {}
  for _, resourceName in ipairs(status.resourceNames()) do
    resources[resourceName] = {
      value = status.resource(resourceName),
      max = status.resourceMax(resourceName),
      locked = status.resourceLocked(resourceName)
    }
  end

  local personalityData = nil
  if type(personality) == "function" then
    personalityData = personality()
  end

  return {
    schemaVersion = 3,
    name = world.entityName(entity.id()),
    species = npc.species(),
    gender = world.entityGender(entity.id()),
    npcType = npc.npcType(),
    level = npc.level(),
    seed = npc.seed(),
    identity = identity,
    personality = personalityData,
    storage = storageData,
    equipment = itemSlots,
    resources = resources,
    health = status.resource("health"),
    maxHealth = status.resourceMax("health"),
    parameters = {
      persistent = true,
      level = npc.level(),
      identity = copyJson(identity),
      scriptConfig = {
        personality = copyJson(personalityData),
        initialStorage = copyJson(storageData)
      }
    }
  }
end

function fwnpcpods_restoreSnapshot(data, uniqueId)
  if uniqueId then
    fwnpcpods_setUniqueId(uniqueId)
  end

  if data.storage then
    for k, v in pairs(data.storage) do
      storage[k] = copyJson(v)
    end
  end

  if data.equipment then
    for slotName, item in pairs(data.equipment) do
      if settableSlots[slotName] then
        fwnpcpods_setItemSlot(slotName, item)
      end
    end
  end

  if data.resources then
    for resourceName, resourceData in pairs(data.resources) do
      if status.isResource(resourceName) then
        if resourceData.locked ~= nil then
          status.setResourceLocked(resourceName, resourceData.locked)
        end
        if resourceData.value ~= nil then
          status.setResource(resourceName, resourceData.value)
        end
      end
    end
  elseif data.health then
    status.setResource("health", math.min(data.health, status.resourceMax("health")))
  end
end

function fwnpcpods_setUniqueId(uniqueId)
  if uniqueId then
    self.uniqueId = uniqueId
    npc.setUniqueId(uniqueId)
  end
  npc.setPersistent(true)
end

function fwnpcpods_setItemSlot(slotName, item)
  if not item then return end

  if type(setNpcItemSlot) == "function" then
    setNpcItemSlot(slotName, item)
  else
    npc.setItemSlot(slotName, item)
  end
end

function copyJson(value)
  local valueType = type(value)

  if valueType == "nil"
      or valueType == "boolean"
      or valueType == "number"
      or valueType == "string" then
    return value
  end

  if valueType ~= "table" then
    return nil
  end

  local result = {}
  for k, v in pairs(value) do
    local copiedKey = copyJson(k)
    local copiedValue = copyJson(v)

    if copiedKey ~= nil and copiedValue ~= nil then
      result[copiedKey] = copiedValue
    end
  end

  return result
end