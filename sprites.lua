local Sprites = {}
local imgs = {}
local quads = {}

-- Color palette mapped by single character
local PALETA = {
    ["."] = nil,
    ["k"] = { 0.08, 0.07, 0.10, 1 },
    ["w"] = { 0.96, 0.95, 0.90, 1 },
    ["p"] = { 0.95, 0.78, 0.62, 1 },
    ["b"] = { 0.22, 0.45, 0.85, 1 },
    ["c"] = { 0.40, 0.88, 0.98, 1 },
    ["y"] = { 0.98, 0.84, 0.25, 1 },
    ["g"] = { 0.25, 0.82, 0.35, 1 },
    ["d"] = { 0.14, 0.52, 0.22, 1 },
    ["v"] = { 0.58, 0.24, 0.78, 1 },
    ["r"] = { 0.88, 0.22, 0.24, 1 },
    ["o"] = { 0.98, 0.52, 0.18, 1 },
    ["m"] = { 0.38, 0.12, 0.18, 1 },
    ["f"] = { 0.15, 0.16, 0.20, 1 },
    ["F"] = { 0.11, 0.12, 0.15, 1 },
    ["s"] = { 0.34, 0.36, 0.42, 1 },
    ["S"] = { 0.48, 0.50, 0.56, 1 },
    ["u"] = { 0.32, 0.22, 0.14, 1 },
    ["U"] = { 0.22, 0.14, 0.08, 1 },
    ["l"] = { 0.44, 0.32, 0.20, 1 },
}

-- Pixel-art sprite and tile grids
local RAW = {
  hero = {
    "....KKKKKKKK....",
    "...KRRRRRRRRK...",
    "...KSSSSSSSSK...",
    "...KSKSSSSKSK...", 
    "...KSSKSSKSSK...", 
    "...KSSSSSSSSK...",
    "....KSKKKKsK....", 
    "..KKSSssssSSKK..",
    ".KSSSSsSSsSSSSK.", 
    ".KSSsKSssSKsSSK.", 
    ".KSSsKSSSSKsSSK.", 
    ".KSSK.KssK.KSSK.", 
    "..KK.KBBBBK.KK..", 
    ".....KBKKBK.....",
    ".....Kb..bK.....",
    "....KKK..KKK...."  
},

    slime = {
        "..........",
        "...kkkk...",
        "..kggggk..",
        ".kggwgggk.",
        "kggwgggggk",
        "kggkggkggk",
        "kggggggggk",
        "kddddddddk",
        ".kkkkkkkk.",
        "..........",
    },
    bat = {
        "k........k",
        "kvk.kk.kvk",
        "kvvkvvkvvk",
        ".kvrvvrvk.",
        "..kvvvvk..",
        "...k..k...",
    },
    boss = {
        "....kkkkkkkk....",
        "..kkmmmmmmmmkk..",
        ".kmmrrrrrrrrrmk.",
        "kmmrrmmmmmmrrmmk",
        "kmrmmwwmmwwmmrmk",
        "kmrmmrrmmrrmmrmk",
        "kmmmmmmmmmmmmmmk",
        "kmmmkkmmmmkkmmmk",
        "kmmkwwkkkkwwkmmk",
        ".kmmkkkkkkkkmmk.",
        "..kmmmmmmmmmmk..",
        "...kmmk..kmmk...",
        "...kkk....kkk...",
    },
    orb = {
        "..kkkk..",
        ".kcccck.",
        "kcwwwwck",
        "kcwccwck",
        "kcccccck",
        ".kcccck.",
        "..kkkk..",
    },
    bullet = {
        ".kkk.",
        "kywyk",
        "kwwwk",
        "kywyk",
        ".kkk.",
    },
    bossBullet = {
        "..kkk..",
        ".krrrk.",
        "kroork.",
        "kroyork",
        "kroork.",
        ".krrrk.",
        "..kkk..",
    },
    floor = {
        "ffffffff",
        "fFffffFf",
        "ffffffff",
        "fffffFff",
        "FFffffff",
        "ffffffff",
        "fffFffff",
        "fffffffF",
    },
    wall = {
        "kkkkkkkk",
        "kSSSskSS",
        "ksssskss",
        "kkkkkkkk",
        "SSskSSSk",
        "sssksssk",
        "sssksssk",
        "kkkkkkkk",
    },
    mud = {
        "uuuuuuuu",
        "uUuuulUu",
        "uuuuuuuu",
        "uuuUuuuu",
        "ulUuuuUu",
        "uuuuuuuu",
        "uuUuuulu",
        "uuuuuuuu",
    },
}

-- Converts a text grid into a crisp pixel-art LOVE Image
local function buildImage(grid)
    local h = #grid
    local w = #grid[1]
    local data = love.image.newImageData(w, h)
    for y = 1, h do
        local row = grid[y]
        for x = 1, w do
            local ch = row:sub(x, x)
            local color = PALETA[ch]
            if color then
                data:setPixel(x - 1, y - 1, color[1], color[2], color[3], color[4])
            else
                data:setPixel(x - 1, y - 1, 0, 0, 0, 0)
            end
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    img:setWrap("repeat", "repeat")
    return img
end

-- Generates all images and quads on game startup
function Sprites.load()
    for name, grid in pairs(RAW) do
        local img = buildImage(grid)
        imgs[name] = img
        local w, h = img:getDimensions()
        quads[name] = love.graphics.newQuad(0, 0, w, h, w, h)
    end
end

-- Draws a sprite centered at (x, y) with optional damage flash
function Sprites.draw(name, x, y, scale, flash)
    local img = imgs[name]
    if not img then return end
    local s = scale or 2
    local w, h = img:getDimensions()

    if flash then
        love.graphics.setColor(1, 0.35, 0.35, 0.85)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end

    love.graphics.draw(img, math.floor(x), math.floor(y), 0, s, s, w / 2, h / 2)
end

-- Draws a repeating pixel-art tile filling any (x, y, w, h) rectangle
function Sprites.drawTiled(name, x, y, w, h, scale)
    local img = imgs[name]
    local q = quads[name]
    if not img or not q then return end

    local s = scale or 3
    q:setViewport(0, 0, w / s, h / s)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, q, math.floor(x), math.floor(y), 0, s, s)
end

return Sprites