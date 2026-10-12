local _G, _M = getfenv(0), {}
setfenv(1, setmetatable(_M, {__index=_G}))

CreateFrame('GameTooltip', 'SortBagsTooltip', nil, 'GameTooltipTemplate')

local function IsPlayingOnTurtleWoW()
	-- https://github.com/refaim/Turtle-WoW-UI-Source/blob/d6137c2ebd291f10ce284e586a5733dd5141bef2/Interface/FrameXML/TargetFrame.xml#L183
	return TargetHPText ~= nil and TargetHPPercText ~= nil
end

local function IsSuperWoWLoaded()
	-- https://github.com/balakethelock/SuperWoW/wiki/Features
	return SetAutoloot ~= nil
end

local function IsNampowerLoaded()
	-- https://github.com/Emyrk/nampower
	return GetNampowerVersion ~= nil
end

-- Set SortBagsNoClassicAPI to force the cursor/tooltip path.
local usingClassicAPI
local sorting

local function HasClassicAPI()
	if SortBagsNoClassicAPI then
		return false
	end
	return C_Container
		and C_Container.SwapItems
		and C_Container.MoveItem
		and C_Container.GetContainerItemInfo
		and C_Item
		and C_Item.GetItemDataByID
		and C_Item.GetItemFamily
		and true
end

local function ItemKey(itemID, enchantID, suffixID, uniqueID, charges, soulbound)
	return format('%s:%s:%s:%s:%s:%s', itemID, enchantID, suffixID, uniqueID, charges, soulbound and 1 or 0)
end

-- Vanilla 1.12 has no bit library
local function HasFlag(value, flag)
	return value and mod(floor(value / flag), 2) == 1
end

-- GetBagItem returns a reusable table; copy scalars immediately
local function SnapshotBagItem(container, position)
	if not IsNampowerLoaded() then
		return
	end
	local info = GetBagItem(container, position)
	if not info then
		return
	end
	return {
		itemId = info.itemId,
		stackCount = info.stackCount,
		spellChargesRemaining = info.spellChargesRemaining,
		flags = info.flags,
		permanentEnchantId = info.permanentEnchantId,
		randomPropertiesId = info.randomPropertiesId,
	}
end

local function GetContainerItemCount(container, position)
	if usingClassicAPI then
		local info = C_Container.GetContainerItemInfo(container, position)
		if info and info.stackCount then
			return info.stackCount
		end
	end
	if IsNampowerLoaded() then
		local info = GetBagItem(container, position)
		if info and info.stackCount then
			return info.stackCount
		end
	end
	local _, countOrCharges = GetContainerItemInfo(container, position)
	local count = countOrCharges
	if IsSuperWoWLoaded() and countOrCharges < 0 then
		count = 1
	end
	return count
end

-- CLASSES array index -> ItemBagFamily.dbc id (nampower unifies both)
local CLASSES_INDEX_TO_FAMILY = {
	[1] = 1, -- arrows
	[2] = 2, -- bullets
	[3] = 3, -- soul shards
	[4] = 7, -- enchanting
	[5] = 6, -- herbs
}

-- Container (DBC class 1) subclass -> family when bagFamily is 0
-- Stock 1.12: Soul/Herb/Enchanting/Engineering
-- Turtle extras: Mining/Leather/Meat/Fish
local CONTAINER_SUBCLASS_FAMILY = {
	[1] = 3,  -- soul
	[2] = 6,  -- herb
	[3] = 7,  -- enchanting
	[4] = 8,  -- engineering
	[5] = 10, -- gem (TBC)
	[6] = 13, -- mining (Turtle; TBC mining is 11)
	[7] = 12, -- leather
	[8] = 10, -- meat (Turtle)
	[9] = 11, -- fish (Turtle)
}

-- Quiver (DBC class 11) subclass -> family
local QUIVER_SUBCLASS_FAMILY = {
	[2] = 1, -- quiver / arrows
	[3] = 2, -- ammo pouch / bullets
}

-- Equipped bags: never trust bagFamily (1.12 often 0, sometimes garbage).
-- Generic bags are Container subclass 0; only subclass 1+ is specialty.
local function GetNampowerBagFamily(itemID)
	if not itemID then
		return
	end
	local itemClass = tonumber(GetItemStatsField(itemID, 'class'))
	local subclass = tonumber(GetItemStatsField(itemID, 'subclass'))
	if not subclass or subclass == 0 then
		return
	end
	if itemClass == 1 then
		return CONTAINER_SUBCLASS_FAMILY[subclass]
	end
	if itemClass == 11 then
		return QUIVER_SUBCLASS_FAMILY[subclass]
	end
end

-- Loot items: bagFamily is the real routing key. Ignore unknown/garbage values
-- so ordinary items are not treated as specialty-only.
local KNOWN_BAG_FAMILIES = {
	[1] = true, [2] = true, [3] = true,
	[6] = true, [7] = true, [8] = true, [9] = true,
	[10] = true, [11] = true, [12] = true, [13] = true,
}

local function GetNampowerItemFamily(itemID)
	if not itemID then
		return
	end
	local family = tonumber(GetItemStatsField(itemID, 'bagFamily'))
	if family and KNOWN_BAG_FAMILIES[family] then
		return family
	end
end

local function NampowerClassFromClassesIndex(class)
	return CLASSES_INDEX_TO_FAMILY[class] or class
end

local CONTAINERS
local sortingBank

function _G.SortBags()
	CONTAINERS = {0, 1, 2, 3, 4}
	sortingBank = false
	Start()
end

function _G.SortBankBags()
	if GetContainerNumSlots(BANK_CONTAINER) == 0 then
		DEFAULT_CHAT_FRAME:AddMessage('SortBags: bank is not open')
		return
	end
	CONTAINERS = {-1, 5, 6, 7, 8, 9, 10}
	sortingBank = true
	Start()
end

function _G.GetSortBagsRightToLeft(enabled)
	return SortBagsRightToLeft
end

function _G.SetSortBagsRightToLeft(enabled)
	_G.SortBagsRightToLeft = enabled and 1 or nil
end

local function set(...)
	local t = {}
	for i = 1, arg.n do
		t[arg[i]] = true
	end
	return t
end

local function union(...)
	local t = {}
	for i = 1, arg.n do
		for k in arg[i] do
			t[k] = true
		end
	end
	return t
end

local ITEM_TYPES = {GetAuctionItemClasses()}

local MOUNTS = set(
	-- rams
	5864, 5872, 5873, 18785, 18786, 18787, 18244, 19030, 13328, 13329,
	-- horses
	2411, 2414, 5655, 5656, 18778, 18776, 18777, 18241, 12353, 12354,
	-- sabers
	8629, 8631, 8632, 18766, 18767, 18902, 18242, 13086, 19902, 12302, 12303, 8628, 12326,
	-- mechanostriders
	8563, 8595, 13321, 13322, 18772, 18773, 18774, 18243, 13326, 13327,
	-- kodos
	15277, 15290, 18793, 18794, 18795, 18247, 15292, 15293,
	-- wolves
	1132, 5665, 5668, 18796, 18797, 18798, 18245, 12330, 12351,
	-- raptors
	8588, 8591, 8592, 18788, 18789, 18790, 18246, 19872, 8586, 13317,
	-- undead horses
	13331, 13332, 13333, 13334, 18791, 18248, 13335,
	-- qiraji battle tanks
	21218, 21321, 21323, 21324, 21176
)

local SPECIAL = set(5462, 17696, 17117, 13347, 13289, 11511)

local KEYS = set(9240, 17191, 13544, 12324, 16309, 12384, 20402, 50545)

local TOOLS = set(7005, 12709, 19727, 5956, 2901, 6219, 10498, 6218, 6339, 11130, 11145, 16207, 9149, 15846, 6256, 6365, 6367, 42004)

local ENCHANTING_MATERIALS = set(
	-- dust
	10940, 11083, 11137, 11176, 16204,
	-- essence
	10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,
	-- shard
	10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344,
	-- crystal
	20725
)

local HERBS = set(765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819, 3820, 3821, 4625, 8153, 8831, 8836, 8838, 8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468)

local SEEDS = set(17034, 17035, 17036, 17037, 17038)

local CLASSES = {
	-- arrow
	{
		containers = {2101, 5439, 7278, 11362, 3573, 3605, 7371, 8217, 2662, 19319, 18714},
		items = set(2512, 2515, 42198, 3030, 3464, 9399, 10579, 11285, 42200, 42201, 12654, 18042, 19316),
	},
	-- bullet
	{
		containers = {2102, 5441, 7279, 11363, 3574, 3604, 7372, 8218, 2663, 19320},
		items = set(2516, 4960, 8067, 2519, 5568, 8068, 3033, 8069, 3034, 3465, 10512, 11284, 10513, 11630, 19317, 15997, 13377),
	},
	-- soul
	{
		containers = {22243, 22244, 21340, 21341, 21342},
		items = set(6265),
	},
	-- ench
	{
		containers = {22246, 22248, 22249},
		items = union(
			ENCHANTING_MATERIALS,
			-- rods
			set(6218, 6339, 11130, 11145, 16207)
		),
	},
	-- herb
	{
		containers = {22250, 22251, 22252},
		items = union(HERBS, SEEDS)
	},
}

local defaultDelay = .2
if IsPlayingOnTurtleWoW() then
	-- https://turtle-wow.org/bug-report?id=2395
	defaultDelay = 1.2
end

local OUTFIT_ITEM_ALIASES = {
	[18608] = 18609, -- Benediction -> Anathema
	[18609] = 18608, -- Anathema -> Benediction
	[17223] = 17074, -- Thunderstrike -> Shadowstrike
	[17074] = 17223, -- Shadowstrike -> Thunderstrike
}

local OUTFIT_SLOT_ORDER = {
	HeadSlot = 1,
	ShoulderSlot = 2,
	ChestSlot = 3,
	WristSlot = 4,
	HandsSlot = 5,
	WaistSlot = 6,
	LegsSlot = 7,
	FeetSlot = 8,
	MainHandSlot = 9,
	TwoHandSlot = 9,
	Weapon0Slot = 9,
	SecondaryHandSlot = 10,
	Weapon1Slot = 10,
	RangedSlot = 11,
	AmmoSlot = 12,
	BackSlot = 13,
	NeckSlot = 14,
	ShirtSlot = 15,
	TabardSlot = 16,
	Finger0Slot = 17,
	Finger1Slot = 18,
	Trinket0Slot = 19,
	Trinket1Slot = 20,
}

local LookupOutfitSort, BuildOutfitSortMap
do
	local outfitExactMap, outfitLooseMap

	local function registerOutfitItem(itemCode, enchantCode, subCode, info)
		itemCode = tonumber(itemCode)
		if not itemCode then
			return
		end
		enchantCode = tonumber(enchantCode) or 0
		subCode = tonumber(subCode) or 0

		local exactKey = format('%s:%s:%s', itemCode, enchantCode, subCode)
		local looseKey = format('%s:%s', itemCode, subCode)
		if not outfitExactMap[exactKey] then
			outfitExactMap[exactKey] = info
		end
		if not outfitLooseMap[looseKey] then
			outfitLooseMap[looseKey] = info
		end

		local altCode = OUTFIT_ITEM_ALIASES[itemCode]
		if altCode then
			local altExactKey = format('%s:%s:%s', altCode, enchantCode, subCode)
			local altLooseKey = format('%s:%s', altCode, subCode)
			if not outfitExactMap[altExactKey] then
				outfitExactMap[altExactKey] = info
			end
			if not outfitLooseMap[altLooseKey] then
				outfitLooseMap[altLooseKey] = info
			end
		end
	end

	function BuildOutfitSortMap()
		outfitExactMap, outfitLooseMap = {}, {}

		if not (Outfitter_IsInitialized and Outfitter_IsInitialized()) then
			return
		end
		if not Outfitter_GetOutfitsByCategoryID then
			return
		end

		local categories
		if Outfitter_GetCategoryOrder then
			categories = Outfitter_GetCategoryOrder()
		else
			categories = {'Complete', 'Partial', 'Accessory', 'Special'}
		end

		local outfitIndex = 0
		for i = 1, table.getn(categories) do
			local outfits = Outfitter_GetOutfitsByCategoryID(categories[i])
			if outfits then
				local list = {}
				for _, outfit in outfits do
					tinsert(list, outfit)
				end
				sort(list, function(a, b)
					return (a.Name or '') < (b.Name or '')
				end)

				for j = 1, table.getn(list) do
					local outfit = list[j]
					if outfit.Items then
						local hasItems
						for _, item in outfit.Items do
							if item.Code and item.Code ~= 0 then
								hasItems = true
								break
							end
						end
						if hasItems then
							outfitIndex = outfitIndex + 1
							for slotName, item in outfit.Items do
								if item.Code and item.Code ~= 0 then
									registerOutfitItem(item.Code, item.EnchantCode, item.SubCode, {
										outfitIndex,
										OUTFIT_SLOT_ORDER[slotName] or 99,
									})
								end
							end
						end
					end
				end
			end
		end
	end

	function LookupOutfitSort(itemID, enchantID, suffixID)
		if not outfitExactMap then
			return
		end
		enchantID = tonumber(enchantID) or 0
		suffixID = tonumber(suffixID) or 0
		return outfitExactMap[format('%s:%s:%s', itemID, enchantID, suffixID)]
			or outfitLooseMap[format('%s:%s', itemID, suffixID)]
	end
end

-- Lower numbers sit at the start of the sort. Junk is placed separately, at the far end.
local CATEGORY = {
	HEARTH = 1,
	MOUNT = 2,
	SPECIAL = 3,
	KEY = 4,
	TOOL = 5,
	GEAR = 6,
	AMMO = 7,
	POTION = 8,
	FOOD = 9,
	BANDAGE = 10,
	CONSUMABLE = 11,
	CONJURED = 12,
	REAGENT = 13,
	QUEST = 14,
	HERB = 15,
	ENCHANT = 16,
	TRADE = 17,
	RECIPE = 18,
	OTHER = 19,
	JUNK = 20,
}

local CATEGORY_NAME = {
	'hearth', 'mount', 'special', 'key', 'tool',
	'gear', 'ammo', 'potion', 'food', 'bandage',
	'consumable', 'conjured', 'reagent', 'quest', 'herb',
	'enchant', 'trade', 'recipe', 'other', 'junk',
}

-- Item.dbc class ids. Auction class names are the fallback when no id is available.
local CLASS_CONSUMABLE = 0
local CLASS_WEAPON = 2
local CLASS_ARMOR = 4
local CLASS_REAGENT = 5
local CLASS_PROJECTILE = 6
local CLASS_TRADEGOODS = 7
local CLASS_RECIPE = 9
local CLASS_QUEST = 12

local AUCTION_CLASS = {
	[CLASS_CONSUMABLE] = 4,
	[CLASS_WEAPON] = 1,
	[CLASS_ARMOR] = 2,
	[CLASS_REAGENT] = 9,
	[CLASS_PROJECTILE] = 6,
	[CLASS_TRADEGOODS] = 5,
	[CLASS_RECIPE] = 8,
}

local function IsClass(classID, typeName, wanted)
	if classID ~= nil then
		return classID == wanted
	end
	local index = AUCTION_CLASS[wanted]
	return index and typeName == ITEM_TYPES[index]
end

local function FirstSpellCategory(itemID)
	if not IsNampowerLoaded() then
		return
	end
	local cats = GetItemStatsField(itemID, 'spellCategory', 1)
	if type(cats) == 'number' then
		if cats ~= 0 then
			return cats
		end
		return
	end
	if type(cats) ~= 'table' then
		return
	end
	for i = 1, 5 do
		if cats[i] and cats[i] ~= 0 then
			return cats[i]
		end
	end
end

-- spellCategory: 4 potion cooldown, 11 food, 59 drink, 150 bandage.
-- Elixirs and flasks use potion icons but not the potion cooldown.
local function ConsumableCategory(itemID, texture)
	local spellCategory = FirstSpellCategory(itemID)
	if spellCategory == 11 or spellCategory == 59 then
		return CATEGORY.FOOD, spellCategory
	end
	if spellCategory == 150 then
		return CATEGORY.BANDAGE, spellCategory
	end
	local icon = type(texture) == 'string' and strlower(texture) or ''
	if spellCategory == 4 or strfind(icon, 'inv_potion') then
		return CATEGORY.POTION, spellCategory
	end
	return CATEGORY.CONSUMABLE, spellCategory
end

local model, itemStacks, itemClasses, itemSortKeys

local CLASSIC_MAX_ROUNDS = 10
local CLASSIC_TIMEOUT = 15
local CLASSIC_QUIET = .5

do
	local f = CreateFrame'Frame'
	f:Hide()

	local timeout
	local initialized
	local state
	local rounds
	local startedAt
	local quietUntil
	local running
	local rerun
	local rerunBudget

	local function Stop()
		f:UnregisterEvent('BAG_UPDATE_DELAYED')
		f:UnregisterEvent('ITEM_DATA_LOAD_RESULT')
		f:UnregisterEvent('ITEM_LOCK_CHANGED')
		f:UnregisterEvent('BANKFRAME_CLOSED')
		f:Hide()
		usingClassicAPI = false
		sorting = false
		state = nil
	end

	local function Report(done)
		if SortBagsDebug then
			DEFAULT_CHAT_FRAME:AddMessage(format(
				'SortBags: %s in %d rounds, %.2fs',
				done and 'done' or 'incomplete',
				rounds or 0,
				GetTime() - (startedAt or GetTime())
			))
		end
		if not done then
			DEFAULT_CHAT_FRAME:AddMessage('SortBags: sorting incomplete, please run again')
		end
		Stop()
	end

	-- Predicted slot keys use the same identity Item() builds, so a settle
	-- check can tell a charges/enchant swap from "same item id, already there".
	local function LiveMatchesModel()
		for _, slot in model do
			local info = C_Container.GetContainerItemInfo(slot.container, slot.position)
			if slot.item == nil then
				if info then
					return false
				end
			else
				if not info then
					return false
				end
				-- Same link fields Item() keeps, so enchant/suffix swaps are visible.
				local _, _, itemID, enchantID, suffixID, uniqueID = strfind(GetContainerItemLink(slot.container, slot.position) or '', 'item:(%d+):(%d*):(%d*):(%d*)')
				if info.hyperlink then
					local _, _, _, linkEnchant, linkSuffix, linkUnique = strfind(info.hyperlink, 'item:(%d+):(%d*):(%d*):(%d*)')
					if linkEnchant and linkEnchant ~= '' then
						enchantID = linkEnchant
					end
					if linkSuffix and linkSuffix ~= '' then
						suffixID = linkSuffix
					end
					if linkUnique and linkUnique ~= '' then
						uniqueID = linkUnique
					end
				end
				if not itemID then
					return false
				end
				local charges = 1
				if info.stackCount and info.stackCount > 0 and C_Container.GetContainerItemCharges then
					local uses = C_Container.GetContainerItemCharges(slot.container, slot.position)
					if uses then
						charges = uses / info.stackCount
					end
				end
				if ItemKey(itemID, enchantID, suffixID, uniqueID, charges, info.isBound) ~= slot.item
					or info.stackCount ~= slot.count then
					return false
				end
			end
		end
		return true
	end

	local Step

	local function FinishStep()
		running = false
		-- A cache hit can fire ITEM_DATA_LOAD_RESULT inside Initialize.
		-- Replay once, but don't spin if the item still isn't readable.
		if rerun and f:IsShown() and rerunBudget > 0 then
			rerun = false
			rerunBudget = rerunBudget - 1
			Step()
		end
	end

	Step = function()
		if running then
			rerun = true
			return
		end
		rerun = false
		running = true

		if GetTime() > timeout then
			Report(false)
			FinishStep()
			return
		end

		if not Initialize() then
			state = 'waitdata'
			FinishStep()
			return
		end

		if LayoutComplete() then
			Report(true)
			FinishStep()
			return
		end

		if rounds >= CLASSIC_MAX_ROUNDS then
			Report(false)
			FinishStep()
			return
		end

		rounds = rounds + 1
		local sent = Consolidate()
		if sent == 0 then
			sent = Place()
		end
		if SortBagsDebug then
			DEFAULT_CHAT_FRAME:AddMessage(format('SortBags: round %d sent %d', rounds, sent))
		end
		if sent == 0 then
			Report(false)
		else
			state = 'settle'
			quietUntil = GetTime() + CLASSIC_QUIET
		end
		FinishStep()
	end

	-- Only leave 'settle' once. OnEvent and the quiet timer can both
	-- observe the same round; the second call must not start another.
	local function NextRound()
		if state ~= 'settle' then
			return
		end
		quietUntil = nil
		state = 'run'
		Step()
	end

	function Start()
		if f:IsShown() then return end
		sorting = true
		usingClassicAPI = HasClassicAPI()
		initialized = false
		if usingClassicAPI then
			state = 'run'
			rounds = 0
			rerunBudget = 8
			startedAt = GetTime()
			timeout = GetTime() + CLASSIC_TIMEOUT
			quietUntil = nil
			f:RegisterEvent('BAG_UPDATE_DELAYED')
			f:RegisterEvent('ITEM_DATA_LOAD_RESULT')
			f:RegisterEvent('ITEM_LOCK_CHANGED')
			f:RegisterEvent('BANKFRAME_CLOSED')
			f:Show()
			Step()
			return
		end
		timeout = GetTime() + 35 * defaultDelay
		f:Show()
	end

	f:SetScript('OnEvent', function()
		if not usingClassicAPI then
			return
		end
		if event == 'BANKFRAME_CLOSED' and sortingBank then
			if SortBagsDebug then
				DEFAULT_CHAT_FRAME:AddMessage(format(
					'SortBags: bank closed after %.2fs',
					GetTime() - (startedAt or GetTime())
				))
			end
			DEFAULT_CHAT_FRAME:AddMessage('SortBags: bank closed, sorting stopped')
			Stop()
			return
		end
		if state == 'waitdata' and (event == 'ITEM_DATA_LOAD_RESULT' or event == 'ITEM_LOCK_CHANGED') then
			Step()
			return
		end
		if state == 'settle' and event == 'BAG_UPDATE_DELAYED' then
			quietUntil = GetTime() + CLASSIC_QUIET
			if LiveMatchesModel() then
				NextRound()
			end
		end
	end)

	local delay = 0
	f:SetScript('OnUpdate', function()
		if usingClassicAPI then
			if GetTime() > timeout then
				Report(false)
				return
			end
			if state == 'settle' and quietUntil and GetTime() >= quietUntil then
				NextRound()
			end
			return
		end

		delay = delay - arg1
		if delay <= 0 then
			delay = defaultDelay

			if not initialized then
				if not Initialize() then
					if GetTime() > timeout then
						DEFAULT_CHAT_FRAME:AddMessage('SortBags: sorting incomplete, please run again')
						sorting = false
						f:Hide()
					end
					return
				end
				initialized = true
			end

			local complete = Sort()
			if complete then
				sorting = false
				f:Hide()
				return
			end
			if GetTime() > timeout then
				DEFAULT_CHAT_FRAME:AddMessage('SortBags: sorting incomplete, please run again')
				sorting = false
				f:Hide()
				return
			end
			Stack()
		end
	end)
end

do
	local function key(table, value)
		for k, v in table do
			if v == value then
				return k
			end
		end
	end

	local typeKeys, subTypeKeys, invTypeKeys = {}, {}, {}

	function ItemTypeKey(itemClass)
		if not itemClass or itemClass == '' then
			return 0
		end
		if typeKeys[itemClass] == nil then
			typeKeys[itemClass] = key(ITEM_TYPES, itemClass) or 0
		end
		return typeKeys[itemClass]
	end

	function ItemSubTypeKey(itemClass, itemSubClass)
		local cacheKey = (itemClass or '') .. '\0' .. (itemSubClass or '')
		if subTypeKeys[cacheKey] == nil then
			subTypeKeys[cacheKey] = key({GetAuctionItemSubClasses(ItemTypeKey(itemClass))}, itemSubClass) or 0
		end
		return subTypeKeys[cacheKey]
	end

	function ItemInvTypeKey(itemClass, itemSubClass, itemSlot)
		local cacheKey = (itemClass or '') .. '\0' .. (itemSubClass or '') .. '\0' .. (itemSlot or '')
		if invTypeKeys[cacheKey] == nil then
			invTypeKeys[cacheKey] = key({GetAuctionInvTypes(ItemTypeKey(itemClass), ItemSubTypeKey(itemClass, itemSubClass))}, itemSlot) or 0
		end
		return invTypeKeys[cacheKey]
	end
end

function LT(a, b)
	local i = 1
	while true do
		if a[i] and b[i] and a[i] ~= b[i] then
			return a[i] < b[i]
		elseif not a[i] and b[i] then
			return true
		elseif not b[i] then
			return false
		end
		i = i + 1
	end
end

function Move(src, dst)
    local texture, _, srcLocked = GetContainerItemInfo(src.container, src.position)
    local _, _, dstLocked = GetContainerItemInfo(dst.container, dst.position)
    
	if texture and not srcLocked and not dstLocked then
		ClearCursor()
       	PickupContainerItem(src.container, src.position)
		PickupContainerItem(dst.container, dst.position)

		if src.item == dst.item then
			local count = min(src.count, itemStacks[dst.item] - dst.count)
			src.count = src.count - count
			dst.count = dst.count + count
			if src.count == 0 then
				src.item = nil
			end
		else
			src.item, dst.item = dst.item, src.item
			src.count, dst.count = dst.count, src.count
		end

		return true
    end
end

local function MakeChargesPattern(template)
	if not template then
		return
	end
	return '^' .. gsub(gsub(template, '%%d', '(%%d+)'), '%%%d+%$d', '(%%d+)') .. '$'
end

local CHARGES_PATTERNS = {}
do
	local p1 = MakeChargesPattern(ITEM_SPELL_CHARGES_P1)
	if p1 then
		tinsert(CHARGES_PATTERNS, p1)
	end
	if ITEM_SPELL_CHARGES and ITEM_SPELL_CHARGES ~= ITEM_SPELL_CHARGES_P1 then
		local p = MakeChargesPattern(ITEM_SPELL_CHARGES)
		if p then
			tinsert(CHARGES_PATTERNS, p)
		end
	end
end

function TooltipInfo(container, position)
	SortBagsTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	SortBagsTooltip:ClearLines()

	if container == BANK_CONTAINER then
		SortBagsTooltip:SetInventoryItem('player', BankButtonIDToInvSlotID(position))
	else
		SortBagsTooltip:SetBagItem(container, position)
	end

	local charges, usable, soulbound, quest, conjured
	for i = 1, SortBagsTooltip:NumLines() do
		local text = getglobal('SortBagsTooltipTextLeft' .. i):GetText()
		if text then
			local chargeString
			for _, pattern in CHARGES_PATTERNS do
				local _, _, match = strfind(text, pattern)
				if match then
					chargeString = match
					break
				end
			end
			if chargeString then
				charges = tonumber(chargeString)
			elseif strfind(text, '^' .. ITEM_SPELL_TRIGGER_ONUSE) then
				usable = true
			elseif text == ITEM_SOULBOUND then
				soulbound = true
			elseif text == ITEM_BIND_QUEST then
				quest = true
			elseif text == ITEM_CONJURED then
				conjured = true
			end
		end
	end

	return charges or 1, usable, soulbound, quest, conjured
end

local function NampowerItemInfo(bagItem, itemID)
	local instanceFlags = bagItem.flags or 0
	local dbcFlags = GetItemStatsField(itemID, 'flags') or 0
	local bonding = GetItemStatsField(itemID, 'bonding')

	local soulbound = HasFlag(instanceFlags, 1) or bonding == 1
	local quest = bonding == 4 or bonding == 5
	local conjured = HasFlag(dbcFlags, 2)

	local usable
	local spellIDs = GetItemStatsField(itemID, 'spellID', 1)
	local spellTriggers = GetItemStatsField(itemID, 'spellTrigger', 1)
	if spellIDs and spellTriggers then
		for i = 1, 5 do
			if spellIDs[i] and spellIDs[i] ~= 0 and spellTriggers[i] == 0 then
				usable = true
				break
			end
		end
	end

	local charges = 1
	local spellCharges = GetItemStatsField(itemID, 'spellCharges', 1)
	local hasCharges
	if spellCharges then
		for i = 1, 5 do
			if spellCharges[i] and spellCharges[i] ~= 0 then
				hasCharges = true
				break
			end
		end
	end
	if hasCharges then
		charges = abs(bagItem.spellChargesRemaining or 0)
	end

	return charges, usable, soulbound, quest, conjured
end

function Sort()
	local complete = true

	for _, dst in model do
		if dst.targetItem and (dst.item ~= dst.targetItem or dst.count < dst.targetCount) then
			complete = false

			local sources, rank = {}, {}

			for _, src in model do
				if src.item == dst.targetItem
					and src ~= dst
					and not (dst.item and src.class and src.class ~= itemClasses[dst.item])
					and not (src.targetItem and src.item == src.targetItem and src.count <= src.targetCount)
				then
					rank[src] = abs(src.count - dst.targetCount + (dst.item == dst.targetItem and dst.count or 0))
					tinsert(sources, src)
				end
			end

			sort(sources, function(a, b) return rank[a] < rank[b] end)

			for _, src in sources do
				if Move(src, dst) then
					break
				end
			end
		end
	end

	return complete
end

function Stack()
	for _, src in model do
		if src.item and src.count < itemStacks[src.item] and src.item ~= src.targetItem then
			for _, dst in model do
				if dst ~= src and dst.item and dst.item == src.item and dst.count < itemStacks[dst.item] and dst.item ~= dst.targetItem then
					if Move(src, dst) then
						return
					end
				end
			end
		end
	end
end

function LayoutComplete()
	for _, dst in model do
		if dst.targetItem and (dst.item ~= dst.targetItem or dst.count < dst.targetCount) then
			return false
		end
	end
	return true
end

-- SwapItems/MoveItem resolve the source against client state, which stays
-- at the pre-batch snapshot until the server replies. A slot is only a
-- valid source while the model still matches that snapshot.
local function sameAsLive(slot)
	return slot.item == slot.liveItem and slot.count == slot.liveCount
end

local function sourceFresh(slot)
	return slot.item and slot.liveOccupied and sameAsLive(slot)
end

function MoveBatch(src, dst, count)
	if src == dst or not src.item then
		return
	end

	if src.item == dst.item then
		if not sourceFresh(src) or dst.liveItem ~= src.item or dst.item ~= src.item then
			return
		end
		local space = itemStacks[dst.item] - dst.count
		if not count then
			count = min(src.count, space)
		end
		count = min(count, space, src.count)
		if count < 1 then
			return
		end
		-- A full-stack MoveItem reads the live count and is rejected once an
		-- earlier packet in this batch has already emptied that stack.
		local ok
		if count >= src.count then
			ok = C_Container.SwapItems(src.container, src.position, dst.container, dst.position)
		else
			ok = C_Container.MoveItem(src.container, src.position, dst.container, dst.position, count)
		end
		if not ok then
			return
		end
		src.count = src.count - count
		dst.count = dst.count + count
		if src.count == 0 then
			src.item = nil
		end
		return true
	end

	if not sourceFresh(src) or not sameAsLive(dst) then
		return
	end
	local ok = C_Container.SwapItems(src.container, src.position, dst.container, dst.position)
	if not ok and sourceFresh(dst) then
		ok = C_Container.SwapItems(dst.container, dst.position, src.container, src.position)
	end
	if not ok then
		return
	end
	src.item, dst.item = dst.item, src.item
	src.count, dst.count = dst.count, src.count
	return true
end

function Place()
	local sent = 0

	for _, dst in model do
		if dst.targetItem and (dst.item ~= dst.targetItem or dst.count < dst.targetCount) then
			local sources, rank = {}, {}

			for _, src in model do
				if src.item == dst.targetItem
					and src ~= dst
					and not (dst.item and src.class and src.class ~= itemClasses[dst.item])
					and not (src.targetItem and src.item == src.targetItem and src.count <= src.targetCount)
				then
					rank[src] = abs(src.count - dst.targetCount + (dst.item == dst.targetItem and dst.count or 0))
					tinsert(sources, src)
				end
			end

			sort(sources, function(a, b) return rank[a] < rank[b] end)

			for _, src in sources do
				if MoveBatch(src, dst) then
					sent = sent + 1
					break
				end
			end
		end
	end

	return sent
end

function Consolidate()
	local groups = {}
	for _, slot in model do
		if slot.item and slot.count < itemStacks[slot.item] then
			if not groups[slot.item] then
				groups[slot.item] = {}
			end
			tinsert(groups[slot.item], slot)
		end
	end

	local sent = 0
	for _, stacks in groups do
		if table.getn(stacks) >= 2 then
			sort(stacks, function(a, b)
				return a.count > b.count
			end)
			local lo, hi = 1, table.getn(stacks)
			while lo < hi do
				local dst, src = stacks[lo], stacks[hi]
				local space = itemStacks[dst.item] - dst.count
				if space <= 0 then
					lo = lo + 1
				elseif MoveBatch(src, dst, min(space, src.count)) then
					sent = sent + 1
					if src.count == 0 then
						hi = hi - 1
					else
						lo = lo + 1
					end
				else
					hi = hi - 1
				end
			end
		end
	end
	return sent
end

do
	local counts

	local function insert(t, v)
		if SortBagsRightToLeft then
			tinsert(t, v)
		else
			tinsert(t, 1, v)
		end
	end

	local function assign(slot, item)
		if counts[item] > 0 then
			local count
			if SortBagsRightToLeft and mod(counts[item], itemStacks[item]) ~= 0 then
				count = mod(counts[item], itemStacks[item])
			else
				count = min(counts[item], itemStacks[item])
			end
			slot.targetItem = item
			slot.targetCount = count
			counts[item] = counts[item] - count
			return true
		end
	end

	function Initialize()
		model, counts, itemStacks, itemClasses, itemSortKeys = {}, {}, {}, {}, {}
		BuildOutfitSortMap()

		for _, container in CONTAINERS do
			local class = ContainerClass(container)
			if class == false then
				return false
			end
			for position = 1, GetContainerNumSlots(container) do
				local slot = {container=container, position=position, class=class}
				if usingClassicAPI then
					local info = C_Container.GetContainerItemInfo(container, position)
					if info and info.isLocked then
						return false
					end
				else
					local texture, _, locked = GetContainerItemInfo(container, position)
					if texture and locked then
						return false
					end
				end
				local item = Item(container, position)
				if item == false then
					return false
				end
				if item then
					local count = GetContainerItemCount(container, position)
					slot.item = item
					slot.count = count
					counts[item] = (counts[item] or 0) + count
				end
				slot.liveItem = slot.item
				slot.liveCount = slot.count
				slot.liveOccupied = slot.item ~= nil
				insert(model, slot)
			end
		end

		local free = {}
		for item, count in counts do
			local stacks = ceil(count / itemStacks[item])
			free[item] = stacks
			if itemClasses[item] then
				free[itemClasses[item]] = (free[itemClasses[item]] or 0) + stacks
			end
		end
		for _, slot in model do
			if slot.class and free[slot.class] then
				free[slot.class] = free[slot.class] - 1
			end
		end

		local items = {}
		for item in counts do
			tinsert(items, item)
		end
		sort(items, function(a, b) return LT(itemSortKeys[a], itemSortKeys[b]) end)

		-- Junk with no specialty bag sits at the far end of the sort.
		-- Empty slots stay between the other items and the junk.
		local normal, junk = {}, {}
		for _, item in items do
			if itemSortKeys[item][1] == CATEGORY.JUNK and not itemClasses[item] then
				tinsert(junk, item)
			else
				tinsert(normal, item)
			end
		end

		local generic = {}
		for _, slot in model do
			if not slot.class then
				tinsert(generic, slot)
			end
		end
		local junkSlots = 0
		for _, item in junk do
			junkSlots = junkSlots + ceil(counts[item] / itemStacks[item])
		end
		local firstJunk = table.getn(generic) - junkSlots + 1
		if firstJunk < 1 then
			firstJunk = 1
		end
		for i = firstJunk, table.getn(generic) do
			local slot = generic[i]
			for _, item in junk do
				if assign(slot, item) then
					break
				end
			end
		end

		for _, slot in model do
			if not slot.targetItem then
				if slot.class then
					for _, item in normal do
						if itemClasses[item] == slot.class and assign(slot, item) then
							break
						end
					end
				else
					for _, item in normal do
						if (not itemClasses[item] or free[itemClasses[item]] > 0) and assign(slot, item) then
							if itemClasses[item] then
								free[itemClasses[item]] = free[itemClasses[item]] - 1
							end
							break
						end
					end
				end
			end
		end

		return true
	end
end

function ContainerClass(container)
	if container ~= 0 and container ~= BANK_CONTAINER then
		if usingClassicAPI then
			local invID = ContainerIDToInventoryID(container)
			local bagLink = invID and GetInventoryItemLink('player', invID)
			if not bagLink then
				return
			end
			local _, _, bagItemID = strfind(bagLink, 'item:(%d+)')
			bagItemID = tonumber(bagItemID)
			local family = C_Item.GetItemFamily(bagItemID or bagLink)
			if family == nil then
				if bagItemID and C_Item.GetItemDataByID(bagItemID) then
					family = 0
				else
					if bagItemID and C_Item.RequestLoadItemDataByID then
						C_Item.RequestLoadItemDataByID(bagItemID)
					end
					return false
				end
			end
			if family ~= 0 then
				return family
			end
			return
		end
		if IsNampowerLoaded() then
			local invID = ContainerIDToInventoryID(container)
			local bagLink = invID and GetInventoryItemLink('player', invID)
			if bagLink then
				local _, _, bagItemID = strfind(bagLink, 'item:(%d+)')
				local family = GetNampowerBagFamily(tonumber(bagItemID))
				if family then
					return family
				end
			end
		end
		local name = GetBagName(container)
		if name then
			for class, info in CLASSES do
				for _, itemID in info.containers do
					if name == GetItemInfo(itemID) then
						if IsNampowerLoaded() then
							return NampowerClassFromClassesIndex(class)
						end
						return class
					end
				end
			end
		end
	end
end

function Item(container, position)
	local link = GetContainerItemLink(container, position)
	if link then
		local _, _, itemID, enchantID, suffixID, uniqueID = strfind(link, 'item:(%d+):(%d*):(%d*):(%d*)')
		itemID = tonumber(itemID)
		if not itemID then
			return false
		end

		local name, quality, type, subType, stack, invType
		local charges, usable, soulbound, quest, conjured
		local classID

		if usingClassicAPI then
			local info = C_Container.GetContainerItemInfo(container, position)
			if info and info.hyperlink then
				local _, _, _, linkEnchant, linkSuffix, linkUnique = strfind(info.hyperlink, 'item:(%d+):(%d*):(%d*):(%d*)')
				if linkEnchant and linkEnchant ~= '' then
					enchantID = linkEnchant
				end
				if linkSuffix and linkSuffix ~= '' then
					suffixID = linkSuffix
				end
				if linkUnique and linkUnique ~= '' then
					uniqueID = linkUnique
				end
			end

			local data = C_Item.GetItemDataByID(itemID)
			if not data or not data.name then
				if C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(itemID)
				end
				return false
			end

			name = data.name
			quality = data.quality or 0
			type = data.className
			subType = data.subclassName
			stack = data.maxStackSize
			if not stack or stack < 1 then
				stack = 1
			end
			classID = data.classID
			if data.equipLoc and data.equipLoc ~= '' then
				invType = getglobal(data.equipLoc)
			end
			soulbound = info and info.isBound
			quest = data.bindType == 4 or data.bindType == 5
			conjured = data.isConjured
			if C_Item.GetItemSpell then
				usable = C_Item.GetItemSpell(itemID) ~= nil
			end
			charges = 1
			if info and info.stackCount and info.stackCount > 0 and C_Container.GetContainerItemCharges then
				local uses = C_Container.GetContainerItemCharges(container, position)
				if uses then
					charges = uses / info.stackCount
				end
			end
		else
			local infoName, _, infoQuality, _, infoType, infoSubType, infoStack, infoInvType = GetItemInfo(itemID)
			name, quality, type, subType, stack, invType = infoName, infoQuality, infoType, infoSubType, infoStack, infoInvType
			if not name then
				return false
			end

			local bagItem = SnapshotBagItem(container, position)
			if bagItem then
				charges, usable, soulbound, quest, conjured = NampowerItemInfo(bagItem, itemID)
				if (not enchantID or enchantID == '') and bagItem.permanentEnchantId and bagItem.permanentEnchantId ~= 0 then
					enchantID = tostring(bagItem.permanentEnchantId)
				end
				if (not suffixID or suffixID == '') and bagItem.randomPropertiesId and bagItem.randomPropertiesId ~= 0 then
					suffixID = tostring(bagItem.randomPropertiesId)
				end
			else
				charges, usable, soulbound, quest, conjured = TooltipInfo(container, position)
			end
		end
		if classID == nil and IsNampowerLoaded() then
			classID = tonumber(GetItemStatsField(itemID, 'class'))
		end
		local family
		if IsNampowerLoaded() then
			family = GetNampowerItemFamily(itemID)
		end
		local texture = GetContainerItemInfo(container, position)
		local outfitInfo = LookupOutfitSort(itemID, enchantID, suffixID)

		local isWeapon = IsClass(classID, type, CLASS_WEAPON)
		local isArmor = IsClass(classID, type, CLASS_ARMOR)
		local isRecipe = IsClass(classID, type, CLASS_RECIPE)
		local category
		local spellCategory
		local sortKey = {}

		-- hearthstone and related
		if itemID == 6948 or itemID == 41915 or itemID == 61000 then
			category = CATEGORY.HEARTH
			tinsert(sortKey, itemID)

		-- mounts
		elseif MOUNTS[itemID] then
			category = CATEGORY.MOUNT

		-- special items
		elseif SPECIAL[itemID] then
			category = CATEGORY.SPECIAL

		-- key items
		elseif KEYS[itemID] then
			category = CATEGORY.KEY

		-- tools
		elseif TOOLS[itemID] then
			category = CATEGORY.TOOL

		-- soul shards sit with class reagents
		elseif itemID == 6265 then
			category = CATEGORY.REAGENT

		-- quest items
		elseif quest or IsClass(classID, type, CLASS_QUEST) then
			category = CATEGORY.QUEST

		-- junk
		elseif quality == 0 then
			category = CATEGORY.JUNK

		-- conjured items
		elseif conjured then
			category = CATEGORY.CONJURED

		-- Outfitter outfit items, then bound gear, then the rest
		elseif outfitInfo then
			category = CATEGORY.GEAR
			tinsert(sortKey, 1)
			tinsert(sortKey, outfitInfo[1])
			tinsert(sortKey, outfitInfo[2])

		elseif isWeapon or isArmor then
			category = CATEGORY.GEAR
			tinsert(sortKey, soulbound and 2 or 3)

		-- ammo
		elseif IsClass(classID, type, CLASS_PROJECTILE) then
			category = CATEGORY.AMMO

		-- reagents, including druid seeds
		elseif IsClass(classID, type, CLASS_REAGENT) or SEEDS[itemID] then
			category = CATEGORY.REAGENT

		-- consumables, plus usable items that are not gear or recipes
		elseif IsClass(classID, type, CLASS_CONSUMABLE) or (usable and not isWeapon and not isArmor and not isRecipe) then
			category, spellCategory = ConsumableCategory(itemID, texture)
			if category == CATEGORY.POTION then
				tinsert(sortKey, spellCategory == 4 and 1 or 2)
			elseif category == CATEGORY.FOOD and spellCategory then
				tinsert(sortKey, spellCategory)
			end

		-- herbs, including turtle herbs that fit a herb bag
		elseif HERBS[itemID] or family == 6 then
			category = CATEGORY.HERB

		-- enchanting dust, essence, shards, crystals
		elseif ENCHANTING_MATERIALS[itemID] or family == 7 then
			category = CATEGORY.ENCHANT

		-- other profession materials, clustered by bag family
		elseif IsClass(classID, type, CLASS_TRADEGOODS) then
			category = CATEGORY.TRADE
			tinsert(sortKey, family or 0)

		-- recipes
		elseif isRecipe then
			category = CATEGORY.RECIPE

		else
			category = CATEGORY.OTHER
		end

		tinsert(sortKey, 1, category)
		tinsert(sortKey, ItemTypeKey(type))
		tinsert(sortKey, ItemInvTypeKey(type, subType, invType))
		tinsert(sortKey, ItemSubTypeKey(type, subType))
		tinsert(sortKey, -quality)
		tinsert(sortKey, itemID)
		tinsert(sortKey, (SortBagsRightToLeft and 1 or -1) * charges)
		tinsert(sortKey, suffixID)
		tinsert(sortKey, enchantID)
		tinsert(sortKey, uniqueID)

		local key = ItemKey(itemID, enchantID, suffixID, uniqueID, charges, soulbound)

		itemStacks[key] = stack
		itemSortKeys[key] = sortKey

		if usingClassicAPI then
			-- Containers and quivers are bags you carry, not items that
			-- belong inside a specialty bag of the same family.
			if classID ~= 1 and classID ~= 11 then
				local family = C_Item.GetItemFamily(itemID)
				if family and family ~= 0 then
					itemClasses[key] = family
				end
			end
		elseif IsNampowerLoaded() then
			local family = GetNampowerItemFamily(itemID)
			if family then
				itemClasses[key] = family
			end
		end
		if not itemClasses[key] and not usingClassicAPI then
			for class, info in CLASSES do
				if info.items[itemID] then
					if IsNampowerLoaded() then
						itemClasses[key] = NampowerClassFromClassesIndex(class)
					else
						itemClasses[key] = class
					end
					break
				end
			end
		end

		return key
	end
end

function _G.SortBagsDump()
	if sorting then
		DEFAULT_CHAT_FRAME:AddMessage('SortBags: sorting in progress')
		return
	end

	local savedClassic = usingClassicAPI
	local savedStacks = itemStacks
	local savedClasses = itemClasses
	local savedKeys = itemSortKeys

	local function restore()
		usingClassicAPI = savedClassic
		itemStacks = savedStacks
		itemClasses = savedClasses
		itemSortKeys = savedKeys
	end

	usingClassicAPI = HasClassicAPI()
	itemStacks, itemClasses, itemSortKeys = {}, {}, {}

	local ok, err = pcall(function()
		BuildOutfitSortMap()
		for _, container in {0, 1, 2, 3, 4} do
			for position = 1, GetContainerNumSlots(container) do
				local link = GetContainerItemLink(container, position)
				if link then
					local key = Item(container, position)
					local name = 'unloaded'
					if key and itemSortKeys[key] then
						name = CATEGORY_NAME[itemSortKeys[key][1]] or '?'
					end
					DEFAULT_CHAT_FRAME:AddMessage(link .. ' -> ' .. name)
				end
			end
		end
	end)

	restore()
	if not ok then
		DEFAULT_CHAT_FRAME:AddMessage('SortBags: dump failed: ' .. tostring(err))
	end
end
