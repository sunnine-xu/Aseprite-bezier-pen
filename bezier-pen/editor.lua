local root,C,Shapes
local prefs={}
local defaults={zoom=6400,width=300,weight=1000,nodes=256,paths=64}
local caps={zoom=64000,width=10000,weight=10000,nodes=16384,paths=1024}
local function loadPreferences()
 for k,v in pairs(defaults) do local n=tonumber(prefs[k]);C.limits[k]=n and math.max(1,math.min(caps[k],math.floor(n))) or v end
end
local curveClipboard
local active
local function alert(fn)
 return function(...)
  local ok,err=pcall(fn,...)
  if not ok then app.alert{title='貝茲鋼筆',text=tostring(err)} end
 end
end
local function reference(s,target,frame)
 local oldLayer=app.layer
 local oldFrame=app.frame
 local copy=Sprite(s)
 local function hide(a,b)
  for i,l in ipairs(a) do
   if l==target then b[i].isVisible=false end
   if l.isGroup then hide(l.layers,b[i].layers) end
  end
 end
 hide(s.layers,copy.layers)
 local img=Image(s.width,s.height,ColorMode.RGB);img:drawSprite(copy,frame); copy:close(); app.sprite=s; app.layer=oldLayer;app.frame=oldFrame
 return img
end
local function resizePrompt(source,s,target,frame)
 local dlg;local ax,ay=0.5,0.5;local candidate,preview;local ready=false
 local background=reference(s,target,frame)
 local vw,vh=400,240;local zoom=nil;local panx,pany=0,0;local panDrag;local settingZoom=false
 local curveBox,screenBox;local curveDrag;local settingOffsets=false;local autoAll=true
 local function bounds()
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,child in ipairs(candidate.paths or {candidate}) do if #child.nodes>0 then
   local a,b,c,d=C.pathBounds(child);x0=math.min(x0,a);y0=math.min(y0,b);x1=math.max(x1,c);y1=math.max(y1,d)
  end end
  if x0~=math.huge then return {x0,y0,x1,y1} end
 end
 local function fit() return math.max(0.01,math.min(C.limits.zoom/100,math.min((vw-16)/s.width,(vh-16)/s.height))) end
 local function zoomText()
  settingZoom=true;dlg:modify{id='previewZoom',text=string.format('%.2f',(zoom or fit())*100)};settingZoom=false
 end
 local function showAll()
  local b=curveBox or {0,0,s.width,s.height}
  local x0,y0=math.min(0,b[1]),math.min(0,b[2]);local x1,y1=math.max(s.width,b[3]),math.max(s.height,b[4])
  zoom=math.max(0.01,math.min(C.limits.zoom/100,math.min((vw-36)/math.max(1,x1-x0),(vh-36)/math.max(1,y1-y0))))
  panx=(s.width/2-(x0+x1)/2)*zoom;pany=(s.height/2-(y0+y1)/2)*zoom
  zoomText()
 end
 local function setZoom(value,x,y)
  autoAll=false
  if not value or value~=value then return end
  local old=zoom or fit();value=math.max(0.01,math.min(C.limits.zoom/100,value))
  x,y=x or vw/2,y or vh/2
  panx=(x-vw/2)+(panx-(x-vw/2))*value/old
  pany=(y-vh/2)+(pany-(y-vh/2))*value/old
  zoom=value;zoomText();dlg:repaint()
 end
 local function update()
  if not ready or settingOffsets then return end
  local scaling=dlg.data.mode=='依新尺寸縮放'
  local dx,dy=tonumber(dlg.data.offsetX),tonumber(dlg.data.offsetY)
  if not dx or not dy or dx~=dx or dy~=dy or math.abs(dx)>1000000 or math.abs(dy)>1000000 then
   candidate=nil;dlg:modify{id='status',text='請輸入有效的 X／Y（±1000000 px 內）'};dlg:modify{id='accept',enabled=false};return
  end
  local tx,ty=0,0
  if scaling then candidate=C.resize(source,s.width,s.height,true,dlg.data.lineWidth)
  else candidate,tx,ty=C.reposition(source,s.width,s.height,ax,ay,dx,dy) end
  local range=math.max(source.canvasWidth,source.canvasHeight,s.width,s.height)*2
  settingOffsets=true
  dlg:modify{id='offsetX',min=-math.ceil(math.max(range,math.abs(dx))),max=math.ceil(math.max(range,math.abs(dx)))}
  dlg:modify{id='offsetY',min=-math.ceil(math.max(range,math.abs(dy))),max=math.ceil(math.max(range,math.abs(dy)))}
  settingOffsets=false
  curveBox=bounds();if autoAll then showAll() end
  preview=Image(background);local img,pos=C.raster(candidate,s.width,s.height);preview:drawImage(img,pos)
  dlg:modify{id='status',text=scaling and '預覽：依新尺寸縮放' or string.format('平移 X：%g　Y：%g px；曲線與線寬維持原尺寸',tx,ty)}
  dlg:modify{id='lineWidth',enabled=scaling};dlg:modify{id='offsetX',enabled=not scaling};dlg:modify{id='offsetY',enabled=not scaling}
  for i=1,9 do dlg:modify{id='anchor'..i,enabled=not scaling} end
  dlg:modify{id='accept',enabled=true};dlg:repaint()
 end
 dlg=Dialog{title='作品尺寸已改變'}
 dlg:label{text=source.canvasWidth..' × '..source.canvasHeight..' → '..s.width..' × '..s.height}
 dlg:newrow();dlg:combobox{id='mode',label='路徑處理',options={'只平移（保留曲線尺寸）','依新尺寸縮放'},option='只平移（保留曲線尺寸）',onchange=update}
 dlg:newrow();dlg:label{text='九宮格：新舊畫布對齊位置（預設中央）'}
 local names={'左上','上中','右上','左中','中央','右中','左下','下中','右下'}
 for row=0,2 do
  dlg:newrow()
  for col=0,2 do
   local x,y=col/2,row/2;local index=row*3+col+1
   dlg:button{id='anchor'..index,text=(index==5 and '● ' or '')..names[index],onclick=function()
    ax,ay=x,y
    for i=1,9 do dlg:modify{id='anchor'..i,text=(i==index and '● ' or '')..names[i]} end
    update()
   end}
  end
 end
 dlg:newrow();dlg:slider{id='offsetX',label='額外 X px',value=0,min=-1000000,max=1000000,onchange=update}
 dlg:newrow();dlg:slider{id='offsetY',label='額外 Y px',value=0,min=-1000000,max=1000000,onchange=update}
 dlg:newrow();dlg:check{id='lineWidth',text='縮放時一起縮放線寬',selected=false,onclick=update}
 dlg:newrow();dlg:number{id='previewZoom',label='預覽縮放 %',text='100',decimals=2,onchange=function()
  if not settingZoom then setZoom(tonumber(dlg.data.previewZoom) and tonumber(dlg.data.previewZoom)/100) end
 end}
 dlg:newrow();dlg:button{id='previewFit',text='適合視窗',onclick=function() autoAll=false;zoom=nil;panx,pany=0,0;zoomText();dlg:repaint() end}
 dlg:button{id='preview100',text='100%',onclick=function() setZoom(1) end}
 dlg:button{id='previewAll',text='顯示作品與曲線',onclick=function() autoAll=true;showAll();dlg:repaint() end}
 dlg:newrow();dlg:canvas{id='resizePreview',width=400,height=240,onpaint=function(ev)
  local g=ev.context;vw,vh=g.width,g.height;if autoAll then showAll() end
  g.color=Color{r=110,g=110,b=110};g:fillRect(Rectangle(0,0,vw,vh))
  if preview then local z=zoom or fit();local w,h=s.width*z,s.height*z
   g:drawImage(preview,Rectangle(0,0,s.width,s.height),Rectangle((vw-w)/2+panx,(vh-h)/2+pany,w,h))
   local function xy(x,y) return (vw-w)/2+panx+(x+.5)*z,(vh-h)/2+pany+(y+.5)*z end
   g.color=Color{r=80,g=210,b=255}
   for _,child in ipairs(candidate.paths or {candidate}) do
    for _,seg in ipairs(C.segments(child)) do
     local a,b=child.nodes[seg[1]],child.nodes[seg[2]]
     g:beginPath();g:moveTo(xy(a.x,a.y))
     local x1,y1=xy(a.x+a.ox,a.y+a.oy);local x2,y2=xy(b.x+b.ix,b.y+b.iy);local x3,y3=xy(b.x,b.y)
     g:cubicTo(x1,y1,x2,y2,x3,y3);g:stroke()
    end
   end
   screenBox=nil
   if curveBox then
    local x0,y0=xy(curveBox[1],curveBox[2]);local x1,y1=xy(curveBox[3],curveBox[4])
    screenBox={x0-6,y0-6,math.max(12,x1-x0+12),math.max(12,y1-y0+12)}
    g.color=Color{r=255,g=215,b=60};g:strokeRect(Rectangle(screenBox[1],screenBox[2],screenBox[3],screenBox[4]))
   end
  end
 end,onwheel=function(ev)
  if ev.deltaY~=0 then setZoom((zoom or fit())*(ev.deltaY<0 and 1.2 or 1/1.2),ev.x,ev.y) end
 end,onmousedown=function(ev)
  if ev.button==MouseButton.MIDDLE or (ev.button==MouseButton.LEFT and ev.spaceKey) then autoAll=false;panDrag={x=ev.x,y=ev.y,px=panx,py=pany}
  elseif ev.button==MouseButton.LEFT and dlg.data.mode~='依新尺寸縮放' and screenBox and ev.x>=screenBox[1] and ev.x<=screenBox[1]+screenBox[3] and ev.y>=screenBox[2] and ev.y<=screenBox[2]+screenBox[4] then
   autoAll=false;curveDrag={x=ev.x,y=ev.y,dx=tonumber(dlg.data.offsetX),dy=tonumber(dlg.data.offsetY),z=zoom or fit()}
  end
 end,onmousemove=function(ev)
  if curveDrag then
   local dx=math.max(-1000000,math.min(1000000,math.floor(curveDrag.dx+(ev.x-curveDrag.x)/curveDrag.z+.5)))
   local dy=math.max(-1000000,math.min(1000000,math.floor(curveDrag.dy+(ev.y-curveDrag.y)/curveDrag.z+.5)))
   settingOffsets=true;dlg:modify{id='offsetX',min=-math.max(1000,math.abs(dx)),max=math.max(1000,math.abs(dx)),value=dx};dlg:modify{id='offsetY',min=-math.max(1000,math.abs(dy)),max=math.max(1000,math.abs(dy)),value=dy};settingOffsets=false;update()
  end
  if panDrag then panx=panDrag.px+ev.x-panDrag.x;pany=panDrag.py+ev.y-panDrag.y;dlg:repaint() end
 end,onmouseup=function(ev)
  if curveDrag then
   local dx=math.max(-1000000,math.min(1000000,math.floor(curveDrag.dx+(ev.x-curveDrag.x)/curveDrag.z+.5)))
   local dy=math.max(-1000000,math.min(1000000,math.floor(curveDrag.dy+(ev.y-curveDrag.y)/curveDrag.z+.5)))
   settingOffsets=true;dlg:modify{id='offsetX',min=-math.max(1000,math.abs(dx)),max=math.max(1000,math.abs(dx)),value=dx};dlg:modify{id='offsetY',min=-math.max(1000,math.abs(dy)),max=math.max(1000,math.abs(dy)),value=dy};settingOffsets=false;update()
  end
  curveDrag=nil
  if panDrag then panx=panDrag.px+ev.x-panDrag.x;pany=panDrag.py+ev.y-panDrag.y;panDrag=nil;dlg:repaint() end
 end}
 dlg:newrow();dlg:label{text='拖曳黃色框移動曲線；藍線含畫布外路徑；中鍵拖曳視角'}
 dlg:newrow();dlg:label{id='status',text=''}
 dlg:newrow();dlg:button{id='accept',text='繼續編輯'};dlg:button{text='取消'}
 ready=true;update();zoomText();dlg:show()
 if dlg.data.accept then return candidate end
end
local function openEditor(editExisting)
 assert(not active,'請先完成或取消目前的路徑編輯。')
 local s=app.sprite
 assert(s and s.colorMode==ColorMode.RGB,'請先開啟 RGB 作品。')
 local editFrame=(app.frame and app.frame.frameNumber) or 1
 local frameCount=#s.frames
 local target=editExisting and app.layer or nil
 local path=editExisting and C.read(target,editFrame) or C.new(s.width,s.height,app.fgColor)
 assert(not editExisting or (target and target.properties[C.KEY]),'請選取由本插件建立的路徑圖層。')
 if path.canvasWidth~=s.width or path.canvasHeight~=s.height then
  path=resizePrompt(path,s,target,editFrame)
  if not path then return end
 end
 local document=C.collection(path)
 local current=1
 path=document.paths[current]
 for _,child in ipairs(document.paths) do child.fillColor=child.fillColor or C.clone(child.color) end
 local backdrop=reference(s,target,editFrame)
 local d,selected,drag= nil,0,nil
 local picked={}
 local itemSelection={}
 local penTip=nil
 local history,redo={},{}
 local raster,origin
 local zoom,panx,pany=nil,0,0
 local canvasWidth,canvasHeight=440,260
 local suppress=false
 local fullscreen=false
 local normalBounds
 local toggleFullscreen
 local autosaveTimer
 local configureAutosave
 local refreshSections
 local function fitScale() return math.max(0.01,math.min(C.limits.zoom/100,math.min((canvasWidth-24)/s.width,(canvasHeight-24)/s.height))) end
 local function setZoom(value,cx,cy)
  if drag then return end
  value=math.max(0.01,math.min(C.limits.zoom/100,value))
  local old=zoom or fitScale()
  cx,cy=cx or canvasWidth/2,cy or canvasHeight/2
  panx=(cx-canvasWidth/2)*(1-value/old)+panx*value/old
  pany=(cy-canvasHeight/2)*(1-value/old)+pany*value/old
  zoom=value
  if d then
   suppress=true;d:modify{id='zoom',text=string.format('%.0f',zoom*100)};suppress=false;d:repaint()
  end
 end
 local view={scale=1,x=0,y=0}
 local function remember()
  history[#history+1]={document=C.clone(document),current=current,selected=selected,picked=C.clone(picked),items=C.clone(itemSelection)}; if #history>64 then table.remove(history,1) end; redo={}
 end
 local function rebuild() C.resolve(document);path=document.paths[current];raster,origin=C.raster(document,s.width,s.height) end
 local function sync()
  if not d then return end
  suppress=true
  local n=path.nodes[selected]
  local options={}
  for _,i in ipairs(C.order(document)) do local child=document.paths[i];options[#options+1]='路徑 '..i..(child.name and '：'..child.name or '')..'（'..#child.nodes..' 點）'..(C.link(document,i) and ' ← 路徑 '..C.link(document,i).source or '') end
  local option;for _,text in ipairs(options) do if tonumber(text:match('^路徑 (%d+)'))==current then option=text end end
  d:modify{id='paths',options=options,option=option}
  d:modify{id='pathName',text=path.name or ''}
  local order=C.order(document);local at;for j,i in ipairs(order) do if i==current then at=j end end
  d:modify{id='forward',enabled=at<#order};d:modify{id='backward',enabled=at>1}
  d:modify{id='deletePath',enabled=#document.paths>1 or #path.nodes>0}
  d:modify{id='addPath',enabled=#document.paths<C.limits.paths}
  d:modify{id='copyPath',enabled=#path.nodes>0 and #document.paths<C.limits.paths}
  d:modify{id='mirrorX',enabled=#path.nodes>0}
  d:modify{id='mirrorY',enabled=#path.nodes>0}
  d:modify{id='pointStatus',text=n and ('錨點 '..selected..' / '..#path.nodes) or ('共 '..#path.nodes..' 個錨點')}
  d:modify{id='smooth',selected=n and n.smooth or false,enabled=n~=nil}
  d:modify{id='weight',max=math.max(C.limits.weight,n and math.ceil(n.weight) or 100),value=n and n.weight or 100,enabled=n~=nil}
  d:modify{id='width',max=math.max(C.limits.width,math.ceil(path.width)),value=path.width}
  d:modify{id='closed',selected=path.closed}
  d:modify{id='lineStyle',option=path.lineStyle=='dash' and '虛線' or '實線'}
  for i=1,4 do d:modify{id='dash'..i,text=tostring((path.dash or {4,8,4,8})[i]),enabled=not C.link(document,current)} end
  d:modify{id='fill',selected=path.fill or false}
  d:modify{id='stroke',selected=path.stroke~=false}
  local activeRun
  for _,r in ipairs(C.runs(path)) do for i=r.first,r.last do if picked[i] then activeRun=r;break end end;if activeRun then break end end
  local fc=(activeRun and activeRun.fillColor) or path.fillColor or path.color
  local sc=(activeRun and activeRun.color) or path.color
  d:modify{id='colorScope',text=activeRun and '改色：所選錨點所在的整段線（多色顯示第一段）' or '改色：路徑預設色'}
  d:modify{id='fillColor',color=Color{r=fc.r,g=fc.g,b=fc.b,a=fc.a}}
  d:modify{id='strokeColor',color=Color{r=sc.r,g=sc.g,b=sc.b,a=sc.a}}
  d:modify{id='undo',enabled=#history>0}; d:modify{id='redo',enabled=#redo>0}
  local link=C.link(document,current)
  d:modify{id='linkStatus',text=link and ('連動鏡像：跟隨路徑 '..link.source..'；請編輯原曲線或解除連動。') or '獨立路徑：可以直接編輯'}
  d:modify{id='detachMirror',enabled=link~=nil};d:modify{id='editSource',enabled=link~=nil}
  for _,id in ipairs({'width','closed','fill','stroke','fillColor','strokeColor','makeHandle','corner','removeNode','mirrorX','mirrorY'}) do d:modify{id=id,enabled=not link} end
  d:modify{id='mirrorX',enabled=not link and #path.nodes>0};d:modify{id='mirrorY',enabled=not link and #path.nodes>0}
  d:modify{id='smooth',enabled=not link and n~=nil};d:modify{id='weight',enabled=not link and n~=nil}
  local total=0;for i in pairs(picked) do if path.nodes[i] then total=total+1 end end
  if total>1 then
   d:modify{id='pointStatus',text='已選取 '..total..' 個錨點；拖曳任一已選錨點一起移動'}
   for _,id in ipairs({'smooth','weight','makeHandle','corner'}) do d:modify{id=id,enabled=false} end
  end
  d:modify{id='transformPath',enabled=not link and #path.nodes>0}
  d:modify{id='shapeSides',visible=d.data.tool=='多邊形' or d.data.tool=='星形'}
  d:modify{id='starDepth',visible=d.data.tool=='星形'}
  local itemCount=0;for _ in pairs(itemSelection) do itemCount=itemCount+1 end
  if itemCount>1 then d:modify{id='pointStatus',text='已選取 '..itemCount..' 個路徑：共同控制框可移動、縮放、旋轉；其他設定作用於目前路徑'} end
  if refreshSections then refreshSections() end
  suppress=false; d:repaint()
 end
 local function changed()
  if next(itemSelection) and not next(picked) then itemSelection={} end
  rebuild(); sync()
 end
 local function undoPath(back)
  local from,to=back and history or redo,back and redo or history
  if #from==0 then return end
  to[#to+1]={document=C.clone(document),current=current,selected=selected,picked=C.clone(picked),items=C.clone(itemSelection)}
  local saved=table.remove(from);document=saved.document;current=saved.current
  path=document.paths[current];selected=math.min(saved.selected,#path.nodes);picked=saved.picked or {};itemSelection=saved.items or {};penTip=nil;drag=nil;changed()
 end
 local function selectPath(index)
  itemSelection={};penTip=nil
  if drag or not document.paths[index] then return end
  current=index;path=document.paths[current];selected=0;picked={};sync()
 end
 local function addPath()
  itemSelection={}
  if drag then return end
  assert(#document.paths<C.limits.paths,'已達路徑數量上限，可在偏好設定調整。')
  remember()
  local fresh=C.clone(path);fresh.nodes={};fresh.runs=nil;fresh.version=1;fresh.name=nil;penTip=nil
  document.paths[#document.paths+1]=fresh;current=#document.paths;path=fresh;selected=0;picked={}
  d:modify{id='tool',option='鋼筆：新增錨點'};changed()
 end
 local function deletePath()
  if drag then return end
  remember();itemSelection={}
  if #document.paths==1 then path.nodes={};path.runs=nil;path.version=1
  else C.removePath(document,current);current=math.min(current,#document.paths);path=document.paths[current] end
  selected=0;picked={};penTip=nil;changed()
 end
 local function colorSelection(key,c)
  if suppress or C.link(document,current) then return end
  remember();local color={r=c.red,g=c.green,b=c.blue,a=c.alpha}
  if next(picked) then
   if not path.runs then path.runs=C.clone(C.runs(path));path.version=5 end
   for _,r in ipairs(path.runs) do for i=r.first,r.last do if picked[i] then r[key]=C.clone(color);break end end end
  else path[key]=color end
  changed()
 end
 local function copyCurve(cut)
  if drag then return end
  local chosen=C.clone(picked)
  assert(next(chosen),'請先用選取或框選工具選中錨點。')
  assert(not cut or not C.link(document,current),'連動鏡像不能直接剪下，請先解除連動或編輯來源。')
  C.resolve(document)
  local copy=C.clone(document.paths[current]);local excluded={}
  for i in ipairs(copy.nodes) do if not chosen[i] then excluded[i]=true end end
  C.cutNodes(copy,excluded);assert(#copy.nodes>0,'沒有選中的錨點。');curveClipboard=copy
  if cut then remember();C.cutNodes(path,chosen);selected=0;picked={};penTip=nil;changed() end
 end
 local function pasteCurve()
  if drag then return end
  assert(curveClipboard,'尚未複製曲線；請先在鋼筆編輯器按複製。')
  assert(not C.link(document,current),'請先解除鏡像連動或選擇可編輯的路徑。')
  assert(#path.nodes+#curveClipboard.nodes<=C.limits.nodes,'貼上後超過錨點上限，請調整偏好設定。')
  local fresh=C.clone(curveClipboard);fresh.canvasWidth=s.width;fresh.canvasHeight=s.height;C.validate(fresh)
  remember();local offset=#path.nodes
  if offset==0 then
   fresh.name=path.name;document.paths[current]=fresh;path=fresh
  else
   local runs=C.clone(C.runs(path))
   for _,r in ipairs(C.runs(fresh)) do
    local copy=C.clone(r);copy.first=copy.first+offset;copy.last=copy.last+offset
    copy.color=C.clone(r.color or fresh.color);copy.fillColor=C.clone(r.fillColor or fresh.fillColor or fresh.color)
    runs[#runs+1]=copy
   end
   for _,n in ipairs(fresh.nodes) do path.nodes[#path.nodes+1]=C.clone(n) end
   path.runs=runs;path.version=5;path.closed=true
   for _,r in ipairs(runs) do if not r.closed then path.closed=false end end
  end
  selected=offset+1;picked={};penTip=nil;for i=offset+1,#path.nodes do picked[i]=true end
  d:modify{id='tool',option='框選錨點'};changed()
 end
 local function copyOrMirror(axis)
  penTip=nil
  if drag then return end
  assert(#path.nodes>0,'請先建立路徑。')
  assert(not axis or not C.link(document,current),'請先編輯原曲線，或解除連動。')
  local live=axis and d.data.liveMirror
  local sourceIndex=current
  local duplicate=not axis or d.data.mirrorCopy or live
  assert(not duplicate or #document.paths<C.limits.paths,'已達路徑數量上限，可在偏好設定調整。')
  local fixedSum
  if axis and d.data.mirrorBase=='自訂中線' then
   local value=tonumber(axis=='x' and d.data.mirrorAxisX or d.data.mirrorAxisY)
   local limit=axis=='x' and s.width or s.height
   assert(value and value==value and value>=-0.5 and value<=limit-0.5,'中線需位於作品範圍內（-0.5 到 '..(limit-0.5)..'）。')
   fixedSum=value*2
  end
  local copy=axis and C.mirror(path,axis,d.data.mirrorBase=='目前路徑中心' and 'path' or 'canvas',fixedSum) or C.clone(path)
  if duplicate and copy.name then copy.name=copy.name..' 副本';if #copy.name>240 then copy.name=nil end end
  remember()
  if duplicate then document.paths[#document.paths+1]=copy;current=#document.paths
  else document.paths[current]=copy end
  if live then
   document.version=document.order and 4 or 3;document.links=document.links or {}
   local a,b=path.nodes[1],copy.nodes[1]
   document.links[tostring(current)]={source=sourceIndex,axis=axis,sum=a[axis]+b[axis]}
   current=sourceIndex;path=document.paths[current]
  else path=copy end
  selected=0;picked={}
  if not axis then d:modify{id='tool',option='移動整條路徑'} end
  changed()
 end
 local function renamePath()
  if drag then return end
  local name=(d.data.pathName or ''):match('^%s*(.-)%s*$')
  assert(#name<=240,'路徑名稱過長，請縮短名稱。')
  if name=='' then name=nil end
  if path.name~=name then remember();path.name=name;changed() end
 end
 local function reorderPath(delta)
  if drag then return end
  local copy=C.clone(document)
  if C.reorder(copy,current,delta) then remember();document=copy;path=document.paths[current];changed() end
 end
 local function transformPath()
  if drag or C.link(document,current) or #path.nodes==0 then return end
  local before=C.clone(document);local index=current;local original=C.clone(path)
  local committed=false;local valid=true;local t
  local function restore() document=C.clone(before);current=index;path=document.paths[current];changed() end
  local function preview()
   local angle,sx,sy=tonumber(t.data.angle),tonumber(t.data.scaleX),tonumber(t.data.scaleY)
   local ok,result=pcall(function()
    assert(angle and sx and sy and sx>=1 and sx<=1000 and sy>=1 and sy<=1000,'縮放請輸入 1–1000%。')
    return C.transform(original,angle,sx/100,sy/100,t.data.pivot=='作品中心' and 'canvas' or 'path')
   end)
   valid=ok
   t:modify{id='transformStatus',text=ok and '預覽中：確認保留，取消還原。線寬維持原設定。' or tostring(result)}
   if ok then document.paths[index]=result;path=result;changed() end
  end
  t=Dialog{title='旋轉／縮放目前路徑',parent=d,onclose=function() if not committed then restore() end end}
  t:combobox{id='pivot',label='中心',options={'目前路徑中心','作品中心'},option='目前路徑中心',onchange=preview}
  t:number{id='angle',label='順時針角度',text='0',decimals=2,onchange=preview}
  t:number{id='scaleX',label='水平縮放 %',text='100',decimals=2,onchange=preview}
  t:number{id='scaleY',label='垂直縮放 %',text='100',decimals=2,onchange=preview}
  t:label{id='transformStatus',text='預覽中：確認保留，取消還原。線寬維持原設定。'}
  t:button{id='acceptTransform',text='確認變形',onclick=function()
   preview();if not valid then return end
   local result=C.clone(document);document=before;path=document.paths[index];remember()
   document=result;path=document.paths[index];committed=true;changed();t:close()
  end}
  t:button{text='取消',onclick=function() t:close() end}
  t:show{wait=true};return t
 end
 local function applyDocument()
  local result=C.compact(document)
  if #result.paths==0 then
   assert(target,'請先畫出或貼上曲線。')
   assert(s.isValid and #s.frames==frameCount,'影格已變更，請重新開啟。')
   local exists=false;local function find(layers) for _,l in ipairs(layers) do if l==target then exists=true end;if l.isGroup then find(l.layers) end end end;find(s.layers);assert(exists,'原圖層已刪除。')
   app.transaction('清空此幀曲線',function()
    local cel=target:cel(editFrame);if cel then s:deleteCel(cel) end
    if editFrame==1 then target.properties[C.KEY]=json.encode({version=6,perFrame=true}) end
   end)
   app.refresh();d:close();return
  end
  assert(#s.frames==frameCount,'影格數量已改變，請取消後重新開啟。')
  C.apply(s,target,#result.paths==1 and result.paths[1] or result,d.data.name,editFrame)
  d:close()
 end
 local function canvasPoint(ev)
  return (ev.x-view.x)/view.scale-0.5,(ev.y-view.y)/view.scale-0.5
 end
 local function screen(x,y) return view.x+(x+0.5)*view.scale,view.y+(y+0.5)*view.scale end
 local function hit(ev,anchorsOnly)
  local n=path.nodes[selected]
  if n and not anchorsOnly then
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
 local function selectionFrame()
  if (d.data.tool~='框選錨點' and d.data.tool~='選取：只移動') or C.link(document,current) or not d.data.handles then return end
  local count=0;local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for i in pairs(picked) do local n=path.nodes[i];if n then count=count+1;x0=math.min(x0,n.x);y0=math.min(y0,n.y);x1=math.max(x1,n.x);y1=math.max(y1,n.y) end end
  for index in pairs(itemSelection) do if index~=current and document.paths[index] and not C.link(document,index) then
   for _,n in ipairs(document.paths[index].nodes) do count=count+1;x0=math.min(x0,n.x);y0=math.min(y0,n.y);x1=math.max(x1,n.x);y1=math.max(y1,n.y) end
  end end
  if count<2 then return end
  if x1-x0<1/view.scale then local mid=(x0+x1)/2;x0=mid-0.5/view.scale;x1=mid+0.5/view.scale end
  if y1-y0<1/view.scale then local mid=(y0+y1)/2;y0=mid-0.5/view.scale;y1=mid+0.5/view.scale end
  return {x0=x0,y0=y0,x1=x1,y1=y1,cx=(x0+x1)/2,cy=(y0+y1)/2}
 end
 local function frameHandles(b)
  local a,c=screen(b.x0,b.y0);local e,f=screen(b.x1,b.y1)
  a=a-9;c=c-9;e=e+9;f=f+9
  return {{a,c,-1,-1},{(a+e)/2,c,0,-1},{e,c,1,-1},{e,(c+f)/2,1,0},{e,f,1,1},{(a+e)/2,f,0,1},{a,f,-1,1},{a,(c+f)/2,-1,0},{(a+e)/2,c-24,0,0,'rotate'}}
 end
 local function frameHit(ev)
  local b=selectionFrame();if not b then return end
  for _,h in ipairs(frameHandles(b)) do
   if (h[1]-ev.x)^2+(h[2]-ev.y)^2<=36 then return b,h end
  end
 end
 local shapeTools={['直線']=true,['長方形']=true,['圓形']=true,['三角形']=true,['多邊形']=true,['星形']=true}
 local function down(ev)
  if ev.button==MouseButton.LEFT and ev.x>=canvasWidth-28 and ev.y>=canvasHeight-28 then toggleFullscreen();return end
  if ev.button==MouseButton.MIDDLE or ev.spaceKey then drag={kind='pan',x=ev.x,y=ev.y,px=panx,py=pany}; return end
  if ev.button~=MouseButton.LEFT then return end
  local x,y=canvasPoint(ev)
  if shapeTools[d.data.tool] then
   if C.link(document,current) then return end
   local sides=tonumber(d.data.shapeSides);local depth=tonumber(d.data.starDepth);local radius=tonumber(d.data.shapeRadius)
   assert(sides and sides%1==0 and sides>=3 and sides<=128,'角數需為 3–128。')
   assert(depth and depth>=1 and depth<=99,'星形深度需為 1–99%。')
   assert(radius and radius>=0 and radius<=10000,'圓角半徑需為 0–10000 px。')
   local count=d.data.tool=='直線' and 2 or (d.data.tool=='圓形' and 4 or (d.data.tool=='長方形' and 4 or (d.data.tool=='三角形' and 3 or sides*(d.data.tool=='星形' and 2 or 1))))
   if radius>0 and d.data.tool~='圓形' and d.data.tool~='直線' then count=count*2 end
   assert(#path.nodes+count<=C.limits.nodes,'新增形狀後超過錨點上限，請調低角數或調整偏好設定。')
   remember();drag={kind='shape',tool=d.data.tool,x=x,y=y,source=C.clone(path),sides=sides,depth=depth,radius=radius};penTip=nil;return
  end
  if d.data.tool=='移除錨點'  then
   if C.link(document,current) then return end
   local i=hit(ev,true)
   if i then remember();C.deleteNodes(path,{[i]=true});penTip=nil;selected=0;picked={};changed() end
   return
  end
  if d.data.tool=='選取：只移動' and not C.link(document,current) then
   local index,side=hit(ev,false)
   if index and side~='anchor' then
    remember();itemSelection={};picked={[index]=true};selected=index;drag={kind=side,x=x,y=y,node=C.clone(path.nodes[index])};return
   end
  end
  if ev.shiftKey and (d.data.tool=='框選錨點' or d.data.tool=='選取：只移動') then
   local order=C.order(document)
   for j=#order,1,-1 do local index=order[j];local candidate=document.paths[index]
    local segment,t,dist=C.nearest(candidate,x,y);local touched=dist and dist<=(7/view.scale)^2
    if not touched then for _,n in ipairs(candidate.nodes) do if (n.x-x)^2+(n.y-y)^2<=(7/view.scale)^2 then touched=true;break end end end
    if not touched and candidate.fill then local im,pos=C.raster(candidate,s.width,s.height);local px,py=math.floor(x+.5)-pos.x,math.floor(y+.5)-pos.y;touched=px>=0 and py>=0 and px<im.width and py<im.height and app.pixelColor.rgbaA(im:getPixel(px,py))>0 end
    if touched then
     if index~=current or next(itemSelection) then
      if C.link(document,index) then app.alert('連動鏡像請選取來源路徑，會隨來源一起更新。');return end
      if not next(itemSelection) and not C.link(document,current) and #path.nodes>0 then itemSelection[current]=true end
      itemSelection[index]=not itemSelection[index] or nil
      if not itemSelection[current] then for k in pairs(itemSelection) do current=k;path=document.paths[k];break end end
      picked={};if itemSelection[current] then for i in ipairs(path.nodes) do picked[i]=true end end
      selected=next(picked) or 0;penTip=nil;sync();return
     end
     break
    end
   end
  end
  local box,handle=frameHit(ev)
  if box then
   remember();drag={kind=handle[5] or 'scale',box=box,handle=handle,source=C.clone(path),sources=C.clone(document),picked=C.clone(picked),items=C.clone(itemSelection),startx=x,starty=y}
   d:repaint();return
  end
  if d.data.tool=='移動整條路徑' and #path.nodes>0 and not C.link(document,current) then
   remember();drag={kind='path',x=x,y=y,source=C.clone(path)};return
  end
  local b=selectionFrame()
  if b and not ev.shiftKey then
   local padding=9/view.scale
   if x>=b.x0-padding and x<=b.x1+padding and y>=b.y0-padding and y<=b.y1+padding then
    remember();drag={kind='nodes',x=x,y=y,source=C.clone(path),sources=C.clone(document),picked=C.clone(picked),items=C.clone(itemSelection)};return
   end
  end
  local i,kind=hit(ev,d.data.tool=='框選錨點' or d.data.tool=='插入錨點')
  if not C.link(document,current) and d.data.tool=='插入錨點' then
   if i then selected=i;picked={[i]=true};sync();return end
   local segment,t,dist=C.nearest(path,x,y)
   if segment and dist<=(9/view.scale)^2 and t>0.00001 and t<0.99999 then
    assert(#path.nodes<C.limits.nodes,'已達錨點上限，可在偏好設定調整。')
    remember();penTip=nil;selected=C.split(path,segment,t);picked={[selected]=true};changed()
   end
   return
  end
  -- In selection mode, click another path's anchors or visible pixels to select it.
  if not i and d.data.tool=='選取：只移動' then
   local drawOrder=C.order(document)
   for orderIndex=#drawOrder,1,-1 do
    local index=drawOrder[orderIndex]
    if index~=current then
     local candidate=document.paths[index];local found
     for j=#candidate.nodes,1,-1 do
      local sx,sy=screen(candidate.nodes[j].x,candidate.nodes[j].y)
      if (sx-ev.x)^2+(sy-ev.y)^2<49 then found=j;break end
     end
     local img,pos=C.raster(candidate,s.width,s.height)
     local px,py=math.floor(x+0.5)-pos.x,math.floor(y+0.5)-pos.y
     local visible=px>=0 and py>=0 and px<img.width and py<img.height and app.pixelColor.rgbaA(img:getPixel(px,py))>0
     if found or visible then
      selectPath(index)
      if found then i,kind=found,'anchor' else return end
      break
     end
    end
   end
  end
  if not C.link(document,current) and (d.data.tool=='框選錨點' or d.data.tool=='選取：只移動') then
   if i and kind=='anchor' then
    if ev.shiftKey then
     if picked[i] then picked[i]=nil else picked[i]=true end
     selected=0;for j in pairs(picked) do selected=j end;sync();return
    end
    if not picked[i] then picked={[i]=true} end
    selected=i;remember();drag={kind='nodes',x=x,y=y,source=C.clone(path),sources=C.clone(document),picked=C.clone(picked),items=C.clone(itemSelection)}
   else
    itemSelection={}
    local base=ev.shiftKey and C.clone(picked) or {}
    drag={kind='box',x=x,y=y,tox=x,toy=y,base=base};picked=C.clone(base);selected=0
   end
   sync();return
  end
  if C.link(document,current) then sync();return end
  if i and kind=='anchor' and d.data.tool=='鋼筆：新增錨點' and C.endpoint(path,i) then
   if penTip and penTip~=i and C.endpoint(path,penTip) then
    remember();C.join(path,penTip,i);penTip=nil;selected=0;picked={};changed();return
   end
   penTip=i
  end
  if i then
   selected=i;picked={[i]=true}; remember()
   drag={kind=kind,x=x,y=y,node=C.clone(path.nodes[i])}
  elseif d.data.tool=='鋼筆：新增錨點' and x>=0 and y>=0 and x<s.width and y<s.height then
   assert(#path.nodes<C.limits.nodes,'已達錨點上限，可在偏好設定調整。')
   remember();selected=C.extend(path,penTip,C.node(x,y));penTip=selected;picked={[selected]=true}
   drag={kind='new',x=x,y=y}
  else selected=0;picked={}; drag=nil end
  changed()
 end
 local function move(ev)
  if not drag then return end
  if drag.kind=='shape' then
   local x,y=canvasPoint(ev)
   if ev.shiftKey then
    local dx,dy=x-drag.x,y-drag.y
    if drag.tool=='直線' then local length=math.sqrt(dx*dx+dy*dy);local angle=math.floor(math.atan(dy,dx)/(math.pi/4)+0.5)*math.pi/4;x=drag.x+math.cos(angle)*length;y=drag.y+math.sin(angle)*length
    else local size=math.max(math.abs(dx),math.abs(dy));x=drag.x+(dx<0 and -size or size);y=drag.y+(dy<0 and -size or size) end
   end
   if math.abs(x-drag.x)+math.abs(y-drag.y)<0.01 then return end
   local shape=Shapes.make(drag.source,drag.tool,drag.x,drag.y,x,y,drag.sides,drag.depth,drag.radius)
   local result=Shapes.append(drag.source,shape);document.paths[current]=result;path=result;picked={};selected=#drag.source.nodes+1
   for i=selected,#path.nodes do picked[i]=true end
   changed();return
  end
  if drag.kind=='pan'  then panx=drag.px+ev.x-drag.x; pany=drag.py+ev.y-drag.y; d:repaint(); return end
  if drag.kind=='scale' or drag.kind=='rotate' then
   local x,y=canvasPoint(ev);local b=drag.box;local h=drag.handle
   local sx,sy=1,1;local co,si=1,0;local px,py=b.cx,b.cy
   if drag.kind=='rotate' then
    local angle=math.atan(y-b.cy,x-b.cx)-math.atan(drag.starty-b.cy,drag.startx-b.cx)
    if ev.shiftKey then angle=math.floor(angle/(math.pi/12)+0.5)*(math.pi/12) end
    co,si=math.cos(angle),math.sin(angle)
   else
    if not ev.ctrlKey then
     px=h[3]<0 and b.x1 or (h[3]>0 and b.x0 or b.cx)
     py=h[4]<0 and b.y1 or (h[4]>0 and b.y0 or b.cy)
    end
    if h[3]~=0 then local anchor=h[3]<0 and b.x0 or b.x1;sx=(anchor+x-drag.startx-px)/(anchor-px) end
    if h[4]~=0 then local anchor=h[4]<0 and b.y0 or b.y1;sy=(anchor+y-drag.starty-py)/(anchor-py) end
    if ev.shiftKey then
     local scale=h[3]==0 and sy or (h[4]==0 and sx or (math.abs(sx-1)>math.abs(sy-1) and sx or sy))
     sx,sy=scale,scale
    end
    local function clamp(v) return math.max(0.01,math.min(100,v)) end
    sx,sy=clamp(sx),clamp(sy)
   end
   local function vector(vx,vy) vx=vx*sx;vy=vy*sy;return vx*co-vy*si,vx*si+vy*co end
   drag.map=function(vx,vy) local dx,dy=vector(vx-px,vy-py);return px+dx,py+dy end
   for i in pairs(drag.picked) do
    local a=drag.source.nodes[i];local n=path.nodes[i]
    n.x,n.y=drag.map(a.x,a.y);n.ix,n.iy=vector(a.ix,a.iy);n.ox,n.oy=vector(a.ox,a.oy)
   end
   for index in pairs(drag.items or {}) do if index~=current and not C.link(document,index) then
    for i,n in ipairs(document.paths[index].nodes) do local a=drag.sources.paths[index].nodes[i];n.x,n.y=drag.map(a.x,a.y);n.ix,n.iy=vector(a.ix,a.iy);n.ox,n.oy=vector(a.ox,a.oy) end
   end end
   changed();return
  end
  if drag.kind=='box'  then
   local x,y=canvasPoint(ev);drag.tox=x;drag.toy=y;picked=C.clone(drag.base);selected=0
   for i,n in ipairs(path.nodes) do
    if n.x>=math.min(x,drag.x) and n.x<=math.max(x,drag.x) and n.y>=math.min(y,drag.y) and n.y<=math.max(y,drag.y) then picked[i]=true end
   end
   for i in pairs(picked) do selected=i end;sync();return
  end
  if drag.kind=='nodes' then
   local x,y=canvasPoint(ev)
   for i in pairs(drag.picked) do local n=path.nodes[i];local a=drag.source.nodes[i];n.x=a.x+x-drag.x;n.y=a.y+y-drag.y end
   for index in pairs(drag.items or {}) do if index~=current and not C.link(document,index) then
    for i,n in ipairs(document.paths[index].nodes) do local a=drag.sources.paths[index].nodes[i];n.x=a.x+x-drag.x;n.y=a.y+y-drag.y end
   end end
   changed();return
  end
  if drag.kind=='path'  then
   local x,y=canvasPoint(ev)
   for i,n in ipairs(path.nodes) do n.x=drag.source.nodes[i].x+x-drag.x;n.y=drag.source.nodes[i].y+y-drag.y end
   changed();return
  end
  local x,y=canvasPoint(ev); local n=path.nodes[selected]
  if not n then return end
  x=math.max(-s.width,math.min(s.width*2,x)); y=math.max(-s.height,math.min(s.height*2,y))
  if drag.kind=='anchor' then n.x=drag.node.x+x-drag.x; n.y=drag.node.y+y-drag.y
  elseif drag.kind=='new' then n.ox=x-n.x; n.oy=y-n.y; n.ix=-n.ox; n.iy=-n.oy
  else C.handle(n,drag.kind,x-n.x,y-n.y,ev.altKey) end
  changed()
 end
 local function up(ev) if drag then move(ev) end; drag=nil;d:repaint() end
 local fullscreenIcon=Image{fromFile=app.fs.joinPath(root or BEZIER_TEST_ROOT,'icons','fullscreen.png')}
 local function drawFullscreen(gc)
  gc.color=Color{r=205,g=205,b=205};gc:fillRect(Rectangle(gc.width-27,gc.height-27,26,26))
  gc:drawImage(fullscreenIcon,Rectangle(0,0,fullscreenIcon.width,fullscreenIcon.height),Rectangle(gc.width-22,gc.height-22,16,16))
 end
 local function paint(ev)
  local gc=ev.context
  gc.color=Color{r=45,g=48,b=55}; gc:fillRect(Rectangle(0,0,gc.width,gc.height))
  canvasWidth,canvasHeight=gc.width,gc.height
  view.scale=zoom or fitScale()
  view.x=(gc.width-s.width*view.scale)/2+panx; view.y=(gc.height-s.height*view.scale)/2+pany
  gc:save(); gc:beginPath(); gc:rect(Rectangle(view.x,view.y,s.width*view.scale,s.height*view.scale)); gc:clip()
  for y=0,gc.height-1,12 do for x=0,gc.width-1,12 do
   local v=(math.floor(x/12)+math.floor(y/12))%2==0 and 190 or 225
   gc.color=Color{r=v,g=v,b=v}; gc:fillRect(Rectangle(x,y,12,12))
  end end
  if d.data.background then gc:drawImage(backdrop,Rectangle(0,0,s.width,s.height),Rectangle(view.x,view.y,s.width*view.scale,s.height*view.scale)) end
  if raster then gc:drawImage(raster,Rectangle(0,0,raster.width,raster.height),Rectangle(view.x+origin.x*view.scale,view.y+origin.y*view.scale,raster.width*view.scale,raster.height*view.scale)) end
  gc:restore()
  -- Guides use source pixel-center coordinates, just like anchors; never rasterized.
  if d.data.mirrorBase=='自訂中線' and d.data.mirrorGuides then
   gc:save();gc:beginPath();gc:rect(Rectangle(view.x,view.y,s.width*view.scale,s.height*view.scale));gc:clip()
   gc.strokeWidth=1
   local x,y=tonumber(d.data.mirrorAxisX),tonumber(d.data.mirrorAxisY)
   if x and x==x and x>=-0.5 and x<=s.width-0.5 then
    local sx=screen(x,0);gc.color=Color{r=30,g=215,b=245,a=220}
    gc:beginPath();gc:moveTo(sx,0);gc:lineTo(sx,gc.height);gc:stroke()
   end
   if y and y==y and y>=-0.5 and y<=s.height-0.5 then
    local _,sy=screen(0,y);gc.color=Color{r=255,g=175,b=55,a=220}
    gc:beginPath();gc:moveTo(0,sy);gc:lineTo(gc.width,sy);gc:stroke()
   end
   gc:restore()
  end
  if drag and drag.kind=='box' then
   local x0,y0=screen(drag.x,drag.y);local x1,y1=screen(drag.tox,drag.toy)
   gc.color=Color{r=70,g=180,b=255,a=45};gc:fillRect(Rectangle(math.min(x0,x1),math.min(y0,y1),math.abs(x1-x0),math.abs(y1-y0)))
   gc.color=Color{r=70,g=180,b=255};gc.strokeWidth=1;gc:strokeRect(Rectangle(math.min(x0,x1),math.min(y0,y1),math.abs(x1-x0),math.abs(y1-y0)))
  end
  if not d.data.handles then drawFullscreen(gc);return end
  gc.antialias=true; gc.strokeWidth=1
  for index,child in ipairs(document.paths) do
   if index~=current then
    gc.color=itemSelection[index] and Color{r=255,g=210,b=60} or Color{r=145,g=155,b=170}
    for _,n in ipairs(child.nodes) do local x,y=screen(n.x,n.y);gc:strokeRect(Rectangle(x-2,y-2,4,4)) end
   end
  end
  -- A thin path skeleton keeps fully transparent/tapered sections selectable.
  gc.color=Color{r=40,g=160,b=255,a=170}; gc:beginPath()
  for _,edge in ipairs(C.segments(path)) do
   local a,b=path.nodes[edge[1]],path.nodes[edge[2]]
   local x,y=screen(a.x,a.y);gc:moveTo(x,y)
   local x1,y1=screen(a.x+a.ox,a.y+a.oy);local x2,y2=screen(b.x+b.ix,b.y+b.iy);local x3,y3=screen(b.x,b.y)
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
   gc.color=(picked[i] or i==selected) and Color{r=255,g=210,b=60} or Color{r=255,g=255,b=255}
   gc:fillRect(Rectangle(x-3,y-3,6,6)); gc.color=Color{r=30,g=95,b=160}; gc:strokeRect(Rectangle(x-3,y-3,6,6))
  end
  local box=selectionFrame()
  if box and (not drag or drag.kind~='box') then
   local handles=frameHandles(box)
   gc.color=Color{r=55,g=175,b=255};gc.strokeWidth=1
   if drag and drag.map then
    local b=drag.box;gc:beginPath()
    for i,v in ipairs({{b.x0,b.y0},{b.x1,b.y0},{b.x1,b.y1},{b.x0,b.y1},{b.x0,b.y0}}) do
     local x,y=drag.map(v[1],v[2]);x,y=screen(x,y);if i==1 then gc:moveTo(x,y) else gc:lineTo(x,y) end
    end;gc:stroke()
   else
    gc:strokeRect(Rectangle(handles[1][1],handles[1][2],handles[5][1]-handles[1][1],handles[5][2]-handles[1][2]))
    gc:beginPath();gc:moveTo(handles[2][1],handles[2][2]);gc:lineTo(handles[9][1],handles[9][2]);gc:stroke()
    for _,h in ipairs(handles) do gc.color=Color{r=255,g=255,b=255};gc:fillRect(Rectangle(h[1]-3,h[2]-3,6,6));gc.color=Color{r=40,g=140,b=230};gc:strokeRect(Rectangle(h[1]-3,h[2]-3,6,6)) end
   end
  end
  drawFullscreen(gc)
 end
 local recoveryDir=app.fs.joinPath(BEZIER_TEST_ROOT and 'work' or app.fs.userConfigPath,'bezier-pen-recovery')
 local recoveryId=tostring(os.time())..'-'..tostring(math.random(100000,999999))
 local recoverySlot=0;local lastSaved
 local function saveRecovery()
  if drag or not s.isValid then return end
  local payload=json.encode({document=document,name=d.data.name,source=s.filename or '',frame=editFrame,layer=target and target.name or ''})
  if payload==lastSaved then return end
  app.fs.makeAllDirectories(recoveryDir)
  local filename=app.fs.joinPath(recoveryDir,recoveryId..'-'..tostring(recoverySlot%2)..'.json')
  local f=assert(io.open(filename,'wb'));local ok,err=f:write(payload);local closed,closeErr=f:close();assert(ok and closed,err or closeErr)
  lastSaved=payload;recoverySlot=recoverySlot+1
  d:modify{id='autosaveStatus',text='已自動備份 '..os.date('%H:%M:%S')}
 end
 configureAutosave=function()
  if autosaveTimer then autosaveTimer:stop();autosaveTimer=nil end
  if prefs.autosave==false then d:modify{id='autosaveStatus',text='自動備份已關閉'};return end
  autosaveTimer=Timer{interval=math.max(1,tonumber(prefs.autosaveSeconds) or 60),ontick=function()
   local ok,err=pcall(saveRecovery)
   if not ok then d:modify{id='autosaveStatus',text='自動備份失敗：'..tostring(err)} end
  end};autosaveTimer:start();d:modify{id='autosaveStatus',text='自動備份已開啟'}
 end
 local function recover()
  local files={}
  if app.fs.isDirectory(recoveryDir) then for _,filename in ipairs(app.fs.listFiles(recoveryDir)) do if filename:match('%.json$') then files[#files+1]=filename end end end
  table.sort(files,function(a,b) return a>b end);assert(#files>0,'目前沒有自動備份。')
  local t=Dialog{title='載入曲線自動備份',parent=d}
  t:combobox{id='file',label='備份檔',options=files,option=files[1]}
  t:label{text='請選原作品的備份；只載入曲線，套用前可取消或復原。'}
  t:button{text='載入',onclick=alert(function()
   local filename=app.fs.joinPath(recoveryDir,t.data.file);local f=assert(io.open(filename,'rb'));local raw=f:read('*a');f:close()
   local data=C.clone(json.decode(raw));local restored=C.collection(data.document)
   assert(restored.canvasWidth==s.width and restored.canvasHeight==s.height,'備份尺寸與目前作品不同。')
   local answer=app.alert{title='確認備份來源',text={'來源：'..(data.source or ''),'圖層：'..(data.layer or ''),'備份影格：'..tostring(data.frame or 1)..'；目前影格：'..editFrame,'要載入到目前編輯器嗎？'},buttons={'載入','取消'}}
   if answer~=1 then return end
   remember();document=restored;current=1;path=document.paths[1];selected=0;picked={};penTip=nil
   d:modify{id='name',text=data.name or '復原曲線'};changed();t:close()
  end)}
  t:button{text='取消',onclick=function() t:close() end};t:show{wait=false}
 end
 d=Dialog{title=target and '編輯貝茲曲線' or '新增貝茲曲線',resizeable=true,autofit=0,onclose=function() if autosaveTimer then autosaveTimer:stop() end;active=nil end}
 active=d
 d:button{id='preferences',text='偏好設定…',onclick=alert(function()
  local t=Dialog{title='偏好設定（記住上限）',parent=d}
  local labels={zoom='縮放上限 %',width='線寬上限 px',weight='錨點線寬上限 %',nodes='每項目錨點上限',paths='每層路徑上限'}
  for _,k in ipairs({'zoom','width','weight','nodes','paths'}) do t:number{id=k,label=labels[k],text=tostring(C.limits[k]),decimals=0} end
  t:check{id='autosave',text='開啟自動備份（未套用的曲線）',selected=prefs.autosave~=false}
  local seconds=tonumber(prefs.autosaveSeconds) or 60
  t:number{id='minutes',label='間隔 分鐘',text=tostring(math.floor(seconds/60)),decimals=0}
  t:number{id='seconds',label='加上 秒',text=tostring(seconds%60),decimals=0}
  t:label{text='降低上限不會刪除既有資料；大量錨點與粗線會增加運算時間。'}
  t:button{text='恢復預設',onclick=function() for k,v in pairs(defaults) do t:modify{id=k,text=tostring(v)} end end}
  t:button{text='儲存',onclick=alert(function()
   local values={}
   for k in pairs(defaults) do local n=tonumber(t.data[k]);assert(n and n%1==0 and n>=1 and n<=caps[k],labels[k]..'：請輸入 1–'..caps[k]);values[k]=n end
   local minutes,seconds=tonumber(t.data.minutes),tonumber(t.data.seconds)
   assert(minutes and seconds and minutes>=0 and minutes<=1440 and seconds>=0 and seconds<=59 and minutes%1==0 and seconds%1==0 and minutes*60+seconds>=1,'間隔請設定至少 1 秒，秒欄為 0–59。')
   prefs.autosave=t.data.autosave;prefs.autosaveSeconds=minutes*60+seconds
   for k,v in pairs(values) do prefs[k]=v end;loadPreferences();sync();configureAutosave();t:close()
  end)}
  t:button{text='取消',onclick=function() t:close() end};t:show{wait=false}
 end)}
 d:button{id='recover',text='載入自動備份…',onclick=alert(recover)}
 d:label{id='autosaveStatus',text='自動備份'}
 d:entry{id='name',label='名稱',hexpand=true,text=target and target.name or '貝茲曲線'}


 d:newrow();d:label{id='editingFrame',text='正在編輯第 '..editFrame..' / '..frameCount..' 幀（只套用此幀）'}
 d:button{id='copyPreviousFrame',text='複製前一幀曲線',enabled=target~=nil and editFrame>1,onclick=alert(function()
  local previous=C.read(target,editFrame-1);assert(previous,'前一幀沒有可編輯的曲線。')
  assert(previous.canvasWidth==s.width and previous.canvasHeight==s.height,'前一幀路徑尺寸不同，請先處理尺寸。')
  if app.alert{title='複製前一幀',text='取代目前編輯器的曲線草稿？可復原。',buttons={'複製','取消'}}~=1 then return end
  remember();document=C.collection(previous);current=1;path=document.paths[1];picked={};selected=0;penTip=nil;changed()
 end)}
 d:newrow();d:button{id='clipboardCopy',text='複製所選錨點',onclick=alert(function() copyCurve(false) end)}
 d:button{id='clipboardCut',text='剪下所選錨點',onclick=alert(function() copyCurve(true) end)}
 d:button{id='clipboardPaste',text='貼上錨點',onclick=alert(pasteCurve)}
 d:newrow();d:combobox{id='paths',label='目前路徑',options={'路徑 1'},option='路徑 1',onchange=function()
  if not suppress then local index=tonumber((d.data.paths or ''):match('^路徑 (%d+)'));if index then selectPath(index) end end
 end}
 d:entry{id='pathName',label='路徑名稱',text=path.name or ''}
 d:button{id='renamePath',text='套用名稱',onclick=alert(renamePath)}
 d:button{id='forward',text='往前一層（覆蓋）',onclick=function() reorderPath(1) end}
 d:button{id='backward',text='往後一層（被覆蓋）',onclick=function() reorderPath(-1) end}
 d:newrow();d:button{id='addPath',text='新增獨立路徑',onclick=alert(addPath)}
 d:button{id='deletePath',text='刪除目前路徑',onclick=alert(deletePath)}
 d:button{id='copyPath',text='複製目前路徑',onclick=alert(function() copyOrMirror() end)}
 local function updateMirrorUI() if refreshSections then refreshSections() end;d:repaint() end
 d:newrow();d:check{id='mirrorSection',text='鏡像設定',selected=false,onclick=updateMirrorUI}
 d:newrow();d:combobox{id='mirrorBase',label='鏡像基準',options={'作品中心','目前路徑中心','自訂中線'},option='作品中心',onchange=updateMirrorUI}
 d:number{id='mirrorAxisX',label='垂直中線 X（左右鏡像）',text=tostring((s.width-1)/2),decimals=2,visible=false,onchange=function() d:repaint() end}
 d:number{id='mirrorAxisY',label='水平中線 Y（上下鏡像）',text=tostring((s.height-1)/2),decimals=2,visible=false,onchange=function() d:repaint() end}
 d:check{id='mirrorGuides',text='顯示中線（青色 X／橘色 Y）',selected=true,visible=false,onclick=function() d:repaint() end}
 d:button{id='centerAxes',text='中線回到作品中心',visible=false,onclick=function()
  d:modify{id='mirrorAxisX',text=tostring((s.width-1)/2)};d:modify{id='mirrorAxisY',text=tostring((s.height-1)/2)};d:repaint()
 end}
 d:label{id='axisHelp',text='座標 0 是首個像素中心；中線設定只影響新建立的鏡像。',visible=false}
 d:check{id='mirrorCopy',text='保留原曲線（鏡像複製）',selected=true}
 d:check{id='liveMirror',text='連動鏡像（持續跟隨原曲線）',selected=false}
 d:newrow();d:label{id='linkStatus',text='獨立路徑：可以直接編輯'}
 d:newrow();d:button{id='editSource',text='編輯原曲線',onclick=function() local link=C.link(document,current);if link then selectPath(link.source) end end}
 d:button{id='detachMirror',text='解除連動',onclick=function()
  if not drag and C.link(document,current) then remember();document.links[tostring(current)]=nil;changed() end
 end}
 d:newrow();d:button{id='mirrorX',text='水平鏡像（左右）',onclick=alert(function() copyOrMirror('x') end)}
 d:button{id='mirrorY',text='垂直鏡像（上下）',onclick=alert(function() copyOrMirror('y') end)}
 d:newrow();
 d:check{id='closed',text='閉合路徑',selected=path.closed,onclick=function() if not suppress and not C.link(document,current) then remember(); C.setClosed(path,d.data.closed); if not path.closed then path.fill=false; path.stroke=true end; changed() end end}

 d:newrow(); d:check{id='stroke',text='描邊',selected=path.stroke~=false,onclick=function()
  if not suppress and not C.link(document,current) then remember(); path.stroke=d.data.stroke; if not path.stroke then path.fill=true; C.setClosed(path,true) end; changed() end
 end}
 d:newrow();d:slider{id='width',label='整體線寬 px',min=1,max=math.max(C.limits.width,math.ceil(path.width)),value=path.width,onchange=function() if not suppress and not C.link(document,current) then remember(); path.width=d.data.width; changed() end end}
 d:label{id='colorScope',text='改色：路徑預設色'}
 d:color{id='strokeColor',label='顏色',color=Color{r=path.color.r,g=path.color.g,b=path.color.b,a=path.color.a},onchange=function()
  colorSelection('color',d.data.strokeColor)
 end}
 d:newrow();d:combobox{id='lineStyle',label='線條樣式',options={'實線','虛線'},option='實線',onchange=function()
  if not suppress and not C.link(document,current) then remember();path.lineStyle=d.data.lineStyle=='虛線' and 'dash' or 'solid';changed() end
 end}
 for i=1,4 do
  d:number{id='dash'..i,label='第 '..i..' 段 '..(i%2==0 and '實線' or '空白')..' px',text=tostring((path.dash or {4,8,4,8})[i]),decimals=1,onchange=alert(function()
   if suppress or C.link(document,current) then return end
   local v=tonumber(d.data['dash'..i]);if not v or v<0.5 or v>10000 then return end
   remember();path.dash=path.dash or {4,8,4,8};path.dash[i]=v;changed()
  end)}
 end
 d:button{id='customStyle',text='自訂線條（預留）',enabled=false}
 d:check{id='fill',text='填色',selected=path.fill or false,onclick=function()
  if not suppress and not C.link(document,current) then remember(); path.fill=d.data.fill; if path.fill then C.setClosed(path,true) else path.stroke=true end; changed() end
 end}
 d:color{id='fillColor',label='填色',color=Color{r=path.fillColor.r,g=path.fillColor.g,b=path.fillColor.b,a=path.fillColor.a},onchange=function()
  colorSelection('fillColor',d.data.fillColor)
 end}
 local toolNames={'鋼筆：新增錨點','插入錨點','移除錨點','框選錨點','選取：只移動','移動整條路徑','直線','長方形','圓形','三角形','多邊形','星形'}
 local toolLabels={'鋼筆','增加錨點','移除錨點','框選','移動錨點','移動路徑','直線','長方形','圓形','三角形','多邊形','星形'}
 local toolImages={}
 for i,name in ipairs({'pen','insert','remove','select','anchor','move','line','rectangle','ellipse','triangle','polygon','star'}) do
  toolImages[i]=Image{fromFile=app.fs.joinPath(root or BEZIER_TEST_ROOT,'icons',name..'.png')}
 end
 d:newrow();d:combobox{id='tool',visible=false,options=toolNames,option='鋼筆：新增錨點'}
 d:newrow();d:number{id='zoom',label='縮放 %',text='100',decimals=0,onchange=function() if not suppress then local v=tonumber(d.data.zoom);if v then setZoom(v/100) end end end}
 d:newrow();d:button{id='zoomFit',text='適合視窗',onclick=function()
  zoom=fitScale();panx=0;pany=0;suppress=true;d:modify{id='zoom',text=string.format('%.0f',zoom*100)};suppress=false;d:repaint()
 end}
 d:button{id='zoomActual',text='100%',onclick=function() setZoom(1) end}
 d:newrow();d:button{id='newRun',text='另起一段線',onclick=function() penTip=nil;selected=0;picked={};drag=nil;d:modify{id='tool',option='鋼筆：新增錨點'};sync() end}
 d:button{id='transformPath',text='旋轉／縮放路徑…',onclick=alert(transformPath)}
 local toolButtonHeight=43
 local toolbarHeight=114
 local toolbarColumns=6
 d:newrow();d:canvas{id='toolbar',width=440,height=114,hexpand=true,vexpand=false,onpaint=function(ev)
  local g=ev.context
  local textHeight=0
  for _,label in ipairs(toolLabels) do textHeight=math.max(textHeight,g:measureText(label).height) end
  toolButtonHeight=23+textHeight+5
  toolbarColumns=math.max(1,math.floor(g.width/72))
  local desiredHeight=math.ceil(#toolImages/toolbarColumns)*(toolButtonHeight+3)+14
  if toolbarHeight~=desiredHeight then toolbarHeight=desiredHeight;d:modify{id='toolbar',height=toolbarHeight} end
  for i,img in ipairs(toolImages) do
   local x=((i-1)%toolbarColumns)*72;local y=math.floor((i-1)/toolbarColumns)*(toolButtonHeight+3)
   g.color=d.data.tool==toolNames[i] and Color{r=170,g=210,b=230} or Color{r=205,g=205,b=205}
   g:fillRect(Rectangle(x,y,70,toolButtonHeight));g.color=Color{r=90,g=90,b=90};g:strokeRect(Rectangle(x,y,70,toolButtonHeight))
   g:drawImage(img,Rectangle(0,0,img.width,img.height),Rectangle(x+27,y+3,16,16))
   g.color=Color{r=30,g=30,b=30};local size=g:measureText(toolLabels[i]);g:fillText(toolLabels[i],x+(70-size.width)/2,y+23)
  end
 end,onmousedown=alert(function(ev)
  if ev.button~=MouseButton.LEFT or ev.y<0 or ev.y>=toolbarHeight-14 or ev.x<0 or ev.y%(toolButtonHeight+3)>=toolButtonHeight then return end
  local column=math.floor(ev.x/72);if column>=toolbarColumns then return end
  local i=math.floor(ev.y/(toolButtonHeight+3))*toolbarColumns+column+1
  if toolNames[i] then itemSelection={};d:modify{id='tool',option=toolNames[i]};penTip=nil;drag=nil;sync() end
 end)}

 d:newrow();d:number{id='shapeSides',label='多邊形／星形角數',text='5',decimals=0}
 d:number{id='starDepth',label='星形深度 %',text='50',decimals=1}
 d:slider{id='shapeRadius',label='圓角半徑 px',min=0,max=1000,value=0}
 d:button{id='roundSelected',text='所選尖角套用圓角',onclick=alert(function()
  if drag or C.link(document,current) then return end
  assert(next(picked),'請先選取直線交接的尖角錨點。')
  local radius=tonumber(d.data.shapeRadius);assert(radius and radius>0,'請先設定大於 0 的圓角半徑。')
  local rounded=Shapes.round(path,radius,picked)
  assert(#rounded.nodes>#path.nodes,'所選點沒有可圓角化的直線轉角；曲線控制柄或線段端點不適用。')
  remember();document.paths[current]=rounded;path=rounded;picked={};selected=0;penTip=nil;changed()
 end)}
 d:newrow();d:canvas{id='canvas',width=440,height=280,hexpand=true,vexpand=true,onpaint=paint,onmousedown=alert(down),onmousemove=alert(move),onmouseup=alert(up),
  onwheel=function(ev) if ev.deltaY~=0 then setZoom((zoom or view.scale)*(ev.deltaY<0 and 1.2 or 1/1.2),ev.x,ev.y) end end,
  onkeydown=alert(function(ev)
   if ev.ctrlKey and (ev.code=='KeyC' or ev.key=='c') then copyCurve(false);ev:stopPropagation();return end
   if ev.ctrlKey and (ev.code=='KeyX' or ev.key=='x') then copyCurve(true);ev:stopPropagation();return end
   if ev.ctrlKey and (ev.code=='KeyV' or ev.key=='v') then pasteCurve();ev:stopPropagation();return end
   if ev.code=='Delete' or ev.key=='Delete' then
    if not C.link(document,current) and next(picked) then remember();C.cutNodes(path,picked);penTip=nil;selected=0;picked={};changed() end
    ev:stopPropagation();return
   end
   if ev.code=='Escape' then penTip=nil end
   if ev.code=='Escape' and fullscreen then toggleFullscreen();ev:stopPropagation();return end
   if ev.ctrlKey and (ev.code=='KeyZ' or ev.key=='z') then
    undoPath(not ev.shiftKey); ev:stopPropagation()
   elseif ev.ctrlKey and (ev.code=='KeyY' or ev.key=='y') then
    undoPath(false); ev:stopPropagation()
   end
  end)}
 d:newrow();
 d:newrow(); d:label{id='pointStatus',text='共 0 個錨點'}
 d:check{id='smooth',text='控制柄平滑連動',selected=true,onclick=function()
  local n=path.nodes[selected]; if n and not suppress and not C.link(document,current) then remember(); n.smooth=d.data.smooth; if n.smooth then C.handle(n,'out',n.ox,n.oy,false) end; changed() end
 end}
 d:newrow();d:slider{id='weight',label='此錨點線寬 %',min=0,max=C.limits.weight,value=100,onchange=function()
  local n=path.nodes[selected]; if n and not suppress and not C.link(document,current) then remember(); n.weight=d.data.weight; changed() end
 end}
 d:newrow(); d:button{id='makeHandle',text='建立控制柄',onclick=alert(function()
  local n=path.nodes[selected]; if n then remember(); local v=math.max(2,math.min(s.width,s.height)/8); n.ix=-v; n.iy=0; n.ox=v; n.oy=0; changed() end
 end)}
 d:button{id='corner',text='轉為尖角',onclick=function() local n=path.nodes[selected]; if n then remember(); n.ix=0;n.iy=0;n.ox=0;n.oy=0;n.smooth=false;changed() end end}
 d:button{id='removeNode',text='刪除所選錨點',onclick=function()
  if C.link(document,current) then return end
  local indices=C.clone(picked);if not next(indices) and path.nodes[selected] then indices[selected]=true end
  if next(indices) then remember();C.cutNodes(path,indices);penTip=nil;selected=0;picked={};changed() end
 end}
 d:newrow(); d:button{id='undo',text='復原路徑',onclick=function() undoPath(true) end}; d:button{id='redo',text='重做路徑',onclick=function() undoPath(false) end}
 
 d:newrow(); d:check{id='background',text='顯示作品參考',selected=true,onclick=function() d:repaint() end}
 d:check{id='handles',text='顯示錨點與控制柄',selected=true,onclick=function() d:repaint() end}
 d:newrow(); d:label{id='help',text='點端點接續；點另一端點連接；Esc 停筆另起；Delete 刪除錨點'}
 d:newrow(); d:button{id='apply',text='確認套用',onclick=alert(applyDocument)}
 d:button{id='cancel',text='取消',onclick=function() d:close() end}
 refreshSections=function()
  if fullscreen then
   for _,id in ipairs({'lineStyle','dash1','dash2','dash3','dash4','customStyle'}) do d:modify{id=id,visible=false} end
   d:modify{id='width',visible=path.stroke~=false};d:modify{id='strokeColor',visible=path.stroke~=false};d:modify{id='fillColor',visible=path.fill or false};return
  end
  local stroke=path.stroke~=false
  d:modify{id='width',visible=stroke};d:modify{id='strokeColor',visible=stroke}
  d:modify{id='fillColor',visible=path.fill or false}
  d:modify{id='lineStyle',visible=stroke,enabled=not C.link(document,current)}
  d:modify{id='customStyle',visible=stroke}
  for i=1,4 do d:modify{id='dash'..i,visible=stroke and path.lineStyle=='dash'} end
  local expanded=d.data.mirrorSection or false
  for _,id in ipairs({'mirrorBase','mirrorCopy','liveMirror','linkStatus','editSource','detachMirror','mirrorX','mirrorY'}) do d:modify{id=id,visible=expanded} end
  local custom=expanded and d.data.mirrorBase=='自訂中線'
  for _,id in ipairs({'mirrorAxisX','mirrorAxisY','mirrorGuides','centerAxes','axisHelp'}) do d:modify{id=id,visible=custom} end
 end
 toggleFullscreen=function()
  drag=nil
  fullscreen=not fullscreen
  if fullscreen then local b=d.bounds;normalBounds=Rectangle(b.x,b.y,b.width,b.height) end
  for _,id in ipairs({'name','pathName','renamePath','forward','backward','addPath','deletePath','copyPath','mirrorSection','mirrorBase','mirrorAxisX','mirrorAxisY','mirrorGuides','centerAxes','axisHelp','mirrorCopy','liveMirror','linkStatus','editSource','detachMirror','mirrorX','mirrorY','lineStyle','dash1','dash2','dash3','dash4','customStyle','transformPath','background','handles','help'}) do d:modify{id=id,visible=not fullscreen} end
  refreshSections()
  if fullscreen then d.bounds=Rectangle(0,0,app.window.width,app.window.height)
  elseif normalBounds then d.bounds=normalBounds end
  d:repaint()
 end
 rebuild(); sync(); d:show{wait=false,autoscrollbars=true}
 configureAutosave()
 zoom=zoom or view.scale
 d:modify{id='zoom',text=string.format('%.0f',(zoom or view.scale)*100)}
 return {dialog=d,copyCurve=copyCurve,pasteCurve=pasteCurve,saveRecovery=saveRecovery,getPath=function() return path end,getDocument=function() return document end,selectPath=selectPath,getSelection=function() return picked end,getItemSelection=function() return itemSelection end,selectionFrame=selectionFrame,frameHandles=frameHandles,toggleFullscreen=function() toggleFullscreen() end,transformPath=transformPath,reorderPath=reorderPath,addPath=addPath,deletePath=deletePath,down=down,move=move,up=up,paint=paint,view=view,undo=undoPath,setZoom=setZoom}
end
function init(plugin)
 root=plugin.path; C=dofile(app.fs.joinPath(root,'core.lua'));prefs=plugin.preferences;Shapes=dofile(app.fs.joinPath(root,'shapes.lua'))(C);loadPreferences()
 plugin:newCommand{id='BezierPenNew',title='貝茲鋼筆：新增路徑…',group='cel_popup_properties',onclick=alert(function() openEditor(false) end)}
 plugin:newCommand{id='BezierPenEdit',title='貝茲鋼筆：編輯此路徑…',group='cel_popup_properties',onclick=alert(function() openEditor(true) end)}
end
function exit(plugin) if active then active:close();active=nil end end
if BEZIER_TEST then
 C=dofile(app.fs.joinPath(BEZIER_TEST_ROOT,'core.lua'))
 Shapes=dofile(app.fs.joinPath(BEZIER_TEST_ROOT,'shapes.lua'))(C)
 loadPreferences()
 BEZIER_TEST({core=C,open=openEditor,resizePrompt=resizePrompt})
end
