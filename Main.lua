-- Constants ----------------------------------------------------------------
local SINGLETON_CLASSIFICATIONS = {
	"player",
	"pet",
	"pettarget",
	"target",
	"targettarget",
	"targettargettarget",
	"focus",
	"focustarget",
	"focustargettarget",
}

local LibSharedMedia = LibStub("LibSharedMedia-3.0", true)
if not LibSharedMedia then
	LoadAddOn("LibSharedMedia-3.0")
	LibSharedMedia = LibStub("LibSharedMedia-3.0", true)
end

local DEFAULT_LSM_FONT = "Arial Narrow"
if LibSharedMedia then
	if not LibSharedMedia:IsValid("font", DEFAULT_LSM_FONT) then
		-- non-Western languages
		
		DEFAULT_LSM_FONT = LibSharedMedia:GetDefault("font")
	end
end

local DATABASE_DEFAULTS = {
	profile = {
		classifications = {
			['**'] = {
				hidden = false,
				position_x = 0,
				position_y = 0,
				scale = 1,
				layout = "Normal",
				horizontal_mirror = false,
				vertical_mirror = false,
			},
		},
		layouts = {
			['**'] = {
				size_x = 300,
				size_y = 100,
				scale = 1,
				font = DEFAULT_LSM_FONT,
				status_bar_texture = LibSharedMedia and LibSharedMedia:GetDefault("statusbar") or "Blizzard",
			},
			Normal = {}
		},
	}
}
-----------------------------------------------------------------------------

local _G = _G

local PitBull4 = LibStub("AceAddon-3.0"):NewAddon("PitBull4", "AceEvent-3.0", "AceTimer-3.0")
_G.PitBull4 = PitBull4

PitBull4.SINGLETON_CLASSIFICATIONS = SINGLETON_CLASSIFICATIONS

local db

if not _G.ClickCastFrames then
	-- for click-to-cast addons
	_G.ClickCastFrames = {}
end

do
	-- unused tables go in this set
	-- if the garbage collector comes around, they'll be collected properly
	local cache = setmetatable({}, {__mode='k'})
	
	--- Return a table
	-- @usage local t = PitBull4.new()
	-- @return a blank table
	function PitBull4.new()
		local t = next(cache)
		if t then
			cache[t] = nil
			return t
		end
		
		return {}
	end
	
	local wipe = _G.wipe
	
	--- Delete a table, clearing it and putting it back into the queue
	-- @usage local t = PitBull4.new()
	-- t = del(t)
	-- @return nil
	function PitBull4.del(t)
		--@alpha@
		expect(t, 'typeof', 'table')
		expect(t, 'not_inset', cache)
		--@end-alpha@
		
		wipe(t)
		cache[t] = true
		return nil
	end
end

local new, del = PitBull4.new, PitBull4.del

-- A set of all unit frames
local all_frames = {}
PitBull4.all_frames = all_frames

-- A set of all unit frames with the is_wacky flag set to true
local wacky_frames = {}

-- A set of all unit frames with the is_wacky flag set to false
local non_wacky_frames = {}

-- metatable that automatically creates keys that return tables on access
local auto_table__mt = {__index = function(self, key)
	local value = {}
	self[key] = value
	return value
end}

-- A dictionary of UnitID to a set of all unit frames of that UnitID
local unit_id_to_frames = setmetatable({}, auto_table__mt)

-- A dictionary of classification to a set of all unit frames of that classification
local classification_to_frames = setmetatable({}, auto_table__mt)

--- Wrap the given function so that any call to it will be piped through PitBull4:RunOnLeaveCombat.
-- @param func function to call
-- @usage myFunc = PitBull4:OutOfCombatWrapper(func)
-- @usage MyNamespace.MyMethod = PitBull4:OutOfCombatWrapper(MyNamespace.MyMethod)
-- @return the wrapped function
function PitBull4:OutOfCombatWrapper(func)
	return function(...)
		return PitBull4:RunOnLeaveCombat(func, ...)
	end
end

-- iterate through a set of frames and return those that are shown
local function iterate_shown_frames(set, frame)
	frame = next(set, frame)
	if frame == nil then
		return
	end
	if frame:IsShown() then
		return frame
	end
	return iterate_shown_frames(set, frame)
end

-- iterate through and return only the keys of a table
local function half_next(set, key)
	key = next(set, key)
	if key == nil then
		return nil
	end
	return key
end

-- iterate through and return only the keys of a table. Once exhausted, recycle the table.
local function half_next_with_del(set, key)
	key = next(set, key)
	if key == nil then
		del(set)
		return nil
	end
	return key
end

--- Iterate over all frames.
-- This iterates over only shown frames unless also_hidden is passed in.
-- @param also_hidden also return frames that are hidden
-- @usage for frame in PitBull4:IterateFrames() do
--     doSomethingWith(frame)
-- end
-- @usage for frame in PitBull4:IterateFrames(true) do
--     doSomethingWith(frame)
-- end
-- @return iterator which returns frames
function PitBull4:IterateFrames(also_hidden)
	--@alpha@
	expect(also_hidden, 'typeof', 'boolean;nil')
	--@end-alpha@
	
	return not also_hidden and iterate_shown_frames or half_next, all_frames
end

--- Iterate over all wacky frames.
-- This iterates over only shown frames unless also_hidden is passed in.
-- @param also_hidden also return frames that are hidden
-- @usage for frame in PitBull4:IterateWackyFrames() do
--     doSomethingWith(frame)
-- end
-- @usage for frame in PitBull4:IterateWackyFrames(true) do
--     doSomethingWith(frame)
-- end
-- @return iterator which returns frames
function PitBull4:IterateWackyFrames(also_hidden)
	--@alpha@
	expect(also_hidden, 'typeof', 'boolean;nil')
	--@end-alpha@
	
	return not also_hidden and iterate_shown_frames or half_next, wacky_frames
end

--- Iterate over all non-wacky frames.
-- This iterates over only shown frames unless also_hidden is passed in.
-- @param also_hidden also return frames that are hidden
-- @usage for frame in PitBull4:IterateNonWackyFrames() do
--     doSomethingWith(frame)
-- end
-- @usage for frame in PitBull4:IterateNonWackyFrames(true) do
--     doSomethingWith(frame)
-- end
-- @return iterator which returns frames
function PitBull4:IterateNonWackyFrames(also_hidden)
	--@alpha@
	expect(also_hidden, 'typeof', 'boolean;nil')
	--@end-alpha@
	
	return not also_hidden and iterate_shown_frames or half_next, non_wacky_frames
end

--- Iterate over all frames with the given unit ID
-- This iterates over only shown frames unless also_hidden is passed in.
-- @param unit the UnitID of the unit in question
-- @param also_hidden also return frames that are hidden
-- @usage for frame in PitBull4:IterateFramesForUnitID("player") do
--     doSomethingWith(frame)
-- end
-- @usage for frame in PitBull4:IterateFramesForUnitID("party1", true) do
--     doSomethingWith(frame)
-- end
-- @return iterator which returns frames
function PitBull4:IterateFramesForUnitID(unit, also_hidden)
	--@alpha@
	expect(unit, 'typeof', 'string')
	expect(also_hidden, 'typeof', 'boolean;nil')
	--@end-alpha@
	
	local id = PitBull4.Utils.GetBestUnitID(unit)
	if not id then
		error(("Bad argument #1 to `IterateFramesForUnitID'. %q is not a valid UnitID"):format(tostring(unit)), 2)
	end
	
	return not also_hidden and iterate_shown_frames or half_next, unit_id_to_frames[id]
end

--- Iterate over all shown frames with the given UnitIDs.
-- To iterate over hidden frames as well, pass in true as the last argument.
-- @param ... a tuple of UnitIDs.
-- @usage for frame in PitBull4:IterateFramesForUnitIDs("player", "target", "pet") do
--     somethingAwesome(frame)
-- end
-- @usage for frame in PitBull4:IterateFramesForUnitIDs("player", "target", "pet", true) do
--     somethingAwesome(frame)
-- end
-- @return iterator which returns frames
function PitBull4:IterateFramesForUnitIDs(...)
	local t = new()
	local n = select('#', ...)
	
	local also_hidden = ((select(n, ...)) == true)
	if also_hidden then
		n = n - 1
	end
	
	for i = 1, n do
		local unit = (select(i, ...))
		local frames = unit_id_to_frames[unit]
		
		for frame in pairs(frames) do
			if also_hidden or frame:IsShown() then
				t[frame] = true
			end
		end
	end
	
	return half_next_with_del, t
end

--- Iterate over all frames with the given classification.
-- This iterates over only shown frames unless also_hidden is passed in.
-- @param classification the classification to check
-- @param also_hidden also return frames that are hidden
-- @usage for frame in PitBull4:IterateFramesForClassification("player") do
--     doSomethingWith(frame)
-- end
-- @usage for frame in PitBull4:IterateFramesForClassification("party", true) do
--     doSomethingWith(frame)
-- end
-- @return iterator which returns frames
function PitBull4:IterateFramesForClassification(classification, also_hidden)
	--@alpha@
	expect(classification, 'typeof', 'string')
	expect(also_hidden, 'typeof', 'boolean;nil')
	--@end-alpha@

	local unit_id_to_frames__classification = rawget(unit_id_to_frames, classification)
	if not unit_id_to_frames__classification then
		return donothing
	end
	
	return not also_hidden and iterate_shown_frames or half_next, unit_id_to_frames__classification
end

local function layout_iter(layout, frame)
	frame = next(all_frames, frame)
	if not frame then
		return nil
	end
	if frame.layout == layout then
		return frame
	end
	return layout_iter(layout, frame)
end

local function layout_shown_iter(layout, frame)
	frame = next(all_frames, frame)
	if not frame then
		return nil
	end
	if frame.layout == layout and frame:IsShown() then
		return frame
	end
	return layout_iter(layout, frame)
end

--- Iterate over all frames with the given layout.
-- This iterates over only shown frames unless also_hidden is passed in.
-- @param layout the layout to check
-- @param also_hidden also return frames that are hidden
-- @usage for frame in PitBull4:IterateFramesForLayout("Normal") do
--     frame:UpdateLayout()
-- end
-- @usage for frame in PitBull4:IterateFramesForLayout("Normal", true) do
--     frame:UpdateLayout()
-- end
-- @return iterator which returns frames
function PitBull4:IterateFramesForLayout(layout, also_hidden)
	--@alpha@
	expect(layout, 'typeof', 'string')
	expect(also_hidden, 'typeof', 'boolean;nil')
	--@end-alpha@
	
	return not also_hidden and layout_shown_iter or layout_iter, layout
end

--- call :Update() on all frames with the given layout
-- @param layout the layout to check
-- @usage PitBull4:UpdateForLayout("Normal")
function PitBull4:UpdateForLayout(layout)
	for frame in self:IterateFramesForLayout(layout) do
		frame:Update(true, true)
	end
end

local function guid_iter(guid, frame)
	frame = next(all_frames, frame)
	if not frame then
		return nil
	end
	if frame.guid == guid then
		return frame
	end
	return guid_iter(guid, frame)
end

--- Iterate over all frame with the given GUID
-- @param guid the GUID to check
-- @usage for frame in PitBull4:IterateFramesForGUID("0x0000000000071278") do
--     doSomethingWith(frame)
-- end
-- @return iterator which returns frames
function PitBull4:IterateFramesForGUID(guid)
	--@alpha@
	expect(guid, 'typeof', 'string')
	expect(guid, 'match', '^0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$')
	--@end-alpha@
	
	return guid_iter, guid, nil
end

--- Make a singleton unit frame.
-- @param unit the UnitID of the frame in question
-- @usage local frame = PitBull4:MakeSingletonFrame("player")
function PitBull4:MakeSingletonFrame(unit)
	--@alpha@
	expect(unit, 'typeof', 'string')
	--@end-alpha@
	
	local id = PitBull4.Utils.GetBestUnitID(unit)
	if not PitBull4.Utils.IsSingletonUnitID(id) then
		error(("Bad argument #1 to `MakeSingletonFrame'. %q is not a singleton UnitID"):format(tostring(unit)), 2)
	end
	unit = id
	
	local frame_name = "PitBull4_Frames_" .. unit
	local frame = _G[frame_name]
	
	if not frame then
		frame = CreateFrame("Button", frame_name, UIParent, "SecureUnitButtonTemplate")
		
		all_frames[frame] = true
		_G.ClickCastFrames[frame] = true
		
		frame.is_singleton = true
		
		-- for singletons, its classification is its UnitID
		local classification = unit
		frame.classification = classification
		frame.classification_db = db.profile.classifications[classification]
		classification_to_frames[classification][frame] = true
		
		local is_wacky = PitBull4.Utils.IsWackyClassification(classification)
		frame.is_wacky = is_wacky;
		(is_wacky and wacky_frames or non_wacky_frames)[frame] = true
		
		frame.unit = unit
		unit_id_to_frames[unit][frame] = true
		
		frame:SetAttribute("unit", unit)
		
		frame:SetClampedToScreen(true)
		
		self:ConvertIntoUnitFrame(frame)
	end
	
	frame:Activate()
	
	frame:RefreshLayout()
	
	frame:UpdateGUID(UnitGUID(unit))
end
PitBull4.MakeSingletonFrame = PitBull4:OutOfCombatWrapper(PitBull4.MakeSingletonFrame)

function PitBull4:OnInitialize()
	db = LibStub("AceDB-3.0"):New("PitBull4DB", DATABASE_DEFAULTS, 'global')
	DATABASE_DEFAULTS = nil
	self.db = db
end

function PitBull4:OnEnable()
	self:ScheduleRepeatingTimer("CheckWackyFramesForGUIDUpdate", 0.15)
	
	-- register unit change events
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	self:RegisterEvent("PLAYER_PET_CHANGED")
	self:RegisterEvent("UNIT_TARGET")
	self:RegisterEvent("UNIT_PET")
	
	-- enter/leave combat for :RunOnLeaveCombat
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	
	-- show initial frames
	local db_classifications = db.profile.classifications
	for _, classification in ipairs(SINGLETON_CLASSIFICATIONS) do
		if not db_classifications[classification].hidden then
			self:MakeSingletonFrame(classification)
		end
	end
end

--- Iterate over all wacky frames, and call their respective :UpdateGUID methods.
-- @usage PitBull4:CheckWackyFramesForGUIDUpdate()
function PitBull4:CheckWackyFramesForGUIDUpdate()
	for frame in self:IterateWackyFrames(true) do
		frame:UpdateGUID(UnitGUID(frame.unit))
	end
end

--- Check the GUID of the given UnitID and send that info to all frames for that UnitID
-- @param unit the UnitID to check
-- @usage PitBull4:CheckGUIDForUnitID("player")
function PitBull4:CheckGUIDForUnitID(unit)
	if not PitBull4.Utils.GetBestUnitID(unit) then
		-- for ids such as npctarget
		return
	end
	local guid = UnitGUID(unit)
	for frame in self:IterateFramesForUnitID(unit, true) do
		frame:UpdateGUID(guid)
	end
end

function PitBull4:PLAYER_TARGET_CHANGED() self:CheckGUIDForUnitID("target") end
function PitBull4:PLAYER_FOCUS_CHANGED() self:CheckGUIDForUnitID("focus") end
function PitBull4:UPDATE_MOUSEOVER_UNIT() self:CheckGUIDForUnitID("mouseover") end
function PitBull4:PLAYER_PET_CHANGED() self:CheckGUIDForUnitID("pet") end
function PitBull4:UNIT_TARGET(_, unit) self:CheckGUIDForUnitID(unit .. "target") end
function PitBull4:UNIT_PET(_, unit) self:CheckGUIDForUnitID(unit .. "pet") end

do
	local in_combat = false
	local actions_to_perform = {}
	local pool = {}
	function PitBull4:PLAYER_REGEN_ENABLED()
		in_combat = false
		for i, t in ipairs(actions_to_perform) do
			t[1](unpack(t, 2, t.n+1))
			for k in pairs(t) do
				t[k] = nil
			end
			actions_to_perform[i] = nil
			pool[t] = true
		end
	end
	function PitBull4:PLAYER_REGEN_DISABLED()
		in_combat = true
	end
	--- Call a function if out of combat or schedule to run once combat ends.
	-- You can also pass in a table (or frame), method, and arguments.
	-- If current out of combat, the function provided will be called without delay.
	-- @param func function to call
	-- @param ... arguments to pass into func
	-- @usage PitBull4:RunOnLeaveCombat(someSecureFunction)
	-- @usage PitBull4:RunOnLeaveCombat(someSecureFunction, "player")
	-- @usage PitBull4:RunOnLeaveCombat(frame.SetAttribute, frame, "key", "value")
	-- @usage PitBull4:RunOnLeaveCombat(frame, 'SetAttribute', "key", "value")
	function PitBull4:RunOnLeaveCombat(func, ...)
		if type(func) == "table" then
			return self:RunOnLeaveCombat(func[(...)], func, select(2, ...))
		end
		if not in_combat then
			-- out of combat, call right away and return
			func(...)
			return
		end
		local t = next(pool) or {}
		pool[t] = nil
		
		t[1] = func
		local n = select('#', ...)
		t.n = n
		for i = 1, n do
			t[i+1] = select(i, ...)
		end
	end
end	