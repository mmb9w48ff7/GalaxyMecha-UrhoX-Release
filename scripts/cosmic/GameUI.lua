-- GameUI.lua：战斗界面（HUD + 弹窗 + 触控输入），对应网页版 cosmic_run.js 里用 DOM 实现的 buildHUD / updateHUD / openLevelUp /
-- openShop / openPause / openRevive / endRun 弹窗 / startTutorial / bindPointer。游戏逻辑仍由转换后的网页版代码执行，这里只负责显示与点击。
local U = require("cosmic.Util")
local UI = require("cosmic.UI")
local GameUI = { toast = nil }
local S, C, HOST
local COL = UI.COL
local ORANGE_ = { 200, 130, 20 }
local u = {}                                  -- 界面状态：levelup / shop / pause / revive / tut
GameUI.state = u
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function R() return S.R end
function GameUI.Toast(msg) GameUI.toast = { text = msg, t = 2.6 } end

-- ---------------------------------------------------------------- 覆盖网页版的 DOM 函数
function GameUI.Install(mod, cosmic, host)
    S, C, HOST = mod, cosmic, host
    host.onToast = GameUI.Toast
    S.buildHUD = function() end
    S.updateHUD = function() end
    S.bindPointer = function() end
    local function finishLevel()
        u.levelup = nil; S.paused = false; S:afterChoice()
        local r = R(); r.gems:forEach(function(_, g) if S:dd(g, S:P()) < 2025 then g.pull = true end end)
    end
    GameUI.finishLevel = finishLevel
    S.openLevelUp = function()
        S.paused = true; local r = R(); r.pendingLevels = r.pendingLevels - 1; C:sfx("level"); r.rr = r.rr or { free = 1, ad = 0 }
        u.levelup = { ids = S:choices() }
    end
    S.openShop = function(_, n)
        S.paused = true; local r = R()
        local offers = {
            { name = "紧急维修", text = "修复 50% 耐久", cost = math.floor(150 + 0.5), go = function() r.hull = math.min(S:hullMax(), r.hull + S:hullMax() * 0.5) end },
            { name = "强化芯片", text = "立即升级 1 次", cost = 260, go = function() r.pendingLevels = r.pendingLevels + 1 end },
            { name = "星魂结晶", text = "驾驶员碎片 +5", cost = 400, go = function() r.frags[r.pilot] = (r.frags[r.pilot] or 0) + 5 end },
        }
        u.shop = { offers = offers }
    end
    S.openPause = function()
        if S.paused or not R() then return end
        S.paused = true; u.pause = true
    end
    S.openRevive = function()
        if R().ended then return end
        S.paused = true; u.revive = true
    end
    S.startTutorial = function()
        local r = R()
        local steps = {
            { text = "左半屏拖动：朝镜头方向飞行。右半屏拖动：转动视角", done = function() return math.sqrt(r.vx * r.vx + r.vy * r.vy + r.vz * r.vz) > 5 end },
            { text = "武器会自动锁定开火。飞过去捡青色的能量升级", done = function() return r.level >= 2 end },
            { text = "右下大按钮是机甲技能，旁边的小按钮是氮气推进，能冲刺并短暂无敌。点一下技能试试", done = function() return r.tutorialSkill end },
            { text = "跟着屏幕边缘的箭头，完成本星域的目标。目标可能在上方或下方", done = function() return S:objectiveDone() end },
            { text = "星门开启了！飞进去前往下一个星域", done = function() return r.sector >= 2 end },
        }
        local i = 1; u.tut = { text = steps[1].text, n = 1, total = #steps }
        r.tutorial = {
            event = function(_, k) if k == "skill" then r.tutorialSkill = true end end,
            tick = function()
                if i > #steps or S.paused then return end
                if steps[i].done() then
                    i = i + 1; C:sfx("pick")
                    if i > #steps then u.tut = nil; C.save.tutorialDone = true; C:write(); r.tutorial = nil; GameUI.Toast("引导完成，祝你远征顺利！")
                    else u.tut = { text = steps[i].text, n = i, total = #steps } end
                end
            end,
        }
    end
end
function GameUI.Reset() u.levelup, u.shop, u.pause, u.revive, u.tut = nil, nil, nil, nil, nil end
function GameUI.ModalOpen() return u.levelup or u.shop or u.pause or u.revive or (R() and R().result and R().ended) end

-- ---------------------------------------------------------------- 绘制
local function mmss(t) return U.fmtTime(t) end
local function dim(W) nvgBeginPath(UI.vg); nvgRect(UI.vg, 0, 0, W, 1080); nvgFillColor(UI.vg, nvgRGBA(0, 0, 10, 175)); nvgFill(UI.vg) end
function GameUI.DrawHud()
    local r = R(); if not r then return end
    local W = UI.lw; local pad = 40; local m = S:M()
    -- 顶部经验条（带边框）与等级
    nvgBeginPath(UI.vg); nvgRect(UI.vg, pad, 18, W - pad * 2, 26); nvgFillColor(UI.vg, nvgRGBA(9, 12, 34, 200)); nvgFill(UI.vg)
    UI.Bar(pad + 3, 21, W - pad * 2 - 6, 20, clamp(r.xp / S:xpNeed(r.level), 0, 1), COL.teal, { 0, 0, 0 })
    nvgBeginPath(UI.vg); nvgRect(UI.vg, pad, 18, W - pad * 2, 26); nvgStrokeColor(UI.vg, nvgRGBA(52, 64, 122, 255)); nvgStrokeWidth(UI.vg, 3); nvgStroke(UI.vg)
    UI.Text(W - pad - 6, 48, "Lv " .. r.level, 24, COL.bone, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    -- 耐久 / 信用点 / 星源（带图标）
    UI.Text(pad, 58, "耐久 " .. math.ceil(r.hull) .. " / " .. S:hullMax(), 30, COL.bone)
    UI.Icon(UI.ResIcon("credit"), pad, 98, 30); UI.Text(pad + 42, 98, tostring(math.floor(r.credits)), 28, COL.bone)
    UI.Icon(UI.ResIcon("shard"), pad, 136, 30); UI.Text(pad + 42, 136, "星源 " .. r.src, 28, COL.bone)
    -- 槽位：主武器 + 已装备卡牌 + 已获得的被动强化（图标 + 等级）
    local sx = pad
    local function slot(ic, label, hot)
        UI.Panel(sx, 180, 66, 66, 210); UI.Icon(ic, sx + 10, 186, 46); UI.Text(sx + 56, 226, tostring(label), 18, hot and COL.amber or COL.bone, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP); sx = sx + 72
    end
    slot(UI.CatIcon(r.mech), S:lv("main"))
    r.mods:forEach(function(_, md) slot(C:modIcon(md.m), md.evo and "★" or md.lv, md.evo) end)
    for _, k in ipairs(require("jsrt.JS").keys(S.UPG)) do if k ~= "main" and k ~= "support" and S:lv(k) > 0 then slot(C.ICON[k], S:lv(k)) end end
    local head
    if r.daily then head = "每日挑战　第 " .. r.wave .. " 波　剩余 " .. mmss(C.DC_TIME - r.secT) .. "　得分 " .. S:dcScore()
    elseif r.endless then head = "无尽模式　第 " .. r.wave .. " 波　" .. mmss(r.t)
    else head = "星域 " .. r.sector .. " / " .. S.SECTORS .. "　" .. ((r.gate.state == "open") and "飞进星门" or tostring(r.objective or "")) end
    if r.danger > 1 then head = head .. "　危险 " .. r.danger end
    if r.affix then head = head .. "　[" .. r.affix.name .. "：" .. r.affix.desc .. "]" end
    UI.Text(W / 2, 62, "第 " .. r.ch.id .. " 章 " .. r.ch.name, 32, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(W / 2, 104, head, 26, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    -- 连击 / Boss / 提示 / 横幅
    if r.combo >= 5 and r.comboT > 0 then UI.Text(W - 340, 200, tostring(r.combo), 64, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W - 340, 270, "连击", 26, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
    if r.boss and r.boss.hp > 0 then UI.Text(W / 2, 150, r.boss.d.name, 30, COL.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Bar(W / 2 - 450, 188, 900, 22, clamp(r.boss.hp / r.boss.max, 0, 1), COL.danger) end
    if r.bannerT > 0 then UI.Text(W / 2, 250, r.banner, 56, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, math.min(255, math.floor(r.bannerT * 400))) end
    local n = r.nearNode
    if n then UI.Text(W / 2, 960, n.info.name .. "　" .. ((n.type == "derelict" and n.state == "active") and ("搜刮中 " .. math.floor(n.progress * 100 + 0.5) .. "%") or ((n.type == "gate" and n.state ~= "open") and ("先完成本星域目标：" .. tostring(r.objective)) or tostring(n.info.hint))), 28, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
    if u.tut then UI.Panel(W / 2 - 520, 790, 1040, 90, 235); UI.Text(W / 2, 800, "新手引导 " .. u.tut.n .. " / " .. u.tut.total, 20, COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W / 2, 830, u.tut.text, 24, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
    -- 驾驶员卡片（头像 + 支援技能冷却 + 等级）
    local cop = C:char(r.pilot); local st = S:supportStat()
    UI.Panel(pad, 904, 340, 110, 225); UI.Icon(UI.CatIcon(r.pilot), pad + 12, 914, 54)
    UI.Text(pad + 80, 912, cop.name, 26, COL.bone); UI.Text(pad + 80 + 6 + 26 * #cop.name * 0.5 + 30, 916, r.match and "专属 +20%" or "驾驶员", 18, COL.teal)
    UI.Text(pad + 80, 948, cop.support.name, 20, COL.muted); UI.Text(pad + 326, 914, "Lv " .. st.lv, 18, COL.muted, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Bar(pad + 80, 984, 244, 10, clamp(1 - r.supportCd / (cop.support.cd * st.cd), 0, 1), COL.teal)
    -- 机甲技能 / 氮气 / 暂停
    local ready = r.activeCd <= 0
    local bx, by = W - pad - 230, 1080 - 30 - 230
    if UI.Button(bx, by, 230, 230, "", { color = ready and { 52, 44, 110 } or COL.hi, border = r.nitroT > 0 and COL.teal or (ready and ORANGE_ or nil) }) then S:castActive() end
    UI.Icon(UI.CatIcon(r.mech), bx + 65, by + 20, 100)
    UI.Text(bx + 115, by + 170, ready and m.active.name or tostring(math.ceil(r.activeCd)), ready and 28 or 54, ready and COL.bone or COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if not ready then UI.Bar(bx, by + 222, 230, 8, clamp(1 - r.activeCd / S:activeCdMax(), 0, 1), COL.amber) end
    local N = S:nitroOf(); local dgReady = r.dodgeCd <= 0
    if UI.Button(W - pad - 250 - 140, 1080 - 40 - 140, 140, 140, dgReady and N.name or tostring(math.ceil(r.dodgeCd)), { size = 24, color = dgReady and { 30, 100, 150 } or COL.hi, border = dgReady and { 87, 184, 255 } or nil }) then S:dodge() end
    local ex = HOST.exitRect; local pauseX = W - 170 - ((ex and ex.right and ex.right > 0.8) and 170 or 0)
    if UI.Button(pauseX, 60, 130, 56, "暂停", { size = 26 }) then S:openPause() end
end
local function drawLevelUp()
    local r, W = R(), UI.lw; dim(W)
    UI.Text(W / 2, 80, "升级！", 90, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W / 2, 190, "选择一项强化", 34, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local ids = u.levelup.ids; local cw, gap = 520, 40; local x0 = (W - (ids.length * cw + (ids.length - 1) * gap)) / 2
    for i = 0, ids.length - 1 do
        local id = ids[i]; local info = S:choiceInfo(id); local x, y = x0 + i * (cw + gap), 270
        UI.Panel(x, y, cw, 530, 235)
        if info.evo then nvgBeginPath(UI.vg); nvgRect(UI.vg, x, y, cw, 530); nvgStrokeColor(UI.vg, nvgRGBA(245, 165, 36, 255)); nvgStrokeWidth(UI.vg, 6); nvgStroke(UI.vg) end
        UI.Text(x + cw / 2, y + 22, info.tag, 28, info.evo and COL.amber or COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        UI.Text(x + cw / 2, y + 80, info.name, 42, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Wrap(x + 30, y + 170, cw - 60, info.text, 26, COL.muted)
        if UI.Button(x + 40, y + 450, cw - 80, 62, "选择", { size = 30, color = info.evo and { 200, 130, 20 } or COL.hi }) then S:applyChoice(id); GameUI.finishLevel() end
    end
    local free = r.rr.free > 0; local left = free and 0 or math.max(0, 2 - r.rr.ad)
    local label = free and "刷新选项（免费 1 次）" or (left > 0 and ("看广告 刷新选项（还可 " .. left .. " 次）") or "刷新次数已用完")
    if UI.Button(W / 2 - 440, 850, 430, 80, label, { size = 26, disabled = (not free) and left <= 0, color = free and COL.hi or { 30, 100, 150 } }) then
        if free then r.rr.free = r.rr.free - 1; C:sfx("click"); u.levelup.ids = S:choices()
        elseif r.rr.ad < 2 then C:showAd("刷新升级选项", function(_, res) if not res.success then GameUI.Toast("需要完整看完广告才能刷新") return end r.rr.ad = r.rr.ad + 1; C:sfx("click"); u.levelup.ids = S:choices() end) end
    end
    if UI.Button(W / 2 + 10, 850, 430, 80, "跳过，回复 30% 耐久", { size = 26 }) then r.hull = math.min(S:hullMax(), r.hull + S:hullMax() * 0.3); GameUI.Toast("跳过：回复 30% 耐久"); GameUI.finishLevel() end
end
local function drawShop()
    local r, W = R(), UI.lw; dim(W); UI.Panel(W / 2 - 600, 220, 1200, 600, 245)
    UI.Text(W / 2, 240, "流浪商人", 64, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W / 2, 320, "用本局收集的信用点交易。当前：" .. math.floor(r.credits), 28, COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    for i, o in ipairs(u.shop.offers) do
        local x = W / 2 - 560 + (i - 1) * 380
        UI.Panel(x, 380, 360, 300, 230); UI.Text(x + 180, 400, o.name, 36, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(x + 180, 460, o.text, 26, COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if UI.Button(x + 30, 590, 300, 70, o.cost .. " 信用点", { size = 28, disabled = r.credits < o.cost, color = { 200, 130, 20 } }) then r.credits = r.credits - o.cost; o.go(); GameUI.Toast("购买了 " .. o.name); S:openShop() end
    end
    if UI.Button(W / 2 - 150, 720, 300, 70, "离开", { size = 30 }) then u.shop = nil; S.paused = false end
end
local function drawPause()
    local W = UI.lw; dim(W); UI.Panel(W / 2 - 560, 200, 1120, 640, 245); UI.Text(W / 2, 220, "暂停", 72, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Wrap(W / 2 - 500, 330, 1000, "左半屏拖动飞行（朝镜头方向），右半屏拖动转视角；武器自动锁定开火。右下大按钮释放机甲技能（电脑空格），小按钮氮气推进（电脑 Shift，每台机甲氮气形态不同）。电脑：WASD 飞行，R/F 升降，方向键转视角。每个星域完成箭头指向的目标，星门就会开启。闯过 6 个星域、击败首领即可通关。", 28, COL.bone)
    if UI.Button(W / 2 - 440, 700, 420, 90, "继续", { size = 36, color = { 200, 130, 20 } }) then u.pause = nil; S.paused = false end
    if UI.Button(W / 2 + 20, 700, 420, 90, "撤退返回", { size = 34 }) then u.pause = nil; S:endRun(false, true) end
end
local function drawRevive()
    local r, W = R(), UI.lw; dim(W); UI.Panel(W / 2 - 480, 280, 960, 460, 245); UI.Text(W / 2, 300, "机甲被击毁", 64, COL.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(W / 2, 400, "看一段广告可以原地复活（耐久 50%），每局限一次。", 30, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if not r.adRevived then
        if UI.Button(W / 2 - 440, 560, 420, 90, "看广告复活", { size = 32, color = { 30, 100, 150 } }) then
            C:showAd("复活机甲", function(_, res)
                if not res.success then GameUI.Toast("需要完整看完广告才能复活") return end
                u.revive = nil; r.adRevived = true; r.over = false; S.paused = false; r.hull = S:hullMax() * 0.5; r.iframe = 2; S:nova(S:P(), 14, 60, "#5CF2DC"); S:banner("复活！")
            end)
        end
    end
    if UI.Button(W / 2 + 20, 560, 420, 90, "结束远征", { size = 32 }) then u.revive = nil; S:endRun(false) end
end
local function drawResult()
    local r, W = R(), UI.lw; local rs = r.result; local s = C.save; dim(W); UI.Panel(W / 2 - 560, 140, 1120, 800, 248)
    local title = r.daily and (rs.win and "每日挑战完成" or "每日挑战结束") or r.endless and "无尽模式结束" or rs.win and "远征成功" or rs.retreat and "已撤退返回" or "远征失败"
    UI.Text(W / 2, 160, title, 72, rs.win and COL.amber or COL.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local reach = r.daily and ("得分 " .. rs.dcScore) or r.endless and ("第 " .. r.wave .. " 波") or rs.win and "通关" or (r.sector .. " / " .. S.SECTORS)
    local rows = { { "到达", reach }, { "用时", mmss(r.t) }, { "击破", tostring(r.kills) }, { "信用点", "+" .. rs.credits }, { "星源", "+" .. rs.src }, { "本局等级", "Lv " .. r.level }, { "最高连击", tostring(r.bestCombo or 0) }, { "造成伤害", tostring(math.floor((r.dmgDealt or 0) + 0.5)) }, { "承受伤害", tostring(math.floor((r.dmgTaken or 0) + 0.5)) } }
    for i, row in ipairs(rows) do local x = W / 2 - 500 + ((i - 1) % 3) * 340; local y = 270 + ((i - 1) // 3) * 110; UI.Text(x, y, row[1], 24, COL.muted); UI.Text(x, y + 34, row[2], 44, COL.bone) end
    local ny = 610
    local function note(t, c) UI.Text(W / 2, ny, t, 26, c or COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); ny = ny + 36 end
    if rs.achNow and rs.achNow > 0 then note("有 " .. rs.achNow .. " 个成就可以领取，去“每日”页领取星源。") end
    if rs.first then note("首次通关奖励：星源 +" .. r.ch.first) end
    if rs.dgUnlock then note("危险等级 " .. s.dangerMax .. " 已解锁（奖励更高，敌人更强）。", COL.amber) end
    if r.endless and not r.daily then note("无尽最高纪录：第 " .. s.endlessBest .. " 波。") end
    if r.daily then note("今日最高分 " .. C:dailyChallenge().state.best .. (rs.dcFirst and "。首次完成奖励已发放。" or "。今日奖励已领取。")) end
    if not rs.win and not rs.retreat and not r.endless then note("远征失败只带回 70% 信用点。", COL.muted) end
    if rs.fragTxt and rs.fragTxt ~= "" then note(rs.fragTxt) end
    if UI.Button(W / 2 - 520, 850, 330, 80, rs.doubled and "已翻倍" or "看广告 信用点翻倍", { size = 26, disabled = rs.doubled, color = { 30, 100, 150 } }) then
        C:showAd("结算奖励翻倍", function(_, res) if not res.success then GameUI.Toast("需要完整看完广告才能领取") return end s.credits = s.credits + rs.credits; C:write(); rs.doubled = true; GameUI.Toast("信用点再 +" .. rs.credits) end)
    end
    if UI.Button(W / 2 - 170, 850, 330, 80, "分享战绩", { size = 28 }) then
        local tx = "我在《宇宙银河机甲》" .. (r.daily and ("每日挑战拿到了 " .. rs.dcScore .. " 分") or r.endless and ("无尽模式撑到了第 " .. r.wave .. " 波") or rs.win and ("通关了第 " .. r.ch.id .. " 章") or ("闯到了星域 " .. r.sector)) .. "！用 " .. C:mech(r.mech).name .. "击破 " .. r.kills .. " 个敌人。来挑战我吧！"
        if HOST.onShare then HOST.onShare(tx) end; GameUI.Toast("战绩：" .. tx)
    end
    if UI.Button(W / 2 + 190, 850, 330, 80, "返回机库", { size = 32, color = { 200, 130, 20 } }) then S.R = nil; GameUI.Reset(); if GameUI.onHome then GameUI.onHome() end end
end
function GameUI.DrawModals()
    local r = R(); if not r then return end
    if r.ended and r.result then drawResult()
    elseif u.levelup then drawLevelUp()
    elseif u.shop then drawShop()
    elseif u.revive then drawRevive()
    elseif u.pause then drawPause() end
    if GameUI.toast and GameUI.toast.t > 0 then UI.Panel(UI.lw / 2 - 360, 40, 720, 56, 235); UI.Text(UI.lw / 2, 50, GameUI.toast.text, 28, COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
end

-- ---------------------------------------------------------------- 输入（对应 bindPointer / keydown）
local KEYMAP = { KeyW = KEY_W, KeyA = KEY_A, KeyS = KEY_S, KeyD = KEY_D, KeyR = KEY_R, KeyF = KEY_F, ArrowLeft = KEY_LEFT, ArrowRight = KEY_RIGHT, ArrowUp = KEY_UP, ArrowDown = KEY_DOWN }
function GameUI.Input(W, H, viewS)
    local r = R(); if not r or GameUI.ModalOpen() then return end
    local joy, look, keys = S.joy, S.look, S.keys
    for _, t in ipairs(UI.taps) do
        if not t.used then
            if t.px < W * 0.5 and joy.id == nil then joy.id = t.id; joy.cx = t.px; joy.cy = t.py; joy.dx = 0; joy.dy = 0; t.used = true
            elseif look.id == nil then look.id = t.id; look.x = t.px; look.y = t.py; look.idle = 0; t.used = true end
        end
    end
    for id, st in pairs(UI.ptr) do
        if id == joy.id then
            local R0 = 60 * math.max(0.55, viewS * 1.5); local dx, dy = st.px - joy.cx, st.py - joy.cy; local l = math.sqrt(dx * dx + dy * dy)
            if l > R0 then dx = dx / l * R0; dy = dy / l * R0 end
            joy.dx = dx / R0; joy.dy = -dy / R0
        elseif id == look.id then
            local k = 0.32 / math.max(0.3, viewS * 1.5)
            r.camYaw = r.camYaw + (st.px - look.x) * k; r.camPitch = clamp(r.camPitch + (st.py - look.y) * k, -70, 70); look.x = st.px; look.y = st.py; look.idle = 0
        end
    end
    for _, st in ipairs(UI.released) do
        if st.id == joy.id then joy.id = nil; joy.dx = 0; joy.dy = 0 end
        if st.id == look.id then look.id = nil; look.idle = 0 end
    end
    for code, k in pairs(KEYMAP) do keys[code] = input:GetKeyDown(k) or nil end
    if input:GetKeyPress(KEY_SPACE) then S:castActive() end
    if input:GetKeyPress(KEY_SHIFT) then S:dodge() end
    if input:GetKeyPress(KEY_ESCAPE) and not r.ended then S:openPause() end
end
function GameUI.DrawToast() if GameUI.toast and GameUI.toast.t > 0 then UI.Panel(UI.lw / 2 - 360, 40, 720, 56, 235); UI.Text(UI.lw / 2, 50, GameUI.toast.text, 28, COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end end
function GameUI.Update(dt) if GameUI.toast then GameUI.toast.t = GameUI.toast.t - dt end end
return GameUI
