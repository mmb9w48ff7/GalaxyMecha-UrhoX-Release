-- Hub.lua：机库（出击 / 机库 / 驾驶员 / 工坊 / 召唤 / 每日 / 设置 / 关于）。
-- 网页版机库是 HTML + CSS 做的，这里用 NanoVG 重画版面；每个按钮的处理逻辑与 cosmic_hub.js 里的 onclick 逐条对应，
-- 所有数据与规则（抽取、费用、保底、成就、每日挑战……）都直接调用由网页版转换来的 C（cosmic_data.js），不在这里重新实现。
local U = require("cosmic.Util")
local UI = require("cosmic.UI")
local Hub = { tab = "home", wsub = "mods", banner = "mech", chapterSel = 1, dangerSel = 1, wk = { form = "homing", elem = "fire", tier = 0, v = 0 }, modal = nil, results = nil, t = 0 }
local C, HOST
local COL, GRADE = UI.COL, UI.GRADE
local ORDER = { S = 0, SS = 1, SSR = 2, SSSR = 3 }
local TIERC = { { 230, 234, 245 }, { 87, 184, 255 }, { 180, 124, 255 }, { 245, 165, 36 } }
local ORANGE = { 200, 130, 20 }
local drawSummonAnim
local function toast(m) if HOST.onToast then HOST.onToast(m) end end
local function sv() return C.save end
local function list(a) local t = {}; if a then for i = 0, a.length - 1 do t[#t + 1] = a[i] end end return t end
local function find(a, f) for i = 0, a.length - 1 do if f(a[i]) then return a[i], i end end return nil end
local function has(a, id) for i = 0, a.length - 1 do if a[i] == id then return i end end return nil end
local function fmt(n) return tostring(math.floor(n + 0.5)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local function save() C:write() end
function Hub.Init(cosmic, host)
    C, HOST = cosmic, host; Hub.chapterSel = math.min(sv().chapter, C.CHAPTERS.length); Hub.dangerSel = math.min(1, sv().dangerMax or 1)
end
local function sortG(arr)
    local t = list(arr); local s = sv()
    local function own(x) return (arr == C.MECHS and s.mechs[x.id] or (arr ~= C.MECHS and s.chars[x.id])) and 1 or 0 end
    table.sort(t, function(a, b) if ORDER[a.grade] ~= ORDER[b.grade] then return ORDER[a.grade] > ORDER[b.grade] end return own(a) > own(b) end)
    return t
end
local function mechPower(id) local m, k = C:mech(id), C:mechMul(id); return { hp = m.hp * k, fire = m.fire * 20 * k, spd = m.spd * 6 } end
local function mechUpgradable() local s = sv(); for _, m in ipairs(list(C.MECHS)) do if s.mechs[m.id] then local lv = C:mechLv(m.id); local st = C:mechStar(m.id)
    if (lv < C.MECH_MAX and s.credits >= C:mechCost(lv)) or (st < 5 and (s.frags[m.id] or 0) >= C.STAR_FRAGS[st]) then return true end end end return false end
local function pilotUpgradable() local s = sv(); for _, c in ipairs(list(C.CHARS)) do local o = s.chars[c.id]; if o and o.star < 5 and (s.frags[c.id] or 0) >= (C.STAR_FRAGS[o.star] or 10) then return true end end return false end
local function dailyClaimable()
    local s = sv(); if not s.daily.supply or s.daily.supply == 0 then return true end
    if not C:loginState().claimed then return true end
    if C:achReady() > 0 then return true end
    for _, t in ipairs(list(C.TASKS)) do if (s.daily[t.key] or 0) >= t.need and not s.daily.claimed[t.id] then return true end end
    return false
end
local function nextSteps()
    local s, out = sv(), {}; local cards, eqN = s.modules.length, s.modEq.length
    if (s.runs or 0) == 0 and not s.best[1] then out[#out + 1] = { go = "home", t = "出击第 1 章", d = "跟着新手引导飞一圈，赚信用点和星源" } end
    if cards < 3 or eqN < 3 then out[#out + 1] = { go = "work", t = "去工坊抽技能卡牌", d = "装备 3 张卡牌，出击时全部生效（现有 " .. cards .. " 张，已装备 " .. eqN .. " / 3）" } end
    if s.credits >= C:MOD_COST(s.modBuys or 0) and cards >= 3 then out[#out + 1] = { go = "work", t = "信用点够抽卡了", d = "再抽一张：重复抽到会升级卡牌，抽到金卡有专属特效" } end
    local nc = C.CHAPTERS[math.min(C.CHAPTERS.length, s.chapter) - 1]
    if nc and C:power() < nc.rec * 0.9 then table.insert(out, 1, { go = "hangar", t = "战力不足（" .. C:power() .. " / 推荐 " .. nc.rec .. "）", d = "先升级机甲等级 / 星级，再装备卡牌与芯片" }) end
    if mechUpgradable() then out[#out + 1] = { go = "hangar", t = "机甲可以升级", d = "到机库提升等级或星级，耐久与火力一起变强" } end
    if pilotUpgradable() then out[#out + 1] = { go = "pilots", t = "驾驶员可以升星", d = "碎片足够了，升星提高支援技能" } end
    if dailyClaimable() then out[#out + 1] = { go = "daily", t = "每日有奖励可领", d = "补给、任务和巡航收益" } end
    if s.chips.length < 3 then out[#out + 1] = { go = "work", t = "研发天赋芯片", d = "芯片属性永久生效，凑齐同系列有额外效果" } end
    local r = {}; for i = 1, math.min(3, #out) do r[i] = out[i] end return r
end

-- ---------------------------------------------------------------- 通用控件
local function header(title)
    local W = UI.lw
    UI.Text(W / 2, 24, title, 56, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(W - 40, 30, "信用点 " .. fmt(sv().credits) .. "　星源 " .. fmt(sv().src), 30, COL.bone, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
end
local function gtag(g, x, y, size) UI.Text(x, y, g, size or 36, GRADE[g]) end
local function statBar(label, v, max, col, x, y)
    UI.Text(x, y, label, 26, COL.muted); UI.Bar(x + 100, y + 8, 300, 20, v / max, col); UI.Text(x + 420, y, tostring(math.floor(v + 0.5)), 26, COL.bone)
end
local function nav()
    local W = UI.lw
    local items = { { "出击", "home" }, { "机库", "hangar" }, { "驾驶员", "pilots" }, { "工坊", "work" }, { "召唤", "summon" }, { "每日", "daily" } }
    for i, it in ipairs(items) do
        local dot = (it[2] == "daily" and dailyClaimable()) or (it[2] == "hangar" and mechUpgradable()) or (it[2] == "pilots" and pilotUpgradable())
        if UI.Button(W / 2 - 560 + (i - 1) * 190, 980, 180, 80, it[1] .. (dot and " ●" or ""), { size = 28, color = Hub.tab == it[2] and ORANGE or COL.hi }) then C:sfx("click"); Hub.tab = it[2]; Hub.mechSel = nil; Hub.pilotSel = nil; Hub.wsel = nil end
    end
    if UI.Button(W - 250, 975, 100, 70, "设置", { size = 24 }) then Hub.modal = "settings" end
    if UI.Button(W - 140, 975, 100, 70, "+星源", { size = 22, color = { 30, 100, 150 } }) then Hub.modal = "getsrc" end
end

-- ---------------------------------------------------------------- 出击
local function homeView()
    local W, s = UI.lw, sv(); local m = C:mech(s.mech); local pw = mechPower(s.mech); local p = C:char(s.pilot)
    header("宇宙银河机甲")
    UI.Panel(40, 110, 600, 400)
    UI.Text(60, 125, "出战机甲", 22, COL.teal); gtag(m.grade, 60, 155); UI.Text(180, 150, m.name, 52, COL.bone); UI.Text(60, 220, m.type .. "　Lv " .. C:mechLv(s.mech) .. "　" .. string.rep("★", C:mechStar(s.mech)), 24, COL.muted)
    statBar("耐久", pw.hp, 260, { 100, 230, 130 }, 60, 270); statBar("火力", pw.fire, 190, COL.amber, 60, 318); statBar("机动", pw.spd, 100, COL.teal, 60, 366)
    UI.Text(60, 420, m.weapon.name .. "，技能 " .. m.active.name, 24, COL.muted)
    UI.Panel(40, 520, 600, 130)
    -- 提示：下方三条推荐总高度 < 200，避免压住底部导航（y >= 975）
    UI.Text(60, 532, "驾驶员", 22, COL.teal); gtag(p.grade, 60, 560, 32); UI.Text(150, 558, p.name .. "　" .. p.role, 36, COL.bone); UI.Text(60, 610, p.support.name .. "：" .. p.support.desc, 20, COL.muted)
    if UI.Button(40, 660, 290, 60, "更换机甲", { size = 26 }) then Hub.tab = "hangar" end
    if UI.Button(350, 660, 290, 60, "更换驾驶员", { size = 26 }) then Hub.tab = "pilots" end
    local steps = nextSteps()
    if #steps > 0 then UI.Text(40, 735, "推荐下一步", 24, COL.teal) end
    for i, t in ipairs(steps) do if UI.Button(40, 768 + (i - 1) * 68, 600, 62, t.t, { size = 22, sub = t.d, subSize = 17, color = { 24, 32, 70 } }) then C:sfx("click"); Hub.tab = t.go end end
    -- 章节 / 危险等级
    local ch = C.CHAPTERS[Hub.chapterSel - 1]; local locked = Hub.chapterSel > s.chapter
    UI.Panel(W - 700, 110, 660, 640)
    UI.Text(W - 370, 125, "第 " .. ch.id .. " 章", 26, COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W - 370, 160, ch.name, 56, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Wrap(W - 670, 240, 600, ch.desc, 26, COL.bone)
    local pwr = C:power(); local col = pwr >= ch.rec and { 100, 230, 130 } or (pwr >= ch.rec * 0.8 and COL.amber or COL.danger)
    UI.Text(W - 670, 340, "推荐战力 " .. ch.rec, 26, COL.muted); UI.Text(W - 70, 340, "你的战力 " .. pwr, 26, col, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Text(W - 670, 380, pwr / ch.rec >= 1.15 and "战力充足，可以放心挑战" or pwr / ch.rec >= 1 and "战力达标" or pwr / ch.rec >= 0.8 and "略显吃力，建议先升级机甲或装备卡牌" or "战力不足，建议先去机库 / 工坊变强", 22, col)
    UI.Text(W - 670, 420, "首领　" .. ch.bossName .. (s.cleared[ch.id] and "　已通关" or ""), 26, COL.bone)
    if UI.Button(W - 690, 470, 80, 64, "‹", { size = 40 }) then C:sfx("click"); Hub.chapterSel = math.max(1, Hub.chapterSel - 1) end
    if UI.Button(W - 130, 470, 80, 64, "›", { size = 40 }) then C:sfx("click"); Hub.chapterSel = math.min(C.CHAPTERS.length, Hub.chapterSel + 1) end
    UI.Text(W - 370, 485, locked and "通关上一章解锁" or ("章节 " .. ch.id .. " / " .. C.CHAPTERS.length), 28, locked and COL.danger or COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local dm = s.dangerMax or 1; Hub.dangerSel = math.max(1, math.min(dm, Hub.dangerSel))
    if UI.Button(W - 690, 550, 80, 64, "‹", { size = 40 }) then C:sfx("click"); Hub.dangerSel = math.max(1, Hub.dangerSel - 1) end
    if UI.Button(W - 130, 550, 80, 64, "›", { size = 40 }) then C:sfx("click"); Hub.dangerSel = math.min(dm, Hub.dangerSel + 1) end
    UI.Text(W - 370, 552, "危险等级 " .. Hub.dangerSel, 32, { 255, 138, 58 }, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(W - 370, 592, "敌人血量 +" .. 12 * (Hub.dangerSel - 1) .. "%　伤害 +" .. 8 * (Hub.dangerSel - 1) .. "%　奖励 +" .. 15 * (Hub.dangerSel - 1) .. "%", 20, COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if UI.Button(W - 690, 640, 640, 90, "出  击", { size = 52, color = ORANGE, disabled = locked }) then C:sfx("gate"); Hub.onStart(Hub.chapterSel, { danger = Hub.dangerSel }) end
    if UI.Button(W - 690, 760, 640, 70, "无尽模式（最高第 " .. (s.endlessBest or 0) .. " 波）", { size = 28, color = { 60, 38, 100 }, disabled = not s.cleared[1] }) then
        C:sfx("gate"); Hub.onStart(Hub.chapterSel <= s.chapter and Hub.chapterSel or 1, { danger = Hub.dangerSel, endless = true }) end
    if not s.cleared[1] then UI.Text(W - 370, 836, "通关第 1 章解锁无尽模式", 22, COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
end

-- ---------------------------------------------------------------- 机库 / 驾驶员
local function listCol(arr, selId, isMech)
    local s = sv(); local items = sortG(arr)
    for i, x in ipairs(items) do
        local own = isMech and s.mechs[x.id] or (not isMech and s.chars[x.id]); local y = 110 + (i - 1) * 100
        if y < 940 then UI.Icon(UI.CatIcon(x.id), 40, y + 10, 52) end
        if y < 940 and UI.Button(30, y, 400, 92, (own and "" or "（未获得）") .. x.name, { size = 30, sub = x.grade .. (isMech and (own and ("　Lv " .. C:mechLv(x.id)) or "") or ("　" .. x.role)), color = selId == x.id and { 52, 100, 150 } or COL.hi, border = GRADE[x.grade], textColor = own and COL.bone or COL.muted }) then
            C:sfx("click"); if isMech then Hub.mechSel = x.id else Hub.pilotSel = x.id end
        end
    end
end
local function hangarView()
    local W, s = UI.lw, sv(); local id = Hub.mechSel or s.mech; local m = C:mech(id); local own = C:ownsMech(id); local lv = C:mechLv(id); local pw = mechPower(id)
    local aw = lv >= C.MECH_AWAKE; local cost = C:mechCost(lv); local max = lv >= C.MECH_MAX; local st = C:mechStar(id); local frags = s.frags[id] or 0; local need = st >= 5 and 0 or C.STAR_FRAGS[st]; local pilot = C:char(m.match)
    header("机库"); listCol(C.MECHS, id, true)
    UI.Panel(W - 760, 110, 720, 840)
    gtag(m.grade, W - 740, 125, 44); UI.Text(W - 620, 120, m.name, 56, COL.bone); UI.Text(W - 740, 195, m.type .. (own and (" · Lv " .. lv .. (aw and " · 已觉醒" or "")) or " · 未获得"), 26, COL.muted)
    statBar("耐久", pw.hp, 260, { 100, 230, 130 }, W - 740, 250); statBar("火力", pw.fire, 190, COL.amber, W - 740, 298); statBar("机动", pw.spd, 100, COL.teal, W - 740, 346)
    UI.Text(W - 740, 410, "主武器　" .. m.weapon.name, 28, COL.teal); UI.Wrap(W - 740, 448, 680, m.weapon.desc, 22, COL.muted)
    UI.Text(W - 740, 520, "机甲技能　" .. m.active.name .. "（冷却 " .. m.active.cd .. " 秒）", 28, COL.amber); UI.Wrap(W - 740, 558, 680, m.active.desc .. "。" .. m.active.awake, 22, COL.muted)
    UI.Text(W - 740, 660, "专属驾驶员　" .. pilot.name, 26, COL.bone); UI.Text(W - 740, 696, (s.chars[pilot.id] and "已拥有，" or "未获得，") .. "搭配时耐久与火力 +20%", 22, COL.muted)
    if own then
        if UI.Button(W - 740, 760, 330, 80, max and "已满级" or ("升级  " .. fmt(cost)), { size = 30, color = ORANGE, disabled = max }) then
            if s.credits < cost then toast("信用点不足：去出击赚取，或在每日里领巡航收益") else s.credits = s.credits - cost; s.mechs[id].lv = lv + 1; save(); C:sfx("level"); toast(m.name .. " 升到 Lv " .. (lv + 1) .. ((lv + 1 == C.MECH_AWAKE) and "，技能觉醒！" or "")) end
        end
        if UI.Button(W - 390, 760, 330, 80, st >= 5 and "已满星" or ("升星（碎片 " .. frags .. "/" .. need .. "）"), { size = 26, disabled = st >= 5 or frags < need }) then
            s.frags[id] = frags - need; s.mechs[id].star = st + 1; save(); C:sfx("win"); toast(m.name .. " 升到 " .. (st + 1) .. " 星")
        end
        if id ~= s.mech and UI.Button(W - 740, 855, 680, 70, "设为出战机甲", { size = 30 }) then s.mech = id; save(); C:sfx("click"); toast("出战机甲：" .. m.name) end
    elseif UI.Button(W - 740, 800, 680, 80, "前往机甲召唤", { size = 32, color = ORANGE }) then Hub.tab = "summon"; Hub.banner = "mech" end
end
local function pilotsView()
    local W, s = UI.lw, sv(); local id = Hub.pilotSel or s.pilot; local c = C:char(id); local own = s.chars[id]; local st = own and own.star or 0
    local frags = s.frags[id] or 0; local need = st >= 5 and 0 or (C.STAR_FRAGS[st] or 10)
    header("驾驶员"); listCol(C.CHARS, id, false)
    UI.Panel(W - 760, 110, 720, 840)
    gtag(c.grade, W - 740, 125, 44); UI.Text(W - 620, 120, c.name, 56, COL.bone); UI.Text(W - 740, 195, c.role .. (own and (" · " .. st .. " 星") or " · 未获得"), 26, COL.muted)
    UI.Text(W - 740, 260, "支援技能　" .. c.support.name .. "（冷却 " .. c.support.cd .. " 秒）", 28, COL.teal); UI.Wrap(W - 740, 298, 680, c.support.desc, 22, COL.muted)
    UI.Text(W - 740, 380, "被动　" .. c.passive.name, 26, COL.amber)
    UI.Text(W - 740, 440, "专属机甲　" .. C:mech(c.mech).name, 26, COL.bone); UI.Text(W - 740, 476, (C:ownsMech(c.mech) and "已拥有，" or "未获得，") .. "搭配时耐久与火力 +20%", 22, COL.muted)
    UI.Text(W - 740, 540, "当前倍率　支援技能 x" .. string.format("%.2f", C:pilotMul(id)), 26, COL.bone); UI.Text(W - 740, 576, c.grade .. " 级基础 x" .. C.GRADE[c.grade].mul .. "，每升 1 星 +15%", 22, COL.muted)
    if own then
        if UI.Button(W - 740, 700, 680, 80, st >= 5 and "已满星" or ("升星（碎片 " .. frags .. "/" .. need .. "）"), { size = 28, color = ORANGE, disabled = st >= 5 or frags < need }) then s.frags[id] = frags - need; own.star = own.star + 1; save(); C:sfx("level"); toast(c.name .. " 升到 " .. own.star .. " 星") end
        if id ~= s.pilot and UI.Button(W - 740, 800, 680, 70, "设为驾驶员", { size = 30 }) then s.pilot = id; save(); C:sfx("click"); toast("驾驶员：" .. c.name) end
    elseif UI.Button(W - 740, 760, 680, 80, "前往驾驶员召唤", { size = 32, color = ORANGE }) then Hub.tab = "summon"; Hub.banner = "pilot" end
end

-- ---------------------------------------------------------------- 工坊
local function adUp(item, name)
    local lv, left = item.lvl or 1, C:adUpLeft()
    if UI.Button(0, 0, 0, 0, "", { disabled = true }) then end
    return lv, left
end
local function doAdUp(it, name)
    C:showAd("升级" .. name, function(_, r) if not r.success then toast("需要完整看完广告才能升级") return end local u = C:adUpgrade(it); if u.err then toast(u.err) return end C:sfx("level"); toast(name .. " 升到 Lv " .. it.lvl) end)
end
local function modsView()
    local W, s, wk = UI.lw, sv(), Hub.wk
    local eq = s.modEq
    UI.Text(40, 175, "已收集 " .. s.modules.length .. " / " .. C:MOD_TOTAL() .. " 张卡牌　出击时 3 张装备全部生效", 24, COL.muted)
    for i = 0, 2 do
        local c = eq[i] and find(s.modules, function(x) return x.id == eq[i] end); local x = 40 + i * 370
        if UI.Button(x, 210, 350, 70, c and (c.name .. "  Lv" .. (c.lvl or 1)) or "空槽位", { size = 24, color = c and { 30, 40, 80 } or COL.panel, border = c and TIERC[c.tier + 1] or nil }) and c then
            local k = has(eq, c.id); if k then eq:splice(k, 1); save(); C:sfx("click") end
        end
    end
    local tnames = { "白色", "蓝色", "紫色", "金色" }
    for t = 0, 3 do local n = 0; for _, c in ipairs(list(s.modules)) do if c.tier == t then n = n + 1 end end
        if UI.Button(40 + t * 215, 300, 205, 56, tnames[t + 1] .. "  " .. n, { size = 24, color = wk.tier == t and TIERC[t + 1] or COL.hi, textColor = wk.tier == t and { 20, 20, 30 } or COL.bone }) then wk.tier = t; wk.v = 0; C:sfx("click") end end
    for i, F in ipairs(list(C.MOD_FORMS)) do
        local x, y = 40 + ((i - 1) % 5) * 172, 370 + ((i - 1) // 5) * 62; local own = 0; for _, c in ipairs(list(s.modules)) do if c.form == F.k then own = own + 1 end end
        if UI.Button(x, y, 166, 56, F.n .. (own > 0 and ("·" .. own) or ""), { size = 22, color = wk.form == F.k and { 52, 100, 150 } or COL.hi, textColor = own > 0 and COL.bone or COL.muted }) then wk.form = F.k; C:sfx("click") end
    end
    local nv = C.VARIANTS[wk.tier]
    for i, E in ipairs(list(C.ELEMENTS)) do
        local y = 618 + (i - 1) * 56; UI.Text(40, y + 12, E.n, 24, COL.muted)
        for v = 0, nv - 1 do
            local card = C:makeModule(wk.tier, wk.form, E.k, v); local own = C:modOwned(wk.form, E.k, wk.tier, v); local sel = wk.elem == E.k and wk.v == v
            if UI.Button(130 + v * 330, y, 320, 50, (card.name:gsub("^" .. E.n, "")) .. (own and ("  Lv" .. (own.lvl or 1)) or ""), { size = 20, color = own and { 40, 56, 110 } or { 30, 34, 56 }, border = sel and COL.teal or (own and TIERC[wk.tier + 1] or nil), textColor = own and COL.bone or COL.muted }) then wk.elem = E.k; wk.v = v; C:sfx("click") end
        end
    end
    UI.Panel(W - 700, 170, 660, 800, 235)
    local card = C:makeModule(wk.tier, wk.form, wk.elem, wk.v); local own = C:modOwned(wk.form, wk.elem, wk.tier, wk.v); local F, E = C:modForm(wk.form), C:modElem(wk.elem)
    UI.Text(W - 670, 190, card.name, 44, TIERC[wk.tier + 1]); UI.Text(W - 670, 250, C.RARITY[wk.tier].n .. (own and ("　Lv " .. (own.lvl or 1)) or "　未获得"), 26, own and COL.bone or COL.muted)
    UI.Wrap(W - 670, 300, 600, C:modDesc(card), 24, COL.bone); UI.Wrap(W - 670, 420, 600, "元素：" .. E.d, 24, COL.teal)
    local g = C:goldTag(card); if g then UI.Wrap(W - 670, 480, 600, "金色特效：" .. g.d, 24, COL.amber) end
    local ev = C:evoOf(card); if ev then UI.Wrap(W - 670, 560, 600, "进化「" .. ev.n .. "」：" .. ev.d .. "（卡牌 Lv5 + 对应被动 Lv" .. C.EVO_PASS_LV .. "，局内触发）", 22, COL.muted) end
    if own then
        local eqd = has(eq, own.id)
        if UI.Button(W - 670, 680, 290, 70, eqd and "卸下" or "装备", { size = 30, color = ORANGE }) then
            if eqd then eq:splice(eqd, 1) elseif eq.length >= 3 then toast("槽位已满，先卸下一个") else eq:push(own.id) end; save(); C:sfx("click")
        end
        local lv, left = own.lvl or 1, C:adUpLeft()
        if UI.Button(W - 360, 680, 310, 70, lv >= C.LV_MAX and "已满级" or ("看广告 升到 Lv " .. math.min(C.LV_MAX, lv + 1)), { size = 24, sub = lv >= C.LV_MAX and nil or ("今日还可 " .. left .. " 次"), color = { 30, 100, 150 }, disabled = lv >= C.LV_MAX or left <= 0 }) then doAdUp(own, own.name) end
    end
    if UI.Button(W - 670, 790, 620, 90, "研发技能卡牌", { size = 34, sub = "信用点 " .. fmt(C:MOD_COST(s.modBuys or 0)) .. "，随机抽取 " .. C:MOD_TOTAL() .. " 张之一", color = ORANGE }) then
        local r = C:buyModule(); if r.err then toast(r.err) else
            local it = r.mod; save(); C:sfx(it.tier >= 2 and "win" or "level"); wk.form, wk.elem, wk.tier, wk.v = it.form, it.elem, it.tier, it.v or 0
            if r.isNew and eq.length < 3 then eq:push(it.id) end
            Hub.results = { kind = "card", item = it, dup = r.dup, refund = r.refund, name = it.name, tier = it.tier } end
    end
    UI.Text(W - 670, 890, "品质：白 60% / 蓝 28% / 紫 10% / 金 2%；每 10 次至少蓝色，每 40 次必出金色", 20, COL.muted)
end
local function chipsView()
    local W, s = UI.lw, sv(); local slots = C:chipSlots()
    local eq = s.chipEq; if not eq then eq = require("jsrt.JS").newarr(0); s.chipEq = eq end
    UI.Text(40, 175, "已装备 " .. eq.length .. " / " .. slots .. "（通关章节解锁更多槽位）　仓库 " .. s.chips.length .. " / " .. C.INV_MAX, 24, COL.muted)
    for i = 0, 5 do
        local c = eq[i] and find(s.chips, function(x) return x.id == eq[i] end); local x = 40 + i * 190
        if UI.Button(x, 210, 182, 90, c and ((c.name or ""):sub(1, 12) .. "\nLv" .. (c.lvl or 1)) or (i >= slots and "未解锁" or "空槽"), { size = 20, color = c and { 30, 40, 80 } or COL.panel, border = c and TIERC[c.tier + 1] or nil, disabled = i >= slots and not c }) and c then Hub.wsel = c.id end
    end
    local items = list(s.chips); table.sort(items, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return (a.lvl or 1) > (b.lvl or 1) end)
    for i, c in ipairs(items) do local x, y = 40 + ((i - 1) % 6) * 190, 330 + ((i - 1) // 6) * 100
        if y < 940 and UI.Button(x, y, 182, 92, c.series .. "\nLv" .. (c.lvl or 1) .. (has(eq, c.id) and " 已装备" or ""), { size = 20, color = Hub.wsel == c.id and { 52, 100, 150 } or COL.hi, border = TIERC[c.tier + 1] }) then Hub.wsel = c.id; C:sfx("click") end end
    UI.Panel(W - 700, 170, 660, 800, 235)
    local c = Hub.wsel and find(s.chips, function(x) return x.id == Hub.wsel end)
    if c then
        UI.Text(W - 670, 190, c.name, 40, TIERC[c.tier + 1]); UI.Text(W - 670, 250, C.RARITY[c.tier].n .. "　Lv " .. (c.lvl or 1), 26, COL.bone)
        for i, a in ipairs(list(c.aff)) do UI.Text(W - 670, 300 + (i - 1) * 40, "· " .. C:affText(a, c), 26, COL.bone) end
        if c.trait then local t = C:trait(c.trait); UI.Wrap(W - 670, 440, 600, "金色特性「" .. t.n .. "」：" .. t.d, 24, COL.amber) end
        local k = has(eq, c.id)
        if UI.Button(W - 670, 540, 290, 70, k and "卸下" or "装备", { size = 30, color = ORANGE }) then
            if k then eq:splice(k, 1) elseif eq.length >= slots then toast("槽位已满，先卸下一个") else eq:push(c.id) end; save(); C:sfx("click")
        end
        local lv, left = c.lvl or 1, C:adUpLeft()
        if UI.Button(W - 360, 540, 310, 70, lv >= C.LV_MAX and "已满级" or ("看广告 升到 Lv " .. math.min(C.LV_MAX, lv + 1)), { size = 24, sub = lv >= C.LV_MAX and nil or ("今日还可 " .. left .. " 次"), color = { 30, 100, 150 }, disabled = lv >= C.LV_MAX or left <= 0 }) then doAdUp(c, c.name) end
        if UI.Button(W - 670, 630, 620, 60, "分解  +" .. C.REFUND[c.tier] .. " 信用点", { size = 26 }) then
            local kk = has(eq, c.id); if kk then eq:splice(kk, 1) end; local _, idx = find(s.chips, function(x) return x == c end); s.chips:splice(idx, 1); s.credits = s.credits + C.REFUND[c.tier]; Hub.wsel = nil; save(); C:sfx("pop"); toast("分解完成：信用点 +" .. C.REFUND[c.tier])
        end
    else UI.Wrap(W - 670, 220, 600, "点选左侧的芯片查看详情。芯片属性永久生效，装备越多越强；每升 1 级词条 +12%。", 26, COL.muted) end
    if UI.Button(W - 670, 790, 620, 90, "研发天赋芯片", { size = 34, sub = "信用点 " .. fmt(C:CHIP_COST(s.chipBuys or 0)) .. "，仓库 " .. s.chips.length .. " / " .. C.INV_MAX, color = ORANGE }) then
        local r = C:buyChip(); if r.err then toast(r.err) else local it = r.chip; save(); C:sfx(it.tier >= 2 and "win" or "level"); if eq.length < slots then eq:push(it.id) end; Hub.wsel = it.id; Hub.results = { kind = "chip", item = it, name = it.name, tier = it.tier } end
    end
end
local function workView()
    header("工坊")
    if UI.Button(240, 100, 260, 60, "技能卡牌", { size = 28, color = Hub.wsub == "mods" and ORANGE or COL.hi }) then Hub.wsub = "mods"; C:sfx("click") end
    if UI.Button(520, 100, 260, 60, "天赋芯片", { size = 28, color = Hub.wsub == "chips" and ORANGE or COL.hi }) then Hub.wsub = "chips"; C:sfx("click") end
    if Hub.wsub == "mods" then modsView() else chipsView() end
end

-- ---------------------------------------------------------------- 召唤
local function summonView()
    local W, s = UI.lw, sv(); header("召唤")
    local isM = Hub.banner == "mech"; local arr = isM and C.MECHS or C.CHARS; local RT = C.SUMMON.rates
    if UI.Button(60, 110, 420, 90, "机甲召唤", { size = 34, color = isM and ORANGE or COL.hi }) then Hub.banner = "mech"; C:sfx("click") end
    if UI.Button(500, 110, 420, 90, "驾驶员召唤", { size = 34, color = (not isM) and ORANGE or COL.hi }) then Hub.banner = "pilot"; C:sfx("click") end
    local b = Hub.banner; local p1, p3 = s[b .. "Pity"] or 0, s[b .. "Pity3"] or 0
    UI.Text(60, 230, string.format("SSSR %.0f%%　SSR %.0f%%　SS %.0f%%　S %.0f%%", RT.SSSR * 100, RT.SSR * 100, RT.SS * 100, RT.S * 100), 28, COL.bone)
    UI.Text(60, 276, "十连必出 SS 以上；" .. C.SUMMON.pitySSR .. " 抽内必出 SSR 以上，" .. C.SUMMON.pitySSSR .. " 抽内必出 SSSR（两个池分开计算）。重复获得会转成碎片。", 22, COL.muted)
    UI.Text(60, 316, "保底进度：SSR+ " .. p1 .. " / " .. C.SUMMON.pitySSR .. "　SSSR " .. p3 .. " / " .. C.SUMMON.pitySSSR, 24, COL.teal)
    local top = {}; for _, x in ipairs(list(arr)) do if x.grade == "SSR" or x.grade == "SSSR" then top[#top + 1] = x.grade .. " " .. x.name end end
    UI.Text(60, 360, "本池 SSR 以上：" .. table.concat(top, "、"), 24, COL.amber)
    local function pull(n, cost)
        if s.src < cost then Hub.modal = "getsrc" return end
        s.src = s.src - cost; s.daily.pulls = (s.daily.pulls or 0) + n
        local out = {}; for i = 1, n do out[#out + 1] = C:pull(b, false) end
        local all = true; for _, r in ipairs(out) do if r.grade ~= "S" then all = false end end
        if n == 10 and all then s[b .. "Pity"] = s[b .. "Pity"] - 1; out[10] = C:pull(b, true) end
        save(); Hub.StartSummon(out)
    end
    if UI.Button(60, 430, 420, 100, "召唤 1 次", { size = 36, sub = "星源 " .. C.SUMMON.single }) then pull(1, C.SUMMON.single) end
    if UI.Button(500, 430, 420, 100, "召唤 10 次", { size = 36, sub = "星源 " .. C.SUMMON.ten, color = ORANGE }) then pull(10, C.SUMMON.ten) end
    if UI.Button(940, 430, 420, 100, s.daily.free and "今日免费已领取" or "每日免费 看广告召唤 1 次", { size = 26, disabled = s.daily.free and true or false, color = { 30, 100, 150 } }) then
        C:showAd("每日免费召唤", function(_, r) if not r.success then toast("需要完整看完广告才能召唤") return end s.daily.free = 1; s.daily.pulls = (s.daily.pulls or 0) + 1; local res = { C:pull(b, false) }; save(); Hub.StartSummon(res) end)
    end
    UI.Text(60, 570, "拥有情况", 26, COL.teal)
    for i, x in ipairs(sortG(arr)) do
        local own = isM and s.mechs[x.id] or (not isM and s.chars[x.id])
        UI.Text(60 + ((i - 1) % 3) * 500, 610 + ((i - 1) // 3) * 50, x.grade .. " " .. x.name .. (own and ("　" .. (isM and ("Lv " .. own.lv .. " ") or "") .. string.rep("★", own.star)) or "　未获得"), 26, own and GRADE[x.grade] or COL.muted)
    end
end

-- ---------------------------------------------------------------- 每日
local function dailyView()
    local W, s = UI.lw, sv(); header("每日")
    local ls = C:loginState()
    UI.Text(40, 100, "7 日登录奖励", 26, COL.teal)
    for i, r in ipairs(list(C.LOGIN_REWARDS)) do local x = 40 + (i - 1) * 118; local done = (ls.claimed and (i - 1) <= ls.idx) or ((not ls.claimed) and (i - 1) < ls.idx); local cur = (not ls.claimed) and (i - 1) == ls.idx
        UI.Panel(x, 135, 110, 110, done and 120 or 225); UI.Text(x + 55, 143, "第" .. i .. "天", 20, cur and COL.amber or COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        UI.Text(x + 55, 175, r.cr and (r.cr .. "\n信用点") or (r.src .. "\n星源"), 20, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); if r.draw then UI.Text(x + 55, 222, "+抽卡", 18, COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end end
    if UI.Button(40, 255, 400, 56, ls.claimed and "今日已领取" or "领取今日奖励", { size = 26, disabled = ls.claimed and true or false, color = ORANGE }) then local t = C:loginClaim(); if t then C:sfx("win"); toast("登录奖励：" .. t) end end
    -- 每日挑战
    local dc = C:dailyChallenge()
    UI.Panel(40, 325, 840, 270, 230); UI.Text(60, 335, "每日挑战　第 " .. dc.chapter .. " 章　限时 4 分钟", 30, { 255, 138, 58 })
    for i, id in ipairs(list(dc.mods)) do local m = C:dcMod(id); UI.Text(60, 380 + (i - 1) * 40, m.n .. "：" .. m.d, 24, COL.bone) end
    UI.Text(60, 465, "今日最高分 " .. dc.state.best .. "　历史最高 " .. (s.dcBest or 0) .. "　" .. (dc.state.done and "今日奖励已领取" or "首次完成：信用点 +800，星源 +10"), 22, COL.muted)
    if UI.Button(60, 505, 800, 70, "开始挑战", { size = 34, color = ORANGE }) then C:sfx("gate"); Hub.onStart(dc.chapter, { daily = true, mods = dc.mods, danger = dc.danger }) end
    -- 巡航收益 / 补给 / 看广告得星源
    local a = C:idleAmount()
    UI.Text(40, 610, "巡航收益　离线也会累积，最多 8 小时　信用点 " .. fmt(a.credits), 24, COL.teal)
    local function claimIdle(mult) s.credits = s.credits + a.credits * mult; s.idleT = require("jsrt.JS").G.Date:now(); save(); C:sfx("pick"); toast("巡航收益：信用点 +" .. fmt(a.credits * mult)) end
    if UI.Button(40, 650, 400, 60, "领取", { size = 26 }) then claimIdle(1) end
    if UI.Button(460, 650, 420, 60, "看广告 双倍", { size = 26, color = { 30, 100, 150 } }) then C:showAd("巡航收益双倍", function(_, r) if not r.success then toast("需要完整看完广告才能领取") return end claimIdle(2) end) end
    UI.Text(40, 730, "每日补给", 24, COL.teal)
    if UI.Button(40, 765, 400, 56, (s.daily.supply and s.daily.supply ~= 0) and "补给已领取" or ("领取补给 星源 +" .. C.DAILY_SUPPLY), { size = 24, disabled = (s.daily.supply and s.daily.supply ~= 0) and true or false }) then s.daily.supply = 1; s.src = s.src + C.DAILY_SUPPLY; save(); C:sfx("pick"); toast("每日补给：星源 +" .. C.DAILY_SUPPLY) end
    local left = C.AD.srcDaily - (s.daily.ads or 0)
    if UI.Button(460, 765, 420, 56, "看广告 星源 +" .. C.AD.srcReward .. "（今日还可 " .. math.max(0, left) .. " 次）", { size = 22, disabled = left <= 0, color = { 30, 100, 150 } }) then
        C:showAd("领取星源", function(_, r) if not r.success then toast("需要完整看完广告才能领取") return end s.daily.ads = (s.daily.ads or 0) + 1; s.src = s.src + C.AD.srcReward; save(); C:sfx("pick"); toast("星源 +" .. C.AD.srcReward) end)
    end
    UI.Text(920, 100, "每日任务", 26, COL.teal)
    for i, t in ipairs(list(C.TASKS)) do local yy = 130 + (i - 1) * 62; local v = math.min(t.need, s.daily[t.key] or 0); local done = v >= t.need
        UI.Text(920, yy + 6, t.name .. "　" .. v .. " / " .. t.need, 24, COL.bone); UI.Text(1500, yy + 8, "星源 +" .. t.reward, 22, COL.teal)
        if UI.Button(1680, yy, 200, 52, s.daily.claimed[t.id] and "已领取" or "领取", { size = 22, disabled = s.daily.claimed[t.id] and true or (not done) }) then s.daily.claimed[t.id] = 1; s.src = s.src + t.reward; save(); C:sfx("pick"); toast("任务奖励：星源 +" .. t.reward) end end
    local nach = 0; for _ in pairs(s.ach) do nach = nach + 1 end
    UI.Text(920, 340, "成就（" .. nach .. " / " .. C.ACH.length .. "）", 26, COL.teal)
    for i, a in ipairs(list(C.ACH)) do
        local col, row = (i - 1) // 9, (i - 1) % 9; local x, yy = 920 + col * 480, 380 + row * 62; local ok = a.ok(nil, s)
        UI.Panel(x, yy, 470, 56, 200)
        UI.Text(x + 8, yy + 4, a.name .. "　星源 +" .. a.src, 20, ok and COL.bone or COL.muted); UI.Text(x + 8, yy + 30, a.desc, 16, COL.muted)
        if UI.Button(x + 350, yy + 8, 112, 40, s.ach[a.id] and "已领取" or "领取", { size = 18, disabled = s.ach[a.id] and true or (not ok) }) then if C:achClaim(a.id) then C:sfx("pick"); toast("成就奖励已领取") end end
    end
end

-- ---------------------------------------------------------------- 弹窗：结果 / 设置 / 关于 / 获取星源
local function dim() nvgBeginPath(UI.vg); nvgRect(UI.vg, 0, 0, UI.lw, 1080); nvgFillColor(UI.vg, nvgRGBA(0, 0, 10, 190)); nvgFill(UI.vg) end
local function drawResults()
    local W, r = UI.lw, Hub.results; dim(); UI.Panel(W / 2 - 700, 120, 1400, 800, 248)
    if r.kind == "pull" then
        UI.Text(W / 2, 140, "召唤结果", 64, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        for i, o in ipairs(r.out) do
            local x, y = W / 2 - 660 + ((i - 1) % 5) * 270, 240 + ((i - 1) // 5) * 200; local it = o.kind == "mech" and C:mech(o.id) or C:char(o.id)
            UI.Panel(x, y, 255, 180, 230); UI.Text(x + 14, y + 10, o.grade, 34, GRADE[o.grade]); UI.Text(x + 14, y + 60, it.name, 36, COL.bone)
            UI.Text(x + 14, y + 110, o.isNew and "新获得！" or ("碎片 +" .. (o.frag or 0)), 24, o.isNew and COL.teal or COL.muted)
        end
    else
        UI.Text(W / 2, 140, r.kind == "card" and "研发完成" or "芯片研发完成", 60, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        UI.Text(W / 2, 260, C.RARITY[r.tier].n, 32, TIERC[r.tier + 1], NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W / 2, 320, r.name, 56, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if r.kind == "card" then
            UI.Text(W / 2, 410, r.dup and ("已拥有：卡牌升到 Lv " .. (r.item.lvl or 1) .. (r.refund and ("（已满级，折算信用点 +" .. r.refund .. "）") or "")) or "新卡牌", 28, COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            UI.Wrap(W / 2 - 500, 470, 1000, C:modDesc(r.item), 26, COL.bone)
        else for i, a in ipairs(list(r.item.aff)) do UI.Text(W / 2, 420 + (i - 1) * 44, "· " .. C:affText(a, r.item), 30, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end end
    end
    if UI.Button(W / 2 - 150, 820, 300, 70, "确定", { size = 34, color = ORANGE }) then Hub.results = nil end
end
local function drawSettings()
    local W, s = UI.lw, sv(); dim(); UI.Panel(W / 2 - 560, 120, 1120, 820, 248); UI.Text(W / 2, 140, "设置", 60, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local st = s.settings
    if UI.Button(W / 2 - 520, 240, 500, 70, "音效：" .. (st.sound and "开" or "关"), { size = 28 }) then st.sound = not st.sound; save() end
    if UI.Button(W / 2 + 20, 240, 500, 70, "背景音乐：" .. (st.music and "开" or "关"), { size = 28 }) then st.music = not st.music; save(); C.music:refresh(); if HOST.onMusicRefresh then HOST.onMusicRefresh() end end
    local camN = { chase = "标准", high = "远景", mid = "近景" }
    UI.Text(W / 2 - 520, 340, "镜头", 26, COL.muted)
    for i, k in ipairs({ "mid", "chase", "high" }) do if UI.Button(W / 2 - 400 + (i - 1) * 300, 330, 280, 60, camN[k], { size = 26, color = (st.cam or "chase") == k and ORANGE or COL.hi }) then st.cam = k; save() end end
    UI.Text(W / 2 - 520, 430, "特效", 26, COL.muted)
    for i, k in ipairs({ "high", "soft" }) do if UI.Button(W / 2 - 400 + (i - 1) * 300, 420, 280, 60, k == "high" and "完整" or "柔和（减少粒子）", { size = 24, color = (st.fx or "high") == k and ORANGE or COL.hi }) then st.fx = k; save() end end
    if UI.Button(W / 2 - 520, 520, 500, 70, "省电模式：" .. (st.saver and "开" or "关"), { size = 26 }) then st.saver = not st.saver; save() end
    if UI.Button(W / 2 + 20, 520, 500, 70, "重播新手引导", { size = 26 }) then s.tutorialDone = false; save(); toast("下一次出击会重新播放新手引导") end
    if UI.Button(W / 2 - 520, 620, 500, 70, "关于与合规", { size = 26 }) then Hub.modal = "about" end
    if UI.Button(W / 2 - 150, 800, 300, 80, "关闭", { size = 34, color = ORANGE }) then Hub.modal = nil end
end
local function drawAbout()
    local W = UI.lw; dim(); UI.Panel(W / 2 - 800, 80, 1600, 900, 248); UI.Text(W / 2, 96, "关于与合规", 56, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); local RT = C.SUMMON.rates
    local lines = {
        { "原创声明", "游戏内全部机甲、角色、敌人、场景模型均为原创体素建模；音效与背景音乐为程序合成的原创音频。与任何现有动漫、游戏、影视作品及其角色、机体、商标无关联。" },
        { "抽取概率公示", string.format("召唤（机甲 / 驾驶员）：SSSR %.0f%%，SSR %.0f%%，SS %.0f%%，S %.0f%%；连续 %d 次未出 SSR 以上时下一次必出 SSR 以上，连续 %d 次未出 SSSR 时下一次必出 SSSR。工坊（技能卡牌 / 天赋芯片）：白色 60%%，蓝色 28%%，紫色 10%%，金色 2%%；每 10 次至少蓝色，每 40 次必出金色；技能卡牌共 %d 张。所有抽取只消耗游戏内货币，本版本无真实货币付费。", RT.SSSR * 100, RT.SSR * 100, RT.SS * 100, RT.S * 100, C.SUMMON.pitySSR, C.SUMMON.pitySSSR, C:MOD_TOTAL()) },
        { "广告", "“看广告”为可选行为，用于升级卡牌 / 芯片、刷新升级选项、复活、免费召唤、信用点翻倍或领取星源；不看不影响通关。只有完整观看才发放奖励。" },
        { "隐私", "本游戏不要求登录，不收集个人信息；存档保存在设备本地。" },
        { "适龄提示", "含卡通风格的科幻战斗（无血腥），建议 12 岁及以上；请合理安排游戏时间。" },
    }
    local y = 180; for _, l in ipairs(lines) do UI.Text(W / 2 - 740, y, l[1], 28, COL.teal); UI.Wrap(W / 2 - 740, y + 38, 1480, l[2], 24, COL.bone); y = y + 38 + 32 * (math.floor(#l[2] / 130) + 1) + 20 end
    if UI.Button(W / 2 - 150, 880, 300, 70, "关闭", { size = 32, color = ORANGE }) then Hub.modal = "settings" end
end
local function drawGetSrc()
    local W, s = UI.lw, sv(); dim(); UI.Panel(W / 2 - 520, 220, 1040, 520, 248); UI.Text(W / 2, 240, "获取星源", 60, COL.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local left = C.AD.srcDaily - (s.daily.ads or 0)
    UI.Text(W / 2 - 480, 340, "观看广告　今日还可领取 " .. math.max(0, left) .. " 次　+" .. C.AD.srcReward, 28, COL.bone)
    if UI.Button(W / 2 + 200, 330, 280, 60, "看广告", { size = 26, disabled = left <= 0, color = { 30, 100, 150 } }) then C:showAd("领取星源", function(_, r) if not r.success then toast("需要完整看完广告才能领取") return end s.daily.ads = (s.daily.ads or 0) + 1; s.src = s.src + C.AD.srcReward; save(); C:sfx("pick"); toast("星源 +" .. C.AD.srcReward) end) end
    UI.Text(W / 2 - 480, 430, "每日补给与每日任务：在“每日”页领取", 26, COL.bone); if UI.Button(W / 2 + 200, 420, 280, 60, "前往", { size = 26 }) then Hub.modal = nil; Hub.tab = "daily" end
    UI.Text(W / 2 - 480, 520, "章节首通、营救逃生舱、击败首领：出击时获得", 26, COL.muted)
    if UI.Button(W / 2 - 150, 630, 300, 70, "关闭", { size = 32, color = ORANGE }) then Hub.modal = nil end
end

-- ---------------------------------------------------------------- 入口
function Hub.Draw()
    if Hub.sa then drawSummonAnim(); return end
    if Hub.tab == "work" or Hub.tab == "daily" or Hub.tab == "summon" then nvgBeginPath(UI.vg); nvgRect(UI.vg, 0, 0, UI.lw, 1080); nvgFillColor(UI.vg, nvgRGBA(5, 8, 24, 150)); nvgFill(UI.vg) end
    if Hub.tab == "home" then homeView() elseif Hub.tab == "hangar" then hangarView() elseif Hub.tab == "pilots" then pilotsView() elseif Hub.tab == "work" then workView()
    elseif Hub.tab == "summon" then summonView() elseif Hub.tab == "daily" then dailyView() end
    nav()
    if Hub.results then drawResults() elseif Hub.modal == "settings" then drawSettings() elseif Hub.modal == "about" then drawAbout() elseif Hub.modal == "getsrc" then drawGetSrc() end
end
-- ---------------------------------------------------------------- 机库 3D 场景（移植自 cosmic_hub.js 的 DECOR / frame / summonScene）
local JS = require("jsrt.JS")
local Hostmod = require("jsrt.Host")
local ENV, SUM_ENV
local DECOR
local function buildDecor()
    local d = {}
    for x = -5, 5 do for z = -3, 3 do d[#d + 1] = { "env_deck_tile", x * 2, -0.25, z * 2, 0, 1 } end end
    local k = 0; for _, x in ipairs({ -7.5, -4.5, -1.5, 1.5, 4.5, 7.5 }) do d[#d + 1] = { k == 2 and "env_door" or "env_wall", x, 0, -6.6, 0, 1 }; k = k + 1 end
    d[#d + 1] = { "env_antenna", -9.5, 0, -4.8, 30, 1 }; d[#d + 1] = { "env_antenna", 9.5, 0, -4.8, -30, 1 }
    d[#d + 1] = { "prop_cargo_container", -7.4, 0, -2.6, 90, 1.1 }; d[#d + 1] = { "prop_cargo_container", -7.4, 1.32, -2.6, 85, 1.1 }
    d[#d + 1] = { "prop_supply_crate", 6.6, 0, -3.4, 15, 1.2 }; d[#d + 1] = { "prop_supply_crate", 7.6, 0, -2.6, -10, 1.2 }; d[#d + 1] = { "prop_supply_crate", 7.0, 0.95, -3.0, 30, 1.2 }
    d[#d + 1] = { "prop_fuel_canister", 5.6, 0, -4.4, 0, 1.2 }; d[#d + 1] = { "prop_fuel_canister", 6.2, 0, -5.0, 0, 1.2 }
    d[#d + 1] = { "prop_console", -4.8, 0, -4.6, 20, 1.1 }; d[#d + 1] = { "env_crystal_cluster", 8.8, 0, 1.6, -40, 1.2 }; d[#d + 1] = { "prop_turret", -8.6, 0, 1.8, 140, 1.1 }
    return d
end
local GTINT = { S = { 0.3, 0.7, 1.5 }, SS = { 0.75, 0.4, 1.5 }, SSR = { 1.6, 1.0, 0.25 }, SSSR = { 1.7, 0.35, 0.55 } }
local function top(g) return g == "SSR" or g == "SSSR" end
local starBuf
local function hubStars(E, jsarr)
    if not starBuf then
        local d = jsarr(0); local n = 0
        for _ = 1, 420 do local x, y, z = math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1; local l = math.sqrt(x * x + y * y + z * z); if l == 0 then l = 1 end
            local vals = { x / l * 300, y / l * 300, z / l * 300, 3 + math.random() * 6, math.random() < 0.7 and 0 or (math.random() < 0.5 and 1 or 2) }
            for _, v in ipairs(vals) do rawset(d, n, v); n = n + 1 end end
        rawset(d, "length", n)
        starBuf = E:buildStars({ data = d, colors = jsarr(3, jsarr(3, 0.92, 0.93, 1.0), jsarr(3, 0.6, 0.85, 1.0), jsarr(3, 1.0, 0.8, 0.5)) })
    end
    return starBuf
end
local hp = {}
local function burst(n, c, speed, tint, life, up)
    for _ = 1, n do if #hp >= 220 then break end
        local u, a = math.random() * 2 - 1, math.random() * math.pi * 2; local r = math.sqrt(1 - u * u); local sp = speed * (0.4 + math.random() * 0.6)
        hp[#hp + 1] = { x = c[1], y = c[2], z = c[3], vx = math.cos(a) * r * sp, vy = (up and math.abs(u) or u) * sp, vz = math.min(math.sin(a) * r * sp, sp * 0.15), life = life * (0.6 + math.random() * 0.6), max = life, tint = tint, size = 0.6 + math.random() * 0.6 } end
end
function Hub.StartSummon(res)
    local best = "S"; for _, r in ipairs(res) do if ORDER[r.grade] > ORDER[best] then best = r.grade end end
    local show = {}; for _, r in ipairs(res) do if r.isNew and r.grade ~= "S" then show[#show + 1] = r end end
    Hub.sa = { phase = "charge", t = 0, grade = best, res = res, show = show, si = 1, flipped = {}, flash = 0 }; hp = {}; C:sfx("skill")
end
function Hub.FinishSummon() Hub.sa = nil; hp = {} end
function Hub.Scene(E, jsarr, aspect, dt)
    local A, V = HOST.A, HOST.view
    if not ENV then
        ENV = Hostmod.jsify({ bg = { 0.05, 0.06, 0.14 }, ambient = { 0.46, 0.44, 0.6 }, fog = { 30, 70 }, key = { dir = { -0.4, -0.8, -0.45 }, color = { 1, 0.95, 0.88 }, brightness = 1.25 }, fill = { dir = { 0.6, -0.3, 0.7 }, color = { 0.45, 0.75, 1.0 }, brightness = 0.55 }, bloom = { threshold = 0.55, mix = 0.95 } })
        SUM_ENV = Hostmod.jsify({ bg = { 0.03, 0.03, 0.09 }, ambient = { 0.38, 0.36, 0.55 }, fog = { 40, 160 }, key = { dir = { -0.3, -0.8, -0.5 }, color = { 1, 0.92, 0.85 }, brightness = 1.1 }, fill = { dir = { 0.5, -0.2, 0.8 }, color = { 0.6, 0.45, 1.0 }, brightness = 0.7 }, bloom = { threshold = 0.5, mix = 1.1 } })
        DECOR = buildDecor()
    end
    Hub.t = Hub.t + dt; local t = Hub.t; local s = sv(); local sa = Hub.sa
    local draws = jsarr(0)
    local function add(model, x, y, z, yaw, sc, tint, pitch)
        local m = E:getMesh(model); if m then draws:push({ mesh = m, m = E:trs(jsarr(3, x, y, z), yaw, pitch or 0, 0, sc), s = sc, tint = tint and jsarr(3, tint[1], tint[2], tint[3]) or nil }) end
    end
    local eye, tgt, fov
    if Hub.tab == "summon" or sa then
        local isM = Hub.banner == "mech"; local feat = {}; for _, x in ipairs(list(isM and C.MECHS or C.CHARS)) do if top(x.grade) then feat[#feat + 1] = x end end
        add("sys_pedestal", 0, 0, 0, t * 6, 3.4)
        for i = 0, 4 do local a = math.pi + i / 4 * math.pi; add("env_crystal_cluster", math.cos(a) * 8, 0, math.sin(a) * 5 - 3, a * 57 + t * 8, 1.15) end
        eye, tgt, fov = { 0, 3.3, 12.5 }, { 0, 2.6, 0 }, 44
        local shard = { 0, 3.4 + math.sin(t * 1.5) * 0.25, 0 }; local spin = t * 40
        if not sa then
            add("prop_meteor_shard", shard[1], shard[2], shard[3], spin, 2.2)
            for k, x in ipairs(feat) do local px = (k == 2) and 4.4 or -4.4; local py = 1.6 + math.sin(t * 1.2 + (k - 1) * 2) * 0.15
                add("sys_pedestal", px, py, -1.5, 0, 1.1); add(x.id, px, py + 0.12, -1.5, ((k == 2) and -20 or 20) + math.sin(t * 0.8 + (k - 1)) * 10, isM and 0.72 or 1.5) end
            if math.random() < 0.18 then burst(1, shard, 1, { 0.3, 0.55, 0.85 }, 1.6, true) end
        else
            sa.t = sa.t + dt; local T, tint = sa.t, GTINT[sa.grade]; sa.flash = math.max(0, sa.flash - dt)
            if sa.phase == "charge" then
                spin = t * 40 + T * T * 900; shard[2] = shard[2] + T * 2.5; add("prop_meteor_shard", shard[1], shard[2], shard[3], spin, 2.2 + T)
                for _ = 1, 2 do local aa, rr = math.pi + math.random() * math.pi, 7; hp[#hp + 1] = { x = math.cos(aa) * rr, y = 0.5 + math.random() * 4, z = math.sin(aa) * rr, vx = -math.cos(aa) * rr * 1.4, vy = 1.5, vz = -math.sin(aa) * rr * 1.4, life = 0.7, max = 0.7, tint = { 0.7, 0.75, 0.95 }, size = 1 } end
                if T > 0.9 then sa.phase = "fall"; sa.t = 0; C:sfx("warp") end
            elseif sa.phase == "fall" then
                local k = math.min(1, T / 0.6); local y = 34 - 32 * k * k; local col = k > 0.55 and tint or { 0.8, 0.8, 0.95 }
                add("prop_meteor_shard", 0, y, 0, t * 500, 3.2); burst(2, { 0, y + 1, 0 }, 2.5, col, 0.5)
                eye = { 0, 3.3 + k * 0.6, 12.5 }; tgt = { 0, 2.6 + (1 - k) * 4, 0 }
                if k >= 1 then sa.phase = "burst"; sa.t = 0; burst(90, { 0, 1.5, 0 }, 16, tint, 1.4); C:sfx(top(sa.grade) and "win" or "boom"); sa.flash = 0.6 end
            elseif sa.phase == "burst" then
                local sh = math.max(0, 0.6 - T) * 0.5; eye = { math.random() * sh - sh / 2, 3.3 + math.random() * sh, 12.5 }
                if math.random() < 0.9 then burst(3, { 0, 1, 0 }, 6, tint, 1, true) end
                if T > 0.75 then sa.phase = "cards"; sa.t = 0 end
            elseif sa.phase == "cards" then if math.random() < 0.5 then burst(1, { 0, 1, 0 }, 4, tint, 1.2, true) end
            elseif sa.phase == "show" then
                local it = sa.show[sa.si]; local g = it.grade; local isMech = it.kind == "mech"
                add(it.id, 0, 0.15, 0, math.sin(T * 0.7) * 25 + T * 20, isMech and 1.05 or 2.1)
                if math.random() < 0.9 then burst(2, { math.random() * 4 - 2, 0.2, math.random() * 4 - 2 }, 3, GTINT[g], 1.6, true) end
                eye = { 0, 2.8, 10.5 }; tgt = { 0, 2.3, 0 }
            end
        end
        local keep = {}
        for _, p in ipairs(hp) do p.life = p.life - dt; p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt; local d = math.exp(-dt * 1.8); p.vx, p.vy, p.vz = p.vx * d, p.vy * d, p.vz * d
            if p.life > 0 then keep[#keep + 1] = p; if p.z <= 5 then add("fx_white", p.x, p.y, p.z, p.life * 300, p.size * 1.3 * math.max(0.2, p.life / p.max), p.tint, 45) end end end
        hp = keep
        return { env = SUM_ENV, eye = jsarr(3, eye[1], eye[2], eye[3]), target = jsarr(3, tgt[1], tgt[2], tgt[3]), fov = A:fitFov(fov, aspect), aspect = aspect, near = 0.1, far = 400, draws = draws, stars = hubStars(E, jsarr) }
    end
    for _, d in ipairs(DECOR) do add(d[1], d[2], d[3], d[4], d[5], d[6]) end
    local f = (Hub.tab == "pilots") and { pilot = Hub.pilotSel or s.pilot } or (Hub.tab == "hangar" and { mech = Hub.mechSel or s.mech } or { mech = s.mech, pilot = s.pilot })
    if Hub.tab == "hangar" or Hub.tab == "pilots" then
        Hub.yaw = (Hub.yaw or 0) + dt * 14
        add("sys_pedestal", 0, 0, 0, 0, 2.6)
        if f.mech then add(f.mech, 0, 0.24 + math.sin(t * 1.6) * 0.05, 0, Hub.yaw, 1.15) else add(f.pilot, 0, 0.25 + math.sin(t * 2) * 0.04, 0, Hub.yaw, 2.3) end
        fov = A:fitFov(38, aspect); local dist = 11
        -- 让主体出现在左列表与右详情之间的空白区域中央
        local l, r = 430 * V.s, V.w - 760 * V.s; local ndc = ((l + r) / 2) / V.w * 2 - 1; local sx = ndc * math.tan(fov * math.pi / 360) * (V.w / V.h) * dist
        eye, tgt = { sx, 3.1, dist }, { sx, 2.2, 0 }
    else
        local sway = math.sin(t * 0.5) * 18
        add("sys_pedestal", 0, 0, 0, 0, 2.4)
        if f.mech then add(f.mech, -0.6, 0.24 + math.sin(t * 1.6) * 0.05, 0, sway, 1.1) end
        if f.pilot then add(f.pilot, 2.7, 0, 1.4, -25 + math.sin(t * 0.9) * 6, 1.25) end
        eye, tgt, fov = { 3.2, 3.6, 11.5 }, { 0.2, 2.1, 0 }, A:fitFov(36, aspect)
    end
    return { env = ENV, eye = jsarr(3, eye[1], eye[2], eye[3]), target = jsarr(3, tgt[1], tgt[2], tgt[3]), fov = fov, aspect = aspect, near = 0.1, far = 400, draws = draws }
end

-- ---------------------------------------------------------------- 召唤动画：2D 叠加层（闪光 / 光线 / 翻牌 / 新角色展示）
local GCOLS = { S = { 87, 184, 255 }, SS = { 180, 124, 255 }, SSR = { 245, 165, 36 }, SSSR = { 255, 93, 122 } }
drawSummonAnim = function()
    local sa, W = Hub.sa, UI.lw; local gc = GCOLS[sa.grade]
    if sa.phase == "burst" or sa.phase == "cards" or sa.phase == "show" then
        local lit = sa.phase == "burst" and math.min(1, sa.t / 0.4) or 1
        nvgBeginPath(UI.vg); nvgRect(UI.vg, 0, 0, W, 1080); nvgFillColor(UI.vg, nvgRGBA(gc[1] // 4, gc[2] // 4, gc[3] // 4, math.floor(120 * lit))); nvgFill(UI.vg)
        for k = 0, 15 do                                                                  -- 旋转光线
            local a = k / 16 * math.pi * 2 + Hub.t * 0.3; nvgBeginPath(UI.vg); nvgMoveTo(UI.vg, W / 2, 470); nvgLineTo(UI.vg, W / 2 + math.cos(a - 0.05) * 1800, 470 + math.sin(a - 0.05) * 1800); nvgLineTo(UI.vg, W / 2 + math.cos(a + 0.05) * 1800, 470 + math.sin(a + 0.05) * 1800)
            nvgFillColor(UI.vg, nvgRGBA(gc[1], gc[2], gc[3], math.floor(26 * lit))); nvgFill(UI.vg) end
    end
    if sa.flash > 0 then nvgBeginPath(UI.vg); nvgRect(UI.vg, 0, 0, W, 1080); nvgFillColor(UI.vg, nvgRGBA(255, 255, 255, math.floor(255 * sa.flash / 0.6))); nvgFill(UI.vg) end
    if UI.Button(W - 220, 40, 180, 64, "跳过", { size = 28 }) then
        if sa.phase == "charge" or sa.phase == "fall" or sa.phase == "burst" then sa.phase = "cards"; sa.t = 0; sa.instant = true elseif sa.phase == "cards" then sa.instant = true else Hub.FinishSummon() end
    end
    if sa.phase == "cards" then
        local res = sa.res; local n = #res; local cw, ch = n > 1 and 250 or 420, n > 1 and 300 or 520; local cols = n > 5 and 5 or n; local rows = math.ceil(n / cols)
        for i, r in ipairs(res) do
            local x0 = W / 2 - (cols * (cw + 20) - 20) / 2 + ((i - 1) % cols) * (cw + 20); local y0 = 540 - (rows * (ch + 20) - 20) / 2 + ((i - 1) // cols) * (ch + 20) - 40
            local delay = sa.instant and 0 or (0.15 + (i - 1) * 0.16 + (top(r.grade) and 0.35 or 0)); local p = math.max(0, math.min(1, (sa.t - delay) / 0.4))
            if p >= 0.5 and not sa.flipped[i] then sa.flipped[i] = true; C:sfx(top(r.grade) and "win" or (r.grade == "SS" and "level" or "click")) end
            local gcol = GCOLS[r.grade]; local sw = math.abs(1 - 2 * p) * cw; local cx = x0 + cw / 2
            nvgBeginPath(UI.vg); nvgRect(UI.vg, cx - sw / 2, y0, sw, ch); nvgFillColor(UI.vg, p < 0.5 and nvgRGBA(20, 26, 60, 245) or nvgRGBA(14, 18, 44, 250)); nvgFill(UI.vg)
            nvgBeginPath(UI.vg); nvgRect(UI.vg, cx - sw / 2, y0, sw, ch); nvgStrokeColor(UI.vg, nvgRGBA(gcol[1], gcol[2], gcol[3], 255)); nvgStrokeWidth(UI.vg, top(r.grade) and 8 or 4); nvgStroke(UI.vg)
            if p < 0.5 then UI.Text(cx, y0 + ch / 2, "✦", 90, { 150, 160, 220 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, math.floor(255 * (1 - 2 * p)))
            elseif sw > cw * 0.5 then
                local it = r.kind == "mech" and C:mech(r.id) or C:char(r.id)
                UI.Text(cx, y0 + 16, r.grade, n > 1 and 40 or 64, gcol, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(cx, y0 + ch * 0.4, it.name, n > 1 and 38 or 60, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                UI.Text(cx, y0 + ch - 60, r.isNew and "新获得！" or ("碎片 +" .. (r.frag or 0)), n > 1 and 24 or 32, r.isNew and COL.teal or COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            end
        end
        if sa.t > (sa.instant and 0.1 or 1.2 + #res * 0.16) and UI.Button(W / 2 - 170, 940, 340, 80, (#sa.show > 0) and "查看新角色" or "完成", { size = 34, color = ORANGE }) then
            if #sa.show > 0 then sa.phase = "show"; sa.t = 0; sa.si = 1; hp = {}; C:sfx(top(sa.show[1].grade) and "win" or "level") else Hub.FinishSummon() end
        end
    elseif sa.phase == "show" then
        local r = sa.show[sa.si]; local it = r.kind == "mech" and C:mech(r.id) or C:char(r.id); local gcol = GCOLS[r.grade]
        UI.Text(W / 2 - 520, 220, r.grade, 150, gcol, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W / 2 + 480, 220, it.name, 84, COL.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        UI.Text(W / 2 + 480, 330, r.kind == "mech" and (it.type .. " 机甲") or it.role, 36, COL.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); UI.Text(W / 2 + 480, 390, "新获得！", 44, COL.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        UI.Wrap(W / 2 + 160, 470, 640, r.kind == "mech" and (it.active.name .. "：" .. it.active.desc) or (it.support.name .. "：" .. it.support.desc), 28, COL.bone)
        if UI.Button(W / 2 - 170, 940, 340, 80, (sa.si < #sa.show) and "下一个" or "完成", { size = 34, color = ORANGE }) then
            if sa.si < #sa.show then sa.si = sa.si + 1; sa.t = 0; hp = {}; C:sfx(top(sa.show[sa.si].grade) and "win" or "level") else Hub.FinishSummon() end
        end
    end
end
return Hub
