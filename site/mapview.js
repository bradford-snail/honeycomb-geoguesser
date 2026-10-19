/* Pan / zoom / pick map view */
class MapView{
  constructor(el, opts={}){
    this.el=el; this.onPick=opts.onPick||null; this.pickable=!!opts.pickable;
    el.classList.add('mv'); if(this.pickable) el.classList.add('pick');
    this.stage=document.createElement('div'); this.stage.className='mv-stage';
    this.img=document.createElement('img'); this.img.alt='Map'; this.img.draggable=false;
    this.stage.appendChild(this.img);
    this.overlay=document.createElement('div'); this.overlay.className='mv-overlay';
    this.svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
    this.overlay.appendChild(this.svg);
    const z=document.createElement('div'); z.className='mv-zoom';
    z.innerHTML='<button type="button" aria-label="Zoom in">+</button><button type="button" aria-label="Zoom out">−</button>';
    el.append(this.stage,this.overlay,z);
    z.children[0].addEventListener('click',e=>{e.stopPropagation(); this.zoomBy(1.6)});
    z.children[1].addEventListener('click',e=>{e.stopPropagation(); this.zoomBy(1/1.6)});
    z.addEventListener('pointerdown',e=>e.stopPropagation());
    this.W=1; this.H=1; this.s=1; this.tx=0; this.ty=0; this.min=1;
    this.markers=[]; this.line=null; this.ptrs=new Map(); this.cw=0; this.ch=0;
    el.addEventListener('pointerdown',e=>this._down(e));
    el.addEventListener('pointermove',e=>this._move(e));
    el.addEventListener('pointerup',e=>this._up(e));
    el.addEventListener('pointercancel',e=>this._up(e,true));
    el.addEventListener('wheel',e=>{e.preventDefault(); const r=el.getBoundingClientRect(); this.zoomAt(e.clientX-r.left,e.clientY-r.top,this.s*Math.exp(-e.deltaY*0.0015))},{passive:false});
    new ResizeObserver(()=>this._resize()).observe(el);
  }
  setImage(url,W,H){
    this.W=W; this.H=H; this.img.width=W; this.img.height=H; this.img.src=url; this.fit();
  }
  setPickable(v){this.pickable=v; this.el.classList.toggle('pick',v)}
  setMarkers(m,line){this.markers=m; this.line=line||null; this._render()}
  _size(){this.cw=this.el.clientWidth; this.ch=this.el.clientHeight; this.min=Math.min(this.cw/this.W,this.ch/this.H)||1}
  fit(){this._size(); this.s=this.cover?Math.max(this.cw/this.W,this.ch/this.H):this.min; this._clamp(); this._render()}
  fitTo(pts,pad=80){
    this._size(); if(!pts.length) return this.fit();
    const xs=pts.map(p=>p.x*this.W), ys=pts.map(p=>p.y*this.H);
    const x0=Math.min(...xs), x1=Math.max(...xs), y0=Math.min(...ys), y1=Math.max(...ys);
    const bw=Math.max(x1-x0,1), bh=Math.max(y1-y0,1);
    let s=Math.min((this.cw-pad*2)/bw,(this.ch-pad*2)/bh);
    s=Math.max(this.min,Math.min(s,this._max()));
    this.s=s; this.tx=this.cw/2-(x0+x1)/2*s; this.ty=this.ch/2-(y0+y1)/2*s; this._clamp(); this._render();
  }
  _max(){return Math.max(this.min*16,3)}
  zoomBy(f){this.zoomAt(this.cw/2,this.ch/2,this.s*f)}
  zoomAt(sx,sy,ns){
    ns=Math.max(this.min,Math.min(ns,this._max()));
    const mx=(sx-this.tx)/this.s, my=(sy-this.ty)/this.s;
    this.s=ns; this.tx=sx-mx*ns; this.ty=sy-my*ns; this._clamp(); this._render();
  }
  _clamp(){
    const w=this.W*this.s, h=this.H*this.s;
    this.tx = w<=this.cw ? (this.cw-w)/2 : Math.min(0,Math.max(this.cw-w,this.tx));
    this.ty = h<=this.ch ? (this.ch-h)/2 : Math.min(0,Math.max(this.ch-h,this.ty));
  }
  _resize(){
    const oc=this.cw, oh=this.ch;
    if(!oc||!oh){this.fit(); return}
    const cx=(oc/2-this.tx)/this.s, cy=(oh/2-this.ty)/this.s, wasMin=this.s<=this.min*1.001;
    this._size();
    if(wasMin) this.s=this.min; else this.s=Math.max(this.s,this.min);
    this.tx=this.cw/2-cx*this.s; this.ty=this.ch/2-cy*this.s; this._clamp(); this._render();
  }
  _scr(p){return {x:this.tx+p.x*this.W*this.s, y:this.ty+p.y*this.H*this.s}}
  _render(){
    this.stage.style.transform=`translate(${this.tx}px,${this.ty}px) scale(${this.s})`;
    this.overlay.querySelectorAll('.marker').forEach(n=>n.remove());
    this.svg.innerHTML='';
    if(this.line){
      const a=this._scr(this.line[0]), b=this._scr(this.line[1]);
      const l=document.createElementNS('http://www.w3.org/2000/svg','line');
      l.setAttribute('x1',a.x); l.setAttribute('y1',a.y); l.setAttribute('x2',b.x); l.setAttribute('y2',b.y);
      l.setAttribute('stroke','#ffffff'); l.setAttribute('stroke-width','3'); l.setAttribute('stroke-dasharray','8 7'); l.setAttribute('stroke-linecap','round');
      this.svg.appendChild(l);
    }
    for(const m of this.markers){
      const p=this._scr(m), d=document.createElement('div');
      d.className='marker '+m.kind; d.style.left=p.x+'px'; d.style.top=p.y+'px';
      this.overlay.appendChild(d);
    }
  }
  _down(e){
    if(e.button!==undefined && e.button!==0) return;
    this.el.setPointerCapture(e.pointerId);
    this.ptrs.set(e.pointerId,{x:e.clientX,y:e.clientY});
    if(this.ptrs.size===1){this.start={x:e.clientX,y:e.clientY}; this.moved=false; this.el.style.cursor=this.pickable?'crosshair':'grabbing'}
    else {this.moved=true; this.pinch=null}
  }
  _move(e){
    if(!this.ptrs.has(e.pointerId)) return;
    const prev=this.ptrs.get(e.pointerId); const cur={x:e.clientX,y:e.clientY};
    this.ptrs.set(e.pointerId,cur);
    if(this.ptrs.size===1){
      if(Math.hypot(cur.x-this.start.x,cur.y-this.start.y)>6) this.moved=true;
      if(this.moved){this.tx+=cur.x-prev.x; this.ty+=cur.y-prev.y; this._clamp(); this._render()}
    } else if(this.ptrs.size===2){
      const [a,b]=[...this.ptrs.values()]; const r=this.el.getBoundingClientRect();
      const d=Math.hypot(a.x-b.x,a.y-b.y), mid={x:(a.x+b.x)/2-r.left,y:(a.y+b.y)/2-r.top};
      if(this.pinch){
        this.tx+=mid.x-this.pinch.mid.x; this.ty+=mid.y-this.pinch.mid.y;
        this.zoomAt(mid.x,mid.y,this.s*(d/this.pinch.d));
      }
      this.pinch={d,mid};
    }
  }
  _up(e,cancel){
    if(!this.ptrs.has(e.pointerId)) return;
    this.ptrs.delete(e.pointerId); this.el.style.cursor='';
    if(this.ptrs.size<2) this.pinch=null;
    if(this.ptrs.size===0 && !this.moved && !cancel && this.pickable && this.onPick){
      const r=this.el.getBoundingClientRect();
      const x=(e.clientX-r.left-this.tx)/(this.W*this.s), y=(e.clientY-r.top-this.ty)/(this.H*this.s);
      if(x>=0&&x<=1&&y>=0&&y<=1) this.onPick(x,y);
    }
  }
}

