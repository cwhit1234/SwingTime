local addonName, ST = ...

-- =====================================================================
--  Media.lua
--  LibSharedMedia integration: register a built-in flat bar texture,
--  provide Fetch helpers, and refresh bars when other addons register
--  new media after us.
-- =====================================================================

local Media = {}
ST.Media = Media

local LSM = LibStub("LibSharedMedia-3.0")
Media.LSM = LSM

-- Register a clean solid bar using a built-in Blizzard 8x8 white texture,
-- so a flat colored bar works without shipping any binary asset.
LSM:Register("statusbar", "SwingTime Flat", [[Interface\Buttons\WHITE8X8]])

local FALLBACK_TEXTURE = [[Interface\TargetingFrame\UI-StatusBar]]
local FALLBACK_FONT    = [[Fonts\FRIZQT__.TTF]]

function Media.Texture(key)
	return LSM:Fetch("statusbar", key) or FALLBACK_TEXTURE
end

function Media.Font(key)
	return LSM:Fetch("font", key) or FALLBACK_FONT
end

-- Sorted list of registered keys for a media type (feeds dropdowns).
function Media.List(mediatype)
	return LSM:List(mediatype)
end

function Media.HashTable(mediatype)
	return LSM:HashTable(mediatype)
end

-- When any addon registers new media, re-apply styles so new textures/
-- fonts appear immediately in bars and dropdowns.
LSM.RegisterCallback(Media, "LibSharedMedia_Registered", function()
	if ST.Config and ST.Config.NotifyChanged then
		ST.Config.NotifyChanged()
	end
end)
