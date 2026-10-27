local _, A = ...
local N = A.Navigation

function A.NewDisplay(db)
    local V = {}
    local frame = CreateFrame("Frame", nil, UIParent)
    V.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    -- Transparent overlay: EUI supplies fonts/accent, never window chrome.
    local content = CreateFrame("Frame", nil, frame)
    content:SetSize(300, 160)
    content:SetPoint("CENTER")
    content:SetFrameLevel(frame:GetFrameLevel() + 5)
    local arrow = content:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(58, 58)
    arrow:SetPoint("TOP", 0, -8)
    arrow:SetTexture("Interface\\AddOns\\AlmightreeWaypoint\\Arrow.tga")
    local function label(y, height, size)
        local fs = content:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOP", 0, y)
        fs:SetSize(280, height)
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
        fs:SetJustifyH("CENTER")
        return fs
    end
    local destination = label(-69, 20, 14)
    local distance = label(-91, 18, 12)
    local instruction = label(-112, 40, 12)
    local fonts = { destination, distance, instruction }
    local skin
    local hideReason, renderedKey, renderedSource, updatedAt = "not_initialized"

    function V:ApplyLooks()
        local enabled = skin and skin.IsEnabled()
        local path, outline = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", ""
        local r, g, b = 0.2, 0.85, 0.75
        if enabled then
            path, outline = skin.GetFont()
            r, g, b = skin.GetAccentColor()
        end
        for i, fs in ipairs(fonts) do
            fs:SetFont(path, i == 1 and 14 or 12, outline or "")
            fs:SetTextColor(0.94, 0.96, 0.98)
        end
        distance:SetTextColor(0.75, 0.82, 0.87)
        arrow:SetVertexColor(r, g, b)
    end

    function V:ApplyPosition()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    end

    function V:ApplyAppearance()
        frame:SetSize(300 * db.scale, 160 * db.scale)
        content:SetScale(db.scale)
        frame:SetAlpha(db.opacity)
    end

    function V:ResetPosition()
        db.x, db.y = 0, 180
        self:ApplyPosition()
    end

    function V:SetLocked(locked)
        frame:StopMovingOrSizing()
        frame:EnableMouse(not locked)
    end

    local dragging = false
    local function finishDrag()
        frame:StopMovingOrSizing()
        if not dragging then return end
        dragging = false
        local x, y = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if N.Number(x) and N.Number(y) and N.Number(ux) and N.Number(uy) then
            db.x, db.y = x - ux, y - uy
        end
        V:ApplyPosition()
    end
    frame:SetScript("OnDragStart", function()
        if not db.locked and not InCombatLockdown() then dragging = true; frame:StartMoving() end
    end)
    frame:SetScript("OnDragStop", finishDrag)
    frame:SetScript("OnHide", finishDrag)

    local function plain(text)
        return (N.Text(text) or ""):gsub("|", "||")
    end

    function V:Render(model, reason)
        updatedAt = N.Read(_G, "GetTime")[1]
        renderedKey, renderedSource = model and model.key, model and (model.preview and "preview" or model.source)
        hideReason = reason or (model and model.hideReason) or "no_model"
        -- Clear text/rotation visibility even when hiding; no previous target is retained.
        arrow:Hide()
        destination:SetText("")
        distance:SetText("")
        instruction:SetText("")
        if not model then frame:Hide(); return end
        destination:SetText(plain(model.destination))
        instruction:SetText(plain(model.instruction))
        if N.Number(model.rotation) then arrow:SetRotation(model.rotation); arrow:Show(); hideReason = nil
        elseif not reason and not model.hideReason then hideReason = "bearing_unavailable" end
        if N.Number(model.distance) and model.distance >= 0 then
            distance:SetText((model.preview and "Preview: " or "Straight-line: ~") .. string.format("%.0f yd", model.distance))
        elseif not model.preview then
            distance:SetText("Direction unavailable")
        end
        frame:Show()
    end

    -- Read the actual owned texture's visibility; diagnostics never recalculate navigation.
    function V:GetArrowState()
        local visible = arrow:IsVisible() == true
        return visible, visible and "visible" or hideReason or "texture_or_parent_hidden", frame:IsVisible() == true
    end

    function V:GetTarget() return renderedKey, renderedSource end
    function V:GetUpdatedAt() return updatedAt end

    function V:RegisterSkin(eui)
        if not eui or not eui.RegisterSkin then return end
        eui.RegisterSkin("AlmightreeWaypoint", function(S)
            skin = S
            for _, fs in ipairs(fonts) do S.Font(fs) end
            S.OnLooksChanged(function() V:ApplyLooks() end)
            V:ApplyLooks()
        end)
    end

    V:ApplyAppearance()
    V:ApplyPosition()
    V:SetLocked(db.locked)
    V:ApplyLooks()
    V:Render(nil)
    return V
end
