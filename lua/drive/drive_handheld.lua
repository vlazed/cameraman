AddCSLuaFile()

DEFINE_BASECLASS("drive_base")

local math_sin = math.sin
local math_cos = math.cos
local math_abs = math.abs
local math_deg = math.deg

---@alias WaveFunction fun(A: number, omega: number, phi: number, t: number): number

---@type WaveFunction
local function sin(A, omega, phi, t)
	return A * math_sin(omega * t + phi)
end

---@type WaveFunction
local function rectified_sin(A, omega, phi, t)
	return math_abs(A * math_sin(omega * t + phi))
end

---@type WaveFunction
local function rectified_sin_invert(A, omega, phi, t)
	return -rectified_sin(A, omega, phi, t)
end

---@type WaveFunction
local function square(A, omega, phi, t)
	local phase = math.fmod(t * omega + phi, 1)

	if phase < 0.5 then
		return A
	else
		return -A
	end
end

local methods = {
	sine = sin,
	rectified_sine = rectified_sin,
	rectified_sine_invert = rectified_sin_invert,
	square = square,
}

drive.Register("drive_handheld", {
	--
	-- Called on creation
	--
	Init = function(self)
		self.CameraDist = 4
		self.CameraDistVel = 0.1
		self.CameraShake = Angle(0)
		self.CameraNoise = Angle(0)
	end,

	--
	-- Calculates the view when driving the entity
	--
	CalcView = function(self, view)
		--
		-- Use the utility method on drive_base.lua to give us a 3rd person view
		--
		local idealdist = math.max(10, self.Entity:BoundingRadius()) * self.CameraDist

		self:CalcView_ThirdPerson(view, idealdist, 2, { self.Entity })

		view.angles.roll = 0
	end,

	---@param self any
	---@param cmd CUserCmd
	SetupControls = function(self, cmd)
		--
		-- If we're holding the reload key down then freeze the view angles
		--
		if cmd:KeyDown(IN_RELOAD) then
			self.CameraForceViewAngles = self.CameraForceViewAngles or cmd:GetViewAngles()

			cmd:SetViewAngles(self.CameraForceViewAngles)
		else
			self.CameraForceViewAngles = nil
		end

		--
		-- Zoom out when we use the mouse wheel (this is completely clientside, so it's ok to use a lua var!!)
		--
		self.CameraDistVel = self.CameraDistVel + cmd:GetMouseWheel() * -0.5

		self.CameraDist = self.CameraDist + self.CameraDistVel * FrameTime()
		self.CameraDist = math.Clamp(self.CameraDist, 2, 20)
		self.CameraDistVel = math.Approach(self.CameraDistVel, 0, self.CameraDistVel * FrameTime() * 2)
	end,
	--
	-- Called before each move. You should use your entity and cmd to
	-- fill mv with information you need for your move.
	--
	---@param self any
	---@param mv CMoveData
	---@param cmd CUserCmd
	StartMove = function(self, mv, cmd)
		--
		-- Set the observer mode to chase so that the entity is drawn
		--
		self.Player:SetObserverMode(OBS_MODE_CHASE)

		--
		-- Use (E) was pressed - stop it.
		--
		if mv:KeyReleased(IN_USE) then
			self:Stop()
		end

		--
		-- Update move position and velocity from our entity
		--
		mv:SetOrigin(self.Entity:GetNetworkOrigin())
		mv:SetVelocity(self.Entity:GetAbsVelocity())
		mv:SetMoveAngles(mv:GetAngles()) -- Always move relative to the player's eyes

		local entity_angle = mv:GetAngles()
		entity_angle.roll = self.Entity:GetAngles().roll

		--
		-- Right mouse button is down, don't change the angle of the object
		--
		if mv:KeyDown(IN_ATTACK2) or mv:KeyReleased(IN_ATTACK2) then
			entity_angle = self.Entity:GetAngles()
		end

		--
		-- If reload is down then spin the object around
		--
		if mv:KeyDown(IN_RELOAD) then
			entity_angle.roll = entity_angle.roll + cmd:GetMouseX() * 0.01
		end

		--
		-- Right mouse button was released
		--
		if mv:KeyReleased(IN_ATTACK2) then
			self.Player:SetEyeAngles(self.Entity:GetAngles())
		end

		local method = GetConVar("cameraman_motionmethod"):GetString()
		local motionScale = GetConVar("cameraman_motionscale"):GetFloat()
		local speedScale = GetConVar("cameraman_speedscale"):GetFloat()
		local phase = GetConVar("cameraman_phase"):GetFloat()
		local ptrSpeed = GetConVar("cameraman_ptrspeed"):GetFloat()
		local panAmp, tiltAmp, rotAmp =
			math_deg(GetConVar("cameraman_panamplitude"):GetFloat()),
			math_deg(GetConVar("cameraman_tiltamplitude"):GetFloat()),
			math_deg(GetConVar("cameraman_rotamplitude"):GetFloat())

		local randomnessScale = math_deg(GetConVar("cameraman_randomscale"):GetFloat())
		local randomnessSpeed = GetConVar("cameraman_randomspeed"):GetFloat()

		local func = methods[method] or methods.sine

		local t = CurTime()
		-- Tilt
		self.CameraShake.pitch = func(motionScale * tiltAmp, speedScale * ptrSpeed, phase, t)
		-- Pan
		self.CameraShake.yaw = func(motionScale * panAmp, speedScale * ptrSpeed, phase, t)
		-- Rotation
		self.CameraShake.roll = func(motionScale * rotAmp, speedScale * ptrSpeed, phase, t)
		self.CameraNoise:Random(-randomnessScale, randomnessScale)
		self.CameraNoise:Mul(FrameTime())
		self.CameraShake:Add(self.CameraNoise)

		mv:SetAngles(entity_angle)
	end,

	--
	-- Runs the actual move. On the client when there's
	-- prediction errors this can be run multiple times.
	-- You should try to only change mv.
	--
	---@param self any
	---@param mv CMoveData
	Move = function(self, mv)
		--
		-- Set up a speed, go faster if shift is held down
		--
		local speed = 0.0005 * FrameTime()
		if mv:KeyDown(IN_SPEED) then
			speed = 0.005 * FrameTime()
		end
		if mv:KeyDown(IN_DUCK) then
			speed = 0.00005 * FrameTime()
		end

		-- Simulate noclip's action when holding space
		if mv:KeyDown(IN_JUMP) then
			mv:SetUpSpeed(10000)
		end

		--
		-- Get information from the movedata
		--
		local ang = mv:GetMoveAngles()
		local pos = mv:GetOrigin()
		local vel = mv:GetVelocity()

		-- Cancel out the roll
		ang.roll = 0

		--
		-- Add velocities. This can seem complicated. On the first line
		-- we're basically saying get the forward vector, then multiply it
		-- by our forward speed (which will be > 0 if we're holding W, < 0 if we're
		-- holding S and 0 if we're holding neither) - and add that to velocity.
		-- We do that for right and up too, which gives us our free movement.
		--
		vel = vel + ang:Forward() * mv:GetForwardSpeed() * speed
		vel = vel + ang:Right() * mv:GetSideSpeed() * speed
		vel = vel + ang:Up() * mv:GetUpSpeed() * speed

		--
		-- We don't want our velocity to get out of hand so we apply
		-- a little bit of air resistance. If no keys are down we apply
		-- more resistance so we slow down more.
		--
		if math.abs(mv:GetForwardSpeed()) + math.abs(mv:GetSideSpeed()) + math.abs(mv:GetUpSpeed()) < 0.1 then
			vel = vel * 0.90
		else
			vel = vel * 0.99
		end

		--
		-- Add the velocity to the position (this is the movement)
		--
		pos = pos + vel

		--
		-- We don't set the newly calculated values on the entity itself
		-- we instead store them in the movedata. These get applied in FinishMove.
		--
		mv:SetVelocity(vel)
		mv:SetOrigin(pos)
	end,

	--
	-- The move is finished. Use mv to set the new positions
	-- on your entities/players.
	--
	---@param self any
	---@param mv CMoveData
	FinishMove = function(self, mv)
		--
		-- Update our entity!
		--
		local shake = self.Entity:LocalToWorldAngles(self.CameraShake)

		self.Entity:SetNetworkOrigin(mv:GetOrigin())
		self.Entity:SetAbsVelocity(mv:GetVelocity())
		self.Entity:SetAngles(mv:GetAngles())

		--
		-- If we have a physics object update that too. But only on the server.
		--
		if SERVER and IsValid(self.Entity:GetPhysicsObject()) then
			self.Entity:GetPhysicsObject():EnableMotion(true)
			self.Entity:GetPhysicsObject():SetPos(mv:GetOrigin())
			self.Entity:GetPhysicsObject():SetAngles(LerpAngle(FrameTime(), mv:GetAngles(), shake))
			self.Entity:GetPhysicsObject():Wake()
			self.Entity:GetPhysicsObject():EnableMotion(false)
		end
	end,
}, "drive_base")
