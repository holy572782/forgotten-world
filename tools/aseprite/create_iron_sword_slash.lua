-- Aseprite 1.3 Lua. Adds exactly one editable effect layer to a COPY.
-- CLI from repository root:
-- Aseprite.exe --batch --script tools/aseprite/create_iron_sword_slash.lua
-- Optional script params: input, output, preview, effect.
local root = app.fs.currentPath
local input = app.params.input or app.fs.joinPath(root, "画像フォルダ", "武器", "鉄の剣.png")
local output = app.params.output or app.fs.joinPath(root, "assets/source/weapons/iron_sword_slash.aseprite")
local preview = app.params.preview
local effectExport = app.params.effect
assert(not app.fs.isFile(output), "Output exists; choose a new output filename")
local sprite = Sprite{fromFile=input, oneFrame=true}
assert(sprite.width == 336 and sprite.height == 448, "Expected a 336x448 sheet")
assert(#sprite.layers == 1 and #sprite.frames == 1, "Expected one source PNG layer")
assert(sprite.colorMode == ColorMode.RGB, "Expected an RGBA PNG")
local source = Image(sprite.spec)
source:drawSprite(sprite, 1)
local fx = Image(sprite.spec)
local pc = app.pixelColor
local tau = 2 * math.pi
local stageSpan = {42, 94, 82} -- visual choices, not combat/hitbox settings
local stageOpacity = {0.72, 1.0, 0.74}
local function rgba(r,g,b,a) return pc.rgba(r,g,b,math.floor(a+0.5)) end

-- Detect the brown grip and white blade separately in every existing pose.
-- The geometry follows the current edited PNG rather than an older game copy.
local function pose(col,row)
  local gx,gy,gn,bx,by,bn = 0,0,0,0,0,0
  for y=0,111 do for x=0,111 do
    local p=source:getPixel(col*112+x,row*112+y)
    if pc.rgbaA(p)>0 then
      local r,g,b=pc.rgbaR(p),pc.rgbaG(p),pc.rgbaB(p)
      if r>b*1.3 and r>g*1.3 then gx=gx+x;gy=gy+y;gn=gn+1 end
      if r>200 and g>200 and b>200 then bx=bx+x;by=by+y;bn=bn+1 end
    end
  end end
  assert(gn>0 and bn>0, "Grip/blade not found in a cell")
  gx,gy,bx,by=gx/gn,gy/gn,bx/bn,by/bn
  local dx,dy=bx-gx,by-gy
  local length=math.sqrt(dx*dx+dy*dy)
  dx,dy=dx/length,dy/length
  return gx-dx*28,gy-dy*28,math.atan(dy,dx)
end

for row=0,3 do for col=0,2 do
  local cx,cy,heading=pose(col,row)
  local direction=(row==1) and -1 or 1
  local span=math.rad(stageSpan[col+1])
  local count=0
  -- Draw on a 2px grid matching the doubled pixels of the original sword.
  for y=2,108,2 do for x=2,108,2 do
    local dx,dy=x+0.5-cx,y+0.5-cy
    local distance=math.sqrt(dx*dx+dy*dy)
    local behind=((heading-math.atan(dy,dx))*direction)%tau
    if behind<=span then
      local t=1-behind/span
      local radius=44.0
      local width=0.7+9.3*(math.sin(math.pi*t)^0.68)
      local inset=radius-distance
      local color=nil
      if inset>=0 and inset<=width then
        local edge=inset/width
        local opacity=stageOpacity[col+1]*(0.35+0.65*t)
        if edge<0.22 then color=rgba(245,247,255,245*opacity)
        elseif edge<0.56 then color=rgba(212,201,244,205*opacity)
        else color=rgba(128,137,197,112*opacity) end
      elseif distance>=radius+3 and distance<=radius+4.3 and t>0.2 and t<0.8 then
        -- A broken, faint secondary speed line stays on this same layer.
        if t<0.43 or t>0.58 then color=rgba(186,203,225,88*stageOpacity[col+1]) end
      end
      if color then
        for yy=y,y+1 do for xx=x,x+1 do
          fx:drawPixel(col*112+xx,row*112+yy,color)
          count=count+1
        end end
      end
    end
  end end
  assert(count>0, "Empty effect cell")
  print(string.format("cell %d,%d: %d effect pixels",row,col,count))
end end

app.transaction("Create iron sword slash arc", function()
  local layer=sprite:newLayer()
  layer.name="slash_arc"
  layer.stackIndex=1 -- under the unmodified sword so its metal pixels stay sharp
  sprite:newCel(layer,1,fx,Point(0,0))
  app.layer=layer
end)
assert(#sprite.layers==2, "Expected source plus exactly one effect layer")
sprite:saveAs(output)
if preview then sprite:saveCopyAs(preview) end
if effectExport then fx:saveAs(effectExport) end
print("SAVED "..output)
if app.isUIAvailable then app.refresh() end
