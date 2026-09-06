-- Geometry helpers. All generated shapes remain ordinary editable Bezier nodes.
return function(C)
 local M={}
 function M.round(p,radius,chosen)
  local out=C.clone(p);out.nodes={};out.runs={};out.version=5
  for _,run in ipairs(C.runs(p)) do
   local first=#out.nodes+1
   for i=run.first,run.last do
    local n=p.nodes[i];local prev=p.nodes[i>run.first and i-1 or run.last];local following=p.nodes[i<run.last and i+1 or run.first]
    local eligible=radius>0 and (not chosen or chosen[i]) and (run.closed or (i>run.first and i<run.last))
    -- Rounding straight-sided corners does not disturb adjacent curved segments.
    eligible=eligible and n.ix==0 and n.iy==0 and n.ox==0 and n.oy==0 and prev.ox==0 and prev.oy==0 and following.ix==0 and following.iy==0
    local ax,ay=n.x-prev.x,n.y-prev.y;local bx,by=following.x-n.x,following.y-n.y
    local la,lb=math.sqrt(ax*ax+ay*ay),math.sqrt(bx*bx+by*by)
    if eligible and la>1e-8 and lb>1e-8 then
     ax,ay,bx,by=ax/la,ay/la,bx/lb,by/lb
     local angle=math.abs(math.atan(ax*by-ay*bx,ax*bx+ay*by))
     if angle>1e-6 and angle<math.pi-1e-6 then
      local tangent=math.tan(angle/2)
      local distance=math.min(radius*tangent,la/2,lb/2)
      local handle=4/3*math.tan(angle/4)*(distance/tangent)
      local entry,exit=C.clone(n),C.clone(n)
      entry.x,entry.y=n.x-ax*distance,n.y-ay*distance
      exit.x,exit.y=n.x+bx*distance,n.y+by*distance
      entry.ox,entry.oy=ax*handle,ay*handle
      exit.ix,exit.iy=-bx*handle,-by*handle
      entry.smooth=false;exit.smooth=false
      out.nodes[#out.nodes+1]=entry;out.nodes[#out.nodes+1]=exit
     else out.nodes[#out.nodes+1]=C.clone(n) end
    else out.nodes[#out.nodes+1]=C.clone(n) end
   end
   local r=C.clone(run);r.first=first;r.last=#out.nodes;out.runs[#out.runs+1]=r
  end
  assert(#out.nodes<=C.limits.nodes,'圓角後超過錨點上限。')
  return out
 end
 function M.make(template,kind,x0,y0,x1,y1,sides,depth,radius)
  local p=C.clone(template);p.nodes={};p.runs=nil;p.version=1;p.closed=kind~='直線'
  local left,right=math.min(x0,x1),math.max(x0,x1);local top,bottom=math.min(y0,y1),math.max(y0,y1)
  local cx,cy=(left+right)/2,(top+bottom)/2;local rx,ry=(right-left)/2,(bottom-top)/2
  local function point(x,y) p.nodes[#p.nodes+1]=C.node(x,y) end
  if kind=='直線' then point(x0,y0);point(x1,y1)
  elseif kind=='長方形' then point(left,top);point(right,top);point(right,bottom);point(left,bottom)
  elseif kind=='圓形' then
   local k=0.5522847498307936
   point(cx,top);point(right,cy);point(cx,bottom);point(left,cy)
   local a,b,c,d=table.unpack(p.nodes)
   a.ix=-rx*k;a.ox=rx*k;b.iy=-ry*k;b.oy=ry*k;c.ix=rx*k;c.ox=-rx*k;d.iy=ry*k;d.oy=-ry*k
  else
   local count=kind=='三角形' and 3 or sides
   assert(count and count%1==0 and count>=3 and count<=128,'角數需為 3–128。')
   local star=kind=='星形';local total=star and count*2 or count
   for i=0,total-1 do
    local a=-math.pi/2+i*2*math.pi/total
    local ratio=star and i%2==1 and (1-depth/100) or 1
    point(cx+math.cos(a)*rx*ratio,cy+math.sin(a)*ry*ratio)
   end
  end
  if kind~='圓形' and kind~='直線' and radius>0 then p=M.round(p,radius) end
  assert(#p.nodes<=C.limits.nodes,'形狀超過錨點上限。')
  return p
 end
 function M.append(base,shape)
  local out=C.clone(base);local offset=#out.nodes;out.runs=C.clone(C.runs(base));out.version=5
  for _,n in ipairs(shape.nodes) do out.nodes[#out.nodes+1]=C.clone(n) end
  for _,r in ipairs(C.runs(shape)) do local q=C.clone(r);q.first=q.first+offset;q.last=q.last+offset;out.runs[#out.runs+1]=q end
  out.closed=true;for _,r in ipairs(out.runs) do if not r.closed then out.closed=false end end
  assert(#out.nodes<=C.limits.nodes,'新增形狀後超過錨點上限。')
  return C.validate(out)
 end
 return M
end
