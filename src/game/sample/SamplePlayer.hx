package sample;

/**
  SamplePlayer is an Entity with some extra functionalities:
  - user controlled (using gamepad or keyboard)
  - falls with gravity
  - has basic level collisions
  - some squash animations, because it's cheap and they do the job
 **/

class SamplePlayer extends Entity {

  var ca : ControllerAccess<GameAction>;
  var pressQueue : Map<GameAction, Float> = new Map();
  var speedMul = 0.3;
  var disp : h2d.Tile;

  var origScale: Float = 0.;

  public function new(d) {
    super();
    data = d;
    useLdtkEntity(d);
    // Misc inits
    vBase.setFricts(0.84, 0.94);
    // Camera tracks this
    camera.trackEntity(this, true);
    camera.clampToLevelBounds = true;

    // Init controller
    ca = App.ME.controller.createAccess();
    ca.lockCondition = Game.isGameControllerLocked;
    
    disp = hxd.Res.normalmap.toTile();
    spr.set(D.tiles.fxBlob0);
    spr.colorize(Blue);
    var ol = new dn.heaps.filter.PixelOutline(Blue);
    
    wid = spr.frameData.wid *d.f_size;
    hei = spr.frameData.hei * d.f_size;
    filter = new h2d.filter.Group([ol, new h2d.filter.Displacement(disp,3,3)]);
    // Placeholder display
//    var b = new h2d.Bitmap( h2d.Tile.fromColor(Red, iwid, ihei), spr );

    spr.setCenterRatio(0.5,1);
    origScale = sprScaleX;
    S.Pop(0.5);
  }

  override function onStateChange(old:State,newState:State){
    switch(newState){
      case Carry:
	speedMul = 0.125;
      case Normal:
	speedMul = 0.3;
      default:
	speedMul = 0.3;
    }
  }

  override function dispose() {
    super.dispose();
    ca.dispose(); // don't forget to dispose controller accesses
  }

  inline function queueCommandPress(a:GameAction) {
    if( ca.isPressed(a) )
      pressQueue.set(a, stime);
  }

  inline function isPressedOrQueued(a:GameAction, remove=true) {
    if( ca.isPressed(a) || pressQueue.exists(a) && stime-pressQueue.get(a)<=0.3 ) {
      if( remove )
	pressQueue.set(a,-1);
      return true;
    }
    else
      return false;
  }

  override function onDie(){
    super.onDie();
    App.ME.startGame();
  }

  override function onTouchWall(wallX:Int, wallY:Int) {
    super.onTouchWall(wallX, wallY);
    if( wallX>0 && cx>=level.cWid-1 )
      game.exitToLevel(1,0);

    if( wallX<0 && cx<=0 )
      game.exitToLevel(-1,0);

    if( wallY>0 && cy>=level.cHei-1 )
      game.exitToLevel(0,1);

    if( wallY<0 && cy<=0 )
      game.exitToLevel(0,-1);
  }

  /** X collisions **/
  override function onPreStepX() {
    super.onPreStepX();

    // Right collision
    if( xr>0.8 && level.hasCollision(cx+1,cy) ){
      onTouchWall(1,0);
      xr = 0.8;
    }

    // Left collision
    if( xr<0.2 && level.hasCollision(cx-1,cy) ){
      onTouchWall(-1,0);
      xr = 0.2;
    }
  }


  /** Y collisions **/
  override function onPreStepY() {
    super.onPreStepY();

    // Land on ground
    if( yr>1 && level.hasCollision(cx,cy+1) ) {
      vBase.dy = 0;
      vBump.dy = 0;
      yr = 1;
      ca.rumble(0.2, 0.06);
      onPosManuallyChangedY();
    }

    // Ceiling collision
    if( yr<0.2 && level.hasCollision(cx,cy-M.round(1+radius*2) ))
      yr = 0.2;
  }

  inline function inHitRange(e:Entity, rangeMul:Float) {
    return e.isAlive() && distPx(e)<=6*rangeMul && M.fabs(attachY-e.attachY)<=6+6*rangeMul && dirTo(e)==dir;
  }

  var _atkVictims : FixedArray<Mob> = new FixedArray(20); // alloc cache
  function getVictims(rangeMul:Float) {
    _atkVictims.empty();
    for(e in en.Mob.ALL){
      if(_victims.contains(e)) continue;
      if( getInRadius(e, rangeMul) >0)
	_atkVictims.push(e);
    }

    return _atkVictims;
  }

  /**
	  Control inputs are checked at the beginning of the frame.
	  VERY IMPORTANT NOTE: because game physics only occur during the `fixedUpdate` (at a constant 30 FPS), no physics increment should ever happen here! What this means is that you can SET a physics value (eg. see the Jump below), but not make any calculation that happens over multiple frames (eg. increment X speed when walking).
   **/
  override function preUpdate() {
    super.preUpdate();

    if( onGround )
      cd.setS("recentlyOnGround",0.1); // allows "just-in-time" jumps


    // Jump
    if( ca.isPressed(Jump) ) {
      cd.has("recentlyOnGround") ? vBase.dy = -0.3 : vBase.dy = -0.15;
      setSquashX(0.6);
      cd.unset("recentlyOnGround");
      //			fx.dotsExplosionExample(centerX, centerY, 0xffcc00);
      ca.rumble(0.05, 0.06);
    }

    // Walk
    if(ca.isPressed(MoveLeft) || ca.isPressed(MoveRight)){
      //ca.getAnalogDist2(MoveLeft,MoveRight)>0 ) {
      // As mentioned above, we don't touch physics values (eg. `dx`) here. We just store some "requested walk speed", which will be applied to actual physics in fixedUpdate.
      setSquashY(1-(speedMul*2));
      moveSpeed = ca.getAnalogValue2(MoveLeft,MoveRight); // -1 to 1
      // Apply requested walk movement
      vBase.dy = -0.015;
      vBase.dx += moveSpeed * speedMul; // some arbitrary speed
    }
  }

  override function fixedUpdate() {
    super.fixedUpdate();

    disp.scrollDiscrete(0.6,1.2);

    // Gravity
    if( !onGround )
      vBase.dy+=0.0075;

  }

  override function frameUpdate() {
    super.frameUpdate();
  
    //queueCommandPress(Atk);
    for(e in getVictims(2.5*radius)) {
      if( ca.isPressed(Atk) && e.mass < mass) {
	//setSquashY(0.35);
	e.grab(this);
	startState(Carry);
      }
    }
  }

  override function postUpdate(){
    super.postUpdate();
    //debug(state);
  
    for(v in _victims){
      v.debugFloat(v.getAffectDurationS(Absorb));

      v.vBase.dx = vBase.dx;
      v.vBase.dy = vBase.dy;
      if(!v.hasAffect(Absorb)||!v.isAlive()){
	_victims.remove(v);
	if(_victims.allocated == 0) startState(Normal);
	continue;
      }
      if(!v.cd.hasSetS("drain",0.5)){
	S.Slurp1(1).pitchRandomly();
	v.blink(Red);
	v.cd.onComplete("drain",()->{
	  v.hit(1,this);
	  if(life.isMax()){
	    if(v.mass>0){
	      game.addScore(1);
	      mass+=v.mass*0.05;
	    }
	  }
	  else
	    life.v++;
	  
	  v.mass += -0.25;
	});
      }
    }

    if(mass!=data.f_mass){
      var mr = mass/data.f_mass;
      sprScaleX = sprScaleY = origScale *mr;
    }
  }
}
