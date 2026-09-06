local M={KEY='bezier_pen_v1'}
M.limits={nodes=256,paths=64,width=300,weight=1000,zoom=6400}
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
 if type(p)=='table' and (p.version==2 or p.version==3 or p.version==4) then
  assert(type(p.paths)=='table' and #p.paths>=1 and #p.paths<=1024,'同一圖層需要 1–64 條路徑。')
  for _,child in ipairs(p.paths) do
   assert((child.version==1 or child.version==5),'子路徑資料無效。')
   M.validate(child)
   assert(child.canvasWidth==p.canvasWidth and child.canvasHeight==p.canvasHeight,'子路徑尺寸不一致。')
  end
  if p.version==3 or p.version==4 then
   assert(type(p.links)=='table','缺少鏡像連動資料。')
   for key,link in pairs(p.links) do
    local i=tonumber(key)
    assert(i and i%1==0 and i>=1 and i<=#p.paths,'鏡像路徑編號無效。')
    assert(type(link)=='table' and finite(link.source) and link.source%1==0 and link.source>=1 and link.source<i,'鏡像來源無效。')
    assert((link.axis=='x' or link.axis=='y') and finite(link.sum),'鏡像軸無效。')
   end
  end
  if p.order then
   assert(p.version==4 and type(p.order)=='table','排序資料版本無效。')
   local used={}
   for _,i in ipairs(p.order) do assert(finite(i) and i%1==0 and i>=1 and i<=#p.paths and not used[i],'路徑排序無效。');used[i]=true end
  end
  return p
 end
 assert(type(p)=='table' and (p.version==1 or p.version==5),'不支援的路徑資料版本。')
 assert(finite(p.width) and p.width>=1 and p.width<=10000,'線寬需要介於 1 到 10000 像素；尺寸縮放超出此範圍時，請取消一起縮放線寬。')
 assert(type(p.nodes)=='table' and #p.nodes<=16384,'保存資料最多支援 16384 個錨點。')
 if p.version==5 then
  assert(type(p.runs)=='table','缺少線段資料。');local at=1
  for _,r in ipairs(p.runs) do assert(r.first==at and finite(r.last) and r.last%1==0 and r.last>=at and r.last<=#p.nodes and type(r.closed)=='boolean','線段範圍無效。');at=r.last+1 end
  for _,r in ipairs(p.runs) do for _,key in ipairs({'color','fillColor'}) do if r[key] then for _,c in ipairs({'r','g','b','a'}) do assert(finite(r[key][c]) and r[key][c]>=0 and r[key][c]<=255,'子曲線顏色無效。') end end end end
  assert(at==#p.nodes+1,'線段資料不完整。')
 end
 assert(p.name==nil or (type(p.name)=='string' and #p.name<=240),'路徑名稱過長。')
 assert(type(p.color)=='table','缺少路徑顏色。')
 for _,k in ipairs({'r','g','b','a'}) do assert(finite(p.color[k]) and p.color[k]>=0 and p.color[k]<=255,'顏色資料無效。') end
 if p.fillColor then
  for _,k in ipairs({'r','g','b','a'}) do assert(finite(p.fillColor[k]) and p.fillColor[k]>=0 and p.fillColor[k]<=255,'填色資料無效。') end
 end
 assert(p.lineStyle==nil or p.lineStyle=='solid' or p.lineStyle=='dash','不支援的線條樣式。')
 if p.dash then assert(type(p.dash)=='table' and #p.dash==4,'虛線需要四段長度。');for _,v in ipairs(p.dash) do assert(finite(v) and v>=0.5 and v<=10000,'虛線長度需介於 0.5–10000 px。') end end
 assert(p.fill==nil or type(p.fill)=='boolean','填色設定無效。')
 assert(p.stroke==nil or type(p.stroke)=='boolean','描邊設定無效。')
 for _,n in ipairs(p.nodes) do
  for _,k in ipairs({'x','y','ix','iy','ox','oy','weight'}) do assert(finite(n[k]),'錨點資料無效。') end
  assert(n.weight>=0 and n.weight<=10000,'錨點線寬比例需要介於 0 到 10000%。')
 end
 return p
end
function M.clone(p) return plain(p) end
function M.collection(p)
 M.validate(p)
 if p.version==2 or p.version==3 or p.version==4 then return M.resolve(M.clone(p)) end
 return {version=2,canvasWidth=p.canvasWidth,canvasHeight=p.canvasHeight,paths={M.clone(p)}}
end
function M.new(w,h,c)
 return {version=1,canvasWidth=w,canvasHeight=h,width=3,closed=false,fill=false,stroke=true,fillColor={r=c.red,g=c.green,b=c.blue,a=c.alpha},color={r=c.red,g=c.green,b=c.blue,a=c.alpha},nodes={}}
end
function M.node(x,y) return {x=x,y=y,ix=0,iy=0,ox=0,oy=0,smooth=true,weight=100} end
-- Each run is a disconnected subpath within one styled path item.
function M.runs(p)
 if p.runs then return p.runs end
 return #p.nodes>0 and {{first=1,last=#p.nodes,closed=p.closed or false}} or {}
end
function M.segments(p)
 local out={}
 for _,r in ipairs(M.runs(p)) do
  for i=r.first,r.last-1 do out[#out+1]={i,i+1,closed=r.closed} end
  if r.closed and r.last-r.first>=2 then out[#out+1]={r.last,r.first,closed=true} end
 end
 return out
end
function M.endpoint(p,i)
 for k,r in ipairs(M.runs(p)) do if not r.closed and (i==r.first or i==r.last) then return k,r end end
end
local function parts(p)
 local out={}
 for _,r in ipairs(M.runs(p)) do local q={nodes={},closed=r.closed,color=M.clone(r.color),fillColor=M.clone(r.fillColor)};for i=r.first,r.last do q.nodes[#q.nodes+1]=M.clone(p.nodes[i]) end;out[#out+1]=q end
 return out
end
local function pack(p,qs)
 p.nodes={};p.runs={};p.version=5;p.closed=#qs>0
 for _,q in ipairs(qs) do if #q.nodes>0 then
  local first=#p.nodes+1;for _,n in ipairs(q.nodes) do p.nodes[#p.nodes+1]=n end
  p.runs[#p.runs+1]={first=first,last=#p.nodes,closed=q.closed or false,color=M.clone(q.color),fillColor=M.clone(q.fillColor)}
  if not q.closed then p.closed=false end
 end end
end
local function reverse(q)
 local out={};for i=#q.nodes,1,-1 do local n=q.nodes[i];n.ix,n.ox=n.ox,n.ix;n.iy,n.oy=n.oy,n.iy;out[#out+1]=n end;q.nodes=out
end
function M.cutNodes(p,chosen)
 local out={}
 for _,r in ipairs(M.runs(p)) do
  local removed=false;for i=r.first,r.last do if chosen[i] then removed=true end end
  if not removed then local q={nodes={},closed=r.closed,color=M.clone(r.color),fillColor=M.clone(r.fillColor)};for i=r.first,r.last do q.nodes[#q.nodes+1]=M.clone(p.nodes[i]) end;out[#out+1]=q
  else
   local start=r.first
   if r.closed then for i=r.first,r.last do if chosen[i] then start=i;break end end end
   local q={nodes={},closed=false,color=M.clone(r.color),fillColor=M.clone(r.fillColor)}
   for offset=0,r.last-r.first do local i=r.closed and (r.first+(start-r.first+offset)%(r.last-r.first+1)) or (start+offset)
    if chosen[i] then if #q.nodes>0 then out[#out+1]=q;q={nodes={},closed=false,color=M.clone(r.color),fillColor=M.clone(r.fillColor)} end
    else q.nodes[#q.nodes+1]=M.clone(p.nodes[i]) end
   end
   if #q.nodes>0 then out[#out+1]=q end
  end
 end
 pack(p,out)
end
function M.deleteNodes(p,chosen)
 local out={}
 for _,r in ipairs(M.runs(p)) do
  local q={nodes={},closed=r.closed,color=M.clone(r.color),fillColor=M.clone(r.fillColor)}
  for i=r.first,r.last do if not chosen[i] then q.nodes[#q.nodes+1]=M.clone(p.nodes[i]) end end
  if #q.nodes<3 then q.closed=false end
  if #q.nodes>0 then out[#out+1]=q end
 end
 pack(p,out)
end
function M.resize(p,w,h,scale,scaleWidth)
 M.validate(p);assert(w>0 and h>0 and p.canvasWidth>0 and p.canvasHeight>0,'尺寸無效。')
 local out=M.clone(p);local sx,sy=w/p.canvasWidth,h/p.canvasHeight
 for _,child in ipairs(out.paths or {out}) do
  if scale then
   for _,n in ipairs(child.nodes) do
    n.x=(n.x+0.5)*sx-0.5;n.y=(n.y+0.5)*sy-0.5
    n.ix=n.ix*sx;n.ox=n.ox*sx;n.iy=n.iy*sy;n.oy=n.oy*sy
   end
   if scaleWidth then child.width=child.width*math.sqrt(sx*sy) end
  end
  child.canvasWidth=w;child.canvasHeight=h
 end
 if scale then for _,link in pairs(out.links or {}) do link.sum=(link.sum+1)*(link.axis=='x' and sx or sy)-1 end end
 out.canvasWidth=w;out.canvasHeight=h;return M.resolve(out)
end
-- Resize canvas without changing path geometry; anchor uses 0, 0.5 or 1.
function M.reposition(p,w,h,ax,ay,dx,dy)
 assert(finite(ax) and finite(ay) and finite(dx) and finite(dy),'位移數值無效。')
 local tx=(w-p.canvasWidth)*ax+dx;local ty=(h-p.canvasHeight)*ay+dy
 local out=M.resize(p,w,h,false,false)
 for _,child in ipairs(out.paths or {out}) do
  for _,n in ipairs(child.nodes) do n.x=n.x+tx;n.y=n.y+ty end
 end
 for _,link in pairs(out.links or {}) do link.sum=link.sum+2*(link.axis=='x' and tx or ty) end
 return M.resolve(out),tx,ty
end
function M.extend(p,tip,n)
 assert(#p.nodes<M.limits.nodes,'已達錨點上限，可在偏好設定調整。')
 local qs=parts(p);local k,r=M.endpoint(p,tip)
 if k then local q=table.remove(qs,k);if tip==r.first and r.first~=r.last then reverse(q) end;qs[#qs+1]=q
 else qs[#qs+1]={nodes={},closed=false} end
 qs[#qs].nodes[#qs[#qs].nodes+1]=n;pack(p,qs);return #p.nodes
end
function M.join(p,a,b)
 local ka,ra=M.endpoint(p,a);local kb,rb=M.endpoint(p,b)
 assert(ka and kb and a~=b,'請選兩個不同的開放端點。')
 local qs=parts(p)
 if ka==kb then assert(ra.last-ra.first>=2,'閉合至少需要三個錨點。');qs[ka].closed=true
 else
  local qa,qb=qs[ka],qs[kb]
  if a==ra.first then reverse(qa) end
  if b==rb.last then reverse(qb) end
  for _,n in ipairs(qb.nodes) do qa.nodes[#qa.nodes+1]=n end
  table.remove(qs,math.max(ka,kb));table.remove(qs,math.min(ka,kb));qs[#qs+1]=qa
 end
 pack(p,qs)
end
function M.setClosed(p,value)
 p.closed=value
 if p.runs then for _,r in ipairs(p.runs) do r.closed=value and r.last-r.first>=2 end end
end
-- Exact centerline bounds, including Bezier extrema between anchors.
function M.pathBounds(p)
 assert(#p.nodes>0,'請先建立路徑。')
 local lo={x=math.huge,y=math.huge};local hi={x=-math.huge,y=-math.huge}
 local function include(k,v) lo[k]=math.min(lo[k],v);hi[k]=math.max(hi[k],v) end
 for _,n in ipairs(p.nodes) do include('x',n.x);include('y',n.y) end
 local function segment(a,b)
  for _,k in ipairs({'x','y'}) do
   local v0,v1,v2,v3=a[k],a[k]+a['o'..k],b[k]+b['i'..k],b[k]
   local A=-v0+3*v1-3*v2+v3;local B=2*(v0-2*v1+v2);local D=v1-v0
   local roots={}
   if math.abs(A)<1e-12 then if math.abs(B)>1e-12 then roots[1]=-D/B end
   else local disc=B*B-4*A*D;if disc>=0 then local r=math.sqrt(disc);roots={(-B-r)/(2*A),(-B+r)/(2*A)} end end
   for _,t in ipairs(roots) do if t>0 and t<1 then local u=1-t;include(k,u*u*u*v0+3*u*u*t*v1+3*u*t*t*v2+t*t*t*v3) end end
  end
 end
 for _,e in ipairs(M.segments(p)) do segment(p.nodes[e[1]],p.nodes[e[2]]) end
 return lo.x,lo.y,hi.x,hi.y
end
function M.mirror(p,axis,around,fixedSum)
 M.validate(p);assert((p.version==1 or p.version==5) and #p.nodes>0,'請先建立路徑。')
 assert(axis=='x' or axis=='y','鏡像方向無效。')
 assert(around=='canvas' or around=='path','鏡像基準無效。')
 local sum=axis=='x' and p.canvasWidth-1 or p.canvasHeight-1
 if around=='path' then local x0,y0,x1,y1=M.pathBounds(p);sum=axis=='x' and x0+x1 or y0+y1 end
 if fixedSum~=nil then assert(finite(fixedSum));sum=fixedSum end
 local copy=M.clone(p)
 for _,n in ipairs(copy.nodes) do
  n[axis]=sum-n[axis];n['i'..axis]=-n['i'..axis];n['o'..axis]=-n['o'..axis]
 end
 return M.validate(copy)
end
function M.link(p,i) return p.links and p.links[tostring(i)] end
function M.resolve(p)
 M.validate(p)
 if p.version==3 or p.version==4 then
  for i=1,#p.paths do
   local link=M.link(p,i)
   if link then
    local source=p.paths[link.source];local name=p.paths[i].name
    p.paths[i]=#source.nodes>0 and M.mirror(source,link.axis,'canvas',link.sum) or M.clone(source)
    p.paths[i].name=name
   end
  end
 end
 return p
end
function M.order(p)
 local out,used={},{}
 for _,i in ipairs(p.order or {}) do out[#out+1]=i;used[i]=true end
 for i=1,#p.paths do if not used[i] then out[#out+1]=i end end
 return out
end
function M.reorder(p,index,delta)
 M.validate(p)
 local order=M.order(p);local at
 for j,i in ipairs(order) do if i==index then at=j end end
 assert(at,'路徑不存在。')
 local to=math.max(1,math.min(#order,at+delta))
 if at==to then return false end
 table.remove(order,at);table.insert(order,to,index)
 p.version=4;p.links=p.links or {};p.order=order
 return true
end
function M.removePath(p,index)
 M.resolve(p)
 local links={}
 for i=1,#p.paths do
  local link=M.link(p,i)
  if i~=index and link and link.source~=index then
   local copy=M.clone(link)
   if copy.source>index then copy.source=copy.source-1 end
   links[tostring(i>index and i-1 or i)]=copy
  end
 end
 if p.order then
  local order={};for _,i in ipairs(M.order(p)) do if i~=index then order[#order+1]=i>index and i-1 or i end end;p.order=order
 end
 table.remove(p.paths,index)
 if p.version==3 or p.version==4 then p.links=links end
end
function M.compact(p)
 M.resolve(p)
 local result=M.clone(p);result.paths={};result.links={};local map={}
 for i,child in ipairs(p.paths) do
  if #child.nodes>0 then result.paths[#result.paths+1]=M.clone(child);map[i]=#result.paths end
 end
 for i=1,#p.paths do
  local link=M.link(p,i)
  if map[i] and link and map[link.source] then
   local copy=M.clone(link);copy.source=map[link.source];result.links[tostring(map[i])]=copy
  end
 end
 result.order=nil
 if p.order then
  result.order={};for _,i in ipairs(M.order(p)) do if map[i] then result.order[#result.order+1]=map[i] end end
 end
 result.version=result.order and 4 or (next(result.links) and 3 or 2)
 if result.version==2 then result.links=nil end
 return result
end
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
 local function curve(a,b,edge)
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
  out[#out+1]={points=pts,a=a.weight,b=b.weight,edge=edge}
 end
 for _,e in ipairs(M.segments(p)) do curve(p.nodes[e[1]],p.nodes[e[2]],e) end
 return out
end
function M.evaluate(a,b,t)
 local u=1-t
 return u^3*a.x+3*u*u*t*(a.x+a.ox)+3*u*t*t*(b.x+b.ix)+t^3*b.x,
        u^3*a.y+3*u*u*t*(a.y+a.oy)+3*u*t*t*(b.y+b.iy)+t^3*b.y
end
function M.nearest(p,x,y)
 local best,seg,bt,lower,upper=math.huge
 for i,line in ipairs(M.flatten(p)) do
  for j=2,#line.points do
   local a,b=line.points[j-1],line.points[j];local dx,dy=b.x-a.x,b.y-a.y
   local den=dx*dx+dy*dy;local u=den>0 and math.max(0,math.min(1,((x-a.x)*dx+(y-a.y)*dy)/den)) or 0
   local dist=(a.x+u*dx-x)^2+(a.y+u*dy-y)^2
   if dist<best then best=dist;seg=i;bt=a.t+(b.t-a.t)*u;lower=a.t;upper=b.t end
  end
 end
 if not seg then return end
 local edge=M.segments(p)[seg];local a,b=p.nodes[edge[1]],p.nodes[edge[2]]
 local function distance(t) local px,py=M.evaluate(a,b,t);return (px-x)^2+(py-y)^2 end
 for _=1,40 do
  local t1,t2=(2*lower+upper)/3,(lower+2*upper)/3
  if distance(t1)<distance(t2) then upper=t2 else lower=t1 end
 end
 local t=(lower+upper)/2
 if distance(bt)<distance(t) then t=bt end
 return seg,t,distance(t)
end
function M.split(p,segment,t)
 M.validate(p)
 assert(#p.nodes<M.limits.nodes,'已達錨點上限，可在偏好設定調整。')
 local count=#p.nodes;local last=#M.segments(p)
 assert(segment%1==0 and segment>=1 and segment<=last and finite(t) and t>0 and t<1,'插點位置無效。')
 local edge=M.segments(p)[segment];segment=edge[1]
 local a,b=p.nodes[edge[1]],p.nodes[edge[2]]
 local function lerp(x,y) return x+(y-x)*t end
 local ax,ay=lerp(a.x,a.x+a.ox),lerp(a.y,a.y+a.oy)
 local bx,by=lerp(a.x+a.ox,b.x+b.ix),lerp(a.y+a.oy,b.y+b.iy)
 local cx,cy=lerp(b.x+b.ix,b.x),lerp(b.y+b.iy,b.y)
 local dx,dy=lerp(ax,bx),lerp(ay,by);local ex,ey=lerp(bx,cx),lerp(by,cy)
 local fx,fy=lerp(dx,ex),lerp(dy,ey)
 local n=M.node(fx,fy);n.ix=dx-fx;n.iy=dy-fy;n.ox=ex-fx;n.oy=ey-fy
 n.weight=lerp(a.weight,b.weight)
 a.ox=ax-a.x;a.oy=ay-a.y;b.ix=cx-b.x;b.iy=cy-b.y
 if p.runs then for _,r in ipairs(p.runs) do if r.first>segment then r.first=r.first+1 end;if r.last>=segment then r.last=r.last+1 end end end
 table.insert(p.nodes,segment+1,n)
 return segment+1
end
function M.transform(p,degrees,scaleX,scaleY,around)
 M.validate(p)
 assert(finite(degrees) and finite(scaleX) and finite(scaleY) and scaleX>0 and scaleY>0 and scaleX<=100 and scaleY<=100,'角度或縮放倍率無效。')
 assert(#p.nodes>0,'請先建立路徑。')
 local cx,cy=(p.canvasWidth-1)/2,(p.canvasHeight-1)/2
 if around=='path' then local x0,y0,x1,y1=M.pathBounds(p);cx=(x0+x1)/2;cy=(y0+y1)/2 end
 local angle=math.rad(degrees%360);local co,si=math.cos(angle),math.sin(angle)
 local function vector(x,y) x=x*scaleX;y=y*scaleY;return x*co-y*si,x*si+y*co end
 local out=M.clone(p)
 for _,n in ipairs(out.nodes) do
  local x,y=vector(n.x-cx,n.y-cy);n.x=x+cx;n.y=y+cy
  n.ix,n.iy=vector(n.ix,n.iy);n.ox,n.oy=vector(n.ox,n.oy)
 end
 return M.validate(out)
end
-- Raster preview and applied image use the exact same pixel-art renderer.
-- Round caps; no antialiasing. Repeated samples do not accumulate opacity.
function M.raster(p,w,h)
 M.validate(p)
 if p.version==2 or p.version==3 or p.version==4 then
  M.resolve(p)
  local parts={};local x0,y0,x1,y1=w,h,0,0
  for _,index in ipairs(M.order(p)) do
   local child=p.paths[index]
   local img,pos=M.raster(child,w,h)
   if not img:isEmpty() then
    parts[#parts+1]={img=img,pos=pos}
    x0=math.min(x0,pos.x);y0=math.min(y0,pos.y)
    x1=math.max(x1,pos.x+img.width);y1=math.max(y1,pos.y+img.height)
   end
  end
  if #parts==0 then return Image(1,1,ColorMode.RGB),Point(0,0) end
  local out=Image(x1-x0,y1-y0,ColorMode.RGB)
  for _,part in ipairs(parts) do out:drawImage(part.img,Point(part.pos.x-x0,part.pos.y-y0),255,BlendMode.NORMAL) end
  return out,Point(x0,y0)
 end
 local colored=false;for _,r in ipairs(M.runs(p)) do if r.color or r.fillColor then colored=true end end
 if colored then
  local out=Image(w,h,ColorMode.RGB)
  for _,r in ipairs(M.runs(p)) do
   local child=M.clone(p);child.version=1;child.runs=nil;child.nodes={};child.closed=r.closed
   child.color=M.clone(r.color or p.color);child.fillColor=M.clone(r.fillColor or p.fillColor or p.color)
   for i=r.first,r.last do child.nodes[#child.nodes+1]=M.clone(p.nodes[i]) end
   local image,position=M.raster(child,w,h);out:drawImage(image,position,255,BlendMode.NORMAL)
  end
  return out,Point(0,0)
 end
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
 -- Even-odd scanline fill; half-open edges avoid counting vertices twice.
 if p.fill and #p.nodes>=3 then
  local fc=p.fillColor or p.color
  local fillPixel=pc.rgba(fc.r,fc.g,fc.b,fc.a)
  for yy=miny,maxy do
   local xs={}
   for _,line in ipairs(lines) do if line.edge.closed then for i=2,#line.points do
    local a,b=line.points[i-1],line.points[i]
    if (a.y<=yy and b.y>yy) or (b.y<=yy and a.y>yy) then
     xs[#xs+1]=a.x+(yy-a.y)*(b.x-a.x)/(b.y-a.y)
    end
   end end
   end
   table.sort(xs)
   for i=1,#xs-1,2 do
    for xx=math.max(minx,math.ceil(xs[i])),math.min(maxx,math.ceil(xs[i+1])-1) do im:drawPixel(xx-minx,yy-miny,fillPixel) end
   end
  end
 end
 local covered={}
 local function strokePixel(x,y)
  if not p.fill then im:drawPixel(x,y,pixel); return end
  local key=y*im.width+x
  if covered[key] then return end
  covered[key]=true
  local under=im:getPixel(x,y)
  local ba=pc.rgbaA(under)/255; local sa=c.a/255
  local oa=sa+ba*(1-sa)
  if oa<=0 then return end
  local function mix(v,b) return math.floor((v*sa+b*ba*(1-sa))/oa+0.5) end
  im:drawPixel(x,y,pc.rgba(mix(c.r,pc.rgbaR(under)),mix(c.g,pc.rgbaG(under)),mix(c.b,pc.rgbaB(under)),math.floor(oa*255+0.5)))
 end
 local function stamp(x,y,width)
  if width<=0 then return end
  if width<=1 then
   local ix,iy=math.floor(x+0.5)-minx,math.floor(y+0.5)-miny
   if ix>=0 and iy>=0 and ix<im.width and iy<im.height then strokePixel(ix,iy) end
   return
  end
  local r=width/2
  for yy=math.max(miny,math.ceil(y-r)),math.min(maxy,math.floor(y+r)) do
   local dx=math.sqrt(math.max(0,r*r-(yy-y)^2))
   for xx=math.max(minx,math.ceil(x-dx)),math.min(maxx,math.floor(x+dx)) do
    -- A half-open edge makes integer widths predictable on straight runs.
    if (xx-x)^2+(yy-y)^2<r*r+1e-9 and yy<y+r and xx<x+r then strokePixel(xx-minx,yy-miny) end
   end
  end
 end
 local traveled=0;local starts={}
 for _,r in ipairs(M.runs(p)) do starts[r.first]=true end
 local function ink(distance)
  if p.lineStyle~='dash' then return true end
  local pattern=p.dash or {4,8,4,8};local total=0;for _,v in ipairs(pattern) do total=total+v end
  local at=distance%total
  for i,v in ipairs(pattern) do if at<v then return i%2==0 end;at=at-v end
  return false
 end
 if p.stroke~=false then for _,line in ipairs(lines) do
  if starts[line.edge[1]] then traveled=0 end
  for i=2,#line.points do
   local a,b=line.points[i-1],line.points[i]
   local length=math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)
   local steps=math.max(1,math.ceil(length*2))
   for j=0,steps do
    local u=j/steps; local t=a.t+(b.t-a.t)*u
    if ink(traveled+length*u) then stamp(a.x+(b.x-a.x)*u,a.y+(b.y-a.y)*u,p.width*(line.a+(line.b-line.a)*t)/100) end
   end
   traveled=traveled+length
  end
 end end
 return im,Point(minx,miny)
end
function M.read(layer,frame)
 if not layer then return nil end
 frame=frame or (app.frame and app.frame.frameNumber) or 1
 local cel=layer:cel(frame)
 local raw=cel and cel.properties[M.KEY]
 if not raw and frame==1 then raw=layer.properties[M.KEY] end
 if not raw then return nil end
 local ok,p=pcall(json.decode,raw);assert(ok,'無法讀取路徑資料。')
 if p.version==6 then return nil end
 return M.resolve(plain(p))
end
function M.apply(s,layer,p,name,frame)
 assert(s and s.isValid and s.colorMode==ColorMode.RGB,'原作品已關閉或不是 RGB 模式。')
 frame=frame or (app.frame and app.frame.frameNumber) or 1
 assert(s.frames[frame],'原影格已不存在。')
 M.resolve(p)
 for i,child in ipairs(p.paths or {p}) do
  assert(#child.nodes>=1,'路徑 '..i..' 沒有錨點。')
  if child.version==1 then assert(not child.fill or (child.closed and #child.nodes>=3),'填色需要閉合且至少三個錨點。') end
  -- Only closed runs contribute fill; open runs retain their stroke.
 end
 assert(s.width==p.canvasWidth and s.height==p.canvasHeight,'作品尺寸已改變，請取消並重新開啟編輯器。')
 if layer then
  local found=false
  local function visit(ls) for _,l in ipairs(ls) do if l==layer then found=true end; if l.isGroup then visit(l.layers) end end end
  visit(s.layers); assert(found and (layer.properties[M.KEY] or M.read(layer,frame)),'原路徑圖層已刪除或不再有效。')
 end
 local img,pos=M.raster(p,s.width,s.height)
 app.sprite=s
 app.transaction('套用貝茲路徑',function()
  if not layer then layer=s:newLayer() end
  layer.name=name~='' and name or '貝茲曲線'
  -- Migrate legacy single-frame data before replacing the layer marker.
  local legacy=layer.properties[M.KEY]
  if legacy then local decoded=json.decode(legacy);if decoded.version~=6 and layer:cel(1) and not layer:cel(1).properties[M.KEY] then layer:cel(1).properties[M.KEY]=legacy end end
  local c=layer:cel(frame)
  local metadata
  if c then
   metadata={opacity=c.opacity,zIndex=c.zIndex,color=c.color,data=c.data,properties=plain(c.properties)}
   s:deleteCel(c)
  end
  c=s:newCel(layer,frame,img,pos)
  if metadata then
   c.opacity=metadata.opacity;c.zIndex=metadata.zIndex;c.color=metadata.color;c.data=metadata.data
   for k,v in pairs(metadata.properties) do c.properties[k]=v end
  end
  c.properties[M.KEY]=json.encode(p)
  layer.properties[M.KEY]=json.encode({version=6,perFrame=true})
  layer.color=Color{r=173,g=216,b=255,a=255}
 end)
 app.layer=layer; app.refresh(); return layer
end
return M
