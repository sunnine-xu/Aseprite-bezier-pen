local root,C
local active
local function alert(fn)
 return function(...)
  local ok,err=pcall(fn,...)
  if not ok then app.alert{title='貝茲鋼筆',text=tostring(err)} end
 end
end
local function reference(s,target)
 local oldLayer=app.layer
 local copy=Sprite(s)
 local function hide(a,b)
  for i,l in ipairs(a) do
   if l==target then b[i].isVisible=false end
   if l.isGroup then hide(l.layers,b[i].layers) end
  end
 end
 hide(s.layers,copy.layers)
 local img=Image(copy); copy:close(); app.sprite=s; app.layer=oldLayer
 return img
end
local function openEditor(editExisting)
 assert(not active,'請先完成或取消目前的路徑編輯。')
 local s=app.sprite
 assert(s and s.colorMode==ColorMode.RGB,'請先開啟 RGB 作品。')
 assert(#s.frames==1,'目前版本僅支援單幀作品。')
 local target=editExisting and app.layer or nil
 local path=editExisting and C.read(target) or C.new(s.width,s.height,app.fgColor)
 assert(path,'請選取由本插件建立的路徑圖層。')
 assert(path.canvasWidth==s.width and path.canvasHeight==s.height,'作品尺寸與保存的路徑不同，目前不支援自動縮放路徑。')
 path=C.clone(path)
 local backdrop=reference(s,target)
 local d,selected,drag= nil,0,nil
 local history,redo={},{}
 local raster,origin
 local zoom,panx,pany=1,0,0
 local view={scale=1,x=0,y=0}
 local suppress=false
 local function remember()
  history[#history+1]=C.clone(path); if #history>64 then table.remove(history,1) end; redo={}
 end
 local function rebuild() raster,origin=C.raster(path,s.width,s.height) end
 local function sync()
  if not d then return end
  suppress=true
  local n=path.nodes[selected]
  d:modify{id='pointStatus',text=n and ('錨點 '..selected..' / '..#path.nodes) or ('共 '..#path.nodes..' 個錨點')}
  d:modify{id='smooth',selected=n and n.smooth or false,enabled=n~=nil}
  d:modify{id='weight',value=n and n.weight or 100,enabled=n~=nil}
  d:modify{id='width',value=path.width}
  d:modify{id='closed',selected=path.closed}
  d:modify{id='strokeColor',color=Color{r=path.color.r,g=path.color.g,b=path.color.b,a=path.color.a}}
  d:modify{id='undo',enabled=#history>0}; d:modify{id='redo',enabled=#redo>0}
  suppress=false; d:repaint()
 end
 local function changed() rebuild(); sync() end
 local function undoPath(back)
  local from,to=back and history or redo,back and redo or history
  if #from==0 then return end
  to[#to+1]=C.clone(path); path=table.remove(from); selected=math.min(selected,#path.nodes); drag=nil; changed()
 end
 local function canvasPoint(ev)
  return (ev.x-view.x)/view.scale-0.5,(ev.y-view.y)/view.scale-0.5
 end
 local function screen(x,y) return view.x+(x+0.5)*view.scale,view.y+(y+0.5)*view.scale end
 local function hit(ev)
  local n=path.nodes[selected]
  if n then
   for _,side in ipairs({'in','out'}) do
    local dx,dy=side=='in' and n.ix or n.ox,side=='in' and n.iy or n.oy
    if dx*dx+dy*dy>1e-8 then
     local x,y=screen(n.x+dx,n.y+dy)
     if (x-ev.x)^2+(y-ev.y)^2<49 then return selected,side end
    end
   end
  end
  for i=#path.nodes,1,-1 do
   local x,y=screen(path.nodes[i].x,path.nodes[i].y)
   if (x-ev.x)^2+(y-ev.y)^2<49 then return i,'anchor' end
  end
 end
 local function down(ev)
  if ev.button==MouseButton.MIDDLE or ev.spaceKey then drag={kind='pan',x=ev.x,y=ev.y,px=panx,py=pany}; return end
  if ev.button~=MouseButton.LEFT then return end
  local x,y=canvasPoint(ev)
  local i,kind=hit(ev)
  if i then
   selected=i; remember()
   drag={kind=kind,x=x,y=y,node=C.clone(path.nodes[i])}
  elseif d.data.tool=='鋼筆：新增錨點' and x>=0 and y>=0 and x<s.width and y<s.height then
   assert(#path.nodes<256,'一條路徑最多支援 256 個錨點。')
   remember(); path.nodes[#path.nodes+1]=C.node(x,y); selected=#path.nodes
   drag={kind='new',x=x,y=y}
  else selected=0; drag=nil end
  changed()
 end
 local function move(ev)
  if not drag then return end
  if drag.kind=='pan' then panx=drag.px+ev.x-drag.x; pany=drag.py+ev.y-drag.y; d:repaint(); return end
  local x,y=canvasPoint(ev); local n=path.nodes[selected]
  if not n then return end
  x=math.max(-s.width,math.min(s.width*2,x)); y=math.max(-s.height,math.min(s.height*2,y))
  if drag.kind=='anchor' then n.x=drag.node.x+x-drag.x; n.y=drag.node.y+y-drag.y
  elseif drag.kind=='new' then n.ox=x-n.x; n.oy=y-n.y; n.ix=-n.ox; n.iy=-n.oy
  else C.handle(n,drag.kind,x-n.x,y-n.y,ev.altKey) end
  changed()
 end
 local function up(ev) if drag then move(ev) end; drag=nil end
 local function paint(ev)
  local gc=ev.context
  gc.color=Color{r=45,g=48,b=55}; gc:fillRect(Rectangle(0,0,gc.width,gc.height))
  view.scale=math.max(0.001,math.min((gc.width-24)/s.width,(gc.height-24)/s.height))*zoom
  view.x=(gc.width-s.width*view.scale)/2+panx; view.y=(gc.height-s.height*view.scale)/2+pany
  gc:save(); gc:beginPath(); gc:rect(Rectangle(view.x,view.y,s.width*view.scale,s.height*view.scale)); gc:clip()
  for y=0,gc.height-1,12 do for x=0,gc.width-1,12 do
   local v=(math.floor(x/12)+math.floor(y/12))%2==0 and 190 or 225
   gc.color=Color{r=v,g=v,b=v}; gc:fillRect(Rectangle(x,y,12,12))
  end end
  if d.data.background then gc:drawImage(backdrop,Rectangle(0,0,s.width,s.height),Rectangle(view.x,view.y,s.width*view.scale,s.height*view.scale)) end
  if raster then gc:drawImage(raster,Rectangle(0,0,raster.width,raster.height),Rectangle(view.x+origin.x*view.scale,view.y+origin.y*view.scale,raster.width*view.scale,raster.height*view.scale)) end
  gc:restore()
  if not d.data.handles then return end
  gc.antialias=true; gc.strokeWidth=1
  -- A thin path skeleton keeps fully transparent/tapered sections selectable.
  gc.color=Color{r=40,g=160,b=255,a=170}; gc:beginPath()
  for i,n in ipairs(path.nodes) do
   local x,y=screen(n.x,n.y)
   if i==1 then gc:moveTo(x,y) else
    local prev=path.nodes[i-1]; local a,b=screen(prev.x+prev.ox,prev.y+prev.oy); local c,e=screen(n.x+n.ix,n.y+n.iy)
    gc:cubicTo(a,b,c,e,x,y)
   end
  end
  if path.closed and #path.nodes>2 then
   local a,b=path.nodes[#path.nodes],path.nodes[1]
   local x1,y1=screen(a.x+a.ox,a.y+a.oy); local x2,y2=screen(b.x+b.ix,b.y+b.iy); local x3,y3=screen(b.x,b.y)
   gc:cubicTo(x1,y1,x2,y2,x3,y3)
  end
  gc:stroke()
  local n=path.nodes[selected]
  if n then
   local x,y=screen(n.x,n.y)
   for _,v in ipairs({{n.ix,n.iy},{n.ox,n.oy}}) do
    local hx,hy=screen(n.x+v[1],n.y+v[2]); gc.color=Color{r=255,g=155,b=45}
    gc:beginPath(); gc:moveTo(x,y); gc:lineTo(hx,hy); gc:stroke()
    gc:fillRect(Rectangle(hx-3,hy-3,6,6))
   end
  end
  for i,n in ipairs(path.nodes) do
   local x,y=screen(n.x,n.y)
   gc.color=i==selected and Color{r=255,g=210,b=60} or Color{r=255,g=255,b=255}
   gc:fillRect(Rectangle(x-3,y-3,6,6)); gc.color=Color{r=30,g=95,b=160}; gc:strokeRect(Rectangle(x-3,y-3,6,6))
  end
 end
 d=Dialog{title=target and '編輯貝茲曲線' or '新增貝茲曲線',resizeable=true,onclose=function() active=nil end}
 active=d
 d:entry{id='name',label='名稱',text=target and target.name or '貝茲曲線'}
 d:newrow(); d:combobox{id='tool',label='工具',options={'鋼筆：新增錨點','選取：只移動'},option='鋼筆：新增錨點'}
 d:check{id='closed',text='閉合路徑',selected=path.closed,onclick=function() if not suppress then remember(); path.closed=d.data.closed; changed() end end}
 d:newrow(); d:slider{id='width',label='整體線寬 px',min=1,max=128,value=path.width,onchange=function() if not suppress then remember(); path.width=d.data.width; changed() end end}
 d:color{id='strokeColor',label='顏色',color=Color{r=path.color.r,g=path.color.g,b=path.color.b,a=path.color.a},onchange=function()
  if not suppress then remember(); local c=d.data.strokeColor; path.color={r=c.red,g=c.green,b=c.blue,a=c.alpha}; changed() end
 end}
 d:newrow(); d:canvas{id='canvas',width=440,height=260,hexpand=true,vexpand=true,onpaint=paint,onmousedown=alert(down),onmousemove=alert(move),onmouseup=alert(up),
  onwheel=function(ev) zoom=math.max(0.25,math.min(16,zoom*(ev.deltaY<0 and 1.2 or 1/1.2))); d:repaint() end,
  onkeydown=alert(function(ev)
   if ev.ctrlKey and (ev.code=='KeyZ' or ev.key=='z') then
    undoPath(not ev.shiftKey); ev:stopPropagation()
   elseif ev.ctrlKey and (ev.code=='KeyY' or ev.key=='y') then
    undoPath(false); ev:stopPropagation()
   end
  end)}
 d:newrow(); d:label{id='pointStatus',text='共 0 個錨點'}
 d:check{id='smooth',text='控制柄平滑連動',selected=true,onclick=function()
  local n=path.nodes[selected]; if n and not suppress then remember(); n.smooth=d.data.smooth; if n.smooth then C.handle(n,'out',n.ox,n.oy,false) end; changed() end
 end}
 d:newrow(); d:slider{id='weight',label='此錨點線寬 %',min=0,max=1000,value=100,onchange=function()
  local n=path.nodes[selected]; if n and not suppress then remember(); n.weight=d.data.weight; changed() end
 end}
 d:newrow(); d:button{text='建立控制柄',onclick=alert(function()
  local n=path.nodes[selected]; if n then remember(); local v=math.max(2,math.min(s.width,s.height)/8); n.ix=-v; n.iy=0; n.ox=v; n.oy=0; changed() end
 end)}
 d:button{text='轉為尖角',onclick=function() local n=path.nodes[selected]; if n then remember(); n.ix=0;n.iy=0;n.ox=0;n.oy=0;n.smooth=false;changed() end end}
 d:button{text='刪除錨點',onclick=function() if path.nodes[selected] then remember(); table.remove(path.nodes,selected); selected=math.min(selected,#path.nodes); changed() end end}
 d:newrow(); d:button{id='undo',text='復原路徑',onclick=function() undoPath(true) end}; d:button{id='redo',text='重做路徑',onclick=function() undoPath(false) end}
 d:button{text='縮放還原',onclick=function() zoom=1;panx=0;pany=0;d:repaint() end}
 d:newrow(); d:check{id='background',text='顯示作品參考',selected=true,onclick=function() d:repaint() end}
 d:check{id='handles',text='顯示錨點與控制柄',selected=true,onclick=function() d:repaint() end}
 d:newrow(); d:label{text='點擊新增；拖拉出柄；Alt 拖柄獨立調整；中鍵平移'}
 d:newrow(); d:button{id='apply',text='確認套用',onclick=alert(function() C.apply(s,target,path,d.data.name); d:close() end)}
 d:button{text='取消',onclick=function() d:close() end}
 rebuild(); sync(); d:show{wait=false}
 return {dialog=d,getPath=function() return path end,down=down,move=move,up=up,paint=paint,view=view,undo=undoPath}
end
function init(plugin)
 root=plugin.path; C=dofile(app.fs.joinPath(root,'core.lua'))
 plugin:newCommand{id='BezierPenNew',title='貝茲鋼筆：新增路徑…',group='cel_popup_properties',onclick=alert(function() openEditor(false) end)}
 plugin:newCommand{id='BezierPenEdit',title='貝茲鋼筆：編輯此路徑…',group='cel_popup_properties',onclick=alert(function() openEditor(true) end)}
end
function exit(plugin) if active then active:close();active=nil end end
if BEZIER_TEST then
 C=dofile(app.fs.joinPath(BEZIER_TEST_ROOT,'core.lua'))
 BEZIER_TEST({core=C,open=openEditor})
end
