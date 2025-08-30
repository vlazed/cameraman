AddCSLuaFile()

local cameraClasses = {
	["gmod_cameraprop"] = true,
	["hl_camera"] = true,
}

local driveModes = {
	{ "drive_drone", "Drone", "icon16/joystick.png" },
	{ "drive_handheld", "Handheld", "icon16/joystick.png" },
}

local function addCameraDriveMode(driveInfo, count)
	local driveMode = driveInfo[1]
	local label = driveInfo[2]
	local icon = driveInfo[3]

	properties.Add(driveMode, {
		MenuLabel = label,
		Order = count,
		MenuIcon = icon,

		Filter = function(self, ent, ply)
			if not IsValid(ent) or not IsValid(ply) then
				return false
			end
			if ent:IsPlayer() or IsValid(ply:GetVehicle()) then
				return false
			end
			if not gamemode.Call("CanProperty", ply, "drive", ent) then
				return false
			end
			if not gamemode.Call("CanDrive", ply, ent) then
				return false
			end

			if not cameraClasses[ent:GetClass()] then
				return false
			end
			-- We cannot drive these, maybe this should have a custom GetEntityDriveMode?
			if ent:GetClass() == "prop_vehicle_jeep" or ent:GetClass() == "prop_vehicle_jeep_old" then
				return false
			end

			-- Make sure nobody else is driving this or we can get into really invalid states
			for id, pl in player.Iterator() do
				if pl:GetDrivingEntity() == ent then
					return false
				end
			end

			return true
		end,

		Action = function(self, ent)
			self:MsgStart()
			net.WriteEntity(ent)
			self:MsgEnd()
		end,

		Receive = function(self, length, ply)
			local ent = net.ReadEntity()
			if not properties.CanBeTargeted(ent, ply) then
				return
			end
			if not self:Filter(ent, ply) then
				return
			end

			local drivemode = driveMode

			if ent.GetEntityDriveMode then
				drivemode = ent:GetEntityDriveMode(ply)
			end

			drive.PlayerStartDriving(ply, ent, drivemode)
		end,
	})
end

local count = 1100
for _, driveInfo in ipairs(driveModes) do
	count = count + 1
	addCameraDriveMode(driveInfo, count)
end
