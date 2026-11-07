--  "Connected Discord-GitHub" DiscordName: @Dr.Riz RobloxName: rizwan_pro
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Retrieves the ReplicatedStorage service to access shared client-server modules, configurations, and network remotes.
local Players = game:GetService("Players") -- Retrieves the Players service to manage player instances, user IDs, and fetch avatar thumbnails.
local TweenService = game:GetService("TweenService") -- Retrieves the TweenService to procedurally interpolate UI properties for smooth animations.
local RunService = game:GetService("RunService") -- Retrieves the RunService to hook into frame-by-frame client render step events.

-- TradeController Deals with the UI/UX for the trade system
-- In this trade system Weapons and Towers can be traded between players.

local TradeController = {} -- Instantiates the TradeController singleton table to encapsulate state properties and controller methods for the module loader.
-- using crusher Fires Module loader 
-- allows me to require other modules allowing for the use of reusable components
-- + dictate the module priority (order in which modules load in)


-- Init Function Initialised by the module loader first before the any methods of the module being loaded can be used
-- inside Init we ensure all necessary modules are required and define any constants or default table states here
-- we want to ensure Init is kept light weight as we want initialization times to be as fast as possible

function TradeController:Init() -- Defines the synchronous initialization lifecycle method invoked by the module loader prior to starting runtime connections.
	-- client side Data manager Handles replicating and updating data values altered and validated by the server side.
	-- We use client sided Data to handle UI/ UX updates
	self.State = require(ReplicatedStorage.Client.State) -- Loads the client-side State dependency to read server-replicated player inventory and settings data.
	-- Trade Config contains functions used by both the client and the server and is located in replicated Storage
	-- this helps follow the coding principal DRY Dont Repeat Yourself. (if bugs we only have to fix in 1 location not 2!)
	self.TradeConfig = require(ReplicatedStorage.Configs.TradeConfig) -- Loads the shared TradeConfig module to filter trade-eligible towers and weapons without duplicating validation logic.
	self.TowerConfig = require(ReplicatedStorage.Configs.TowerConfig) -- Loads the TowerConfig module to fetch static metadata, 3D models, and stats for tower instances.
	self.WeaponConfig = require(ReplicatedStorage.Configs.WeaponConfig) -- Loads the WeaponConfig module to fetch static metadata, 3D models, and stats for weapon instances.
	self.ViewportModel = require(ReplicatedStorage.Packages.ViewportModel) -- Loads the open-source ViewportModel utility (by EgoMoose) to calculate camera framing and render 3D models inside ViewportFrames.
	self.EzVisuals = require(ReplicatedStorage.Packages.EasyVisuals) -- Loads the open-source EasyVisuals library (byPressStartToPlay) to apply dynamic UIStroke and UIGradient effects on hover.
	self.TowerInfoOrganizer = require(ReplicatedStorage.Packages.TowerInfoOrganizer) -- Loads the custom TowerInfoOrganizer package to populate the hover tooltip frame with formatted item statistics.
	self.GuiUtils = require(ReplicatedStorage.Utilities.GuiUtils) -- Loads the GuiUtils module to handle container layout sorting by rarity and search bar filtering.
	self.Notifications = require(ReplicatedStorage.Packages.Notifications) -- Loads the Notifications package to display color-coded toast alerts on the client HUD.

	self.OpenListState = false -- Initializes a boolean state flag tracking whether the player trade list modal is currently open.
	self._openTween = false -- Initializes a reference variable to store and cancel active UI opening tweens to prevent animation conflicts.

	self.RECEIVE_REQUEST_TEXT = "From: NAME" -- Defines a constant string template with a placeholder token for dynamically formatting incoming trade request prompts.
	self.LastRequestReceived = nil -- Initializes a state variable to cache the UserId of the most recent player who sent a trade request.
	
	-- Default table state containing the Weapons and towers this client has selected for trade
	-- + the weapons and towers the other client has selected for trade.
	-- as this is the client side this info is easily exploitable
	-- a malicious client could manipulate selected weapons + towers the other client offers.
	-- However this does not matter as this table is purely used for visual feedback to the client
	-- the server is the source of truth and stores the validated info of both players states.
	
	self.TradeInfo = { -- Defines a structured state table to track the visual session data for both trading participants.
		Self = { -- Sub-table storing the local player's current trade session state for UI synchronization.
			SelectedWeapons = {}, -- Dictionary mapping unique weapon IDs to weapon data instances offered by the local client.
			SelectedTowers = {}, -- Dictionary mapping unique tower IDs to tower data instances offered by the local client.
			IsReady = false, -- Boolean flag indicating whether the local player has locked in and readied their trade offer.
		}, -- Closes the local player's state sub-table.
		Target = { -- Sub-table storing the trading partner's current session state replicated from the server.
			SelectedWeapons = {}, -- Dictionary mapping unique weapon IDs to weapon data instances offered by the target player.
			SelectedTowers = {}, -- Dictionary mapping unique tower IDs to tower data instances offered by the target player.
			IsReady = false, -- Boolean flag indicating whether the target player has locked in and readied their trade offer.
			UserId = nil, -- Stores the numerical Roblox UserId of the active trading partner.
		}, -- Closes the target player's state sub-table.
	} -- Closes the TradeInfo state table definition.

	self.RARITY_IMAGES = { -- Defines a lookup dictionary mapping rarity tier strings to their corresponding Roblox decal asset URIs.
		Common = "rbxassetid://133298212277275", -- Maps the Common rarity key to its background icon asset ID.
		Uncommon = "rbxassetid://88892412215656", -- Maps the Uncommon rarity key to its background icon asset ID.
		Rare = "rbxassetid://88500242184814", -- Maps the Rare rarity key to its background icon asset ID.
		Epic = "rbxassetid://139140052041812", -- Maps the Epic rarity key to its background icon asset ID.
		Legendary = "rbxassetid://137147711154391", -- Maps the Legendary rarity key to its background icon asset ID.
		Mythic = "rbxassetid://88395866126168", -- Maps the Mythic rarity key to its background icon asset ID.
	} -- Closes the RARITY_IMAGES lookup dictionary.

	self.HasConfirmed = false -- Initializes a two-step verification boolean requiring the player to click Confirm before firing the final Ready remote.
	self.IsHovering = false -- Initializes a boolean flag indicating if the cursor is actively hovering over an item slot to toggle tooltip rendering.
	self.OffsetX = 5 -- Defines the horizontal pixel offset from the mouse cursor position for rendering the floating info placard.
	self.OffsetY = 10 -- Defines the vertical pixel offset from the mouse cursor position for rendering the floating info placard.
	self.Padding = 60 -- Defines the screen-edge boundary padding in pixels to clamp the tooltip inside the visible viewport.
	self.ActiveHoverEffects = {} -- Initializes an array to track active EasyVisuals effect instances so they can be cleaned up on MouseLeave.
end -- Concludes the Init lifecycle method.


-- second function native to crusher fires module loader.
-- as the method suggests here is where we actually begin to run the script via this function
-- in start we reference memory locations that may take slightly longer to load for the client e.g PlayerGui
-- aswell as establish all the remote conns with in this function + any UI signal events e.g MouseButton1Click

function TradeController:Start() -- Defines the runtime execution lifecycle method invoked after all modules have completed their Init phase.
	self.Data = self.State:GetData() -- Retrieves the local player's synchronized data table from the client State manager.
	if not self.Data then return end -- Guards against uninitialized client data by terminating execution early if the data table is nil.

	self.Player = Players.LocalPlayer -- Caches a reference to the client's LocalPlayer instance.
	self.Mouse = self.Player:GetMouse() -- Retrieves the LocalPlayer's Mouse instance to track 2D screen coordinates for the hover tooltip.
	self.Camera = workspace.CurrentCamera -- Caches the active Workspace Camera instance to read viewport dimensions and parent post-processing blur effects.
	self.TradeRemotes = ReplicatedStorage.RemoteFolder.TradeRemotes -- Caches the folder containing RemoteEvents dedicated to client-server trade synchronization.
	self.PlayerGui = self.Player:WaitForChild("PlayerGui") -- Yields until the LocalPlayer's PlayerGui container is replicated and caches the reference.

	self.TradeGui = self.PlayerGui:WaitForChild("Trade") -- Yields until the main Trade ScreenGui is available in PlayerGui and caches it.

	self.MainFrame = self.TradeGui.MainFrame -- Caches the primary trade window Frame inside the Trade ScreenGui.
	self.InventoryFrame = self.MainFrame.InventoryFrame -- Caches the UI container displaying the player's tradeable towers.
	self.WeaponInventoryFrame = self.MainFrame.WeaponInventoryFrame -- Caches the UI container displaying the player's tradeable weapons.

	self.BackgroundFrame = self.MainFrame.Background -- Caches the central background Frame housing the trade offer slots and action buttons.
	self.HolderButtons = self.BackgroundFrame.HolderButtons -- Caches the Frame containing the Accept/Confirm and Cancel interactive buttons.
	self.OfferPaddedFrame = self.BackgroundFrame.OfferPaddedFrame -- Caches the Frame displaying the local player's selected trade offer items.
	self.OtherOfferPaddedFrame = self.BackgroundFrame.OtherOfferPaddedFrame -- Caches the Frame displaying the trading partner's selected trade offer items.
	self.TitleLabel = self.MainFrame.TitleLabel -- Caches the local player's header label and avatar icon container.
	self.OtherTitleLabel = self.MainFrame.OtherTitleLabel -- Caches the trading partner's header label and avatar icon container.

	self.List = self.TradeGui.List -- Caches the Frame used for the server player list menu where trade requests are sent.
	self.ListBackground = self.List.Background -- Caches the background container of the player list modal.

	self.ConfirmationFrame = self.TradeGui.Confirmation -- Caches the popup modal Frame shown when receiving an incoming trade invite.
	self.ConfirmationButtons = self.ConfirmationFrame.Buttons -- Caches the container holding the Yes and No response buttons for trade invites.

	self.OptionsGui = self.PlayerGui:WaitForChild("OptionsGui") -- Yields until the HUD OptionsGui is replicated and caches the reference.
	self.OpenButton = self.OptionsGui.MainFrame.Trade -- Caches the HUD button used by the player to toggle the trade player list menu.

	self.TowerInfoGui = self.PlayerGui:WaitForChild("TowerInfo") -- Yields until the TowerInfo ScreenGui for item tooltips is replicated.
	self.TowerInfoFrame = self.TowerInfoGui.TowerInfoTradeFrame -- Caches the specific tooltip Frame used to display hovered item stats during trades.

	self.OpenButton.MouseButton1Click:Connect(function() -- Connects an event listener to the HUD trade button to toggle the player list modal on left-click.
		if self.OpenListState then -- Checks the boolean flag to determine if the player list UI is currently open.
			self:HideShop(self.List, self.List.UIScale) -- Calls HideShop to animate the scale down and disable the camera blur if already open.
		else -- Branches to open the UI if the list is currently hidden.
			self:ShowShop(self.List, self.List.UIScale) -- Calls ShowShop to apply an elastic scale tween and enable camera blur.
			self:InitialiseList() -- Populates the scrolling list container with buttons for each active player in the server.
		end -- Closes the conditional check for toggling the trade list.
	end) -- Closes the MouseButton1Click connection for the OpenButton.

	self.ListBackground.Exit.MouseButton1Click:Connect(function() -- Binds a click listener to the Exit button inside the player list modal.
		self:HideShop(self.List, self.List.UIScale) -- Invokes HideShop to close the player list modal with a shrink animation.
	end) -- Closes the Exit button click event connection.

	self.ListBackground.Exit.MouseEnter:Connect(function() -- Binds a listener triggered when the player's cursor enters the Exit button bounds.
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.In) -- Constructs a 0.3-second Cubic easing configuration for the hover color transition.
		local Tween = TweenService:Create(self.ListBackground.Exit.Title, tweenInfo, {TextColor3 = Color3.fromRGB(255, 0, 0)}) -- Creates a Tween instance interpolating the Exit button text color to red.
		Tween:Play() -- Starts playing the red text color hover tween.
	end) -- Closes the MouseEnter connection for the Exit button.

	self.ListBackground.Exit.MouseLeave:Connect(function() -- Binds a listener triggered when the player's cursor leaves the Exit button bounds.
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out) -- Constructs a 0.3-second Cubic Out easing configuration to revert the text color.
		local Tween = TweenService:Create(self.ListBackground.Exit.Title, tweenInfo, {TextColor3 = Color3.fromRGB(255, 255, 255)}) -- Creates a Tween instance interpolating the Exit button text color back to white.
		Tween:Play() -- Starts playing the white text color restoration tween.
	end) -- Closes the MouseLeave connection for the Exit button.

	self.ListBackground.Requests.MouseButton1Click:Connect(function() -- Connects a click listener to the trade request privacy toggle button.
		self.TradeRemotes.ToggleRequest:FireServer() -- Fires a RemoteEvent to the server requesting to invert the player's ReceiveTradeRequests setting.
	end) -- Closes the Requests toggle button click connection.

	self.ConfirmationFrame.Buttons.No.MouseButton1Click:Connect(function() -- Connects a click listener to the No button on the incoming trade invite prompt.
		self.TradeRemotes.RespondToRequest:FireServer(self.LastRequestReceived, false) -- Fires the RespondToRequest remote to the server passing the sender's UserId and false to decline.
		self.ConfirmationFrame.Visible = false -- Hides the confirmation modal frame immediately upon declining.
	end) -- Closes the No button click connection.

	self.ConfirmationFrame.Buttons.Yes.MouseButton1Click:Connect(function() -- Connects a click listener to the Yes button on the incoming trade invite prompt.
		self.TradeRemotes.RespondToRequest:FireServer(self.LastRequestReceived, true) -- Fires the RespondToRequest remote to the server passing the sender's UserId and true to accept.
		self.ConfirmationFrame.Visible = false -- Hides the confirmation modal frame immediately upon accepting.
	end) -- Closes the Yes button click connection.

	self.HolderButtons.Accept.MouseButton1Click:Connect(function() -- Connects a click listener to the Accept/Confirm trade button inside the active trade window.
		if self.TradeInfo.Self.IsReady then return end -- Ignores the click if the local player has already locked in their ready state.
		if self.HasConfirmed then -- Checks if the player has already completed the first confirmation click.
			self.TradeRemotes.Ready:FireServer() -- Fires the Ready RemoteEvent to notify the server that the player has locked in their final offer.
		else -- Executes if this is the player's first click on the Confirm button.
			self.HasConfirmed = true -- Sets the local confirmation state flag to true to unlock the final Accept step.
			self.HolderButtons.Accept.Title.Text = "Accept" -- Updates the button label from "Confirm" to "Accept" as visual feedback for the two-step lock-in.
		end -- Closes the two-step confirmation conditional block.
	end) -- Closes the Accept button click connection.

	self.HolderButtons.Cancel.MouseButton1Click:Connect(function() -- Connects a click listener to the Cancel button inside the active trade window.
		local IsReady = self.TradeInfo.Self.IsReady -- Reads the local player's current ready status from the TradeInfo state table.
		if IsReady then -- Checks if the player is currently in the ready state rather than cancelling the entire trade.
			self.TradeRemotes.Unready:FireServer() -- Fires the Unready remote to the server to revoke the ready lock without terminating the session.
			self.HolderButtons.Accept.Title.Text = "Confirm" -- Reverts the Accept button text back to "Confirm" to reset the two-step verification UI.
		else -- Executes if the player is not ready and wants to abort the trade session completely.
			self.TradeRemotes.Cancel:FireServer() -- Fires the Cancel remote to notify the server to abort the active trade for both participants.
			self:CancelTrade() -- Invokes CancelTrade locally to clean up item containers and hide the trade window.
		end -- Closes the ready-check conditional inside the Cancel button handler.
	end) -- Closes the Cancel button click connection.

	self.InventoryFrame.Search.SearchBox.Changed:Connect(function() -- Connects a property change listener to the tower inventory SearchBox TextBox.
		self.GuiUtils.UpdateSearchedTowers(self.InventoryFrame.Search.SearchBox, self.Data.TowerData, self.InventoryFrame.Container) -- Delegates to GuiUtils to filter visible tower icons matching the current search query string.
	end) -- Closes the SearchBox Changed event connection.

	-- Server Remotes
	self.TradeRemotes.ToggleRequest.OnClientEvent:Connect(function() -- Listens for the server's confirmation event after toggling trade request privacy.
		task.defer(function() -- Defers execution to the next resumption cycle so the State manager finishes updating self.Data first.
			self:UpdateToggleButton() -- Updates the toggle button's text and background color to reflect the new ReceiveTradeRequests boolean.
		end) -- Closes the deferred callback function.
	end) -- Closes the ToggleRequest OnClientEvent listener.

	self.TradeRemotes.SendRequest.OnClientEvent:Connect(function(targetUserId) -- Listens for server confirmation that a trade request was dispatched to a target player.
		self:TradeSent(targetUserId) -- Updates the action label next to the target player's name in the list to "Sent!".
	end) -- Closes the SendRequest OnClientEvent listener.

	self.TradeRemotes.ReceiveRequest.OnClientEvent:Connect(function(playerWhoSentId) -- Listens for incoming trade requests routed from another player via the server.
		self:ReceiveTradeRequest(playerWhoSentId) -- Displays the confirmation prompt populated with the sending player's username.
	end) -- Closes the ReceiveRequest OnClientEvent listener.

	self.TradeRemotes.RespondToRequest.OnClientEvent:Connect(function(targetUserId, isAccept: boolean) -- Listens for the target player's accept or decline response from the server.
		self:ReceiveResponse(targetUserId, isAccept) -- Updates the player list status text and closes the list menu if accepted.
	end) -- Closes the RespondToRequest OnClientEvent listener.

	self.TradeRemotes.Start.OnClientEvent:Connect(function(targetUserId) -- Listens for the server signal to initialize and open an active trade session with a partner.
		self:InitialiseTrading(targetUserId) -- Sets up participant avatars, populates tradeable inventories, and displays the main trade interface.
	end) -- Closes the Start OnClientEvent listener.

	self.TradeRemotes.Unready.OnClientEvent:Connect(function() -- Listens for server replication confirming the local player has unreadied.
		self:Ready(true, false) -- Updates the local player's status indicator color to red and sets Self.IsReady to false.
	end) -- Closes the Unready OnClientEvent listener.

	self.TradeRemotes.TargetUnready.OnClientEvent:Connect(function() -- Listens for server replication indicating the trading partner has unreadied.
		self:Ready(false, false) -- Updates the target player's status indicator color to red and sets Target.IsReady to false.
	end) -- Closes the TargetUnready OnClientEvent listener.

	self.TradeRemotes.Ready.OnClientEvent:Connect(function() -- Listens for server replication confirming the local player is locked in and ready.
		self:Ready(true, true) -- Updates the local player's status indicator color to green and sets Self.IsReady to true.
	end) -- Closes the Ready OnClientEvent listener.

	self.TradeRemotes.TargetReady.OnClientEvent:Connect(function() -- Listens for server replication indicating the trading partner is locked in and ready.
		self:Ready(false, true) -- Updates the target player's status indicator color to green and sets Target.IsReady to true.
	end) -- Closes the TargetReady OnClientEvent listener.

	self.TradeRemotes.SelectTower.OnClientEvent:Connect(function(uniqueTowerId, isSelected) -- Listens for server validation when the local player selects or deselects a tower.
		self:SelectTower(uniqueTowerId, isSelected) -- Toggles the Equipped badge in inventory and adds or removes the tower clone in the local offer container.
	end) -- Closes the SelectTower OnClientEvent listener.

	self.TradeRemotes.TargetAddTower.OnClientEvent:Connect(function(towerInstance) -- Listens for server replication when the trading partner adds a tower to their offer.
		self:TargetAddTower(towerInstance) -- Generates the visual tower icon inside the partner's offer container and records it in state.
	end) -- Closes the TargetAddTower OnClientEvent listener.

	self.TradeRemotes.TargetRemoveTower.OnClientEvent:Connect(function(uniqueTowerId) -- Listens for server replication when the trading partner removes a tower from their offer.
		self:TargetRemoveTower(uniqueTowerId) -- Destroys the corresponding tower icon in the partner's offer frame and clears its key from state.
	end) -- Closes the TargetRemoveTower OnClientEvent listener.

	self.TradeRemotes.Error.OnClientEvent:Connect(function(errorMsg) -- Listens for server-dispatched trade error messages (such as cooldowns or invalid items).
		self.Notifications.Create(self.Data, errorMsg, "Red") -- Renders a red error notification banner on the client's screen using the Notifications package.
	end) -- Closes the Error OnClientEvent listener.

	self.TradeRemotes.Cancel.OnClientEvent:Connect(function() -- Listens for server notification that the trade session was cancelled by either party or disconnected.
		self:CancelTrade() -- Resets all trade UI containers, hides the main window, and restores default table states.
	end) -- Closes the Cancel OnClientEvent listener.

	self.TradeRemotes.Complete.OnClientEvent:Connect(function() -- Listens for server confirmation that the trade transaction has been finalized and items swapped.
		self:CancelTrade() -- Cleans up and closes the active trade interface by reusing the CancelTrade reset logic.
		self.Notifications.Create(self.Data, "Trade Complete!", "Green") -- Displays a green success toast notification informing the player the trade succeeded.
	end) -- Closes the Complete OnClientEvent listener.

	-- Weapon Remotes
	self.TradeRemotes.TradeWeaponRemotes.SelectWeapon.OnClientEvent:Connect(function(uniqueWeaponId, isSelected) -- Listens for server validation when the local player selects or deselects a weapon.
		self:SelectWeapon(uniqueWeaponId, isSelected) -- Toggles the weapon's Equipped badge and adds or removes its icon from the local offer frame.
	end) -- Closes the SelectWeapon OnClientEvent listener.

	self.TradeRemotes.TradeWeaponRemotes.TargetAddWeapon.OnClientEvent:Connect(function(weaponInstance) -- Listens for server replication when the trading partner adds a weapon to their offer.
		self:TargetAddWeapon(weaponInstance) -- Renders the weapon icon inside the partner's offer container and stores it in Target.SelectedWeapons.
	end) -- Closes the TargetAddWeapon OnClientEvent listener.

	self.TradeRemotes.TradeWeaponRemotes.TargetRemoveWeapon.OnClientEvent:Connect(function(uniqueWeaponId) -- Listens for server replication when the trading partner removes a weapon from their offer.
		self:TargetRemoveWeapon(uniqueWeaponId) -- Destroys the weapon icon from the partner's offer container and removes it from Target.SelectedWeapons.
	end) -- Closes the TargetRemoveWeapon OnClientEvent listener.

	task.defer(function() -- Schedules the render-loop binding to run on the next frame tick after Start setup finishes.
		RunService.PreRender:Connect(function() -- Binds a callback to RunService.PreRender to update tooltip coordinates every frame prior to rendering.
			if self.IsHovering then -- Checks if the player's cursor is currently hovering over any tower or weapon icon.
				self:UpdatePosition() -- Recalculates and clamps the tooltip Frame position relative to the current mouse coordinates.
				self.TowerInfoFrame.Visible = true -- Ensures the floating stat placard is visible while hovering.
			else -- Branches when no item slot is actively hovered.
				self.TowerInfoFrame.Visible = false -- Hides the floating stat placard when the cursor is not over an item.
			end -- Closes the hover state visibility check.
		end) -- Closes the RunService.PreRender connection.
	end) -- Closes the task.defer wrapper.
end -- Concludes the Start lifecycle method.





-- visual feedback for the player of UI when they click self.ListBackground.Requests button a remote is fired to the server
-- the server then flips the state of the boolean ReceiveTradeRequests and then a remote is fired to the self.State client data
-- manager to upd the state. at the same time the remote signal is picked up here for visual feedback
-- this is why we use task.defer() at line 184 in order to ensure the state updates first before this method can run.
-- 
function TradeController:UpdateToggleButton() -- Defines a method to synchronize the trade request toggle button visuals with client data.
	local text = if self.Data.ReceiveTradeRequests then "Trade Requests: ON" else "Trade Requests: OFF" -- Evaluates a ternary expression to select the status string based on the ReceiveTradeRequests boolean.
	self.ListBackground.Title.Text = text -- Updates the header title text of the player list window with the current request status.
	self.ListBackground.Requests.Text = text -- Updates the interactive toggle button label with the current request status.
	self.ListBackground.Requests.BackgroundColor3 = if self.Data.ReceiveTradeRequests then Color3.fromRGB(84, 255, 37) -- Sets the toggle button background to green if trade requests are enabled.
		else Color3.fromRGB(255, 73, 73) -- Sets the toggle button background to red if trade requests are disabled.
end -- Concludes the UpdateToggleButton method.

-- we clean all the visuals of the UI and reset the table states + any other booleans that need resetting
-- this method is called when the trade is cancelled or complete
function TradeController:CancelTrade() -- Defines a cleanup method to purge dynamic UI clones and reset session state after a trade ends.
	self:CleanContainer(self.OtherOfferPaddedFrame.OtherCollectionContainer) -- Destroys all dynamically cloned item buttons inside the partner's offer container.
	self:CleanContainer(self.OfferPaddedFrame.CollectionContainer) -- Destroys all dynamically cloned item buttons inside the local player's offer container.
	self:CleanContainer(self.InventoryFrame.Container) -- Destroys all generated tower icons in the local inventory scrolling container.
	self:CleanContainer(self.WeaponInventoryFrame.Container) -- Clean Weapons too -- Destroys all generated weapon icons in the local weapon inventory scrolling container.
	self.MainFrame.Visible = false -- Hides the main trading interface Frame from the screen.

	self.TradeInfo = { -- Reinitializes the TradeInfo table back to its empty default state for future trades.
		Self = { -- Resets the local player's session state sub-table.
			SelectedWeapons = {}, -- Clears the local player's selected weapons table.
			SelectedTowers = {}, -- Clears the local player's selected towers table.
			IsReady = false, -- Resets the local player's ready status boolean to false.
		}, -- Closes the Self reset sub-table.
		Target = { -- Resets the trading partner's session state sub-table.
			SelectedWeapons = {}, -- Clears the trading partner's selected weapons table.
			SelectedTowers = {}, -- Clears the trading partner's selected towers table.
			IsReady = false, -- Resets the trading partner's ready status boolean to false.
			UserId = nil, -- Clears the cached UserId of the previous trading partner.
		}, -- Closes the Target reset sub-table.
	} -- Closes the TradeInfo table reassignment.
	self.HasConfirmed = false -- Resets the two-step confirmation flag back to false.
end -- Concludes the CancelTrade method.

-- Removes the tower visual icon appearing in the other players offer
-- following the removal of a tower when the target deselects a tower
function TradeController:TargetRemoveTower(uniqueTowerId) -- Defines a method to remove a specific tower icon from the partner's offer UI by its unique ID.
	local CollectionClone = self.OtherOfferPaddedFrame.OtherCollectionContainer:FindFirstChild(uniqueTowerId) -- Searches the partner's offer container for a child UI element matching the uniqueTowerId.
	if CollectionClone then -- Verifies that the UI clone exists in the container before attempting removal.
		CollectionClone:Destroy() -- Destroys the tower UI instance and disconnects its associated hover signals.
	end -- Closes the existence check for CollectionClone.
	self.TradeInfo.Target.SelectedTowers[uniqueTowerId] = nil -- Removes the tower entry from the target player's client-side state dictionary.
end -- Concludes the TargetRemoveTower method.


-- Removes the Weapon visual icon appearing in the other players offer
-- following the removal of a weapon when the target deselects a weapon
function TradeController:TargetRemoveWeapon(uniqueWeaponId) -- Defines a method to remove a specific weapon icon from the partner's offer UI by its unique ID.
	local CollectionClone = self.OtherOfferPaddedFrame.OtherCollectionContainer:FindFirstChild(uniqueWeaponId) -- Searches the partner's offer container for a child UI element matching the uniqueWeaponId.
	if CollectionClone then -- Verifies that the weapon UI clone exists before attempting destruction.
		CollectionClone:Destroy() -- Destroys the weapon UI clone from the partner's offer container.
	end -- Closes the existence check for CollectionClone.
	self.TradeInfo.Target.SelectedWeapons[uniqueWeaponId] = nil -- Removes the weapon entry from the target player's client-side state dictionary.
end -- Concludes the TargetRemoveWeapon method.

-- Adds the tower visual icon appearing in the other players offer
-- following the adding of a tower when the target selects a tower to be traded
function TradeController:TargetAddTower(towerInstance) -- Defines a method to render a newly added tower in the trading partner's offer container.
	self:GenerateTower(towerInstance, self.OtherOfferPaddedFrame.OtherCollectionContainer, false) -- Generates a non-clickable tower icon inside the partner's offer container.
	self.TradeInfo.Target.SelectedTowers[towerInstance.UniqueTowerID] = towerInstance -- Records the tower data instance in the target player's SelectedTowers state table.
end -- Concludes the TargetAddTower method.

-- Adds the Weapon visual icon appearing in the other players offer
-- following the adding of a weapon when the target selects a weapon to be traded
function TradeController:TargetAddWeapon(weaponInstance) -- Defines a method to render a newly added weapon in the trading partner's offer container.
	self:GenerateWeapon(weaponInstance, self.OtherOfferPaddedFrame.OtherCollectionContainer, false) -- Generates a non-clickable weapon icon inside the partner's offer container.
	self.TradeInfo.Target.SelectedWeapons[weaponInstance.UniqueWeaponID] = weaponInstance -- Records the weapon data instance in the target player's SelectedWeapons state table.
end -- Concludes the TargetAddWeapon method.

-- if selected:
-- Adds the tower visual icon appearing in the current client (self) offer
-- following the adding of a tower when the client selects a tower to be traded (and once server validated)

-- if not selected the tower visual destroyed -- client (self) removed tower from offer
function TradeController:SelectTower(uniqueTowerId, isSelected) -- Defines a method to update the local inventory and offer UI when a tower's selection state changes.
	local TowerInstance = self.Data.TowerData[uniqueTowerId] -- Looks up the tower data object in the local player's TowerData dictionary using its unique ID.
	if not TowerInstance then return end -- Aborts execution if the tower ID does not exist in the client's data table.

	local InventoryClone = self.InventoryFrame.Container:FindFirstChild(uniqueTowerId) -- Finds the corresponding tower button inside the player's inventory container.
	if InventoryClone then -- Checks if the inventory slot UI element exists.
		InventoryClone.Equipped.Visible = isSelected -- Toggles the checkmark/Equipped overlay visibility to match the selection boolean.
	end -- Closes the InventoryClone check.

	if isSelected then -- Branches if the tower was newly added to the trade offer.
		self:GenerateTower(TowerInstance, self.OfferPaddedFrame.CollectionContainer, false) -- Creates a visual clone of the tower inside the local player's active offer container.
	else -- Branches if the tower was deselected and removed from the trade offer.
		local CollectionClone = self.OfferPaddedFrame.CollectionContainer:FindFirstChild(uniqueTowerId) -- Searches the local offer container for the deselected tower's UI clone.
		if CollectionClone then -- Verifies the offer clone exists before destroying it.
			CollectionClone:Destroy() -- Removes the tower icon from the local player's offer container.
		end -- Closes the CollectionClone existence check.
	end -- Closes the isSelected conditional branch.
end -- Concludes the SelectTower method.

-- if selected:
-- Adds the weapon visual icon appearing in the current client (self) offer
-- following the adding of a weapon when the client selects a weapon to be traded (and once server validated)

-- -- if not selected the weapon visual destroyed -- client (self) removed weapon from offer
function TradeController:SelectWeapon(uniqueWeaponId, isSelected) -- Defines a method to update the local inventory and offer UI when a weapon's selection state changes.
	local WeaponInstance = self.Data.WeaponData[uniqueWeaponId] -- Retrieves the weapon's data table from the local player's WeaponData using its unique ID.
	if not WeaponInstance then return end -- Returns early if the weapon data cannot be found in client state.

	local InventoryClone = self.WeaponInventoryFrame.Container:FindFirstChild(uniqueWeaponId) -- Locates the weapon's button instance inside the weapon inventory container.
	if InventoryClone then -- Verifies that the inventory button instance exists.
		InventoryClone.Equipped.Visible = isSelected -- Sets the visibility of the Equipped indicator overlay based on whether the weapon is selected.
	end -- Closes the InventoryClone existence check.

	if isSelected then -- Branches if the weapon was selected for the trade offer.
		self:GenerateWeapon(WeaponInstance, self.OfferPaddedFrame.CollectionContainer, false) -- Instantiates a visual weapon icon inside the local player's offer container.
	else -- Branches if the weapon was deselected from the trade offer.
		local CollectionClone = self.OfferPaddedFrame.CollectionContainer:FindFirstChild(uniqueWeaponId) -- Searches the local offer container for the weapon UI clone matching uniqueWeaponId.
		if CollectionClone then -- Checks if the weapon clone was found in the offer container.
			CollectionClone:Destroy() -- Destroys the weapon icon from the local offer container.
		end -- Closes the CollectionClone check.
	end -- Closes the isSelected conditional block.
end -- Concludes the SelectWeapon method.


-- optimised function which can be is utilised for both target player and self player
-- used when a client self or target readys or unreadys
-- client must click the button twice: once to confirm (set self.HasConfirmed = true) 
-- seconds actually confirms the clients ready state for the server
-- we also update the state of the tradeInfo table following the remote event declaring the client and target states
-- from the server

function TradeController:Ready(isSelf: boolean, isReady: boolean) -- Defines a shared method to update ready status colors and state flags for either trade participant.
	local TiteLabel = if isSelf then self.TitleLabel else self.OtherTitleLabel -- Selects either the local player's or partner's header label based on the isSelf boolean.
	TiteLabel.ImageColor3 = if isReady then Color3.fromRGB(26, 255, 0) else Color3.fromRGB(255, 0, 0) -- Colors the header banner green if ready or red if unready.

	if isSelf then -- Checks if the state change applies to the local player.
		if not isReady then -- Checks if the local player is transitioning to an unready state.
			self.HasConfirmed = false -- Resets the local two-step confirmation flag so the player must confirm again before readying.
		end -- Closes the inner not isReady check.
	end -- Closes the isSelf check.

	local Index = if isSelf then "Self" else "Target" -- Determines the appropriate key string ("Self" or "Target") to index into self.TradeInfo.
	self.TradeInfo[Index].IsReady = isReady -- Updates the IsReady boolean inside the corresponding participant's state table.
end -- Concludes the Ready method.

-- closes the TradeList which showcases who u can invite to trade once a trade has commenced
-- this function can be thought as the master function for setting all the visuals for the trade sequence to begin
function TradeController:InitialiseTrading(targetUserId) -- Defines the master setup method called when a trade session officially begins with a target player.
	local TargetPlayer = Players:GetPlayerByUserId(targetUserId) -- Resolves the partner's Player instance from the Players service using their numerical UserId.
	if not TargetPlayer then return end -- Aborts initialization if the target player has left the server.
	self.HasConfirmed = false -- Resets the local confirmation state flag at the start of a fresh trade.

	self:UpdateMainTitles(TargetPlayer) -- Fetches player headshots and updates both participants' header banners and names.
	self:GenerateInventoryContainer() -- Populates the tower and weapon inventory containers with all trade-eligible items.
	self.MainFrame.Visible = true -- Makes the primary trade interface visible to the player.
	self:HideShop(self.List, self.List.UIScale) -- Closes the player list modal and removes the background blur effect.
end -- Concludes the InitialiseTrading method.

-- gets all Towers and weapons tradeable (not locked or equipped)
-- we update the layout using the utility module i created
-- it sorts the towers and weapons in order from Mythic --> common

function TradeController:GenerateInventoryContainer() -- Defines a method to populate and sort the local player's tradeable tower and weapon inventories.
	local Towers = self.TradeConfig.GetTradeableTowers(self.Data) -- Calls TradeConfig to filter out equipped or locked towers and return a table of tradeable towers.
	if not Towers then return end -- Returns early if no tradeable towers table is returned.

	local Weapons = self.TradeConfig.GetTradeableWeapons(self.Data) -- Calls TradeConfig to filter out equipped or locked weapons and return tradeable weapons.
	if not Weapons then return end -- Returns early if no tradeable weapons table is returned.

	for _, towerInstance in Towers do -- Iterates through each trade-eligible tower data structure in the filtered table.
		self:GenerateTower(towerInstance, self.InventoryFrame.Container, true) -- Creates an interactive tower slot in the inventory container with click-to-select enabled.
	end -- Concludes the tradeable towers loop.

	self.GuiUtils.UpdateLayout(self.InventoryFrame.Container, self.Data) -- Assigns LayoutOrder values to sort tower icons from Mythic down to Common rarity.

	for _, weaponInstance in Weapons do -- Iterates through each trade-eligible weapon data structure in the filtered table.
		self:GenerateWeapon(weaponInstance, self.WeaponInventoryFrame.Container, true) -- Creates an interactive weapon slot in the weapon inventory container with click-to-select enabled.
	end -- Concludes the tradeable weapons loop.

	self.GuiUtils.UpdateWeaponLayout(self.WeaponInventoryFrame.Container, self.Data) -- Assigns LayoutOrder values to sort weapon icons by rarity tier.
end -- Concludes the GenerateInventoryContainer method.


-- function to generate individual weapon icon found in players inventory (that is tradeable)
function TradeController:GenerateWeapon(weaponInstance, container, isInventory: boolean) -- Defines a factory method to clone, configure, and bind events for a weapon UI slot.
	local ConfigWeapon = self.WeaponConfig.GetConfig(weaponInstance.Model) -- Fetches static weapon configuration data (such as Rarity) using the weapon's model identifier.
	local Clone = container.Template:Clone() -- Clones the hidden Template TextButton inside the target container.
	Clone.Name = weaponInstance.UniqueWeaponID -- Assigns the weapon's UniqueWeaponID as the clone's instance Name for fast lookup.
	Clone.Icon.Image = self.RARITY_IMAGES[ConfigWeapon.Rarity] -- Sets the slot's background image to the decal matching the weapon's rarity tier.
	
	local nameLabel = Clone:FindFirstChild("WeaponName") or Clone:FindFirstChild("TowerName") -- Searches the cloned template for either a WeaponName or fallback TowerName TextLabel.
	if nameLabel then -- Verifies that a valid name TextLabel was found on the template clone.
		nameLabel.Text = weaponInstance.Model -- Sets the label text to display the weapon's model name.
	end -- Closes the nameLabel existence check.

	Clone.StarLevel.Text = weaponInstance.StarLevel -- Displays the weapon's upgrade StarLevel on the slot's StarLevel label.
	local Model = self.WeaponConfig.GetModel(weaponInstance) -- Retrieves a clone of the 3D weapon Model instance from WeaponConfig for viewport rendering.

	task.defer(function() -- Defers viewport camera calculation to avoid blocking the current UI generation thread.
		self.ViewportModel.GenerateViewport(Clone.Icon.ViewportFrame, Model, CFrame.Angles(0, math.rad(0), 0)) -- Renders the 3D weapon model inside the slot's ViewportFrame with zero rotational offset.
	end) -- Closes the deferred viewport generation task.

	Clone.Parent = container -- Parents the configured weapon slot clone into the specified UI container.
	Clone.Visible = true -- Makes the cloned weapon slot visible in the UI hierarchy.

	if isInventory then -- Checks if this slot resides in the player's clickable inventory rather than an offer display box.
		Clone.MouseButton1Click:Connect(function() -- Connects a left-click listener to allow selecting or deselecting the weapon for trade.
			self.TradeRemotes.TradeWeaponRemotes.SelectWeapon:FireServer(weaponInstance.UniqueWeaponID) -- Fires the SelectWeapon remote to the server with the weapon's unique ID for validation.
		end) -- Closes the MouseButton1Click connection.
	end -- Closes the isInventory conditional check.

	Clone.MouseEnter:Connect(function() -- Binds a hover-enter listener to dim the icon and display the weapon stats tooltip.
		local h, s, v = Clone.Icon.ImageColor3:ToHSV() -- Decomposes the current icon ImageColor3 into Hue, Saturation, and Value components.
		v = 0.5 -- Reduces the brightness Value component to 0.5 to create a darkened hover highlight effect.
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v) -- Applies the darkened HSV color back to the slot's Icon image.
		-- Fixed: Was using TowerConfig instead of WeaponConfig.GunInfo
		local WeaponInfo = self.WeaponConfig.GunInfo(weaponInstance) -- Retrieves formatted weapon statistics from WeaponConfig for the hovered weapon instance.
		self.TowerInfoOrganizer(WeaponInfo, self.TowerInfoFrame) -- Populates the floating tooltip Frame labels with the weapon's statistics.
		self.IsHovering = true -- Sets the IsHovering flag to true so the PreRender loop makes the tooltip visible and tracks the cursor.
		self:UpdatePosition() -- Immediately snaps the tooltip Frame to the current cursor coordinates on hover start.

		for _, effect in self.ActiveHoverEffects do -- Iterates over any previously active EasyVisuals effects stored in the tracking array.
			effect:Destroy() -- Destroys each old visual effect instance to prevent memory leaks or stacked gradients.
		end -- Closes the cleanup loop for existing hover effects.
		table.clear(self.ActiveHoverEffects) -- Empties the ActiveHoverEffects array after destroying the old instances.

		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "Shine", 0.25, 1, true, Color3.fromRGB(0, 0, 0))) -- Applies an animated Shine gradient effect to the tooltip frame and tracks it for cleanup.
		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "GoldStroke", 1, 5)) -- Applies an animated GoldStroke border effect to the tooltip frame and tracks it for cleanup.
	end) -- Closes the MouseEnter connection for the weapon slot.

	Clone.MouseLeave:Connect(function() -- Binds a hover-exit listener to restore icon brightness and clean up tooltip effects.
		local h, s, v = Clone.Icon.ImageColor3:ToHSV() -- Extracts the Hue, Saturation, and Value components of the darkened icon color.
		v = 1 -- Restores the brightness Value component back to full intensity (1).
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v) -- Reapplies the full-brightness color to the weapon slot icon.
		self.IsHovering = false -- Sets IsHovering to false so the PreRender loop hides the tooltip frame.

		for _, effect in self.ActiveHoverEffects do -- Loops through all active EasyVisuals instances created during MouseEnter.
			effect:Destroy() -- Destroys each EasyVisuals effect instance to stop its internal RunService animations.
		end -- Closes the effect cleanup loop.
		table.clear(self.ActiveHoverEffects) -- Clears all references from the ActiveHoverEffects table.
	end) -- Closes the MouseLeave connection for the weapon slot.
end -- Concludes the GenerateWeapon method.

-- function to generate individual Tower icon found in players inventory (that is tradeable)
function TradeController:GenerateTower(towerInstance, container, isInventory: boolean) -- Defines a factory method to clone, configure, and bind events for a tower UI slot.
	local ConfigTower = self.TowerConfig.GetConfig(towerInstance.Model) -- Retrieves static configuration data (such as Rarity) for the tower's model type.
	local Clone = container.Template:Clone() -- Clones the invisible Template button inside the target container.
	Clone.Name = towerInstance.UniqueTowerID -- Sets the clone's Name to the tower's UniqueTowerID for direct indexing.
	Clone.Icon.Image = self.RARITY_IMAGES[ConfigTower.Rarity] -- Assigns the rarity background image corresponding to the tower's rarity tier.
	Clone.TowerName.Text = towerInstance.Model -- Sets the TowerName label text to the tower's model identifier.
	Clone.StarLevel.Text = towerInstance.StarLevel -- Sets the StarLevel label text to show the tower's current star rating.
	local Model = self.TowerConfig.GetModel(towerInstance) -- Fetches a 3D Model instance of the tower from TowerConfig for the viewport preview.

	self.ViewportModel.GenerateViewport(Clone.Icon.ViewportFrame, Model, CFrame.Angles(0, math.rad(-90), 0)) -- Positions and renders the 3D tower model inside the ViewportFrame rotated -90 degrees on the Y-axis.

	Clone.Parent = container -- Parents the configured tower button clone into the target UI container.
	Clone.Visible = true -- Makes the cloned tower button visible in the container.

	if isInventory then -- Checks if the tower icon is being generated inside the interactive inventory panel.
		Clone.MouseButton1Click:Connect(function() -- Connects a click listener allowing the player to toggle the tower in their trade offer.
			self.TradeRemotes.SelectTower:FireServer(towerInstance.UniqueTowerID) -- Fires the SelectTower remote to the server passing the tower's unique ID.
		end) -- Closes the MouseButton1Click connection.
	end -- Closes the isInventory conditional check.

	Clone.MouseEnter:Connect(function() -- Connects a hover-enter listener to darken the slot icon and populate the tower tooltip.
		local h, s, v = Clone.Icon.ImageColor3:ToHSV() -- Converts the current icon ImageColor3 into HSV components.
		v = 0.5 -- Halves the Value component to visually dim the slot background while hovered.
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v) -- Updates the icon's ImageColor3 with the dimmed HSV color.
		local TowerInfo = self.TowerConfig.TowerInfo(towerInstance) -- Queries TowerConfig for the specific combat stats of the hovered tower instance.
		self.TowerInfoOrganizer(TowerInfo, self.TowerInfoFrame) -- Formats and writes the tower's stats into the floating TowerInfoFrame tooltip.
		self.IsHovering = true -- Flags IsHovering as true to activate tooltip visibility and mouse tracking in PreRender.
		self:UpdatePosition() -- Updates the tooltip position immediately to prevent a single-frame jump.

		for _, effect in self.ActiveHoverEffects do -- Iterates over any lingering EasyVisuals effects in the tracking table.
			effect:Destroy() -- Cleans up each active visual effect instance.
		end -- Closes the effect destruction loop.
		table.clear(self.ActiveHoverEffects) -- Empties the ActiveHoverEffects tracking table.

		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "Shine", 0.25, 1, true, Color3.fromRGB(0, 0, 0))) -- Instantiates a Shine visual effect on the tooltip frame and stores it for cleanup.
		table.insert(self.ActiveHoverEffects, self.EzVisuals.new(self.TowerInfoFrame, "GoldStroke", 1, 5)) -- Instantiates a GoldStroke border effect on the tooltip frame and stores it for cleanup.
	end) -- Closes the MouseEnter connection for the tower slot.

	Clone.MouseLeave:Connect(function() -- Connects a hover-exit listener to restore the icon color and hide the tooltip.
		local h, s, v = Clone.Icon.ImageColor3:ToHSV() -- Reads the HSV values of the dimmed icon color.
		v = 1 -- Resets the Value brightness component back to 1.
		Clone.Icon.ImageColor3 = Color3.fromHSV(h, s, v) -- Restores the icon's original un-dimmed ImageColor3.
		self.IsHovering = false -- Sets IsHovering to false so the PreRender loop hides the tooltip frame.

		for _, effect in self.ActiveHoverEffects do -- Loops over the active EasyVisuals effects applied during hover.
			effect:Destroy() -- Destroys each effect instance to halt its UI animations.
		end -- Closes the effect cleanup loop.
		table.clear(self.ActiveHoverEffects) -- Purges all entries from the ActiveHoverEffects array.
	end) -- Closes the MouseLeave connection for the tower slot.
end -- Concludes the GenerateTower method.

-- Updates visuals of both the target player trade offer title + self offer title
function TradeController:UpdateMainTitles(targetPlayer) -- Defines a method to initialize the header titles, status colors, and avatar thumbnails for both traders.
	self.HolderButtons.Accept.Title.Text = "Confirm" -- Resets the primary action button text to "Confirm" for the initial confirmation step.
	local ImageSize = Enum.ThumbnailSize.Size420x420 -- Specifies the 420x420 pixel resolution enum for fetching player avatar thumbnails.
	local ImageType = Enum.ThumbnailType.HeadShot -- Specifies the HeadShot thumbnail type enum to fetch a portrait of the player's avatar.
	local content = Players:GetUserThumbnailAsync(self.Player.UserId, ImageType, ImageSize) -- Yields to fetch the local player's headshot thumbnail URI from the Roblox web API.
	self.TitleLabel.Icon.Image = content -- Assigns the fetched headshot URI to the local player's header avatar ImageLabel.
	self.TitleLabel.ImageColor3 = Color3.fromRGB(255, 0, 0) -- Sets the local player's header banner color to red to indicate an unready initial state.

	local targetContent = Players:GetUserThumbnailAsync(targetPlayer.UserId, ImageType, ImageSize) -- Yields to fetch the trading partner's headshot thumbnail URI from the Roblox API.
	self.OtherTitleLabel.Icon.Image = targetContent -- Assigns the partner's headshot URI to the target player's header avatar ImageLabel.
	self.OtherTitleLabel.ImageColor3 = Color3.fromRGB(255, 0, 0) -- Sets the trading partner's header banner color to red to indicate an unready initial state.
	self.OtherTitleLabel.Title.Text = `{targetPlayer.Name}'s Offer:` -- Uses Luau string interpolation to format the partner's offer header with their username.
end -- Concludes the UpdateMainTitles method.


-- once target player procceses response and server handles and tells self client the response
function TradeController:ReceiveResponse(userId: number, isAccept: boolean) -- Defines a method to handle the UI feedback when another player responds to a sent trade request.
	if isAccept then -- Checks if the target player accepted the trade invitation.
		self:HideShop(self.List, self.List.UIScale) -- Closes the player list menu so the main trade window can take focus.
		self.ConfirmationFrame.Visible = false -- Hides any open trade confirmation modal on the screen.
	end -- Closes the isAccept conditional check.

	local Clone = self.ListBackground.Container:FindFirstChild(tostring(userId)) -- Searches the player list container for the row matching the responding player's UserId string.
	if not Clone then return end -- Exits early if the player row no longer exists in the list container.

	Clone.Action.Text = if isAccept then "Accepted!" else "Declined" -- Sets the row's status text to "Accepted!" or "Declined" based on the boolean response.

	task.delay(5, function() -- Schedules a delayed callback to execute after 5 seconds without yielding the current thread.
		if Clone then -- Verifies that the player row instance still exists in memory after the 5-second delay.
			Clone.Action.Text = "" -- Clears the temporary response status text from the player row.
		end -- Closes the Clone existence check.
	end) -- Closes the task.delay callback.
end -- Concludes the ReceiveResponse method.

-- if target player sends trade request to the self player the server handles and sends a response to the self client
function TradeController:ReceiveTradeRequest(userId) -- Defines a method to display the incoming trade invitation popup from another player.
	local PlayerWhoSent = Players:GetPlayerByUserId(userId) -- Looks up the sender's Player instance in the server using their UserId.
	if not PlayerWhoSent then return end -- Ignores the request if the sending player has already left the game.
	self.LastRequestReceived = userId -- Caches the sender's UserId so the Yes/No buttons know which player to respond to.
	self.ConfirmationFrame.Subtitle.Text = self.RECEIVE_REQUEST_TEXT:gsub("NAME", PlayerWhoSent.Name) -- Replaces the "NAME" token in the template string with the sender's username.
	self.ConfirmationFrame.Visible = true -- Displays the incoming trade request confirmation modal on the screen.

	task.delay(15, function() -- Starts a 15-second non-blocking timer to auto-expire the trade request prompt.
		if self.LastRequestReceived == userId then -- Checks if the active request is still the same one from 15 seconds ago (not overwritten by a newer request).
			self.ConfirmationFrame.Visible = false -- Automatically hides the confirmation prompt upon expiration.
			self.LastRequestReceived = nil -- Clears the cached sender UserId after the request times out.
		end -- Closes the expiration identity check.
	end) -- Closes the 15-second task.delay callback.
end -- Concludes the ReceiveTradeRequest method.

-- if self player sends a trade request server handles it and tells the client the trade was successfully sent
function TradeController:TradeSent(userId: number) -- Defines a method to show temporary visual feedback when a trade request is sent to a player.
	local Clone = self.ListBackground.Container:FindFirstChild(tostring(userId)) -- Finds the target player's entry row inside the player list container by UserId.
	if not Clone then return end -- Returns early if the target player's UI row is not found.

	Clone.Action.Text = "Sent!" -- Updates the row's Action label to inform the user the request was transmitted.

	task.delay(15, function() -- Schedules a cleanup function to run after a 15-second cooldown period.
		if Clone then -- Checks that the UI row instance has not been destroyed during the 15-second wait.
			Clone.Action.Text = "" -- Resets the Action label text back to an empty string.
		end -- Closes the Clone validity check.
	end) -- Closes the task.delay block.
end -- Concludes the TradeSent method.

-- function used to clean all elements of a weapon trade container or tower trade container
-- except the Template of said container which is needed to act as a base for which each weapon/tower is cloned and shown
function TradeController:CleanContainer(container) -- Defines a utility method to purge dynamically generated TextButtons from a UI container while preserving layout components.
	for _, child in container:GetChildren() do -- Iterates through all direct child instances of the provided container Frame.
		if child.Name == "Template" or not child:IsA("TextButton") then continue end -- Skips the reusable Template button and any non-button layout instances (like UIGridLayout).
		child:Destroy() -- Destroys the dynamically generated item or player button clone.
	end -- Concludes the container children cleanup loop.
end -- Concludes the CleanContainer method.

-- initialises list containing every1 in the server 
-- we use an if statment to ensure the client self cant send a request to the client itself!
function TradeController:InitialiseList() -- Defines a method to populate the trade player list modal with buttons for every other player in the server.
	self:CleanContainer(self.ListBackground.Container) -- Purges any stale player entries from the list container before rebuilding it.
	for _, player in Players:GetPlayers() do -- Iterates through the array of all currently connected Player instances in the server.
		if player == self.Player then continue end -- Skips the local player so they cannot send a trade request to themselves.
		local Clone = self.ListBackground.Container.Template:Clone() -- Clones the hidden player row Template inside the list container.
		Clone.Name = player.UserId -- Assigns the player's numerical UserId (coerced to string) as the clone's Name for status lookups.
		Clone.Player.Text = player.Name -- Sets the row's Player label text to display the player's Roblox username.
		Clone.Action.Text = "" -- Initializes the status Action label as an empty string.
		Clone.Parent = self.ListBackground.Container -- Parents the populated player row into the scrolling list container.
		Clone.Visible = true -- Makes the cloned player row visible to the user.

		Clone.MouseButton1Click:Connect(function() -- Connects a left-click listener to the player row to initiate a trade request.
			self.TradeRemotes.SendRequest:FireServer(player.UserId) -- Fires the SendRequest remote to the server passing the clicked player's UserId.
		end) -- Closes the MouseButton1Click connection for the player row.
	end -- Concludes the Players iteration loop.
end -- Concludes the InitialiseList method.

-- function used to create a pop out effect when trade menu opens + adds blur effect aswell
function TradeController:ShowShop(shop, shopScale) -- Defines a UI transition method to animate opening a menu frame with an elastic pop-out and camera blur.
	self.OpenListState = true -- Sets the state flag to true indicating the player list menu is open.
	if self._openTween then self._openTween:Cancel() end -- Cancels any currently running open tween to avoid conflicting scale interpolations.
	local Blur = self.Camera:FindFirstChild("Blur") or Instance.new("BlurEffect") -- Retrieves the existing BlurEffect from the Camera or instantiates a new one if absent.
	Blur.Name = "Blur" -- Ensures the BlurEffect instance is named "Blur" for subsequent lookups.
	Blur.Size = 24 -- Sets the depth-of-field blur intensity to 24 to obscure the background gameplay.
	Blur.Enabled = true -- Enables the camera BlurEffect while the modal is open.
	Blur.Parent = self.Camera -- Parents the BlurEffect to Workspace.CurrentCamera so it renders on screen.
	shop.Visible = true -- Makes the target menu Frame visible prior to playing the scale animation.
	shopScale.Scale = 0.8 -- Initializes the UIScale multiplier at 80% size for the start of the pop-out animation.
	self._openTween = TweenService:Create(shopScale, TweenInfo.new(0.9, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1.0 }) -- Creates an Elastic Out tween interpolating the UIScale from 0.8 to 1.0 over 0.9 seconds.
	self._openTween:Play() -- Plays the elastic opening tween.
end -- Concludes the ShowShop method.

-- function used to create a pop in effect when trade menu closes + blur effect is removed
function TradeController:HideShop(shop, shopScale) -- Defines a UI transition method to animate closing a menu frame and disabling the camera blur.
	self.OpenListState = false -- Sets the state flag to false indicating the player list menu is closed.
	if self._openTween then self._openTween:Cancel() end -- Cancels any in-progress opening tween so it does not override the closing animation.
	local Blur = self.Camera:FindFirstChild("Blur") -- Searches the CurrentCamera for the active BlurEffect instance.
	if Blur then Blur.Enabled = false end -- Disables the background blur effect immediately upon closing the menu.
	local shrink = TweenService:Create(shopScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }) -- Creates a fast 0.15-second Quad In tween shrinking the UIScale down to 0.9.
	shrink.Completed:Once(function() -- Connects a one-time listener that fires as soon as the shrink tween finishes playing.
		shop.Visible = false -- Hides the menu Frame completely after the shrink animation completes.
		shopScale.Scale = 0.5 -- Resets the UIScale multiplier to 0.5 while hidden.
	end) -- Closes the Completed:Once callback.
	shrink:Play() -- Starts playing the closing shrink tween.
end -- Concludes the HideShop method.

-- Used in the function when tower or weapon instances are visually generated
-- specifically used when an instance is hovered over .MouseEnter
-- a placard containing the stats of said instance pop ups 
-- this function allows the placard to dynamically move following the mouse
-- the placard disappears and stops folloeing once .MouseLeave is triggered.
function TradeController:UpdatePosition() -- Defines a method to calculate and clamp the floating tooltip's screen coordinates to follow the cursor.
	local ScreenSize = workspace.CurrentCamera.ViewportSize -- Reads the current 2D pixel resolution of the client's screen viewport.
	local FrameSize = self.TowerInfoFrame.AbsoluteSize -- Reads the rendered pixel width and height of the tooltip Frame.

	local PositionX = math.clamp(self.Mouse.X + self.OffsetX, self.Padding, ScreenSize.X - FrameSize.X - self.Padding) -- Calculates the horizontal cursor position with offset and clamps it within left/right screen margins.
	local PositionY = math.clamp(self.Mouse.Y + self.OffsetY, self.Padding, ScreenSize.Y - FrameSize.Y - self.Padding) -- Calculates the vertical cursor position with offset and clamps it within top/bottom screen margins.
	self.TowerInfoFrame.Position = UDim2.fromOffset(PositionX, PositionY) -- Applies the clamped X and Y pixel coordinates to the tooltip Frame's Position property.
end -- Concludes the UpdatePosition method.

return TradeController -- Exports the TradeController module table so the module loader can initialize and start it.
