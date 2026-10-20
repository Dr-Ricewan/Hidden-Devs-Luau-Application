local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- TradeController Deals with the UI/UX for the trade system
-- In this trade system Weapons and Towers can be traded between players.

local TradeController = {}
-- using crusher Fires Module loader 
-- allows me to require other modules allowing for the use of reusable components
-- + dictate the module priority (order in which modules load in)


-- Init Function Initialised by the module loader first before the any methods of the module being loaded can be used
-- inside Init we ensure all necessary modules are required and define any constants or default table states here
-- we want to ensure Init is kept light weight as we want initialization times to be as fast as possible

function TradeController:Init()
	-- client side Data manager Handles replicating and updating data values altered and validated by the server side.
	-- We use client sided Data to handle UI/ UX updates
	self.State = require(ReplicatedStorage.Client.State)
	-- Trade Config contains functions used by both the client and the server and is located in replicated Storage
	-- this helps follow the coding principal DRY Dont Repeat Yourself. (if bugs we only have to fix in 1 location not 2!)
	self.TradeConfig = require(ReplicatedStorage.Configs.TradeConfig)
	self.TowerConfig = require(ReplicatedStorage.Configs.TowerConfig)
	self.WeaponConfig = require(ReplicatedStorage.Configs.WeaponConfig)
	self.ViewportModel = require(ReplicatedStorage.Packages.ViewportModel)
	self.EzVisuals = require(ReplicatedStorage.Packages.EasyVisuals)
	self.TowerInfoOrganizer = require(ReplicatedStorage.Packages.TowerInfoOrganizer)
	self.GuiUtils = require(ReplicatedStorage.Utilities.GuiUtils)
	self.Notifications = require(ReplicatedStorage.Packages.Notifications)

	self.OpenListState = false
	self._openTween = false

	self.RECEIVE_REQUEST_TEXT = "From: NAME"
	self.LastRequestReceived = nil
	
	-- Default table state containing the Weapons and towers this client has selected for trade
	-- + the weapons and towers the other client has selected for trade.
	-- as this is the client side this info is easily exploitable
	-- a malicious client could manipulate selected weapons + towers the other client offers.
	-- However this does not matter as this table is purely used for visual feedback to the client
	-- the server is the source of truth and stores the validated info of both players states.
	
	self.TradeInfo = {
		Self = {
			SelectedWeapons = {},
			SelectedTowers = {},
			IsReady = false,
		},
		Target = {
			SelectedWeapons = {},
			SelectedTowers = {},
			IsReady = false,
			UserId = nil,
		},
	}

	self.RARITY_IMAGES = {
		Common = "rbxassetid://133298212277275",
		Uncommon = "rbxassetid://88892412215656",
		Rare = "rbxassetid://88500242184814",
		Epic = "rbxassetid://139140052041812",
		Legendary = "rbxassetid://137147711154391",
		Mythic = "rbxassetid://88395866126168",
	}

	self.HasConfirmed = false
	self.IsHovering = false
	self.OffsetX = 5
	self.OffsetY = 10
	self.Padding = 60
	self.ActiveHoverEffects = {}
end


-- second function native to crusher fires module loader.
-- as the method suggests here is where we actually begin to run the script via this function
-- in start we reference memory locations that may take slightly longer to load for the client e.g PlayerGui
-- aswell as establish all the remote conns with in this function + any UI signal events e.g MouseButton1Click

function TradeController:Start()
	self.Data = self.State:GetData()
	if not self.Data then return end

	self.Player = Players.LocalPlayer
	self.Mouse = self.Player:GetMouse()
	self.Camera = workspace.CurrentCamera
	self.TradeRemotes = ReplicatedStorage.RemoteFolder.TradeRemotes
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")

	self.TradeGui = self.PlayerGui:WaitForChild("Trade")

	self.MainFrame = self.TradeGui.MainFrame
	self.InventoryFrame = self.MainFrame.InventoryFrame
	self.WeaponInventoryFrame = self.MainFrame.WeaponInventoryFrame

	self.BackgroundFrame = self.MainFrame.Background
	self.HolderButtons = self.BackgroundFrame.HolderButtons
	self.OfferPaddedFrame = self.BackgroundFrame.OfferPaddedFrame
	self.OtherOfferPaddedFrame = self.BackgroundFrame.OtherOfferPaddedFrame
	self.TitleLabel = self.MainFrame.TitleLabel
	self.OtherTitleLabel = self.MainFrame.OtherTitleLabel

	self.List = self.TradeGui.List
	self.ListBackground = self.List.Background

	self.ConfirmationFrame = self.TradeGui.Confirmation
	self.ConfirmationButtons = self.ConfirmationFrame.Buttons

	self.OptionsGui = self.PlayerGui:WaitForChild("OptionsGui")
	self.OpenButton = self.OptionsGui.MainFrame.Trade

	self.TowerInfoGui = self.PlayerGui:WaitForChild("TowerInfo")
	self.TowerInfoFrame = self.TowerInfoGui.TowerInfoTradeFrame

	self.OpenButton.MouseButton1Click:Connect(function()
		if self.OpenListState then
			self:HideShop(self.List, self.List.UIScale)
		else
			self:ShowShop(self.List, self.List.UIScale)
			self:InitialiseList()
		end
	end)

	self.ListBackground.Exit.MouseButton1Click:Connect(function()
		self:HideShop(self.List, self.List.UIScale)
	end)

	self.ListBackground.Exit.MouseEnter:Connect(function()
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
		local Tween = TweenService:Create(self.ListBackground.Exit.Title, tweenInfo, {TextColor3 = Color3.fromRGB(255, 0, 0)})
		Tween:Play()
	end)

	self.ListBackground.Exit.MouseLeave:Connect(function()
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		local Tween = TweenService:Create(self.ListBackground.Exit.Title, tweenInfo, {TextColor3 = Color3.fromRGB(255, 255, 255)})
		Tween:Play()
	end)

	self.ListBackground.Requests.MouseButton1Click:Connect(function()
		self.TradeRemotes.ToggleRequest:FireServer()
	end)

	self.ConfirmationFrame.Buttons.No.MouseButton1Click:Connect(function()
		self.TradeRemotes.RespondToRequest:FireServer(self.LastRequestReceived, false)
		self.ConfirmationFrame.Visible = false
	end)

	self.ConfirmationFrame.Buttons.Yes.MouseButton1Click:Connect(function()
		self.TradeRemotes.RespondToRequest:FireServer(self.LastRequestReceived, true)
		self.ConfirmationFrame.Visible = false
	end)

	self.HolderButtons.Accept.MouseButton1Click:Connect(function()
		if self.TradeInfo.Self.IsReady then return end
		if self.HasConfirmed then
			self.TradeRemotes.Ready:FireServer()
		else
			self.HasConfirmed = true
			self.HolderButtons.Accept.Title.Text = "Accept"
		end
	end)

	self.HolderButtons.Cancel.MouseButton1Click:Connect(function()
		local IsReady = self.TradeInfo.Self.IsReady
		if IsReady then
			self.TradeRemotes.Unready:FireServer()
			self.HolderButtons.Accept.Title.Text = "Confirm"
		else
			self.TradeRemotes.Cancel:FireServer()
			self:CancelTrade()
		end
	end)

	self.InventoryFrame.Search.SearchBox.Changed:Connect(function()
		self.GuiUtils.UpdateSearchedTowers(self.InventoryFrame.Search.SearchBox, self.Data.TowerData, self.InventoryFrame.Container)
	end) 

	-- Server Remotes
	self.TradeRemotes.ToggleRequest.OnClientEvent:Connect(function()
		task.defer(function()
			self:UpdateToggleButton()
		end)
	end)

	self.TradeRemotes.SendRequest.OnClientEvent:Connect(function(targetUserId)
		self:TradeSent(targetUserId)
	end)

	self.TradeRemotes.ReceiveRequest.OnClientEvent:Connect(function(playerWhoSentId)
		self:ReceiveTradeRequest(playerWhoSentId)
	end)

	self.TradeRemotes.RespondToRequest.OnClientEvent:Connect(function(targetUserId, isAccept: boolean)
		self:ReceiveResponse(targetUserId, isAccept)
	end)

	self.TradeRemotes.Start.OnClientEvent:Connect(function(targetUserId)
		self:InitialiseTrading(targetUserId)
	end)

	self.TradeRemotes.Unready.OnClientEvent:Connect(function()
		self:Ready(true, false)
	end)

	self.TradeRemotes.TargetUnready.OnClientEvent:Connect(function()
		self:Ready(false, false)
	end)

	self.TradeRemotes.Ready.OnClientEvent:Connect(function()
		self:Ready(true, true)
	end)

	self.TradeRemotes.TargetReady.OnClientEvent:Connect(function()
		self:Ready(false, true)
	end)

	self.TradeRemotes.SelectTower.OnClientEvent:Connect(function(uniqueTowerId, isSelected)
		self:SelectTower(uniqueTowerId, isSelected)
	end)

	self.TradeRemotes.TargetAddTower.OnClientEvent:Connect(function(towerInstance)
		self:TargetAddTower(towerInstance)
	end)

	self.TradeRemotes.TargetRemoveTower.OnClientEvent:Connect(function(uniqueTowerId)
		self:TargetRemoveTower(uniqueTowerId)
	end)

	self.TradeRemotes.Error.OnClientEvent:Connect(function(errorMsg)
		self.Notifications.Create(self.Data, errorMsg, "Red")
	end)

	self.TradeRemotes.Cancel.OnClientEvent:Connect(function()
		self:CancelTrade()
	end)

	self.TradeRemotes.Complete.OnClientEvent:Connect(function()
		self:CancelTrade()
		self.Notifications.Create(self.Data, "Trade Complete!", "Green")
	end)

	-- Weapon Remotes
	self.TradeRemotes.TradeWeaponRemotes.SelectWeapon.OnClientEvent:Connect(function(uniqueWeaponId, isSelected)
		self:SelectWeapon(uniqueWeaponId, isSelected)
	end)

	self.TradeRemotes.TradeWeaponRemotes.TargetAddWeapon.OnClientEvent:Connect(function(weaponInstance)
		self:TargetAddWeapon(weaponInstance)
	end)

	self.TradeRemotes.TradeWeaponRemotes.TargetRemoveWeapon.OnClientEvent:Connect(function(uniqueWeaponId)
		self:TargetRemoveWeapon(uniqueWeaponId)
	end)

	task.defer(function()
		RunService.PreRender:Connect(function()
			if self.IsHovering then
				self:UpdatePosition()
				self.TowerInfoFrame.Visible = true
			else
				self.TowerInfoFrame.Visible = false
			end
		end)
	end)
end





-- visual feedback for the player of UI when they click self.ListBackground.Requests button a remote is fired to the server
-- the server then flips the state of the boolean ReceiveTradeRequests and then a remote is fired to the self.State client data
-- manager to upd the state. at the same time the remote signal is picked up here for visual feedback
-- this is why we use task.defer() at line 184 in order to ensure the state updates first before this method can run.
-- 
function TradeController:UpdateToggleButton()
	local text = if self.Data.ReceiveTradeRequests then "Trade Requests: ON" else "Trade Requests: OFF"
	self.ListBackground.Title.Text = text
	self.ListBackground.Requests.Text = text
	self.ListBackground.Requests.BackgroundColor3 = if self.Data.ReceiveTradeRequests then Color3.fromRGB(84, 255, 37)
		else Color3.fromRGB(255, 73, 73)
end

-- we clean all the visuals of the UI and reset the table states + any other booleans that need resetting
-- this method is called when the trade is cancelled or complete
function TradeController:CancelTrade()
	self:CleanContainer(self.OtherOfferPaddedFrame.OtherCollectionContainer)
	self:CleanContainer(self.OfferPaddedFrame.CollectionContainer)
	self:CleanContainer(self.InventoryFrame.Container)
	self:CleanContainer(self.WeaponInventoryFrame.Container) -- Clean Weapons too
	self.MainFrame.Visible = false

	self.TradeInfo = {
		Self = {
			SelectedWeapons = {},
			SelectedTowers = {},
			IsReady = false,
		},
		Target = {
			SelectedWeapons = {},
			SelectedTowers = {},
			IsReady = false,
			UserId = nil,
		},
	}
	self.HasConfirmed = false
end

-- Removes the tower visual icon appearing in the other players offer
-- following the removal of a tower when the target deselects a tower
function TradeController:TargetRemoveTower(uniqueTowerId)
	local CollectionClone = self.OtherOfferPaddedFrame.OtherCollectionContainer:FindFirstChild(uniqueTowerId)
	if CollectionClone then
		CollectionClone:Destroy()
	end
	self.TradeInfo.Target.SelectedTowers[uniqueTowerId] = nil
end


-- Removes the Weapon visual icon appearing in the other players offer
-- following the removal of a weapon when the target deselects a weapon
function TradeController:TargetRemoveWeapon(uniqueWeaponId)
	local CollectionClone = self.OtherOfferPaddedFrame.OtherCollectionContainer:FindFirstChild(uniqueWeaponId)
	if CollectionClone then
		CollectionClone:Destroy()
	end
	self.TradeInfo.Target.SelectedWeapons[uniqueWeaponId] = nil
end

-- Adds the tower visual icon appearing in the other players offer
-- following the adding of a tower when the target selects a tower to be traded
function TradeController:TargetAddTower(towerInstance)
	self:GenerateTower(towerInstance, self.OtherOfferPaddedFrame.OtherCollectionContainer, false)
	self.TradeInfo.Target.SelectedTowers[towerInstance.UniqueTowerID] = towerInstance
end

-- Adds the Weapon visual icon appearing in the other players offer
-- following the adding of a weapon when the target selects a weapon to be traded
function TradeController:TargetAddWeapon(weaponInstance)
	self:GenerateWeapon(weaponInstance, self.OtherOfferPaddedFrame.OtherCollectionContainer, false)
	self.TradeInfo.Target.SelectedWeapons[weaponInstance.UniqueWeaponID] = weaponInstance
end

-- if selected:
-- Adds the tower visual icon appearing in the current client (self) offer
-- following the adding of a tower when the client selects a tower to be traded (and once server validated)

-- if not selected the tower visual destroyed -- client (self) removed tower from offer
function TradeController:SelectTower(uniqueTowerId, isSelected)
	local TowerInstance = self.Data.TowerData[uniqueTowerId]
	if not TowerInstance then return end

	local InventoryClone = self.InventoryFrame.Container:FindFirstChild(uniqueTowerId)
	if InventoryClone then
		InventoryClone.Equipped.Visible = isSelected
	end

	if isSelected then
		self:GenerateTower(TowerInstance, self.OfferPaddedFrame.CollectionContainer, false)
	else
		local CollectionClone = self.OfferPaddedFrame.CollectionContainer:FindFirstChild(uniqueTowerId)
		if CollectionClone then
			CollectionClone:Destroy()
		end
	end
end

-- if selected:
-- Adds the weapon visual icon appearing in the current client (self) offer
-- following the adding of a weapon when the client selects a weapon to be traded (and once server validated)

-- -- if not selected the weapon visual destroyed -- client (self) removed weapon from offer
function TradeController:SelectWeapon(uniqueWeaponId, isSelected)
	local WeaponInstance = self.Data.WeaponData[uniqueWeaponId]
	if not WeaponInstance then return end

	local InventoryClone = self.WeaponInventoryFrame.Container:FindFirstChild(uniqueWeaponId)
	if InventoryClone then
		InventoryClone.Equipped.Visible = isSelected
	end

	if isSelected then
		self:GenerateWeapon(WeaponInstance, self.OfferPaddedFrame.CollectionContainer, false)
	else
		local CollectionClone = self.OfferPaddedFrame.CollectionContainer:FindFirstChild(uniqueWeaponId)
		if CollectionClone then
			CollectionClone:Destroy()
		end
	end
end


-- optimised function which can be is utilised for both target player and self player
-- used when a client self or target readys or unreadys
-- client must click the button twice: once to confirm (set self.HasConfirmed = true) 
-- seconds actually confirms the clients ready state for the server
-- we also update the state of the tradeInfo table following the remote event declaring the client and target states
-- from the server

function TradeController:Ready(isSelf: boolean, isReady: boolean)
	local TiteLabel = if isSelf then self.TitleLabel else self.OtherTitleLabel
	TiteLabel.ImageColor3 = if isReady then Color3.fromRGB(26, 255, 0) else Color3.fromRGB(255, 0, 0)

	if isSelf then
		if not isReady then
			self.HasConfirmed = false
		end
	end

	local Index = if isSelf then "Self" else "Target"
	self.TradeInfo[Index].IsReady = isReady
end

-- closes the TradeList which showcases who u can invite to trade once a trade has commenced
-- this function can be thought as the master function for setting all the visuals for the trade sequence to begin
function TradeController:InitialiseTrading(targetUserId)
	local TargetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not TargetPlayer then return end
	self.HasConfirmed = false

	self:UpdateMainTitles(TargetPlayer)
	self:GenerateInventoryContainer()
	self.MainFrame.Visible = true
	self:HideShop(self.List, self.List.UIScale)
end

-- gets all Towers and weapons tradeable (not locked or equipped)
-- we update the layout using the utility module i created
-- it sorts the towers and weapons in order from Mythic --> common

function TradeController:GenerateInventoryContainer()
	local Towers = self.TradeConfig.GetTradeableTowers(self.Data)
	if not Towers then return end

	local Weapons = self.TradeConfig.GetTradeableWeapons(self.Data)
	if not Weapons then return end

	for _, towerInstance in Towers do
		self:GenerateTower(towerInstance, self.InventoryFrame.Container, true)
	end

	self.GuiUtils.UpdateLayout(self.InventoryFrame.Container, self.Data)

	for _, weaponInstance in Weapons do
		self:GenerateWeapon(weaponInstance, self.WeaponInventoryFrame.Container, true)
	end

	self.GuiUtils.UpdateWeaponLayout(self.WeaponInventoryFrame.Container, self.Data)
end


-- function to generate individual weapon icon found in players inventory (that is tradeable)
function TradeController:GenerateWeapon(weaponInstance, container, isInventory: boolean)
	local ConfigWeapon = self.WeaponConfig.GetConfig(weaponInstance.Model)
	local Clone = container.Template:Clone()
	Clone.Name = weaponInstance.UniqueWeaponID
	Clone.Icon.Image = self.RARITY_IMAGES[ConfigWeapon.Rarity]
	
	local nameLabel = Clone:FindFirstChild("WeaponName") or Clone:FindFirstChild("TowerName")
	if nameLabel then
		nameLabel.Text = weaponInstance.Model
	end

	Clone.StarLevel.Text = weaponInstance.StarLevel
	local Model = self.WeaponConfig.GetModel(weaponInstance)

	task.defer(function()
		self.ViewportModel.GenerateViewport(Clone.Icon.ViewportFrame, Model, CFrame.Angles(0, math.rad(0), 0))
	end)

	Clone.Parent = container
	Clone.Visible = true

	if isInventory then
		Clone.MouseButton1Click:Connect(function()
			self.TradeRemotes.TradeWeaponRemotes.SelectWeapon:FireServer(weaponInstance.UniqueWeaponID)
		end)
	end

	Clone.MouseEnter:Connect(function()
		local h, s, v = Clone.Icon.ImageColor3:ToHSV()
		v = 0.5
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v)
		-- Fixed: Was using TowerConfig instead of WeaponConfig.GunInfo
		local WeaponInfo = self.WeaponConfig.GunInfo(weaponInstance)
		self.TowerInfoOrganizer(WeaponInfo, self.TowerInfoFrame)
		self.IsHovering = true
		self:UpdatePosition()

		for _, effect in self.ActiveHoverEffects do
			effect:Destroy()
		end
		table.clear(self.ActiveHoverEffects)

		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "Shine", 0.25, 1, true, Color3.fromRGB(0, 0, 0)))
		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "GoldStroke", 1, 5))
	end)

	Clone.MouseLeave:Connect(function()
		local h, s, v = Clone.Icon.ImageColor3:ToHSV()
		v = 1
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v)
		self.IsHovering = false

		for _, effect in self.ActiveHoverEffects do
			effect:Destroy()
		end
		table.clear(self.ActiveHoverEffects)
	end)
end

-- function to generate individual Tower icon found in players inventory (that is tradeable)
function TradeController:GenerateTower(towerInstance, container, isInventory: boolean)
	local ConfigTower = self.TowerConfig.GetConfig(towerInstance.Model)
	local Clone = container.Template:Clone()
	Clone.Name = towerInstance.UniqueTowerID
	Clone.Icon.Image = self.RARITY_IMAGES[ConfigTower.Rarity]
	Clone.TowerName.Text = towerInstance.Model
	Clone.StarLevel.Text = towerInstance.StarLevel 
	local Model = self.TowerConfig.GetModel(towerInstance)

	self.ViewportModel.GenerateViewport(Clone.Icon.ViewportFrame, Model, CFrame.Angles(0, math.rad(-90), 0))

	Clone.Parent = container
	Clone.Visible = true

	if isInventory then
		Clone.MouseButton1Click:Connect(function()
			self.TradeRemotes.SelectTower:FireServer(towerInstance.UniqueTowerID)
		end)
	end

	Clone.MouseEnter:Connect(function()
		local h, s, v = Clone.Icon.ImageColor3:ToHSV()
		v = 0.5
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v)
		local TowerInfo = self.TowerConfig.TowerInfo(towerInstance)
		self.TowerInfoOrganizer(TowerInfo, self.TowerInfoFrame)
		self.IsHovering = true
		self:UpdatePosition()

		for _, effect in self.ActiveHoverEffects do
			effect:Destroy()
		end
		table.clear(self.ActiveHoverEffects)

		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "Shine", 0.25, 1, true, Color3.fromRGB(0, 0, 0)))
		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "GoldStroke", 1, 5))
	end)

	Clone.MouseLeave:Connect(function()
		local h, s, v = Clone.Icon.ImageColor3:ToHSV()
		v = 1
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v)
		self.IsHovering = false

		for _, effect in self.ActiveHoverEffects do
			effect:Destroy()
		end
		table.clear(self.ActiveHoverEffects)
	end)
end

-- Updates visuals of both the target player trade offer title + self offer title
function TradeController:UpdateMainTitles(targetPlayer)
	self.HolderButtons.Accept.Title.Text = "Confirm"
	local ImageSize = Enum.ThumbnailSize.Size420x420
	local ImageType = Enum.ThumbnailType.HeadShot
	local content = Players:GetUserThumbnailAsync(self.Player.UserId, ImageType, ImageSize)
	self.TitleLabel.Icon.Image = content
	self.TitleLabel.ImageColor3 = Color3.fromRGB(255, 0, 0)

	local targetContent = Players:GetUserThumbnailAsync(targetPlayer.UserId, ImageType, ImageSize)
	self.OtherTitleLabel.Icon.Image = targetContent
	self.OtherTitleLabel.ImageColor3 = Color3.fromRGB(255, 0, 0)
	self.OtherTitleLabel.Title.Text = `{targetPlayer.Name}'s Offer:`
end


-- once target player procceses response and server handles and tells self client the response
function TradeController:ReceiveResponse(userId: number, isAccept: boolean)
	if isAccept then
		self:HideShop(self.List, self.List.UIScale)
		self.ConfirmationFrame.Visible = false
	end

	local Clone = self.ListBackground.Container:FindFirstChild(tostring(userId))
	if not Clone then return end

	Clone.Action.Text = if isAccept then "Accepted!" else "Declined"

	task.delay(5, function()
		if Clone then
			Clone.Action.Text = ""
		end
	end)
end

-- if target player sends trade request to the self player the server handles and sends a response to the self client
function TradeController:ReceiveTradeRequest(userId)
	local PlayerWhoSent = Players:GetPlayerByUserId(userId)
	if not PlayerWhoSent then return end
	self.LastRequestReceived = userId
	self.ConfirmationFrame.Subtitle.Text = self.RECEIVE_REQUEST_TEXT:gsub("NAME", PlayerWhoSent.Name)
	self.ConfirmationFrame.Visible = true

	task.delay(15, function()
		if self.LastRequestReceived == userId then
			self.ConfirmationFrame.Visible = false
			self.LastRequestReceived = nil
		end
	end)
end

-- if self player sends a trade request server handles it and tells the client the trade was successfully sent
function TradeController:TradeSent(userId: number)
	local Clone = self.ListBackground.Container:FindFirstChild(tostring(userId))
	if not Clone then return end

	Clone.Action.Text = "Sent!"

	task.delay(15, function()
		if Clone then
			Clone.Action.Text = ""
		end
	end)
end

-- function used to clean all elements of a weapon trade container or tower trade container
-- except the Template of said container which is needed to act as a base for which each weapon/tower is cloned and shown
function TradeController:CleanContainer(container)
	for _, child in container:GetChildren() do
		if child.Name == "Template" or not child:IsA("TextButton") then continue end
		child:Destroy()
	end
end

-- initialises list containing every1 in the server 
-- we use an if statment to ensure the client self cant send a request to the client itself!
function TradeController:InitialiseList()
	self:CleanContainer(self.ListBackground.Container)
	for _, player in Players:GetPlayers() do
		if player == self.Player then continue end
		local Clone = self.ListBackground.Container.Template:Clone()
		Clone.Name = player.UserId
		Clone.Player.Text = player.Name
		Clone.Action.Text = ""
		Clone.Parent = self.ListBackground.Container
		Clone.Visible = true

		Clone.MouseButton1Click:Connect(function()
			self.TradeRemotes.SendRequest:FireServer(player.UserId)
		end)
	end
end

-- function used to create a pop out effect when trade menu opens + adds blur effect aswell
function TradeController:ShowShop(shop, shopScale)
	self.OpenListState = true
	if self._openTween then self._openTween:Cancel() end
	local Blur = self.Camera:FindFirstChild("Blur") or Instance.new("BlurEffect")
	Blur.Name = "Blur"
	Blur.Size = 24 
	Blur.Enabled = true
	Blur.Parent = self.Camera
	shop.Visible = true
	shopScale.Scale = 0.8
	self._openTween = TweenService:Create(shopScale, TweenInfo.new(0.9, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1.0 })
	self._openTween:Play()
end

-- function used to create a pop in effect when trade menu closes + blur effect is removed
function TradeController:HideShop(shop, shopScale)
	self.OpenListState = false
	if self._openTween then self._openTween:Cancel() end
	local Blur = self.Camera:FindFirstChild("Blur")
	if Blur then Blur.Enabled = false end
	local shrink = TweenService:Create(shopScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 })
	shrink.Completed:Once(function()
		shop.Visible = false
		shopScale.Scale = 0.5
	end)
	shrink:Play()
end

-- Used in the function when tower or weapon instances are visually generated
-- specifically used when an instance is hovered over .MouseEnter
-- a placard containing the stats of said instance pop ups 
-- this function allows the placard to dynamically move following the mouse
-- the placard disappears and stops folloeing once .MouseLeave is triggered.
function TradeController:UpdatePosition()
	local ScreenSize = workspace.CurrentCamera.ViewportSize
	local FrameSize = self.TowerInfoFrame.AbsoluteSize

	local PositionX = math.clamp(self.Mouse.X + self.OffsetX, self.Padding, ScreenSize.X - FrameSize.X - self.Padding)
	local PositionY = math.clamp(self.Mouse.Y + self.OffsetY, self.Padding, ScreenSize.Y - FrameSize.Y - self.Padding)
	self.TowerInfoFrame.Position = UDim2.fromOffset(PositionX, PositionY)
end

return TradeController