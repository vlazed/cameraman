include("drive/drive_handheld.lua")
include("drive/drive_drone.lua")

include("properties/vlazed_drive_camera.lua")

if SERVER then
	return
end

local methods = {
	"sine",
	"rectified_sine",
	"rectified_sine_invert",
	"square",
}

-- Parameters are inspired from DaVinci Resolve
local motionScale = CreateClientConVar("cameraman_motionscale", "1.0", true, true)
local speedScale = CreateClientConVar("cameraman_speedscale", "1.0", true, true)

local panAmplitude = CreateClientConVar("cameraman_panamplitude", "0.1", true, true)
local tiltAmplitude = CreateClientConVar("cameraman_tiltamplitude", "0.3", true, true)
local rotationAmplitude = CreateClientConVar("cameraman_rotamplitude", "0.1", true, true)
local ptrSpeed = CreateClientConVar("cameraman_ptrspeed", "0.5", true, true)
local zoomAmplitude = CreateClientConVar("cameraman_zoomamplitude", "0.0", true, true)
local zoomSpeed = CreateClientConVar("cameraman_zoomspeed", "0", true, true)

local motionMethod = CreateClientConVar("cameraman_motionmethod", "sine", true, true)
local phase = CreateClientConVar("cameraman_phase", "0.75", true, true)
local randomnessScale = CreateClientConVar("cameraman_randomscale", "0.1", true, true)
local randomnessSpeed = CreateClientConVar("cameraman_randomspeed", "0.85", true, true)
local pauseLength = CreateClientConVar("cameraman_pauselength", "0.5", true, true)
local pauseInterval = CreateClientConVar("cameraman_pauselength", "5", true, true)
local pauseRandomness = CreateClientConVar("cameraman_pauselength", "5", true, true)
local randomSeed = CreateClientConVar("cameraman_seed", "1", true, true)

---Helper for DForm
---@param cPanel ControlPanel|DForm
---@param name string
---@param type "ControlPanel"|"DForm"
---@return ControlPanel|DForm
local function makeCategory(cPanel, name, type)
	---@type DForm|ControlPanel
	local category = vgui.Create(type, cPanel)

	category:SetLabel(name)
	cPanel:AddItem(category)
	return category
end

---@param cpanel ControlPanel|DForm
local function options(cpanel)
	local universalSettings = makeCategory(cpanel, "Universal", "DForm")
	local handheldSettings = makeCategory(cpanel, "Handheld", "DForm")
	local droneSettings = makeCategory(cpanel, "Drone", "DForm")

	universalSettings:NumSlider("Motion Scale", "cameraman_motionscale", 0, 2, 2)
	universalSettings:NumSlider("Speed Scale", "cameraman_speedscale", 0, 2, 2)

	universalSettings:Help("Shake Quality")
	universalSettings:NumSlider("Pan Amplitude", "cameraman_panamplitude", 0, 10, 2)
	universalSettings:NumSlider("Tilt Amplitude", "cameraman_tiltamplitude", 0, 10, 2)
	universalSettings:NumSlider("Rotation Amplitude", "cameraman_rotamplitude", 0, 10, 2)
	universalSettings:NumSlider("PTR Speed", "cameraman_ptrspeed", 0, 10, 2)
	universalSettings:NumSlider("Zoom Amplitude", "cameraman_zoomamplitude", 0, 10, 2)
	universalSettings:NumSlider("Zoom Speed", "cameraman_zoomspeed", 0, 10, 2)

	universalSettings:Help("Shake Quality")
	universalSettings:NumSlider("Phase", "cameraman_phase", 0, 10, 2)
	universalSettings:NumSlider("Randomness Scale", "cameraman_randomscale", 0, 10, 2)
	universalSettings:NumSlider("Randomness Speed", "cameraman_randomspeed", 0, 10, 2)
	universalSettings:NumSlider("Pause Length", "cameraman_pauselength", 0, 10, 2)
	universalSettings:NumSlider("Pause Interval", "cameraman_pauselength", 0, 10, 2)
	universalSettings:NumSlider("Pause Randomness", "cameraman_pauselength", 0, 10, 2)
	universalSettings:NumberWang("Random Seed", "cameraman_seed", 0, 10000)
end

hook.Remove("PopulateToolMenu", "vlazed_camera_options")
hook.Add("PopulateToolMenu", "vlazed_camera_options", function()
	spawnmenu.AddToolMenuOption("Options", "vlazed", "vlazed_cameraman", "Cameraman", "", "", options, {})
end)
