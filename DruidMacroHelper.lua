local _, L = ...;
local DRUID_MACRO_HELPER_LOC_IGNORED = { "SCHOOL_INTERRUPT", "DISARM", "PACIFYSILENCE", "SILENCE", "PACIFY" };
local DRUID_MACRO_HELPER_LOC_SHIFTABLE = { "ROOT" };
local DRUID_MACRO_HELPER_LOC_STUN = { "STUN", "STUN_MECHANIC", "FEAR", "CHARM", "CONFUSE", "POSSESS" };

DruidMacroHelper = {};

function DruidMacroHelper:Init()
    self:RegisterItemShortcut("pot", 13446);
    self:RegisterItemShortcut("potion", 13446);
    self:RegisterItemShortcut("hs", 20520);
    self:RegisterItemShortcut("rune", 20520);
    self:RegisterItemShortcut("seed", 20520);
    self:RegisterItemShortcut("sapper", 10646);
    self:RegisterItemShortcut("supersapper", 23827);
    self:RegisterItemShortcut("drums", 13180);
    self:RegisterItemShortcut("holywater", 13180);
    self:RegisterSlashCommand("/dmh");
    self:RegisterSlashCommand("/druidmacro");
    self:RegisterSlashAction('help', 'OnSlashHelp', 'Show list of slash actions (or description for the given action)');
    self:RegisterSlashAction('start', 'OnSlashStart', 'Disable autoUnshift if player is stunned, on gcd or out of mana');
    self:RegisterSlashAction('energy', 'OnSlashEnergy', 'Disable autoUnshift if player energy is above the given value');
    self:RegisterSlashAction('end', 'OnSlashEnd', 'Enable autoUnshift again');
    self:RegisterSlashAction('stun', 'OnSlashStun', 'Disable autoUnshift if stunned');
    self:RegisterSlashAction('gcd', 'OnSlashGcd', 'Disable autoUnshift if on global cooldown');
    self:RegisterSlashAction('mana', 'OnSlashMana', 'Disable autoUnshift if you are missing mana to shift back into form');
    self:RegisterSlashAction('cd', 'OnSlashCooldown', '|cffffff00<itemId|itemShortcut>[ <itemId|itemShortcut> ...]|r Disable autoUnshift if items are on cooldown, player is stunned, on gcd or out of mana');
    self:RegisterSlashAction('debug', 'OnSlashDebug', '|cffffff00on/off|r Enable or disable debugging output');
    self:CreateButton('dmhStart', '/changeactionbar [noform]1;[form:1]2;[form:3]3;[form:4]4;[form:5]5;6;\n/dmh start', 'Change actionbar based on the current form. (includes /dmh start)');
    self:CreateButton('dmhBar', '/changeactionbar [noform]1;[form:1]2;[form:3]3;[form:4]4;[form:5]5;6;', 'Change actionbar based on the current form. (without /dmh start)');
    self:CreateButton('dmhReset', '/changeactionbar 1', 'Change actionbar back to 1.');
    self:CreateButton('dmhEnd', '/use [bar:2]!' .. L["FORM_DIRE_BEAR"] .. ';[bar:3]!' .. L["FORM_CAT"] .. ';[bar:4]!' .. L["FORM_TRAVEL"] .. '\n/click dmhReset\n/dmh end', 'Change back to form based on the current bar. (includes /dmh end)');
    self:CreateButton('dmhPot', '/dmh cd pot\n/dmh start', 'Disable autoUnshift if not ready to use a potion');
    self:CreateButton('dmhHs', '/dmh cd hs\n/dmh start', 'Disable autoUnshift if not ready to use a healthstone');
    self:CreateButton('dmhSap', '/dmh cd sapper\n/dmh start', 'Disable autoUnshift if not ready to use a sapper');
    self:CreateButton('dmhSuperSap', '/dmh cd supersapper\n/dmh start', 'Disable autoUnshift if not ready to use a super sapper');
    self.SpellQueueWindow = 200;
end

function DruidMacroHelper:LogOutput(...)
    print("|cffff0000DMH|r", ...);
end

function DruidMacroHelper:LogDebug(...)
    if self.debug then
        print("|cffff0000DMH|r", "|cffffff00Debug|r", ...);
    end
end

function DruidMacroHelper:OnSlashCommand(parameters)
    if not self.slashActions then
        self:LogOutput("No slash actions registered!");
        return ;
    end
    self:LogDebug("Slash command called: ", unpack(parameters));
    while (#(parameters) > 0) do
        local action = tremove(parameters, 1);
        if not self.slashActions[action] then
            self:LogOutput("Slash action |cffffff00" .. action .. "|r not found!");
        else
            local actionData = self.slashActions[action];
            if type(actionData.callback) == "function" then
                actionData.callback(parameters);
            else
                self[actionData.callback](self, parameters);
            end
        end
    end
end

function DruidMacroHelper:OnSlashHelp(parameters)
    if (#(parameters) > 0) then
        local action = tremove(parameters, 1);
        if not self.slashActions[action] then
            self:LogOutput("Slash action |cffffff00" .. action .. "|r not found!");
        else
            self:LogOutput("|cffffff00" .. action .. "|r", self.slashActions[action].description);
        end
    else
        self:LogOutput("Available slash commands:");
        for action in pairs(self.slashActions) do
            self:LogOutput("|cffffff00/dmh " .. action .. "|r", self.slashActions[action].description);
        end
        self:LogOutput("Available buttons:");
        for btnName in pairs(self.buttons) do
            self:LogOutput("|cffffff00/click " .. btnName .. "|r", self.buttons[btnName]);
        end
    end
end

function DruidMacroHelper:OnSlashStart(parameters)
    self:OnSlashStun(parameters);
    self:OnSlashGcd(parameters);
    self:OnSlashMana(parameters);
    self:OnSlashCooldown(parameters);
    if GetCVar("autoUnshift") == 1 then
        self:LogOutput("Setting SpellQueueWindow to 0")
        self.SpellQueueWindow = GetCVar("SpellQueueWindow");
        SetCVar("SpellQueueWindow", 0);
    end
end

function DruidMacroHelper:OnSlashStun(parameters)
    if self:IsStunned() then
        self:LogDebug("You are stunned");
        SetCVar("autoUnshift", 0);
    end
end

function DruidMacroHelper:OnSlashGcd(parameters)
    if (GetSpellCooldown(768) > 0) then
        self:LogDebug("You are on global cooldown");
        SetCVar("autoUnshift", 0);
    end
end

function DruidMacroHelper:OnSlashMana(parameters)
    local manaCost = 580;
    local manaCostTable = GetSpellPowerCost(spellId);
    if (manaCostTable) then
        for i in ipairs(manaCostTable) do
            if (manaCostTable[i].type == 0) then
                manaCost = manaCostTable[i].cost;
            end
        end
    end
    if (UnitPower("player", 0) < manaCost) then
        self:LogDebug("You missing mana to shift back into form");
        SetCVar("autoUnshift", 0);
    end
end

function DruidMacroHelper:OnSlashEnd(parameters)
    -- Enable autoUnshift again
    self:LogDebug("Enabling autoUnshift again...");
    SetCVar("autoUnshift", 1);
    self:LogDebug("Resetting SpellQueueWindow to " .. self.SpellQueueWindow);
    SetCVar("SpellQueueWindow", self.SpellQueueWindow);
end

function DruidMacroHelper:OnSlashCooldown(parameters)
    local prevent = false;
    while (#(parameters) > 0) do
        local itemNameOrId = tremove(parameters, 1);
        if self:IsItemOnCooldown(itemNameOrId) then
            self:LogDebug("Item on cooldown: ", itemNameOrId);
            prevent = true;
        end
    end
    if prevent then
        SetCVar("autoUnshift", 0);
    end
end

function DruidMacroHelper:OnSlashEnergy(parameters)
    local maxEnergy;

    if (#(parameters) > 0) then
        maxEnergy = tremove(parameters, 1);
    end
    if (not maxEnergy) then
        maxEnergy = 30;
    end
    if UnitPower("player", 3) > tonumber(maxEnergy) then
        self:LogDebug("You are above the given energy value");
        SetCVar("autoUnshift", 0);
    end
end

function DruidMacroHelper:OnSlashDebug(parameters)
    if (#(parameters) > 0) then
        local status = tremove(parameters, 1);
        if (status == "on") then
            self.debug = true;
        else
            self.debug = false;
        end
    else
        if not self.debug then
            self.debug = true;
        else
            self.debug = false;
        end
    end
    if self.debug then
        self:LogOutput("Debug output enabled");
    else
        self:LogOutput("Debug output disabled");
    end
end

function DruidMacroHelper:IsStunned()
    local i = C_LossOfControl.GetActiveLossOfControlDataCount();
    while (i > 0) do
        local locData = C_LossOfControl.GetActiveLossOfControlData(i);
        if (tContains(DRUID_MACRO_HELPER_LOC_STUN, locData.locType)) then
            return true;
        end
        i = i - 1;
    end

    i = 40
    while (i > 0) do
        local name, _, _, _, _, _, _, _, _, spellId = UnitDebuff("player", i);
        if spellId == 38509 then
            -- https://tbc.wowhead.com/spell=38509/shock-blast
            return true;
        end
        i = i - 1;
    end

    return false;
end

function DruidMacroHelper:IsShiftableCC()
    if self:IsStunned() then
        -- Not removable by powershifting if also stunned
        return false;
    end
    -- Check for slows
    local _, _, playerSpeed = GetUnitSpeed("player");
    local playerSpeedNormal = 7;
    if (IsStealthed()) then
        playerSpeedNormal = 4.9;
    end
    if (playerSpeed < playerSpeedNormal) then
        -- Player is slowed
        return true;
    end
    -- Check for roots
    local i = C_LossOfControl.GetActiveLossOfControlDataCount();
    while (i > 0) do
        local locData = C_LossOfControl.GetActiveLossOfControlData(i);
        if (tContains(DRUID_MACRO_HELPER_LOC_SHIFTABLE, locData.locType)) then
            return true;
        end
        i = i - 1;
    end
    return false;
end

function DruidMacroHelper:IsItemOnCooldown(itemNameOrId)
    local itemId = itemNameOrId;
    if self.itemShortcuts and self.itemShortcuts[itemNameOrId] then
        itemId = self.itemShortcuts[itemNameOrId];
    end
    return (GetItemCooldown(itemId) > 0);
end

function DruidMacroHelper:CreateButton(name, macrotext, description)
    local b = _G[name] or CreateFrame('Button', name, nil, 'SecureActionButtonTemplate,SecureHandlerBaseTemplate');
    b:SetAttribute('type', 'macro');
    b:SetAttribute('macrotext', macrotext);
    if not self.buttons then
        self.buttons = {};
    end
    if not description then
        description = "No description available";
    end
    self.buttons[name] = description;
end

function DruidMacroHelper:RegisterCondition(shortcut, itemId)
    if not self.itemShortcuts then
        self.itemShortcuts = {};
    end
    self.itemShortcuts[shortcut] = itemId;
end

function DruidMacroHelper:RegisterItemShortcut(shortcut, itemId)
    if not self.itemShortcuts then
        self.itemShortcuts = {};
    end
    self.itemShortcuts[shortcut] = itemId;
end

function DruidMacroHelper:RegisterSlashAction(action, callback, description)
    if (type(callback) ~= "function") and (type(callback) ~= "string") then
        self:LogOutput("Invalid callback for slash action:", action);
        return ;
    end
    if not description then
        description = "No description available";
    end
    if not self.slashActions then
        self.slashActions = {};
    end
    self.slashActions[action] = {
        ["callback"] = callback, ["description"] = description
    };
end

function DruidMacroHelper:RegisterSlashCommand(cmd)
    if not self.slashCommands then
        self.slashCommands = {};
        -- Add to SlashCmdList when the first command is added
        SlashCmdList["DRUID_MACRO_HELPER"] = function(parameters)
            if (parameters == "") then
                parameters = "help";
            end
            DruidMacroHelper:OnSlashCommand({ strsplit(" ", parameters) });
        end;
    end
    if not tContains(self.slashCommands, cmd) then
        local index = #(self.slashCommands) + 1;
        tinsert(self.slashCommands, cmd);
        _G["SLASH_DRUID_MACRO_HELPER" .. index] = cmd;
    end
end

-- Kickstart the addon
DruidMacroHelper:Init();
