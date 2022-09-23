--
-- Example program: Render sprites with 3D-looking shadows from a light source.
--
local LG = love.graphics

local images = {
	sprites = LG.newImage("gfx/sprites.png"),
	light   = LG.newImage("gfx/light.png"),
}
images.sprites:setFilter("nearest")

local quads = {
	player = LG.newQuad(00,00, 32,32, images.sprites),
	tree   = LG.newQuad(32,00, 32,32, images.sprites),
	sign   = LG.newQuad(00,32, 32,32, images.sprites),
}

local RENDER_SCALE  = 2
local WORLD_SCALE_X = 1.5



local entities = {}

local function addNewEntity(entityType, quad, x,y, flip)
	local entity = {type=entityType, id=#entities, quad=quad, x=x,y=y, flip=flip}
	table.insert(entities, entity)
	return entity
end

local player = addNewEntity("player", quads.player, 200,150, false)

local rand = love.math.random
for i = 1, 30 do  addNewEntity("tree", quads.tree, rand(400),rand(300), rand(2)==1)  end
for i = 1, 4  do  addNewEntity("sign", quads.sign, rand(400),rand(300), rand(2)==1)  end

local lightSource = addNewEntity("light", nil, 0,0, false)



function love.update(dt)
	local moveX = 0
	local moveY = 0

	if love.keyboard.isDown"left"  then  moveX = moveX - 1  end
	if love.keyboard.isDown"right" then  moveX = moveX + 1  end
	if love.keyboard.isDown"up"    then  moveY = moveY - 1  end
	if love.keyboard.isDown"down"  then  moveY = moveY + 1  end

	player.x = player.x + WORLD_SCALE_X*50*moveX*dt
	player.y = player.y +               50*moveY*dt
	if moveX ~= 0 then  player.flip = (moveX < 0)  end

	lightSource.x = love.mouse.getX() / RENDER_SCALE
	lightSource.y = love.mouse.getY() / RENDER_SCALE
end



local vertexFormat = {
	{"VertexPosition", "float", 3}, -- x,y,z
	{"VertexTexCoord", "float", 2}, -- u,v
}
local vertices = {
	{0,0,0, 0,0},
	{0,0,0, 0,0},
	{0,0,0, 0,0},
	{0,0,0, 0,0},
}
local mesh = LG.newMesh(vertexFormat, vertices, "fan", "stream")

local quadShader = LG.newShader[[//GLSL
	// This shader draws a quad with perspective correct texture.
	// (See https://en.wikipedia.org/wiki/Texture_mapping#Perspective_correctness)

	varying float z;

	#ifdef VERTEX
		vec4 position(mat4 proj, vec4 vertPos) {
			z = vertPos.z;
			return proj * vertPos;
		}
	#endif

	#ifdef PIXEL
		uniform vec4 quad; // {x,y,w,h}

		vec4 effect(vec4 loveColor, Image tex, vec2 texUv, vec2 screenPos) {
			texUv       = quad.xy + quad.zw * texUv/z;
			vec4 sample = Texel(tex, texUv);

			// DEBUG
			if (1==0) {
				if (mod(floor(texUv.x*64)+floor(texUv.y*64), 2) == 0) return vec4(1,0,0,1); // Show pixel grid (64x64 image).
				if (sample.a == 0)                                    return vec4(1,1,1,1); // Show transparent pixels.
				return sample;
			}

			return sample * loveColor;
		}
	#endif
]]

local function drawQuad(image, x1,y1,x2,y2,x3,y3,x4,y4, u,v,uvW,uvH)
	local len12 = math.sqrt((x2-x1)^2 + (y2-y1)^2)
	local len23 = math.sqrt((x3-x2)^2 + (y3-y2)^2)
	local len34 = math.sqrt((x4-x3)^2 + (y4-y3)^2)
	local len41 = math.sqrt((x1-x4)^2 + (y1-y4)^2)

	-- Calculate fake z-values to fix the perspective.
	-- (What we do here is enough for our purposes. This will only work for quads with certain shapes.)
	local z1 = 1
	local z2 = 1
	local z3 = len12/len34
	local z4 = len12/len34

	local vert = vertices[1] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x1,y1,1/z1, 0,0
	local vert = vertices[2] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x2,y2,1/z2, 1/z2,0
	local vert = vertices[3] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x3,y3,1/z3, 1/z3,1/z3
	local vert = vertices[4] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x4,y4,1/z4, 0,1/z4

	mesh:setTexture(image)
	mesh:setVertices(vertices)
	pcall(quadShader.send, quadShader, "quad", {u,v,uvW,uvH})

	LG.setShader(quadShader)
	LG.draw(mesh)
	LG.setShader(nil)

	--[[ DEBUG: Show z-values.
	local r,g,b,a = LG.getColor()
	LG.setColor(1, 1, 1)
	LG.print(string.format("%.4f",z1), x1,y1, 0, .5)
	LG.print(string.format("%.4f",z2), x2,y2, 0, .5)
	LG.print(string.format("%.4f",z3), x3,y3, 0, .5)
	LG.print(string.format("%.4f",z4), x4,y4, 0, .5)
	LG.setColor(r,g,b,a)
	--]]
end



local function clamp(v, min, max)
	return math.max(math.min(v, max), min)
end

function love.draw()
	table.sort(entities, function(a, b)
		if a.y ~= b.y then  return a.y < b.y  end
		return a.id < b.id
	end)
	LG.scale(RENDER_SCALE)

	-- Ground.
	LG.clear(0, 0, 0)

	-- Light (on ground).
	local w,h = images.light:getDimensions()
	LG.setColor(.3, .6, .3) ; LG.draw(images.light, lightSource.x,lightSource.y, 0, WORLD_SCALE_X*15,15, w/2,h/2)
	LG.setColor(1, 1, 1)    ; LG.draw(images.light, lightSource.x,lightSource.y, 0, WORLD_SCALE_X*1,1,   w/2,h/2)

	-- Entity shadows.
	for _, e in ipairs(entities) do
		if e.type == "light" then
			-- void

		else
			local scaleX       = e.flip and -1 or 1
			local iw,ih        = images.sprites:getDimensions()
			local qx,qy, qw,qh = e.quad:getViewport()
			local w,h          = qw,qh

			local dxL = lightSource.x - (e.x-w/2) -- left edge of entity
			local dxR = lightSource.x - (e.x+w/2) -- right edge of entity
			local dy  = lightSource.y - e.y

			local SCALE = .7 -- How long the shadows should be.
			dxL = dxL * SCALE
			dxR = dxR * SCALE
			dy  = dy  * SCALE

			local x1, y1 = e.x-w/2-dxL, e.y-dy -- top left
			local x2, y2 = e.x+w/2-dxR, e.y-dy -- top right
			local x3, y3 = e.x+w/2    , e.y    -- bottom right
			local x4, y4 = e.x-w/2    , e.y    -- bottom left

			local u1, v1 = (qx   )/iw, (qy   )/ih -- top left
			local u2, v2 = (qx+qw)/iw, (qy   )/ih -- top right
			local u3, v3 = (qx+qw)/iw, (qy+qh)/ih -- bottom right
			local u4, v4 = (qx   )/iw, (qy+qh)/ih -- bottom left

			if e.flip then
				u1,u2 = u2,u1
				u4,u3 = u3,u4
			end

			LG.setColor(0, 0, 0)
			drawQuad(images.sprites, x1,y1,x2,y2,x3,y3,x4,y4, u1,v1,u2-u1,v4-v1)
		end
	end

	-- Entities.
	for _, e in ipairs(entities) do
		if e.type == "light" then
			LG.setColor(1, 1, 1)
			LG.circle("fill", e.x,e.y-40, 5)

			for i = 1, 6 do
				local lineX = 10 * math.cos(i/6 * math.pi)
				local lineY = 10 * math.sin(i/6 * math.pi)
				LG.line(e.x+lineX,e.y-40+lineY, e.x-lineX,e.y-40-lineY)
			end

		else
			local dx       = lightSource.x - e.x
			local dy       = lightSource.y - e.y
			local distance = math.sqrt((dx/WORLD_SCALE_X)^2 + (dy)^2)

			local LIGHT_REACH       = 400
			local TRANSITION_LENGTH = 20

			local lightDistance = clamp(1 - distance / LIGHT_REACH      , 0, 1) -- Darker if farther away.
			local lightFacing   = clamp(1 + dy       / TRANSITION_LENGTH, 0, 1) -- Darker if facing away.
			local light         = lightDistance * lightFacing

			local scaleX   = e.flip and -1 or 1
			local _,_, w,h = e.quad:getViewport()

			LG.setColor(light, light, light)
			LG.draw(images.sprites, e.quad, e.x,e.y, 0, scaleX,1, w/2,h, 0,0)
		end
	end

	-- Info.
	LG.origin()
	LG.setColor(1, 1, 1)
	LG.print("Arrow keys = move player\nMouse = move light", 3,1)
end



function love.keypressed(key)
	if key == "escape" then
		love.event.quit()
	end
end


