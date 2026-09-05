local M={KEY='bezier_pen_v1'}
local pc=app.pixelColor
local function plain(v)
 if type(v)=='table' or type(v)=='userdata' then
  local out={}
  for k,x in pairs(v) do out[k]=plain(x) end
  for k,x in ipairs(v) do out[k]=plain(x) end
  return out
 end
 return v
end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1000000 end
function M.validate(p)
 assert(type(p)=='table' and p.version==1,'不支援的路徑資料版本。')
 assert(finite(p.width) and p.width>=1 and p.width<=128,'線寬需要介於 1 到 128 像素。')
 assert(type(p.nodes)=='table' and #p.nodes<=256,'路徑最多支援 256 個錨點。')
 assert(type(p.color)=='table','缺少路徑顏色。')
 for _,k in ipairs({'r','g','b','a'}) do assert(finite(p.color[k]) and p.color[k]>=0 and p.color[k]<=255,'顏色資料無效。') end
 for _,n in ipairs(p.nodes) do
  for _,k in ipairs({'x','y','ix','iy','ox','oy','weight'}) do assert(finite(n[k]),'錨點資料無效。') end
  assert(n.weight>=0 and n.weight<=1000,'錨點線寬比例需要介於 0 到 1000%。')
 end
 return p
end
function M.clone(p) return plain(p) end
function M.new(w,h,c)
 return {version=1,canvasWidth=w,canvasHeight=h,width=3,closed=false,color={r=c.red,g=c.green,b=c.blue,a=c.alpha},nodes={}}
end
function M.node(x,y) return {x=x,y=y,ix=0,iy=0,ox=0,oy=0,smooth=true,weight=100} end
function M.handle(n,side,dx,dy,independent)
 local xkey,ykey=side=='in' and 'ix' or 'ox',side=='in' and 'iy' or 'oy'
 local otherx,othery=side=='in' and 'ox' or 'ix',side=='in' and 'oy' or 'iy'
 if independent then n.smooth=false end
 local len=math.sqrt(n[otherx]^2+n[othery]^2)
 n[xkey],n[ykey]=dx,dy
 if n.smooth then
  local d=math.sqrt(dx*dx+dy*dy)
  if d>0 then if len==0 then len=d end; n[otherx],n[othery]=-dx*len/d,-dy*len/d end
 end
end
local function flat(x0,y0,x1,y1,x2,y2,x3,y3)
 local dx,dy=x3-x0,y3-y0; local len=dx*dx+dy*dy
 if len<1e-12 then return math.max((x1-x0)^2+(y1-y0)^2,(x2-x0)^2+(y2-y0)^2)<0.04 end
 local a,b=(x1-x0)*dy-(y1-y0)*dx,(x2-x0)*dy-(y2-y0)*dx
 -- Also check polygon length, so collinear curves that double back are subdivided.
 local poly=math.sqrt((x1-x0)^2+(y1-y0)^2)+math.sqrt((x2-x1)^2+(y2-y1)^2)+math.sqrt((x3-x2)^2+(y3-y2)^2)
 return math.max(a*a,b*b)/len<0.04 and poly-math.sqrt(len)<0.2
end
function M.flatten(p)
 local out={}
 local function curve(a,b)
  local pts={{x=a.x,y=a.y,t=0}}
  local function sub(x0,y0,x1,y1,x2,y2,x3,y3,t0,t1,depth)
   if depth>=14 or flat(x0,y0,x1,y1,x2,y2,x3,y3) then
    pts[#pts+1]={x=x3,y=y3,t=t1}; return
   end
   local ax,ay=(x0+x1)/2,(y0+y1)/2; local bx,by=(x1+x2)/2,(y1+y2)/2
   local cx,cy=(x2+x3)/2,(y2+y3)/2; local dx,dy=(ax+bx)/2,(ay+by)/2
   local ex,ey=(bx+cx)/2,(by+cy)/2; local fx,fy=(dx+ex)/2,(dy+ey)/2; local tm=(t0+t1)/2
   sub(x0,y0,ax,ay,dx,dy,fx,fy,t0,tm,depth+1)
   sub(fx,fy,ex,ey,cx,cy,x3,y3,tm,t1,depth+1)
  end
  sub(a.x,a.y,a.x+a.ox,a.y+a.oy,b.x+b.ix,b.y+b.iy,b.x,b.y,0,1,0)
  out[#out+1]={points=pts,a=a.weight,b=b.weight}
 end
 for i=1,#p.nodes-1 do curve(p.nodes[i],p.nodes[i+1]) end
 if p.closed and #p.nodes>2 then curve(p.nodes[#p.nodes],p.nodes[1]) end
 return out
end
-- Raster preview and applied image use the exact same pixel-art renderer.
-- Round caps; no antialiasing. Repeated samples do not accumulate opacity.
function M.raster(p,w,h)
 M.validate(p)
 local lines=M.flatten(p)
 local minx,miny,maxx,maxy=w,h,-1,-1
 local maxWeight=0
 for _,n in ipairs(p.nodes) do maxWeight=math.max(maxWeight,n.weight) end
 local pad=p.width*maxWeight/200+2
 for _,line in ipairs(lines) do for _,v in ipairs(line.points) do
  minx=math.min(minx,v.x-pad); miny=math.min(miny,v.y-pad); maxx=math.max(maxx,v.x+pad); maxy=math.max(maxy,v.y+pad)
 end end
 minx=math.max(0,math.floor(minx)); miny=math.max(0,math.floor(miny))
 maxx=math.min(w-1,math.ceil(maxx)); maxy=math.min(h-1,math.ceil(maxy))
 if maxx<minx or maxy<miny then return Image(1,1,ColorMode.RGB),Point(0,0) end
 local im=Image(maxx-minx+1,maxy-miny+1,ColorMode.RGB)
 local c=p.color; local pixel=pc.rgba(c.r,c.g,c.b,c.a)
 local function stamp(x,y,width)
  if width<=0 then return end
  if width<=1 then
   local ix,iy=math.floor(x+0.5)-minx,math.floor(y+0.5)-miny
   if ix>=0 and iy>=0 and ix<im.width and iy<im.height then im:drawPixel(ix,iy,pixel) end
   return
  end
  local r=width/2
  for yy=math.max(miny,math.ceil(y-r)),math.min(maxy,math.floor(y+r)) do
   local dx=math.sqrt(math.max(0,r*r-(yy-y)^2))
   for xx=math.max(minx,math.ceil(x-dx)),math.min(maxx,math.floor(x+dx)) do
    -- A half-open edge makes integer widths predictable on straight runs.
    if (xx-x)^2+(yy-y)^2<r*r+1e-9 and yy<y+r and xx<x+r then im:drawPixel(xx-minx,yy-miny,pixel) end
   end
  end
 end
 for _,line in ipairs(lines) do
  for i=2,#line.points do
   local a,b=line.points[i-1],line.points[i]
   local steps=math.max(1,math.ceil(math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)*2))
   for j=0,steps do
    local u=j/steps; local t=a.t+(b.t-a.t)*u
    stamp(a.x+(b.x-a.x)*u,a.y+(b.y-a.y)*u,p.width*(line.a+(line.b-line.a)*t)/100)
   end
  end
 end
 return im,Point(minx,miny)
end
function M.read(layer)
 local raw=layer and layer.properties[M.KEY]
 if not raw then return nil end
 local ok,p=pcall(json.decode,raw)
 assert(ok,'無法讀取此圖層的路徑資料。')
 return M.validate(plain(p))
end
function M.apply(s,layer,p,name)
 assert(s and s.isValid and s.colorMode==ColorMode.RGB,'原作品已關閉或不是 RGB 模式。')
 assert(#s.frames==1,'目前版本僅支援單幀作品。')
 assert(#p.nodes>=2,'至少需要兩個錨點。')
 assert(s.width==p.canvasWidth and s.height==p.canvasHeight,'作品尺寸已改變，請取消並重新開啟編輯器。')
 if layer then
  local found=false
  local function visit(ls) for _,l in ipairs(ls) do if l==layer then found=true end; if l.isGroup then visit(l.layers) end end end
  visit(s.layers); assert(found and M.read(layer),'原路徑圖層已刪除或不再有效。')
 end
 local img,pos=M.raster(p,s.width,s.height)
 app.sprite=s
 app.transaction('套用貝茲路徑',function()
  if not layer then layer=s:newLayer() end
  layer.name=name~='' and name or '貝茲曲線'
  local c=layer:cel(1)
  if c then c.image=img; c.position=pos else s:newCel(layer,1,img,pos) end
  layer.properties[M.KEY]=json.encode(p)
  layer.color=Color{r=173,g=216,b=255,a=255}
 end)
 app.layer=layer; app.refresh(); return layer
end
return M
