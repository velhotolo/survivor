local Sprites = require("sprites")

-- =========================================================================
-- GENERAL CONFIGURATION
-- =========================================================================

local WIDTH, HEIGHT = 1280, 720
local CHANGE_ENEMY_TIME = 30
local TIME_WEAPON2 = 15
local TIME_BOSS = 60

-- =========================================================================
-- GAME STATE
-- =========================================================================

local hero, enemies, projectiles, bulletsBoss
local walls, mud, boss
local time, timerSpawn, kills
local bossShow, state

-- =========================================================================
-- HELPERS
-- =========================================================================

-- Pythagorean theorem to find the straight distance between two points
local function distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

-- Axis-aligned bounding box (AABB) collision check against walls
local function hitWalls(x, y, r)
    for _, p in ipairs(walls) do
        if x + r > p.x and x - r < p.x + p.w and
           y + r > p.y and y - r < p.y + p.h then
            return true
        end
    end
    return false
end

-- Checks if a coordinate is inside the mud area
local function onTheMud(x, y)
    return x > mud.x and x < mud.x + mud.w and
           y > mud.y and y < mud.y + mud.h
end

-- Moves an entity while sliding along walls and clamping inside the screen
local function moveWithCollision(e, dx, dy)
    if not hitWalls(e.x + dx, e.y, e.r) then e.x = e.x + dx end
    if not hitWalls(e.x, e.y + dy, e.r) then e.y = e.y + dy end
    e.x = math.max(e.r, math.min(WIDTH - e.r, e.x))
    e.y = math.max(e.r, math.min(HEIGHT - e.r, e.y))
end

-- Applies damage to the hero and triggers 1 second of invulnerability
local function hurtHero()
    if hero.invul <= 0 then
        hero.life = hero.life - 1
        hero.invul = 1
    end
end

-- Builds a unified list of all valid targets (common enemies + boss)
local function allTargets()
    local list = {}
    for _, e in ipairs(enemies) do table.insert(list, e) end
    if boss then table.insert(list, boss) end
    return list
end

-- Auto-aim system: returns the closest target to the hero
local function closestTarget()
    local target, minorDist = nil, math.huge
    for _, e in ipairs(allTargets()) do
        local d = distance(hero.x, hero.y, e.x, e.y)
        if d < minorDist then target, minorDist = e, d end
    end
    return target
end

-- Calculates the (x, y) position of each orbiting orb from the second weapon
local function orbPos(i)
    local orb = hero.weapons.orb
    local a = orb.angle + (i - 1) * (2 * math.pi / orb.qty)
    return hero.x + math.cos(a) * orb.radius, hero.y + math.sin(a) * orb.radius
end

-- =========================================================================
-- START, RESTART AND SPAWNING
-- =========================================================================

-- Resets all game variables to start or restart a run
local function startGame()
    hero = {
        x = WIDTH / 2, y = HEIGHT / 2, r = 14, spd = 180, life = 10, invul = 0,
        weapons = {
            wand = { recharge = 0.5, timer = 0, damage = 1, shootSpd = 400 },
            orb  = { qty = 2, angle = 0, radius = 60, rotSpd = 3, size = 10, damage = 1 },
        },
    }
    enemies, projectiles, bulletsBoss = {}, {}, {}
    walls = {
    { x = 320, y = 260, w = 192, h = 32 }, 
    { x = 544, y = 160, w = 32,  h = 160 }, 
    { x = 768, y = 420, w = 192, h = 32 }, 
    { x = 992, y = 320, w = 32,  h = 160 }, 
}
mud = { x = 80, y = 260, w = 180, h = 140 }
    boss = nil
    time, timerSpawn, kills = 0, 1, 0
    bossShow = false
    state = "playing"
end

-- Spawns an enemy on one of the 4 screen edges (slimes early, bats later)
local function createEnemy()
    local side = love.math.random(4)
    local x, y
    if side == 1 then
        x, y = love.math.random(WIDTH), 15
    elseif side == 2 then
        x, y = love.math.random(WIDTH), HEIGHT - 15
    elseif side == 3 then
        x, y = 15, love.math.random(HEIGHT)
    else
        x, y = WIDTH - 15, love.math.random(HEIGHT)
    end

    local e = { x = x, y = y, invul = 0 }
    if time < CHANGE_ENEMY_TIME then
        e.type, e.r, e.spd, e.life, e.fly = "slime", 12, 60, 3, false
    else
        e.type, e.r, e.spd, e.life, e.fly = "bat", 9, 115, 2, true
    end
    table.insert(enemies, e)
end

-- Handles enemy spawn rate and summons the boss when TIME_BOSS is reached
local function updateSpawn(dt)
    if time >= TIME_BOSS and not bossShow then
        boss = {
            x = WIDTH / 2, y = 60, r = 40, spd = 45,
            life = 60, maxLife = 60, invul = 0, timerShoot = 2
        }
        bossShow = true
    end
    if bossShow then return end

    timerSpawn = timerSpawn - dt
    if timerSpawn <= 0 then
        createEnemy()
        timerSpawn = 0.4
    end
end

-- =========================================================================
-- ENTITIES AND WEAPONS UPDATE
-- =========================================================================

-- Reads keyboard input, normalizes diagonal speed (0.7071), and slows down on mud
local function updateHero(dt)
    local dx, dy = 0, 0
    if love.keyboard.isDown("left", "a") then dx = dx - 1 end
    if love.keyboard.isDown("right", "d") then dx = dx + 1 end
    if love.keyboard.isDown("up", "w") then dy = dy - 1 end
    if love.keyboard.isDown("down", "s") then dy = dy + 1 end
    if dx ~= 0 and dy ~= 0 then dx, dy = dx * 0.7071, dy * 0.7071 end

    local spd = hero.spd
    if onTheMud(hero.x, hero.y) then spd = spd * 0.4 end
    moveWithCollision(hero, dx * spd * dt, dy * spd * dt)
    if hero.invul > 0 then hero.invul = hero.invul - dt end
end

-- Moves enemies toward the hero (flying enemies ignore walls and mud)
local function updateEnemies(dt)
    for _, e in ipairs(enemies) do
        local d = distance(e.x, e.y, hero.x, hero.y)
        if d > 0 then
            local mx = (hero.x - e.x) / d * e.spd * dt
            local my = (hero.y - e.y) / d * e.spd * dt
            if e.fly then
                e.x, e.y = e.x + mx, e.y + my
            else
                if onTheMud(e.x, e.y) then mx, my = mx * 0.4, my * 0.4 end
                moveWithCollision(e, mx, my)
            end
        end
        if e.invul > 0 then e.invul = e.invul - dt end
        if d < e.r + hero.r then hurtHero() end
    end
end

-- Auto-fires the wand and spins the orbs after TIME_WEAPON2
local function updateWeapons(dt)
    local wand = hero.weapons.wand
    wand.timer = wand.timer - dt
    if wand.timer <= 0 then
        local target = closestTarget()
        if target then
            local d = math.max(distance(hero.x, hero.y, target.x, target.y), 1)
            table.insert(projectiles, {
                x = hero.x, y = hero.y, r = 4, dmg = wand.damage,
                vx = (target.x - hero.x) / d * wand.shootSpd,
                vy = (target.y - hero.y) / d * wand.shootSpd,
            })
            wand.timer = wand.recharge
        end
    end

    if time < TIME_WEAPON2 then return end

    local orb = hero.weapons.orb
    orb.angle = orb.angle + orb.rotSpd * dt
    for i = 1, orb.qty do
        local ox, oy = orbPos(i)
        for _, e in ipairs(allTargets()) do
            if e.invul <= 0 and distance(ox, oy, e.x, e.y) < orb.size + e.r then
                e.life = e.life - orb.damage
                e.invul = 0.5
            end
        end
    end
end

-- Moves wand projectiles and removes them on hit, wall collision, or leaving the screen
local function updateProjectiles(dt)
    for i = #projectiles, 1, -1 do
        local p = projectiles[i]
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt

        local hit = false
        for _, e in ipairs(allTargets()) do
            if not hit and e.life > 0 and
               distance(p.x, p.y, e.x, e.y) < p.r + e.r then
                e.life = e.life - p.dmg
                hit = true
            end
        end

        local out = p.x < 0 or p.x > WIDTH or p.y < 0 or p.y > HEIGHT
        if hit or out or hitWalls(p.x, p.y, p.r) then
            table.remove(projectiles, i)
        end
    end
end

-- Moves the boss, fires radial bullet rings, and triggers victory on death
local function updateBoss(dt)
    local d = distance(boss.x, boss.y, hero.x, hero.y)
    if d > 0 then
        moveWithCollision(
            boss,
            (hero.x - boss.x) / d * boss.spd * dt,
            (hero.y - boss.y) / d * boss.spd * dt
        )
    end
    if d < boss.r + hero.r then hurtHero() end
    if boss.invul > 0 then boss.invul = boss.invul - dt end

    boss.timerShoot = boss.timerShoot - dt
    if boss.timerShoot <= 0 then
        for i = 1, 12 do
            local a = (i / 12) * 2 * math.pi
            table.insert(bulletsBoss, {
                x = boss.x, y = boss.y, r = 6,
                vx = math.cos(a) * 150,
                vy = math.sin(a) * 150,
            })
        end
        boss.timerShoot = 2
    end

    if boss.life <= 0 then
        boss = nil
        state = "victory"
    end
end

-- Moves boss bullets and removes them on hero hit, wall collision, or leaving the screen
local function updateBossBullets(dt)
    for i = #bulletsBoss, 1, -1 do
        local b = bulletsBoss[i]
        b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt

        local hit = distance(b.x, b.y, hero.x, hero.y) < b.r + hero.r
        if hit then hurtHero() end

        local out = b.x < 0 or b.x > WIDTH or b.y < 0 or b.y > HEIGHT
        if hit or out or hitWalls(b.x, b.y, b.r) then
            table.remove(bulletsBoss, i)
        end
    end
end

-- Removes dead enemies and increments the kill counter
local function clearDead()
    for i = #enemies, 1, -1 do
        if enemies[i].life <= 0 then
            table.remove(enemies, i)
            kills = kills + 1
        end
    end
end

-- =========================================================================
-- WIZARDRY-STYLE HUD
-- =========================================================================

-- Draws a classic double-bordered RPG panel
local function drawWizardryBox(x, y, w, h)
    love.graphics.setColor(0.04, 0.04, 0.06, 0.92)
    love.graphics.rectangle("fill", x, y, w, h)

    love.graphics.setColor(0.75, 0.72, 0.62) -- Outer aged-bone border
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)

    love.graphics.setColor(0.35, 0.33, 0.28) -- Inner subtle border
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 3, y + 3, w - 6, h - 6)
end

-- Draws the compact retro dungeon-crawler HUD
local function drawHUD()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local hudH = 40
    drawWizardryBox(6, 6, sw - 12, hudH)

    -- Hero portrait frame
    drawWizardryBox(12, 10, 32, 32)
    love.graphics.setColor(1, 1, 1)
    Sprites.draw("hero", 28, 26, 1.4, hero.invul > 0)

    -- HP label and segmented retro bar
    local maxHP = 10
    love.graphics.setColor(0.85, 0.80, 0.65)
    love.graphics.print(string.format("HP %02d/%02d", math.max(0, hero.life), maxHP), 52, 11)

    for i = 1, maxHP do
        local bx = 52 + (i - 1) * 10
        local by = 28
        if i <= hero.life then
            if hero.life <= 3 then
                love.graphics.setColor(0.85, 0.18, 0.18)
            else
                love.graphics.setColor(0.22, 0.72, 0.30)
            end
        else
            love.graphics.setColor(0.18, 0.16, 0.16)
        end
        love.graphics.rectangle("fill", bx, by, 8, 9)
        love.graphics.setColor(0.05, 0.05, 0.05)
        love.graphics.rectangle("line", bx, by, 8, 9)
    end

    -- Vertical divider 1
    love.graphics.setColor(0.35, 0.33, 0.28)
    love.graphics.line(160, 12, 160, 40)

    -- Arsenal status
    love.graphics.setColor(0.85, 0.80, 0.65)
    love.graphics.print("WAND: ON", 168, 11)
    if time >= TIME_WEAPON2 then
        love.graphics.setColor(0.45, 0.80, 1.0)
        love.graphics.print("ORBS: ON", 168, 26)
    else
        love.graphics.setColor(0.55, 0.52, 0.48)
        love.graphics.print(string.format("ORBS: %02ds", math.ceil(TIME_WEAPON2 - time)), 168, 26)
    end

    -- Vertical divider 2
    love.graphics.setColor(0.35, 0.33, 0.28)
    love.graphics.line(252, 12, 252, 40)

    -- Kills and timer
    local mins = math.floor(time / 60)
    local secs = math.floor(time % 60)
    love.graphics.setColor(0.85, 0.80, 0.65)
    love.graphics.print(string.format("KILLS: %03d", kills), 260, 11)
    love.graphics.print(string.format("TIME: %02d:%02d", mins, secs), 260, 26)

    -- Vertical divider 3
    love.graphics.setColor(0.35, 0.33, 0.28)
    love.graphics.line(355, 12, 355, 40)

    -- Boss countdown
    if boss then
        love.graphics.setColor(0.95, 0.25, 0.25)
        love.graphics.print("BOSS: LIVE!", 363, 19)
    else
        local toBoss = math.max(0, math.ceil(TIME_BOSS - time))
        love.graphics.setColor(0.80, 0.55, 0.30)
        love.graphics.print(string.format("BOSS: %02ds", toBoss), 363, 19)
    end

    -- Bottom Boss HP bar (only appears when boss spawns)
    if boss then
        local bw = math.min(340, sw - 40)
        local bx = (sw - bw) / 2
        drawWizardryBox(bx, sh - 36, bw, 28)
        local ratio = math.max(0, boss.life / boss.maxLife)
        love.graphics.setColor(0.65, 0.10, 0.12)
        love.graphics.rectangle("fill", bx + 6, sh - 30, (bw - 12) * ratio, 16)
        love.graphics.setColor(1, 0.95, 0.85)
        love.graphics.printf(string.format("OVERLORD %d/%d", math.max(0, boss.life), boss.maxLife), bx, sh - 28, bw, "center")
    end

    -- Victory / Defeat overlay
    if state ~= "playing" then
        local bw, bh = 300, 90
        local bx, by = (sw - bw) / 2, (sh - bh) / 2
        drawWizardryBox(bx, by, bw, bh)
        if state == "victory" then
            love.graphics.setColor(0.35, 0.90, 0.45)
            love.graphics.printf("VICTORY! OVERLORD SLAIN", bx, by + 22, bw, "center")
        else
            love.graphics.setColor(0.95, 0.25, 0.25)
            love.graphics.printf("DEFEAT! YOU PERISHED", bx, by + 22, bw, "center")
        end
        love.graphics.setColor(0.85, 0.80, 0.65)
        love.graphics.printf("Press R to restart", bx, by + 52, bw, "center")
    end

    love.graphics.setColor(1, 1, 1)
end

-- =========================================================================
-- LOVE2D CALLBACKS (TEST LOOP, SPRITES CREATED IN THE CODEPIXELCREATOR)
-- =========================================================================

-- Initializes sprites and starts the first run
function love.load()
    love.window.setMode(WIDTH, HEIGHT)
    Sprites.load()
    startGame()
end

-- Updates game timer, entities, boss, and win/loss conditions
function love.update(dt)
    if state ~= "playing" then return end

    time = time + dt
    updateSpawn(dt)
    updateHero(dt)
    updateEnemies(dt)
    updateWeapons(dt)
    updateProjectiles(dt)
    if boss then updateBoss(dt) end
    updateBossBullets(dt)
    clearDead()

    if hero.life <= 0 then state = "defeat" end
end

-- Draws the arena, sprites, projectiles, and Wizardry-style HUD
function love.draw()
    love.graphics.clear(0.09, 0.10, 0.13)

    -- Dungeon floor background
    Sprites.drawTiled("floor", 0, 0, WIDTH, HEIGHT, 3)

    -- Mud area with dark border
    Sprites.drawTiled("mud", mud.x, mud.y, mud.w, mud.h, 3)
    love.graphics.setColor(0.14, 0.09, 0.05)
    love.graphics.rectangle("line", mud.x, mud.y, mud.w, mud.h)

    -- Brick walls
    love.graphics.setColor(1, 1, 1)
    for _, wall in ipairs(walls) do
        for wx = wall.x, wall.x + wall.w - 32, 32 do
            for wy = wall.y, wall.y + wall.h - 32, 32 do
                Sprites.draw("wall", wx + 16, wy + 16, 4)
            end
        end
    end

    -- Hero (flashes when invulnerable)
    local flash = hero.invul > 0 and (math.floor(hero.invul * 15) % 2 == 0)
    Sprites.draw("hero", hero.x, hero.y, 2.5, flash)

    -- Orbiting orbs after TIME_WEAPON2
    if time >= TIME_WEAPON2 then
        for i = 1, hero.weapons.orb.qty do
            local ox, oy = orbPos(i)
            Sprites.draw("orb", ox, oy, 2.5)
        end
    end

    -- Enemies
    for _, e in ipairs(enemies) do
        local scale = (e.type == "slime") and 2.8 or 2.4
        Sprites.draw(e.type, e.x, e.y, scale, e.invul > 0)
    end

    -- Boss
    if boss then
        Sprites.draw("boss", boss.x, boss.y, 5.5, boss.invul > 0)
    end

    -- Hero projectiles
    for _, p in ipairs(projectiles) do
        Sprites.draw("bullet", p.x, p.y, 2)
    end

    -- Boss projectiles
    for _, b in ipairs(bulletsBoss) do
        love.graphics.setColor(0.95, 0.25, 0.25)
        love.graphics.circle("fill", b.x, b.y, b.r)
    end
    love.graphics.setColor(1, 1, 1)

    -- Wizardry-style HUD
    drawHUD()
end

-- Handles global shortcuts (quit and restart)
function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "r" and state ~= "playing" then startGame() end
end