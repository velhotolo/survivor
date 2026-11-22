local Sprites = require("sprites")

-- =========================================================================
-- GENERAL CONFIGURATION
-- =========================================================================

local WIDTH, HEIGHT = 800, 600
local CHANGE_ENEMY_TIME = 40
local TIME_WEAPON2 = 20
local TIME_BOSS = 80

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
        x = 400, y = 300, r = 14, spd = 180, life = 10, invul = 0,
        weapons = {
            wand = { recharge = 0.5, timer = 0, damage = 1, shootSpd = 400 },
            orb  = { qty = 2, angle = 0, radius = 60, rotSpd = 3, size = 10, damage = 1 },
        },
    }
    enemies, projectiles, bulletsBoss = {}, {}, {}
    walls = {
        { x = 150, y = 150, w = 120, h = 30 },
        { x = 530, y = 150, w = 120, h = 30 },
        { x = 150, y = 420, w = 120, h = 30 },
        { x = 530, y = 420, w = 120, h = 30 },
    }
    mud = { x = 40, y = 240, w = 140, h = 120 }
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
        timerSpawn = 0.8
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

-- =========================================================================
-- LOVE2D CALLBACKS (TEST LOOP, SPRITES CREATED IN THE CODEPIXELCREATOR)
-- =========================================================================

-- Initializes sprites and starts the first run
function love.load()
    love.window.setMode(WIDTH, HEIGHT)
    Sprites.load()
    startGame()
end

-- Updates game timer, entities, and removes dead enemies
function love.update(dt)
    if state ~= "playing" then return end

    time = time + dt
    updateSpawn(dt)
    updateHero(dt)
    updateEnemies(dt)
    updateWeapons(dt)
    updateProjectiles(dt)

    -- Remove enemies with 0 or less life
    for i = #enemies, 1, -1 do
        if enemies[i].life <= 0 then
            table.remove(enemies, i)
            kills = kills + 1
        end
    end
end

-- Draws the arena, sprites, and basic test HUD
function love.draw()
    love.graphics.clear(0.09, 0.10, 0.13)

   -- Dungeon floor background
Sprites.drawTiled("floor", 0, 0, WIDTH, HEIGHT, 3)

-- Mud area with dark border
Sprites.drawTiled("mud", mud.x, mud.y, mud.w, mud.h, 3)
love.graphics.setColor(0.14, 0.09, 0.05)
love.graphics.rectangle("line", mud.x, mud.y, mud.w, mud.h)

-- Brick walls
for _, p in ipairs(walls) do
    Sprites.drawTiled("wall", p.x, p.y, p.w, p.h, 3)
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

    -- Projectiles
    for _, p in ipairs(projectiles) do
        Sprites.draw("bullet", p.x, p.y, 2)
    end

    -- Simple test HUD
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(string.format("HP: %d  |  Kills: %d  |  Time: %.1fs", hero.life, kills, time), 12, 12)
end