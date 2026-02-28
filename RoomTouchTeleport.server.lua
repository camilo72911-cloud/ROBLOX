--[[
  RoomTouchTeleport.server.lua
  Coloca este Script en ServerScriptService.

  Requisitos para cada "cuadro" (Part) de sala:
  - Debe tener el tag "RoomTrigger" (CollectionService).
  - Attribute Number "MaxPlayers" (ej. 4).
  - Attribute Number "PlaceId" (Place a donde teletransportar).
  - (Opcional) Attribute String "RoomId" para un nombre legible.

  Comportamiento:
  - Cuando un jugador toca un cuadro, se valida cupo de la sala.
  - Si hay espacio, se agrega a la sala y se teletransporta.
  - Si está llena, se muestra un mensaje y no entra.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")

local ROOM_TAG = "RoomTrigger"

-- roomKey -> { players = { [userId] = true }, maxPlayers = number, placeId = number }
local roomState = {}
-- Simple anti-spam por jugador+room
local touchCooldown = {}

local function getOrCreateState(roomPart: BasePart)
	local key = roomPart:GetFullName()
	if not roomState[key] then
		roomState[key] = {
			players = {},
			maxPlayers = roomPart:GetAttribute("MaxPlayers") or 1,
			placeId = roomPart:GetAttribute("PlaceId") or game.PlaceId,
			roomId = roomPart:GetAttribute("RoomId") or roomPart.Name,
		}
	end
	return key, roomState[key]
end

local function countPlayersInRoom(state)
	local n = 0
	for _ in pairs(state.players) do
		n += 1
	end
	return n
end

local function showMessage(player: Player, text: string)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoomNoticeGui"
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.45, 0.08)
	label.Position = UDim2.fromScale(0.275, 0.06)
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = gui

	gui.Parent = playerGui
	task.delay(2.5, function()
		if gui and gui.Parent then
			gui:Destroy()
		end
	end)
end

local function removePlayerFromAllRooms(userId: number)
	for _, state in pairs(roomState) do
		state.players[userId] = nil
	end
end

local function onRoomTouched(roomPart: BasePart, hit: BasePart)
	local character = hit and hit.Parent
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local roomKey, state = getOrCreateState(roomPart)
	local cdKey = string.format("%d:%s", player.UserId, roomKey)
	if touchCooldown[cdKey] then
		return
	end
	touchCooldown[cdKey] = true
	task.delay(1, function()
		touchCooldown[cdKey] = nil
	end)

	-- Limpia al jugador de otras salas para evitar duplicados de asignación
	removePlayerFromAllRooms(player.UserId)

	local currentCount = countPlayersInRoom(state)
	if currentCount >= state.maxPlayers then
		showMessage(player, "La sala " .. state.roomId .. " ya está llena")
		return
	end

	state.players[player.UserId] = true

	local partyPlayers = {}
	for userId in pairs(state.players) do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			table.insert(partyPlayers, p)
		end
	end

	local success, err = pcall(function()
		TeleportService:TeleportPartyAsync(state.placeId, partyPlayers)
	end)

	if not success then
		warn("Error teletransportando sala " .. tostring(state.roomId) .. ": " .. tostring(err))
		showMessage(player, "No se pudo teletransportar. Intenta de nuevo.")
		state.players[player.UserId] = nil
	end
end

local function connectRoom(roomPart: Instance)
	if not roomPart:IsA("BasePart") then
		warn("RoomTrigger ignorado (no es BasePart):", roomPart:GetFullName())
		return
	end

	roomPart.Touched:Connect(function(hit)
		onRoomTouched(roomPart, hit)
	end)
end

for _, tagged in ipairs(CollectionService:GetTagged(ROOM_TAG)) do
	connectRoom(tagged)
end

CollectionService:GetInstanceAddedSignal(ROOM_TAG):Connect(connectRoom)

Players.PlayerRemoving:Connect(function(player)
	removePlayerFromAllRooms(player.UserId)
end)
