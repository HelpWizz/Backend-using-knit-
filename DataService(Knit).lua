local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DataStoresService = game:GetService("DataStoreService")
local SettingsStore = DataStoresService:GetDataStore("Settings")
local RaisedStore = DataStoresService:GetOrderedDataStore("Raised")
local InvestedStore = DataStoresService:GetOrderedDataStore("Invested")
local TokensStore = DataStoresService:GetOrderedDataStore("Tokens")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileService = require(ServerScriptService.Modules.ProfileService)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)

local DataProfileTemplate1 = {
	DailyBonus = 0,
	Settings = {
		ToggleSettings = {
			["MusicVolume"] = 1,
			["SFXVolume"] = 1,
			["UIScale"] = 100,
			["Low Graphics"] = false,
			["MasterVolume"] = 100,
			["Special Effects"] = true,
		},
	},
	Emotes = {},
	RedeemCodes = {},
	Vip = false,
	Inventory1 = {
		Stalls = {["Basic"] = true};
		Nametags = {["None"] = true}
	},
	DailyReward = {
		Day = 1,
		LastClaim = 0,
		Streak = 1
	},
	EquippedStall = "Basic",
	EquippedNametag = "None",
	Invested = 0,
	Rasied = 0,
	Tokens = 1e14,
	TutorialDone = false,
	TimePlayed = 0,
	FirstJoinGame = true
}

local RELEASE_TIME = .5 
local DataService = Knit.CreateService({Name = "DataService", Client = {}})
DataService.ProfileLoaded = Signal.new()

local profileStore = ProfileService.GetProfileStore("PlayerDataRelease", DataProfileTemplate1)
local profiles = {}

local function tryGet(store, key)
	for i = 1, 5 do --> try 5 times
		local success, message = pcall(function()
			return store:GetAsync(key)
		end)
		if success then
			return message
		else
			warn(message)
			task.wait(3)
		end
	end
end

local function playerAdded(player: Player)
	if profiles[player] and profiles[player]:IsActive() then
		task.wait(.5)
		if profiles[player] and profiles[player]:IsActive() then
			profiles[player]:Release()
			task.wait(.3)
		end
	end
	
	local profile = profileStore:LoadProfileAsync("player_"..player.UserId)
	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		profile:ListenToRelease(function()
			profiles[player] = nil
			player:Kick()
		end)
		if player:IsDescendantOf(Players) then
			profiles[player] = profile
			if profile.Data.FirstJoinGame then
				local PlayerRaised = tryGet(RaisedStore, "player_"..player.UserId)
				profile.Data.Raised = PlayerRaised or 0
				
				local PlayerInvested = tryGet(InvestedStore, "player_"..player.UserId)
				profile.Data.Invested = PlayerInvested or 0
				local PlayerTokens = tryGet(TokensStore, "player_"..player.UserId)
				profile.Data.Tokens = 1e14
			end
			
			DataService.ProfileLoaded:Fire(true, player)
			
			do -- leaderstats

				local leaderstats = Instance.new('Folder')
				leaderstats.Name = 'leaderstats'
				leaderstats.Parent = player

				local Raised = Instance.new('IntValue')
				Raised.Name = 'Raised'
				Raised.Parent = leaderstats
				Raised.Value = profile.Data.Raised
				
				local Invested = Instance.new('IntValue')
				Invested.Name = 'Invested'
				Invested.Parent = leaderstats
				Invested.Value = profile.Data.Invested
			end
		else
			DataService.ProfileLoaded:Fire(false, player)
			profile:Release()
		end
	else
		DataService.ProfileLoaded:Fire(false, player)
		player:Kick()
	end
end



function DataService.Client:GetProfile(player: Player)
	return Promise.new(function(resolve, reject)
		if profiles[player] then
			resolve(profiles[player].Data)
			return
		end

		local yieldSignal = Signal.new()
		local profileLoaded
		profileLoaded = DataService.ProfileLoaded:Connect(function(loaded: boolean, loadedPlayer: Player)
			if loadedPlayer == player then
				if not loaded then
					profileLoaded:Destroy()
					yieldSignal:Destroy()
					return reject()
				end

				profileLoaded:Destroy()
				yieldSignal:Fire()
				yieldSignal:Destroy()
			end
		end)

		yieldSignal:Wait()

		if not profiles[player] then
			reject()
		else
			resolve(profiles[player].Data)
		end
	end)
end


function DataService:Get(player: Player, key: string)
	return Promise.new(function(resolve, reject)
		self.Client:GetProfile(player):andThen(function(profile)
			resolve(profile[key])
		end):catch(function()
			reject(warn)
		end)	
	end)
end


function DataService:Set(player: Player, key: string, value: any, canOverride: boolean)
	self.Client:GetProfile(player):andThen(function(profile)
		if type(profile[key]) == type(value) or canOverride then
			profile[key] = value
		else
			error("Attempting to override type " .. type(profile[key]) .. " of key " .. key .. "with type " .. type(value))
		end
	end)
end


function DataService:Increment(player: Player, key: string, amount: number)
	local profile = self.Client:GetProfile(player):andThen(function(profile)
		profile[key] += amount
	end)
end


function DataService:IsProfileLoaded(player: Player)
	if profiles[player] then
		return true
	else
		return false
	end
end


function DataService:GetTemplate()
	return TableUtil.Copy(DataProfileTemplate1)
end

function DataService:KnitStart()

	Players.PlayerAdded:Connect(playerAdded)

	for _, player: Player in pairs(Players:GetPlayers()) do
		task.defer(playerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		if profile ~= nil then
			DataService:Set(player, "FirstJoinGame", false, true)
			task.wait(RELEASE_TIME)
			profile:Release()
		end
	end)

	game:BindToClose(function()
		for _, player in pairs(Players:GetPlayers()) do
			local profile = profiles[player]
			if profile ~= nil then
				if RunService:IsStudio() then
					task.wait(RELEASE_TIME)
				end
				profile:Release()
			end
		end
	end)
end
return DataService
