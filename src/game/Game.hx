class Game extends AppChildProcess {
  public static var ME : Game;

  /** Game controller (pad or keyboard) **/
  public var ca : ControllerAccess<GameAction>;

  /** Particles **/
  public var fx : Fx;

  /** Basic viewport control **/
  public var camera : Camera;

  /** Container of all visual game objects. Ths wrapper is moved around by Camera. **/
  public var scroller : h2d.Layers;

  /** Level data **/
  public var level : Level;

  /** UI **/
  public var hud : ui.Hud;
  var scoreTf : h2d.Text;
  public var score : Int;
  /** Slow mo internal values**/
  var curGameSpeed = 1.0;
  var slowMos : Map<SlowMoId, { id:SlowMoId, t:Float, f:Float }> = new Map();

  public var player: sample.SamplePlayer;

  public function new() {
    super();

    score = 0;
    ME = this;
    ca = App.ME.controller.createAccess();
    ca.lockCondition = isGameControllerLocked;
    createRootInLayers(App.ME.root, Const.DP_BG);
    dn.Gc.runNow();

    scroller = new h2d.Layers();
    root.add(scroller, Const.DP_BG);
    scroller.filter = new dn.heaps.filter.FogTeint(Blue,0.128);
    fx = new Fx();
    hud = new ui.Hud();
    camera = new Camera();
    scoreTf = new h2d.Text(Assets.fontPixelMono);
    root.add(scoreTf, Const.DP_UI);
    scoreTf.x = 5;
    addScore(0);
    startLevel(Assets.worldData.all_worlds.SampleWorld.all_levels.Level_0);
    Assets.playMusic(true);
  }


  public static function isGameControllerLocked() {
    return !exists() || ME.isPaused() || App.ME.anyInputHasFocus();
  }


	public static inline function exists() {
		return ME!=null && !ME.destroyed;
	}

  public function addScore(?e:Entity, v) {
    score+=v;
    scoreTf.text = "SCORE: "+ dn.Lib.leadingZeros(score, 6);
    if( e!=null ) {
      var tf = new h2d.Text(Assets.fontPixelMono);
      scroller.add(tf, Const.DP_UI);
      tf.text = ""+v;
      tf.setPosition(e.centerX-tf.textWidth*0.5, e.centerY-tf.textHeight*0.5);
      tw.createMs(tf.alpha, 500|0, TEaseIn, 400).end( tf.remove );
    }
  }

  public function exitToLevel(dx:Int, dy:Int) {
    var gx = level.data.worldX + player.attachX + dx*2*Const.GRID;
    var gy = level.data.worldY + player.attachY + dy*2*Const.GRID;
    for(l in Assets.worldData.all_worlds.SampleWorld.levels) {
      if( gx>=l.worldX && gx<l.worldX+l.pxWid && gy>=l.worldY && gy<l.worldY+l.pxHei ) {
	var x = gx-l.worldX;
	var y = gy-l.worldY;
	startLevel(l, x, y);
	return true;
      }
    }
    return false;
  }

  var lastStartX = -1.;
  var lastStartY = -1.;
  /** Load a level **/
  function startLevel(l:World.World_Level,startX=-1., startY=-1.) {
    if( level!=null )
      level.destroy();
    fx.clear();
    for(e in Entity.ALL){
      if(e.data!=null && e.data.f_type=='Player') continue;
      e.destroy();
    }
    garbageCollectEntities();

    level = new Level(l);
    // <---- Here: instanciate your level entities
    if(startX > 0 && startY>0){
      player.setPosPixel(M.round(startX),M.round(startY));
    }

    camera.centerOnTarget();
    hud.onLevelStart();
    dn.Process.resizeAll();
    dn.Gc.runNow();
    for (d in level.data.l_Entities.all_Mob){
      switch d.f_type {
	case 'Player': player = new sample.SamplePlayer(d);
	case 'alg':
	new Mob(d,1);
	default:
	new Mob(d,1);
      }
    }
    
    for(d in level.data.l_Entities.all_Message) new en.Message(d);
    
    lastStartX = player.attachX;
    lastStartY = player.attachY;
  }



	/** Called when either CastleDB or `const.json` changes on disk **/
	@:allow(App)
	function onDbReload() {
		hud.notify("DB reloaded");
	}


	/** Called when LDtk file changes on disk **/
	@:allow(assets.Assets)
	function onLdtkReload() {
		hud.notify("LDtk reloaded");
		if( level!=null )
			startLevel( Assets.worldData.all_worlds.SampleWorld.getLevel(level.data.uid) );
	}

	/** Window/app resize event **/
	override function onResize() {
		super.onResize();
	}


	/** Garbage collect any Entity marked for destruction. This is normally done at the end of the frame, but you can call it manually if you want to make sure marked entities are disposed right away, and removed from lists. **/
	public function garbageCollectEntities() {
		if( Entity.GC==null || Entity.GC.allocated==0 )
			return;

		for(e in Entity.GC)
			e.dispose();
		Entity.GC.empty();
	}

	/** Called if game is destroyed, but only at the end of the frame **/
	override function onDispose() {
		super.onDispose();

		fx.destroy();
		for(e in Entity.ALL)
			e.destroy();
		garbageCollectEntities();

		if( ME==this )
			ME = null;
	}


	/**
		Start a cumulative slow-motion effect that will affect `tmod` value in this Process
		and all its children.

		@param sec Realtime second duration of this slowmo
		@param speedFactor Cumulative multiplier to the Process `tmod`
	**/
	public function addSlowMo(id:SlowMoId, sec:Float, speedFactor=0.3) {
		if( slowMos.exists(id) ) {
			var s = slowMos.get(id);
			s.f = speedFactor;
			s.t = M.fmax(s.t, sec);
		}
		else
			slowMos.set(id, { id:id, t:sec, f:speedFactor });
	}


	/** The loop that updates slow-mos **/
	final function updateSlowMos() {
		// Timeout active slow-mos
		for(s in slowMos) {
			s.t -= utmod * 1/Const.FPS;
			if( s.t<=0 )
				slowMos.remove(s.id);
		}

		// Update game speed
		var targetGameSpeed = 1.0;
		for(s in slowMos)
			targetGameSpeed*=s.f;
		curGameSpeed += (targetGameSpeed-curGameSpeed) * (targetGameSpeed>curGameSpeed ? 0.2 : 0.6);

		if( M.fabs(curGameSpeed-targetGameSpeed)<=0.001 )
			curGameSpeed = targetGameSpeed;
	}


	/**
		Pause briefly the game for 1 frame: very useful for impactful moments,
		like when hitting an opponent in Street Fighter ;)
	**/
	public inline function stopFrame() {
		ucd.setS("stopFrame", 4/Const.FPS);
	}


	/** Loop that happens at the beginning of the frame **/
	override function preUpdate() {
		super.preUpdate();

		for(e in Entity.ALL) if( !e.destroyed ) e.preUpdate();
	}

	/** Loop that happens at the end of the frame **/
	override function postUpdate() {
		super.postUpdate();

		// Update slow-motions
		updateSlowMos();
		baseTimeMul = ( 0.2 + 0.8*curGameSpeed ) * ( ucd.has("stopFrame") ? 0.1 : 1 );
		Assets.tiles.tmod = tmod;

		// Entities post-updates
		for(e in Entity.ALL) if( !e.destroyed ) e.postUpdate();

		// Entities final updates
		for(e in Entity.ALL) if( !e.destroyed ) e.finalUpdate();

		// Dispose entities marked as "destroyed"
		garbageCollectEntities();
	}


	/** Main loop but limited to 30 fps (so it might not be called during some frames) **/
	override function fixedUpdate() {
		super.fixedUpdate();

		// Entities "30 fps" loop
		for(e in Entity.ALL) if( !e.destroyed ) e.fixedUpdate();
	}

	/** Main loop **/
	override function update() {
		super.update();

		// Entities main loop
		for(e in Entity.ALL) if( !e.destroyed ) e.frameUpdate();


		// Global key shortcuts
		if( !App.ME.anyInputHasFocus() && !ui.Window.hasAnyModal() && !Console.ME.isActive() ) {
			// Exit by pressing ESC twice
			#if hl
			if( ca.isKeyboardPressed(K.ESCAPE) )
				if( !cd.hasSetS("exitWarn",3) )
					hud.notify(Lang.t._("Press ESCAPE again to exit."));
				else
					App.ME.exit();
			#end

			// Attach debug drone (CTRL-SHIFT-D)
			#if debug
			if( ca.isPressed(ToggleDebugDrone) )
				new DebugDrone(); // <-- HERE: provide an Entity as argument to attach Drone near it
			#end

			// Restart whole game
			if( ca.isPressed(Restart) )
				App.ME.startGame();

		}
	}
}

