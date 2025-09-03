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

local DOWN = -vector_up
local FLOOR_VECTOR = Vector(1, 1, 0)

drive.Register("drive_handheld", {
	Init = function(self)
		self.CameraDist = 4
		self.CameraDistVel = 0.1
		self.CameraShake = Angle(0)
		self.CameraNoise = Angle(0)
		self.CameraFinalShake = Angle(0)
		self.Speed = 0
		self.MoveDir = vector_origin
		self.WishDir = vector_origin
		self.OnGround = false
	end,

	CalcView = function(self, view)
		local idealdist = math.max(10, self.Entity:BoundingRadius()) * self.CameraDist

		self:CalcView_ThirdPerson(view, idealdist, 2, { self.Entity })

		view.angles.roll = 0
	end,

	---@param self any
	---@param cmd CUserCmd
	SetupControls = function(self, cmd)
		if cmd:KeyDown(IN_RELOAD) then
			self.CameraForceViewAngles = self.CameraForceViewAngles or cmd:GetViewAngles()

			cmd:SetViewAngles(self.CameraForceViewAngles)
		else
			self.CameraForceViewAngles = nil
		end

		self.CameraDistVel = self.CameraDistVel + cmd:GetMouseWheel() * -0.5

		self.CameraDist = self.CameraDist + self.CameraDistVel * FrameTime()
		self.CameraDist = math.Clamp(self.CameraDist, 2, 20)
		self.CameraDistVel = math.Approach(self.CameraDistVel, 0, self.CameraDistVel * FrameTime() * 2)
	end,

	---Give mv some state using cmd and entity
	---@param self any
	---@param mv CMoveData
	---@param cmd CUserCmd
	StartMove = function(self, mv, cmd)
		self.Player:SetObserverMode(OBS_MODE_CHASE)

		if mv:KeyReleased(IN_USE) then
			self:Stop()
		end

		mv:SetOrigin(self.Entity:GetNetworkOrigin())
		mv:SetVelocity(self.Entity:GetAbsVelocity())
		mv:SetMoveAngles(mv:GetAngles()) -- Always move relative to the player's eyes

		local entity_angle = mv:GetAngles()
		entity_angle.roll = self.Entity:GetAngles().roll

		if mv:KeyDown(IN_ATTACK2) or mv:KeyReleased(IN_ATTACK2) then
			entity_angle = self.Entity:GetAngles()
		end

		if mv:KeyDown(IN_RELOAD) then
			entity_angle.roll = entity_angle.roll + cmd:GetMouseX() * 0.01
		end

		if mv:KeyReleased(IN_ATTACK2) then
			self.Player:SetEyeAngles(self.Entity:GetAngles())
		end

		local method = GetConVar("cameraman_motionmethod"):GetString()
		local motionScale = GetConVar("cameraman_motionscale"):GetFloat()
		local speedScale = GetConVar("cameraman_speedscale"):GetFloat()
		local phase = GetConVar("cameraman_phase"):GetFloat()
		local ptrSpeed = GetConVar("cameraman_ptrspeed"):GetFloat()
		local panAmp, tiltAmp, rotAmp =
			GetConVar("cameraman_panamplitude"):GetFloat(),
			GetConVar("cameraman_tiltamplitude"):GetFloat(),
			GetConVar("cameraman_rotamplitude"):GetFloat()

		local randomnessScale = math_deg(GetConVar("cameraman_randomscale"):GetFloat())
		local randomnessSpeed = GetConVar("cameraman_randomspeed"):GetFloat()

		local func = methods[method] or methods.sine

		local t = CurTime()
		-- Tilt
		self.CameraShake.pitch = math_deg(func(-motionScale * tiltAmp, speedScale * ptrSpeed, phase, t))
		-- Pan
		self.CameraShake.yaw = math_deg(func(motionScale * panAmp, speedScale * ptrSpeed, phase - math.pi * 0.5, t))
		-- Rotation
		self.CameraShake.roll = math_deg(func(motionScale * rotAmp, speedScale * ptrSpeed, phase, t))
		self.CameraNoise:Random(-randomnessScale, randomnessScale)
		self.CameraNoise:Mul(randomnessSpeed)
		self.CameraNoise:Mul(FrameTime())
		self.CameraShake:Add(self.CameraNoise)

		local standingHeight = GetConVar("cameraman_standheight")
		local crouchingHeight = GetConVar("cameraman_crouchheight")
		local proneHeight = GetConVar("cameraman_proneheight")
		local height = standingHeight:GetFloat()

		---@type Trace
		local tr = {
			start = mv:GetOrigin(),
			endpos = mv:GetOrigin() + DOWN * 99999,
			filter = self.Entity,
		}
		local groundTrace = util.TraceLine(tr)
		local length = tr.start:Distance(groundTrace.HitPos)
		self.OnGround = length <= height

		mv:SetAngles(entity_angle)
	end,

	---Modify mv
	---@param self any
	---@param mv CMoveData
	Move = function(self, mv)
		local acceleration = GetConVar("cameraman_acceleration"):GetFloat()
		local deceleration = GetConVar("cameraman_deceleration"):GetFloat()
		local walkSpeed = GetConVar("cameraman_walkspeed"):GetFloat()
		local runSpeed = GetConVar("cameraman_runspeed"):GetFloat()
		local sprintSpeed = GetConVar("cameraman_sprintspeed"):GetFloat()

		local maxSpeed = runSpeed

		if mv:KeyDown(IN_SPEED) then
			maxSpeed = sprintSpeed
		elseif mv:KeyDown(IN_WALK) then
			maxSpeed = walkSpeed
		end
		if mv:KeyDown(IN_DUCK) then
			speed = 0.00005 * FrameTime()
		end

		-- Simulate noclip's action when holding space
		if mv:KeyDown(IN_JUMP) then
			mv:SetUpSpeed(10000)
		end

		local ang = mv:GetMoveAngles()
		local pos = mv:GetOrigin()
		local vel = mv:GetVelocity()

		-- Cancel out the roll
		ang.roll = 0
		local fmove, smove = mv:GetForwardSpeed() / 10000, mv:GetSideSpeed() / 10000
		local moving = math.abs(fmove) + math.abs(smove)
		if moving > 0 then
			self.Speed = math.min(self.Speed + acceleration * FrameTime(), maxSpeed)
		else
			self.Speed = math.max(self.Speed - deceleration * FrameTime(), 0)
		end
		if moving ~= 0 then
			self.MoveDir = fmove * ang:Forward() + smove * ang:Right()
		end
		self.MoveDir.z = 0
		self.MoveDir:Normalize()

		self.WishDir = LerpVector(0.5, self.WishDir, self.MoveDir)
		self.WishDir:Normalize()

		vel = self.WishDir * self.Speed

		self.CameraFinalShake.pitch = -self.CameraShake.pitch * (1 + ang:Forward():Dot(vel))
		self.CameraFinalShake.roll = self.CameraShake.roll * (1 - 2 * ang:Right():Dot(vel))
		self.CameraFinalShake.yaw = self.CameraShake.yaw

		pos = pos + vel

		mv:SetVelocity(vel)
		mv:SetOrigin(pos)
	end,

	---Use mv to set state
	---@param self any
	---@param mv CMoveData
	FinishMove = function(self, mv)
		local shake = self.Entity:LocalToWorldAngles(self.CameraFinalShake)

		self.Entity:SetNetworkOrigin(mv:GetOrigin())
		self.Entity:SetAbsVelocity(mv:GetVelocity())
		self.Entity:SetAngles(mv:GetAngles())

		-- Update server physics
		if SERVER and IsValid(self.Entity:GetPhysicsObject()) then
			self.Entity:GetPhysicsObject():EnableMotion(true)
			self.Entity:GetPhysicsObject():SetPos(mv:GetOrigin())
			self.Entity:GetPhysicsObject():SetAngles(LerpAngle(FrameTime(), mv:GetAngles(), shake))
			self.Entity:GetPhysicsObject():Wake()
			self.Entity:GetPhysicsObject():EnableMotion(false)
		end
	end,
}, "drive_base")
