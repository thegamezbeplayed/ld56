package en;

class Mob extends Entity {

  public static var ALL : FixedArray<Mob> = new FixedArray(40);
  var leash:Bool;

  var target: Entity;

  var scolor: dn.Col;
  var sx: Int;//spawn x
  var sy: Int;//spawn y
  //
  var speeds:Map<State,Float> = new Map(); 
  var range:Float;
  var disp : h2d.Tile;
  var sprName: String = "0" ;
  //
  public function new(d,?dis:Int) {
    super();
    ALL.push(this);

    data = d;
    useLdtkEntity(data);
    initLife(3);
    lockAiS(1);
    disp = hxd.Res.normalmap.toTile();
    spr.set(D.tiles.fxBlob+sprName);
    spr.colorize(scolor);

    var ol = new dn.heaps.filter.PixelOutline(scolor);

    filter = new h2d.filter.Group([ol, new h2d.filter.Displacement(disp,3,3)]);
    // Placeholder display
    wid = spr.frameData.wid *d.f_size;
    hei = spr.frameData.hei * d.f_size;

    if(dis!=0)
      setPosCase(d.cx-dis, d.cy-dis);

    leash = false;
    startState(Wander);
  }	

  override function useLdtkEntity(d:Entity_Mob){
    super.useLdtkEntity(d);
    sx=d.cx;
    sy=d.cy;
    var baseSpeed = d.f_speed;
    speeds.set(Normal,baseSpeed);
    speeds.set(Wander,baseSpeed/2);
    var mul = 1.5;
    if(data.f_aggro) mul = 2;
    speeds.set(Engaged,baseSpeed*mul);
    switch d.f_type {
      case 'alg':
      scolor = Green;
      case 'theo':
      scolor = Orange;
      case 'hel':
      sprName = 'Hel';
      scolor = Yellow;
      case 'trich':
      scolor = Lime;
      default:
      sprName="0";
      scolor = Blue;
    }

    range = (wid+hei)/Const.GRID;
    if(d.f_aggro) range *=2;
  }

  function setMoveSpeed(){
    if(speeds.exists(state))
      moveSpeed = speeds.get(state);
    else
      moveSpeed = speeds.get(Normal);
  }

  override function onDamage(dmg:Int, from:Entity){
    switch data.f_type{
      case 'hel','theo':
      if(!_victims.contains(from)&&mass>from.mass)
	from.grab(this);
      default:
      setAffectS(Shield, 1);

    }
  }

  override function onStateChange(old:State, newState:State) {
    switch(newState){
      case Engaged:
	seek(game.player);
      case Wander:
	if(data.f_aggro)
	  wander();
	else{
	  switch(data.f_type){
	    case 'trich':
	      latch();
	     default:
	      track();
	  }
	}
      case Normal:
      	startState(Wander);
      default:
    }
    setMoveSpeed();
  }

  override function dispose() {
    super.dispose();

    ALL.remove(this);
  }

  function seek(t:Entity){
    if(target == t && cd.hasSetS("seeking",0.25*distCase(t)*moveSpeed)) return;
    else target = t;

    var dh = new dn.DecisionHelper(level.cachedEmptyPoints.filter(pt->distCase(pt.cx,pt.cy) <4));
    dh.score( pt->-pt.distCase(t)*0.5 );
    var pt = dh.getBest();
    if(pt!=null)
    gotoCase(pt.cx,pt.cy);
  }

  function latch(){
    var dh = new dn.DecisionHelper(level.cachedEmptyPoints.filter(pt->distCase(pt.cx,pt.cy) <6));
    dh.score( _->rnd(0,2) );
    var pt = dh.getBest();

    if(pt!=null)
      gotoCase(cx,0);
  }

  function track(){
    var dh = new dn.DecisionHelper(level.cachedEmptyPoints.filter(pt->distCase(pt.cx,pt.cy) <6));
    dh.score( _->rnd(0,2) );
    var pt = dh.getBest();
    
    if(pt!=null)
    gotoCase(cx,pt.cy);
  }

  function wander(){
    var dh = new dn.DecisionHelper(level.cachedEmptyPoints.filter(pt->distCase(pt.cx,pt.cy) <4));
    dh.score( _->rnd(0,2) );
    var pt = dh.getBest();
    if(pt!=null)
    gotoCase(pt.cx,pt.cy);
  }

  public static inline function alives() {
    var n = 0;
    for(e in ALL)
      if( e.isAlive() )
	n++;
    return n;
  }

  function aiLocked() {
    return !isAlive() || hasAffect(Stun) || isChargingAction() || cd.has("aiLock");
  }

  function enemyNear(range:Float){
    if(distCase(game.player) <= range) return true;

    return false;
  }

  public inline function lockAiS(t:Float) {
    cd.setS("aiLock",t,false);
  }

  override function hit(dmg:Int, from:Null<Entity>) {
    super.hit(dmg, from);

    //setSquashX(0.4);
    //blink(dmg==0 ? White : Red);

  }

  override function onTargetReached(){
    startState(Normal);
  }

  /** X collisions **/
  override function onPreStepX() {
    super.onPreStepX();

    // Right collision
    if( xr>0.8 && level.hasCollision(cx+1,cy) )
      xr = 0.8;

    // Left collision
    if( xr<0.2 && level.hasCollision(cx-1,cy) )
      xr = 0.2;
  }

  /** Y collisions **/
  override function onPreStepY() {
    super.onPreStepY();

    // Land on ground
    if( yr>1 && level.hasCollision(cx,cy+1) ) {
      vBase.dy = 0;
      vBump.dy = 0;
      yr = 1;
      onPosManuallyChangedY();
    }

    // Ceiling collision
    if( yr<0.2 && level.hasCollision(cx,cy-M.round(1+radius*2) )){
      yr = 0.2;
      cancelMove(true);
    }
  }

  override function fixedUpdate(){
    super.fixedUpdate();
    
    disp.scrollDiscrete(0.6,1.2);

    if( canMoveToTarget() ) {
      var d = distPx(moveTarget.levelX, moveTarget.levelY);
      if(d>brakeDist){
	invalidateDebugBounds = true;

	var a = Math.atan2(moveTarget.levelY-attachY, moveTarget.levelX-attachX);
	vBase.dx=Math.cos(a)*moveSpeed;
	vBase.dy=Math.sin(a)*moveSpeed;
      }
      else{
	cancelMove(true);
      }

    }

    if(enemyNear(range))
      startState(Engaged);
    else
      startState(Wander);

  }

  override function postUpdate(){
    super.postUpdate();
    debug('$cy,${moveTarget.cy}');
    for(v in _victims){
      if(v.data.f_type !='Player')
	continue;

      v.vBase.dx = vBase.dx;
      v.vBase.dy = vBase.dy;
      if(!v.hasAffect(Absorb)||!v.isAlive()) _victims.remove(v);
      if(!v.cd.hasSetS("drain",1)){
	v.blink(Red);
	v.cd.onComplete("drain",()->{
	  v.hit(1,this);
	  mass+=v.mass*0.125;
	  v.mass +=-0.25;
	  if(getInRadius(v,radius)<0)
	  _victims.remove(v);
	});
      }
    }
  }
}
