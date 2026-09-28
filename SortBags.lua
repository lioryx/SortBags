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

function _G.SortBags()
	CONTAINERS = {0, 1, 2, 3, 4}
	Start()
end

function _G.SortBankBags()
	if GetContainerNumSlots(BANK_CONTAINER) == 0 then
		DEFAULT_CHAT_FRAME:AddMessage('SortBags: bank is not open')
		return
	end
	CONTAINERS = {-1, 5, 6, 7, 8, 9, 10}
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

local KEYS = set(9240, 17191, 13544, 12324, 16309, 12384, 20402)

local TOOLS = set(7005, 12709, 19727, 5956, 2901, 6219, 10498, 6218, 6339, 11130, 11145, 16207, 9149, 15846, 6256, 6365, 6367)

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

local model, itemStacks, itemClasses, itemSortKeys

do
	local f = CreateFrame'Frame'
	f:Hide()

	local timeout
	local initialized

	function Start()
		if f:IsShown() then return end
		initialized = false
		timeout = GetTime() + 35 * defaultDelay
		f:Show()
	end

	local delay = 0
	f:SetScript('OnUpdate', function()
		delay = delay - arg1
		if delay <= 0 then
			delay = defaultDelay

			if not initialized then
				if not Initialize() then
					if GetTime() > timeout then
						DEFAULT_CHAT_FRAME:AddMessage('SortBags: sorting incomplete, please run again')
						f:Hide()
					end
					return
				end
				initialized = true
			end

			local complete = Sort()
			if complete then
				f:Hide()
				return
			end
			if GetTime() > timeout then
				DEFAULT_CHAT_FRAME:AddMessage('SortBags: sorting incomplete, please run again')
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

	function ItemTypeKey(itemClass)
		return key(ITEM_TYPES, itemClass) or 0
	end

	function ItemSubTypeKey(itemClass, itemSubClass)
		return key({GetAuctionItemSubClasses(ItemTypeKey(itemClass))}, itemSubClass) or 0
	end

	function ItemInvTypeKey(itemClass, itemSubClass, itemSlot)
		return key({GetAuctionInvTypes(ItemTypeKey(itemClass), ItemSubTypeKey(itemClass, itemSubClass))}, itemSlot) or 0
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
			for position = 1, GetContainerNumSlots(container) do
				local slot = {container=container, position=position, class=class}
				local texture, _, locked = GetContainerItemInfo(container, position)
				if texture and locked then
					return false
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

		for _, slot in model do
			if slot.class then
				for _, item in items do
					if itemClasses[item] == slot.class and assign(slot, item) then
						break
					end
				end
			else
				for _, item in items do
					if (not itemClasses[item] or free[itemClasses[item]] > 0) and assign(slot, item) then
						if itemClasses[item] then
							free[itemClasses[item]] = free[itemClasses[item]] - 1
						end
						break
					end
				end
			end
		end

		return true
	end
end

function ContainerClass(container)
	if container ~= 0 and container ~= BANK_CONTAINER then
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
		local name, _, quality, _, type, subType, stack, invType = GetItemInfo(itemID)
		if not name then
			return false
		end

		local charges, usable, soulbound, quest, conjured
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
		local outfitInfo = LookupOutfitSort(itemID, enchantID, suffixID)

		local sortKey = {}

		-- hearthstone and related
		if itemID == 6948 or itemID == 41915 or itemID == 61000 then
			tinsert(sortKey, 1)
			tinsert(sortKey, itemID)

		-- mounts
		elseif MOUNTS[itemID] then
			tinsert(sortKey, 2)

		-- special items
		elseif SPECIAL[itemID] then
			tinsert(sortKey, 3)

		-- key items
		elseif KEYS[itemID] then
			tinsert(sortKey, 4)

		-- tools
		elseif TOOLS[itemID] then
			tinsert(sortKey, 5)

		-- soul shards
		elseif itemID == 6265 then
			tinsert(sortKey, 14)

		-- conjured items
		elseif conjured then
			tinsert(sortKey, 15)

		-- Outfitter outfit items
		elseif outfitInfo then
			tinsert(sortKey, 6)
			tinsert(sortKey, outfitInfo[1])
			tinsert(sortKey, outfitInfo[2])

		-- soulbound items
		elseif soulbound then
			tinsert(sortKey, 6)
			tinsert(sortKey, 10000)

		-- reagents
		elseif type == ITEM_TYPES[9] then
			tinsert(sortKey, 7)

		-- quest items
		elseif quest then
			tinsert(sortKey, 9)

		-- consumables
		elseif usable and type ~= ITEM_TYPES[1] and type ~= ITEM_TYPES[2] and type ~= ITEM_TYPES[8] or type == ITEM_TYPES[4] then
			tinsert(sortKey, 8)

		-- enchanting materials
		elseif ENCHANTING_MATERIALS[itemID] then
			tinsert(sortKey, 11)

		-- herbs
		elseif HERBS[itemID] then
			tinsert(sortKey, 12)

		-- higher quality
		elseif quality > 1 then
			tinsert(sortKey, 10)

		-- common quality
		elseif quality == 1 then
			tinsert(sortKey, 13)

		-- junk
		elseif quality == 0 then
			tinsert(sortKey, 14)
		end

		tinsert(sortKey, ItemTypeKey(type))
		tinsert(sortKey, ItemInvTypeKey(type, subType, invType))
		tinsert(sortKey, ItemSubTypeKey(type, subType))
		tinsert(sortKey, -quality)
		tinsert(sortKey, itemID)
		tinsert(sortKey, (SortBagsRightToLeft and 1 or -1) * charges)
		tinsert(sortKey, suffixID)
		tinsert(sortKey, enchantID)
		tinsert(sortKey, uniqueID)

		local key = format('%s:%s:%s:%s:%s:%s', itemID, enchantID, suffixID, uniqueID, charges, (soulbound and 1 or 0))

		itemStacks[key] = stack
		itemSortKeys[key] = sortKey

		if IsNampowerLoaded() then
			local family = GetNampowerItemFamily(itemID)
			if family then
				itemClasses[key] = family
			end
		end
		if not itemClasses[key] then
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
