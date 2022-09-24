--
-- Example program: Render sprites with 3D-looking shadows from a light source.
-- by Marcus 'ReFreezed' Thunström
-- License: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
--
local LG  = love.graphics
local TAU = 2*math.pi

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

local RENDER_SCALE     = 2
local WORLD_SCALE_Y    = .7
local MOVE_SPEED       = 65
local LIGHT_MOVE_SPEED = 3



local worldWidth  = LG.getWidth () / RENDER_SCALE
local worldHeight = LG.getHeight() / RENDER_SCALE
local entities    = {}

local function addNewEntity(entityType, quad, x,y, flip)
	local entity = {type=entityType, id=#entities, quad=quad, x=x,y=y, flip=flip}
	table.insert(entities, entity)
	return entity
end

local player = addNewEntity("player", quads.player, .5*worldWidth,.5*worldHeight, false)

local rand = love.math.random
for i = 1, 30 do  addNewEntity("tree", quads.tree, rand(worldWidth),rand(worldHeight), rand(2)==1)  end
for i = 1, 4  do  addNewEntity("sign", quads.sign, rand(worldWidth),rand(worldHeight), rand(2)==1)  end

local lightSource = addNewEntity("light", nil, 0,0, false)
lightSource.z     = 50



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
local quadMesh = LG.newMesh(vertexFormat, vertices, "fan", "stream")

local quadShader = LG.newShader[[//GLSL
	// This shader draws a quad with perspective correct texture.
	// (See https://en.wikipedia.org/wiki/Texture_mapping#Perspective_correctness)

	varying float z;

	#ifdef VERTEX
		vec4 position(mat4 proj, vec4 vertPos) {
			z         = vertPos.z;
			vertPos.z = 0.0; // The Z is for the texture, not the vertex.
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
				if (mod(floor(texUv.x*64.0)+floor(texUv.y*64.0), 2.0) == 0.0)  return vec4(1.0, 0.0, 0.0, 1.0); // Show pixel grid (64x64 image).
				if (sample.a == 0.0)        sample     = vec4(1.0); // Show transparent pixels.
				if (texUv.x-texUv.y < 0.0)  sample.rgb = mix(sample.rgb, vec3(0.0, 1.0, 0.0), 0.3); // Differentiate triangles.
				return sample;
			}

			return sample * loveColor;
		}
	#endif
]]



function love.update(dt)
	local moveX = 0
	local moveY = 0

	if love.keyboard.isDown"left"  then  moveX = moveX - 1  end
	if love.keyboard.isDown"right" then  moveX = moveX + 1  end
	if love.keyboard.isDown"up"    then  moveY = moveY - 1  end
	if love.keyboard.isDown"down"  then  moveY = moveY + 1  end

	player.x = player.x + MOVE_SPEED*moveX*dt
	player.y = player.y + MOVE_SPEED*moveY*dt*WORLD_SCALE_Y
	if moveX ~= 0 then  player.flip = (moveX < 0)  end

	lightSource.x = love.window.hasMouseFocus() and love.mouse.getX()/RENDER_SCALE or player.x
	lightSource.y = love.window.hasMouseFocus() and love.mouse.getY()/RENDER_SCALE or player.y

	if love.keyboard.isDown"pageup"   then  lightSource.z = math.max(lightSource.z*(1*LIGHT_MOVE_SPEED)^dt, 32)  end
	if love.keyboard.isDown"pagedown" then  lightSource.z = math.max(lightSource.z*(1/LIGHT_MOVE_SPEED)^dt, 32)  end
end



-- point = intersectLines( lineA, lineB )
local function intersectLines(ax1,ay1, ax2,ay2,  bx1,by1, bx2,by2)
	local dx1 = ax2 - ax1
	local dy1 = ay2 - ay1
	local dx2 = bx2 - bx1
	local dy2 = by2 - by1

	local det = dx1*dy2 - dx2*dy1
	if det == 0 then  return nil  end -- Parallel lines.

	local t = (dx2*(ay1-by1) - dy2*(ax1-bx1)) / det
	return ax1+t*dx1, ay1+t*dy1
end

-- z = calculateZ( point1, point2, vanishingPoint )
local function calculateZ(x1,y1, x2,y2, vapoX,vapoY)
	local dx1    = x1 - vapoX
	local dy1    = y1 - vapoY
	local dx2    = x2 - vapoX
	local dy2    = y2 - vapoY
	local len2Sq = dx2*dx2 + dy2*dy2
	return math.sqrt((dx1*dx1 + dy1*dy1) * len2Sq) / len2Sq -- Thanks, quickmath.com!
	-- return math.sqrt(dx1*dx1+dy1*dy1) / math.sqrt(dx2*dx2+dy2*dy2)
end

local vec4 = {0,0,0,0}

local function sendVec4(shader, var, x,y,z,w)
	vec4[1],vec4[2],vec4[3],vec4[4] = x,y,z,w
	pcall(shader.send, shader, var, vec4)
end

local function drawPerspectiveCorrectQuad(image, x1,y1,x2,y2,x3,y3,x4,y4, u,v,uvW,uvH)
	-- Calculate fake z-values to fix the perspective.
	local z1 = 1
	local z2 = 1
	local z3 = 1
	local z4 = 1

	local vapo23And41X,vapo23And41Y = intersectLines(x2,y2,x3,y3, x4,y4,x1,y1)
	local vapo12And34X,vapo12And34Y = intersectLines(x1,y1,x2,y2, x3,y3,x4,y4)

	--[[ DEBUG: Show vanishing points.
	if vapo23And41X then  LG.circle("fill", vapo23And41X,vapo23And41Y, 3)  end
	if vapo12And34X then  LG.circle("fill", vapo12And34X,vapo12And34Y, 3)  end
	--]]

	if vapo23And41X then  z4 = calculateZ(x1,y1, x4,y4, vapo23And41X,vapo23And41Y)  end
	if vapo12And34X then  z2 = calculateZ(x1,y1, x2,y2, vapo12And34X,vapo12And34Y)  end

	if vapo23And41X and vapo12And34X then
		local vapo13X,vapo13Y = intersectLines(x1,y1,x3,y3, vapo23And41X,vapo23And41Y,vapo12And34X,vapo12And34Y)
		z3 = not vapo13X and 1 or
		     calculateZ(x1,y1, x3,y3, vapo13X,vapo13Y)
	elseif vapo23And41X then
		z3 = calculateZ(x2,y2, x3,y3, vapo23And41X,vapo23And41Y)
	elseif vapo12And34X then
		z3 = calculateZ(x4,y4, x3,y3, vapo12And34X,vapo12And34Y)
	end

	local vert = vertices[1] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x1,y1,1/z1, 0,0
	local vert = vertices[2] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x2,y2,1/z2, 1/z2,0
	local vert = vertices[3] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x3,y3,1/z3, 1/z3,1/z3
	local vert = vertices[4] ; vert[1],vert[2],vert[3], vert[4],vert[5] = x4,y4,1/z4, 0,1/z4

	-- Draw!
	quadMesh:setTexture(image)
	quadMesh:setVertices(vertices)
	sendVec4(quadShader, "quad", u,v,uvW,uvH)

	LG.setShader(quadShader)
	LG.draw(quadMesh)
	LG.setShader(nil)

	--[[ DEBUG: Show z-values.
	local r,g,b,a = LG.getColor()
	LG.setColor(0, 0, 0)
	LG.print(string.format("%.4f",z1), x1+.5,y1+.5, 0, .5)
	LG.print(string.format("%.4f",z2), x2+.5,y2+.5, 0, .5)
	LG.print(string.format("%.4f",z3), x3+.5,y3+.5, 0, .5)
	LG.print(string.format("%.4f",z4), x4+.5,y4+.5, 0, .5)
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
	LG.setColor(.3, .6, .3) ; LG.draw(images.light, lightSource.x,lightSource.y, 0, 25,25*WORLD_SCALE_Y, w/2,h/2)
	LG.setColor(1, 1, 1)    ; LG.draw(images.light, lightSource.x,lightSource.y, 0, 01,01*WORLD_SCALE_Y, w/2,h/2)

	-- Entity shadows.
	for _, e in ipairs(entities) do
		if e.type == "light" then
			-- void

		else
			local iw,ih      = images.sprites:getDimensions()
			local qx,qy, w,h = e.quad:getViewport()

			--
			--          x light
			--         ##
			--        ####
			--       / ##
			--      /  ||opposite
			--     /   ||
			--  __/θ___||__________
			--   adjacent
			--
			--  tanθ     = opposite / adjacent
			--  adjacent = opposite / tanθ
			--
			local shadowLength = h / math.tan(-math.atan2(math.max(lightSource.z-h, .0001), e.y-lightSource.y))

			--
			--  adjacent
			--   +----+
			--    \θ  |
			--     \  |O opposite
			--      \ /|\
			--       \/ \
			--        x light
			--
			--  tanθ     = opposite / adjacent
			--  adjacent = opposite / tanθ
			--
			local angleL  = math.atan2(lightSource.y-e.y, (e.x-w/2)-lightSource.x)
			local angleR  = math.atan2(lightSource.y-e.y, (e.x+w/2)-lightSource.x)
			local offsetL = shadowLength / math.tan(angleL) / 2
			local offsetR = shadowLength / math.tan(angleR) / 2

			local x1, y1 = e.x-w/2+offsetL, e.y-shadowLength -- top left
			local x2, y2 = e.x+w/2+offsetR, e.y-shadowLength -- top right
			local x3, y3 = e.x+w/2, e.y -- bottom right
			local x4, y4 = e.x-w/2, e.y -- bottom left

			local u1, v1 = (qx  )/iw, (qy  )/ih -- top left
			local u2, v2 = (qx+w)/iw, (qy  )/ih -- top right
			local u3, v3 = (qx+w)/iw, (qy+h)/ih -- bottom right
			local u4, v4 = (qx  )/iw, (qy+h)/ih -- bottom left

			if e.flip then
				u1,u2 = u2,u1
				u4,u3 = u3,u4
			end

			LG.setColor(0, 0, 0)
			drawPerspectiveCorrectQuad(images.sprites, x1,y1,x2,y2,x3,y3,x4,y4, u1,v1,u2-u1,v4-v1)
		end
	end

	-- Entities.
	for _, e in ipairs(entities) do
		if e.type == "light" then
			LG.setColor(1, 1, 1)
			LG.circle("fill", e.x,e.y-e.z, 5)

			for i = 1, 6 do
				local lineX = 10 * math.cos(i/6 * TAU/2)
				local lineY = 10 * math.sin(i/6 * TAU/2)
				LG.line(e.x+lineX,e.y-e.z+lineY, e.x-lineX,e.y-e.z-lineY)
			end

		else
			local LIGHT_REACH       = 400
			local TRANSITION_LENGTH = 20

			local dx       = lightSource.x - e.x
			local dy       = lightSource.y - e.y
			local distance = math.sqrt(dx^2 + (dy/WORLD_SCALE_Y)^2)

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
	LG.print("Arrow keys = move player\nMouse = move light\nPageUp/PageDown = raise/lower light", 3,1)
end



function love.keypressed(key)
	if key == "escape" then
		love.event.quit()
	end
end


