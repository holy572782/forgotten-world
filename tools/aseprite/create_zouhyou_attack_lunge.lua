-- Aseprite Lua: lunging revision of the four-direction artwork.
-- Original fine details are moved, never resampled. New limbs use 3x3 blocks.
local root=app.fs.currentPath
local input=app.params.input or app.fs.joinPath(root,"assets/source/enemies/zouhyou_attack_four_directions.aseprite")
local output=app.params.output or app.fs.joinPath(root,"assets/source/enemies/zouhyou_attack_lunge.aseprite")
local exportDir=app.params.export_dir or app.fs.joinPath(root,"assets/export/enemies/zouhyou_attack_lunge")
assert(not app.fs.isFile(output),"Output exists; choose another filename")
local previous=Sprite{fromFile=input,oneFrame=true}
local original=Image(previous)
previous:close()
assert(original.width==144 and original.height==192)
app.fs.makeAllDirectories(app.fs.filePath(output))
app.fs.makeAllDirectories(exportDir)
local names={"down","left","right","up"}
for _,name in ipairs(names) do
 assert(not app.fs.isFile(app.fs.joinPath(exportDir,"zouhyou_attack_lunge_"..name..".png")),"Export exists")
end
assert(not app.fs.isFile(app.fs.joinPath(exportDir,"zouhyou_attack_lunge.png")),"Sheet exists")
local pc=app.pixelColor
local ink=pc.rgba(0,0,0,255)
local cloth=pc.rgba(121,103,85,255)
local shade=pc.rgba(6,6,8,255)
local skin=pc.rgba(255,231,197,255)
local poses,limbs={},{}
for i=1,4 do poses[i]=Image(60,60,ColorMode.RGB);limbs[i]=Image(60,60,ColorMode.RGB) end
local function block(img,x,y,w,h,color)
 assert(x>=0 and y>=0 and x+w<=20 and y+h<=20)
 for yy=y*3,(y+h)*3-1 do for xx=x*3,(x+w)*3-1 do img:drawPixel(xx,yy,color) end end
end
local function put(img,x,y,p)
 if pc.rgbaA(p)>0 then assert(x>=0 and x<60 and y>=0 and y<60,"Clipped source detail");img:drawPixel(x,y,p) end
end
-- Head leads the shoulders; shoulders lead the hips. No arbitrary-angle rotation.
for y=0,38 do for x=0,47 do
 local lean=(y<21) and -3 or ((y<30) and 0 or 3)
 put(poses[2],x+6+lean,y+6,original:getPixel(x,48+y))
end end
-- Wide front planted leg and bent trailing leg, drawn in logical 3px units.
local l=limbs[2]
block(l,6,13,4,3,ink);block(l,6,13,3,2,cloth)
block(l,4,15,4,2,ink);block(l,5,15,2,1,cloth)
block(l,3,16,3,2,ink);block(l,3,16,2,1,skin)
block(l,1,17,5,2,ink);block(l,2,17,3,1,cloth)
block(l,10,13,3,2,ink);block(l,11,13,2,1,cloth)
block(l,12,14,3,2,ink);block(l,13,14,1,1,cloth)
block(l,14,15,3,2,ink);block(l,15,15,1,1,skin)
block(l,15,16,4,2,ink);block(l,16,16,2,1,cloth)
-- Right is an exact reflection of this finished left pose, including legs.
for y=0,59 do for x=0,59 do
 poses[3]:drawPixel(x,y,poses[2]:getPixel(59-x,y))
 limbs[3]:drawPixel(x,y,limbs[2]:getPixel(59-x,y))
end end

-- Front/back lean is expressed by lowered shoulders and asymmetric leg depth.
for y=0,38 do for x=0,47 do
 local dy=(y<27) and 3 or 0
 put(poses[1],x+6,y+6+dy,original:getPixel(x,y))
 local upDy=(y<27) and -3 or 0
 put(poses[4],x+6,y+9+upDy,original:getPixel(x,144+y))
end end
local d=limbs[1]
block(d,6,13,3,3,ink);block(d,6,13,2,2,cloth)
block(d,5,15,3,3,ink);block(d,5,15,2,2,cloth)
block(d,4,17,5,2,ink);block(d,5,17,3,1,cloth)
block(d,11,13,3,2,ink);block(d,12,13,1,1,cloth)
block(d,13,14,3,2,ink);block(d,14,14,1,1,skin)
block(d,14,15,4,2,ink);block(d,15,15,2,1,cloth)
local u=limbs[4]
block(u,6,14,3,2,ink);block(u,6,14,2,1,cloth)
block(u,5,15,3,3,ink);block(u,5,15,2,2,cloth)
block(u,3,17,5,2,ink);block(u,4,17,3,1,cloth)
block(u,10,13,3,3,ink);block(u,11,13,2,2,cloth)
block(u,12,15,3,2,ink);block(u,13,15,1,1,cloth)
block(u,13,16,4,2,ink);block(u,14,16,2,1,cloth)

local bodySheet=Image(180,240,ColorMode.RGB)
local legSheet=Image(180,240,ColorMode.RGB)
for row=0,3 do for col=0,2 do
 bodySheet:drawImage(poses[row+1],Point(col*60,row*60))
 legSheet:drawImage(limbs[row+1],Point(col*60,row*60))
end end
local s=Sprite(180,240,ColorMode.RGB)
s.layers[1].name="lunge_original_details"
s:newCel(s.layers[1],1,bodySheet,Point(0,0))
local legs=s:newLayer();legs.name="lunge_legs_3x3"
s:newCel(legs,1,legSheet,Point(0,0))
local ref=s:newLayer();ref.name="previous_version_reference";ref.isVisible=false
s:newCel(ref,1,original,Point(0,0))
s.gridBounds=Rectangle(0,0,3,3)
app.layer=legs
s:saveAs(output)
local composite=Image(s)
composite:saveAs(app.fs.joinPath(exportDir,"zouhyou_attack_lunge.png"))
for i,name in ipairs(names) do
 Image(composite,Rectangle(0,(i-1)*60,60,60)):saveAs(app.fs.joinPath(exportDir,"zouhyou_attack_lunge_"..name..".png"))
end
-- Horizontal mirroring maps 3px blocks to 3px blocks on this 60px canvas.
for y=0,239,3 do for x=0,179,3 do
 local p=legSheet:getPixel(x,y)
 for dy=0,2 do for dx=0,2 do assert(legSheet:getPixel(x+dx,y+dy)==p,"3x3 violation") end end
end end
local preview=Image(120,120,ColorMode.RGB)
for i=0,3 do preview:drawImage(Image(composite,Rectangle(0,i*60,60,60)),Point((i%2)*60,math.floor(i/2)*60)) end
preview:resize(480,480)
preview:saveAs(app.params.preview or app.fs.joinPath(root,".godot/zouhyou_art/lunge_preview.png"))
print("PASS: four lunging poses, 60px cells, new legs all 3x3, no clipped source details")
print("SAVED "..output)
