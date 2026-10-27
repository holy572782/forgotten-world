-- Aseprite Lua. Original-size revision using the user's original RIGHT pose.
-- New artwork uses 3x3 blocks; original small details are never resampled.
local root=app.fs.currentPath
local sourceDir=app.params.source_dir or [[C:/Users/INVESTFX/Desktop/Indies - android  アニメーション/img/characters]]
local output=app.params.output or app.fs.joinPath(root,"assets/source/enemies/zouhyou_attack_original_size.aseprite")
local exportDir=app.params.export_dir or app.fs.joinPath(root,"assets/export/enemies/zouhyou_attack_original_size")
assert(not app.fs.isFile(output),"Output exists; choose another filename")
local rightSheet=Image{fromFile=app.fs.joinPath(sourceDir,"$zouhyou_attack_light.png")}
local refs=Image{fromFile=app.fs.joinPath(sourceDir,"$zouhyou_all.png")}
assert(rightSheet.width==144 and rightSheet.height==192)
assert(refs.width==144 and refs.height==192)
app.fs.makeAllDirectories(app.fs.filePath(output))
app.fs.makeAllDirectories(exportDir)
local names={"down","left","right","up"}
for _,name in ipairs(names) do
 assert(not app.fs.isFile(app.fs.joinPath(exportDir,"zouhyou_attack_"..name..".png")),"Export exists")
end
assert(not app.fs.isFile(app.fs.joinPath(exportDir,"zouhyou_attack.png")),"Sheet exists")
local pc=app.pixelColor
local ink=pc.rgba(0,0,0,255)
local cloth=pc.rgba(121,103,85,255)
local skin=pc.rgba(255,231,197,255)
local bases={Image(refs,Rectangle(48,0,48,48)),Image(48,48,ColorMode.RGB),
 Image(rightSheet,Rectangle(0,0,48,48)),Image(refs,Rectangle(48,144,48,48))}
for y=0,47 do for x=0,47 do bases[2]:drawPixel(x,y,bases[3]:getPixel(47-x,y)) end end
local edits={}
for i=1,4 do edits[i]=Image(48,48,ColorMode.RGB) end
local function block(img,x,y,w,h,c)
 assert(x>=0 and y>=0 and x+w<=16 and y+h<=16)
 for yy=y*3,(y+h)*3-1 do for xx=x*3,(x+w)*3-1 do img:drawPixel(xx,yy,c) end end
end
-- Only arm / knee / foot regions are redrawn. Preserve head and torso details.
for _,i in ipairs({1,4}) do block(bases[i],0,12,16,4,0) end
-- Down-facing right arm projects towards the viewer, without a long dangling arm.
block(bases[1],1,9,4,3,0)
local d=edits[1]
block(d,2,9,3,2,ink);block(d,3,9,2,1,cloth)
block(d,3,10,4,3,ink);block(d,4,10,2,2,skin)
-- Bent leading knee and compact planted foot: 9px foot, no stretched boot.
block(d,5,12,3,2,ink);block(d,5,12,2,1,cloth)
block(d,4,13,3,2,ink);block(d,5,13,1,1,skin)
block(d,4,15,4,1,ink);block(d,5,15,2,1,cloth)
-- Trailing foot sits one logical pixel higher than the leading foot.
block(d,9,12,3,2,ink);block(d,9,12,2,1,cloth)
block(d,10,13,3,2,ink);block(d,10,13,2,1,skin)
block(d,10,14,3,1,cloth)

-- Up-facing arm remains beside the hood, matching the character's right arm.
block(bases[4],11,9,4,3,0)
local u=edits[4]
block(u,11,8,3,3,ink);block(u,11,8,2,2,cloth)
block(u,12,5,2,4,ink);block(u,12,6,1,3,cloth)
block(u,11,3,3,3,ink);block(u,11,3,2,2,skin)
block(u,12,5,1,1,cloth)
-- Reverse the depth of the staggered stance for an upward step.
block(u,5,12,3,2,ink);block(u,5,12,2,1,cloth)
block(u,4,13,3,2,ink);block(u,4,13,2,1,skin)
block(u,3,15,4,1,ink);block(u,4,15,2,1,cloth)
block(u,9,12,3,2,ink);block(u,10,12,2,1,cloth)
block(u,10,13,3,2,ink);block(u,10,13,2,1,skin)
block(u,10,14,3,1,cloth)

local baseSheet=Image(144,192,ColorMode.RGB)
local editSheet=Image(144,192,ColorMode.RGB)
for row=0,3 do for col=0,2 do
 baseSheet:drawImage(bases[row+1],Point(col*48,row*48))
 editSheet:drawImage(edits[row+1],Point(col*48,row*48))
end end
local s=Sprite(144,192,ColorMode.RGB)
s.layers[1].name="original_size_details"
s:newCel(s.layers[1],1,baseSheet,Point(0,0))
local editLayer=s:newLayer();editLayer.name="compact_attack_3x3"
s:newCel(editLayer,1,editSheet,Point(0,0))
local ref=s:newLayer();ref.name="original_right_reference";ref.isVisible=false
s:newCel(ref,1,rightSheet,Point(0,0))
local directionRef=s:newLayer();directionRef.name="original_direction_reference";directionRef.isVisible=false
s:newCel(directionRef,1,refs,Point(0,0))
s.gridBounds=Rectangle(0,0,3,3)
app.layer=editLayer
s:saveAs(output)
local composite=Image(s)
composite:saveAs(app.fs.joinPath(exportDir,"zouhyou_attack.png"))
for i,name in ipairs(names) do
 Image(composite,Rectangle(0,(i-1)*48,48,48)):saveAs(app.fs.joinPath(exportDir,"zouhyou_attack_"..name..".png"))
end
for y=0,191,3 do for x=0,143,3 do
 local p=editSheet:getPixel(x,y)
 for dy=0,2 do for dx=0,2 do assert(editSheet:getPixel(x+dx,y+dy)==p,"3x3 mismatch") end end
end end
for y=0,47 do for x=0,47 do
 assert(composite:getPixel(x,96+y)==rightSheet:getPixel(x,y),"Original right changed")
 assert(composite:getPixel(x,48+y)==rightSheet:getPixel(47-x,y),"Left mirror mismatch")
end end
local preview=Image(96,96,ColorMode.RGB)
for i=0,3 do preview:drawImage(Image(composite,Rectangle(0,i*48,48,48)),Point((i%2)*48,math.floor(i/2)*48)) end
preview:resize(384,384)
preview:saveAs(app.params.preview or app.fs.joinPath(root,".godot/zouhyou_art/original_size_preview.png"))
print("PASS original 48px cells / 144x192 sheet; right original unchanged; new 3x3 blocks")
print("SAVED "..output)
