-- Aseprite Lua: preserve original details, draw ONLY new artwork in 3x3 blocks.
-- Run from repository root with Aseprite.exe --batch --script <this file>.
-- Optional params: input, reference, output, export_dir, preview.
local root=app.fs.currentPath
local input=app.params.input or [[C:/Users/INVESTFX/Desktop/Indies - android  アニメーション/img/characters/$zouhyou_attack_left.png]]
local reference=app.params.reference or [[C:/Users/INVESTFX/Desktop/Indies - android  アニメーション/img/characters/$zouhyou_all.png]]
local output=app.params.output or app.fs.joinPath(root,"assets/source/enemies/zouhyou_attack_four_directions.aseprite")
local exportDir=app.params.export_dir or app.fs.joinPath(root,"assets/export/enemies/zouhyou_attack")
assert(not app.fs.isFile(output),"Output exists; choose a new filename")
local src=Image{fromFile=input}
local ref=Image{fromFile=reference}
assert(src.width==144 and src.height==192,"Expected 144x192 attack sheet")
assert(ref.width==144 and ref.height==192,"Expected matching directional reference")
app.fs.makeAllDirectories(app.fs.filePath(output))
app.fs.makeAllDirectories(exportDir)
local names={"down","left","right","up"}
for _,name in ipairs(names) do
  assert(not app.fs.isFile(app.fs.joinPath(exportDir,"zouhyou_attack_"..name..".png")),"Export already exists")
end
assert(not app.fs.isFile(app.fs.joinPath(exportDir,"zouhyou_attack.png")),"Sheet export exists")

local pc=app.pixelColor
-- All colors come from the original attack image.
local colors={
  outline=pc.rgba(0,0,0,255),
  cloth=pc.rgba(121,103,85,255),
  shadow=pc.rgba(6,6,8,255),
  skin=pc.rgba(255,231,197,255),
}
local left=Image(src,Rectangle(0,0,48,48))
local right=Image(48,48,ColorMode.RGB)
for y=0,47 do for x=0,47 do right:drawPixel(x,y,left:getPixel(47-x,y)) end end
local down=Image(ref,Rectangle(48,0,48,48))
local up=Image(ref,Rectangle(48,144,48,48))
local downArms=Image(48,48,ColorMode.RGB)
local upArms=Image(48,48,ColorMode.RGB)

-- x/y/w/h are logical pixels: each maps to exactly 3x3 physical pixels.
local function block(image,x,y,w,h,color)
  assert(x>=0 and y>=0 and x+w<=16 and y+h<=16,"Block outside 48px cell")
  for yy=y*3,(y+h)*3-1 do for xx=x*3,(x+w)*3-1 do
    image:drawPixel(xx,yy,color)
  end end
end
-- Repose only the attacking arm; the original face, hood, torso and feet remain.
-- Front view: right arm (screen left) thrusts toward the viewer/downward.
block(down,1,9,4,4,0)
block(downArms,2,9,3,2,colors.outline)
block(downArms,3,9,2,2,colors.cloth)
block(downArms,3,10,3,3,colors.outline)
block(downArms,4,10,1,2,colors.cloth)
block(downArms,4,12,3,3,colors.outline)
block(downArms,4,12,2,2,colors.skin)
block(downArms,5,14,1,1,colors.cloth)

-- Back view: the same anatomical right arm extends upward, beside the hood.
block(up,11,9,4,4,0)
block(upArms,11,8,3,3,colors.outline)
block(upArms,11,8,2,2,colors.cloth)
block(upArms,12,5,2,4,colors.outline)
block(upArms,12,6,1,3,colors.cloth)
block(upArms,11,3,3,3,colors.outline)
block(upArms,11,3,2,2,colors.skin)
block(upArms,12,5,1,1,colors.cloth)

local bases={down,left,right,up}
local additions={downArms,Image(48,48,ColorMode.RGB),Image(48,48,ColorMode.RGB),upArms}
local sheet=Image(144,192,ColorMode.RGB)
local armSheet=Image(144,192,ColorMode.RGB)
for row=0,3 do
  for col=0,2 do
    sheet:drawImage(bases[row+1],Point(col*48,row*48))
    armSheet:drawImage(additions[row+1],Point(col*48,row*48))
  end
end

local sprite=Sprite(144,192,ColorMode.RGB)
sprite.layers[1].name="direction_bases_original_detail"
sprite:newCel(sprite.layers[1],1,sheet,Point(0,0))
local arms=sprite:newLayer()
arms.name="attack_arms_3x3"
sprite:newCel(arms,1,armSheet,Point(0,0))
local originalLayer=sprite:newLayer()
originalLayer.name="reference_attack_left_original"
sprite:newCel(originalLayer,1,src,Point(0,0))
originalLayer.isVisible=false
local referenceLayer=sprite:newLayer()
referenceLayer.name="reference_four_directions_original"
sprite:newCel(referenceLayer,1,ref,Point(0,0))
referenceLayer.isVisible=false
sprite.gridBounds=Rectangle(0,0,3,3)
app.layer=arms
sprite:saveAs(output)
local composite=Image(sprite)
composite:saveAs(app.fs.joinPath(exportDir,"zouhyou_attack.png"))
for row=0,3 do
  local pose=Image(composite,Rectangle(0,row*48,48,48))
  pose:saveAs(app.fs.joinPath(exportDir,"zouhyou_attack_"..names[row+1]..".png"))
end

-- Validate only new artwork against the requested block rule.
for y=0,191,3 do for x=0,143,3 do
  local p=armSheet:getPixel(x,y)
  for dy=0,2 do for dx=0,2 do
    assert(armSheet:getPixel(x+dx,y+dy)==p,"New artwork violates 3x3 block rule")
  end end
end end
for y=0,47 do for x=0,47 do
  assert(composite:getPixel(x,48+y)==left:getPixel(x,y),"Left original changed")
  assert(composite:getPixel(x,96+y)==left:getPixel(47-x,y),"Right mirror mismatch")
end end

if app.params.preview then
  local review=Image(96,96,ColorMode.RGB)
  for i=0,3 do
    local pose=Image(composite,Rectangle(0,i*48,48,48))
    review:drawImage(pose,Point((i%2)*48,math.floor(i/2)*48))
  end
  review:resize(384,384)
  review:saveAs(app.params.preview)
end
print("PASS: down/left/right/up; original left preserved; exact right mirror; additions are 3x3")
print("SAVED "..output)
