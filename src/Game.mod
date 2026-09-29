IMPLEMENTATION MODULE Game;

IMPORT FrameBuffer, Visuals, Input, Audio, RNG, Arena;

CONST
  FP = 256;
  MaxShots = 56;
  MaxEnemies = 36;
  MaxEnemyShots = 72;
  MaxParticles = 128;
  MaxPowerups = 10;
  MaxStars = 72;

TYPE
  GameState = (Title, Controls, Hangar, LanSetup, LanPlaying, Playing,
               Paused, GameOver, Victory);
  PlayMode = (CampaignMode, EndlessMode, BossRushMode, GauntletMode,
              TimeAttackMode, LanCoopMode, LanVersusMode);

  PlayerRec = RECORD
    x, y, vx, vy : INTEGER;
    cooldown, invuln : CARDINAL;
    lives : CARDINAL;
    shield, reserveShield : BOOLEAN;
    rapidTimer, tripleTimer : CARDINAL;
    pulseCharge : CARDINAL
  END;

  ShotRec = RECORD
    active : BOOLEAN;
    x, y, vx, vy : INTEGER;
    power : CARDINAL
  END;

  EnemyRec = RECORD
    active : BOOLEAN;
    kind : CARDINAL;
    x, y, vx, vy : INTEGER;
    health : INTEGER;
    phase, fireTimer : CARDINAL
  END;

  EnemyShotRec = RECORD
    active : BOOLEAN;
    x, y, vx, vy : INTEGER
  END;

  ParticleRec = RECORD
    active : BOOLEAN;
    x, y, vx, vy : INTEGER;
    life, kind : CARDINAL
  END;

  PowerupRec = RECORD
    active : BOOLEAN;
    kind : CARDINAL;
    x, y, vy : INTEGER;
    life : CARDINAL
  END;

  StarRec = RECORD
    x : INTEGER;
    y, speed : INTEGER;
    layer : CARDINAL
  END;

VAR
  state : GameState;
  player : PlayerRec;
  shots : ARRAY [0..MaxShots-1] OF ShotRec;
  enemies : ARRAY [0..MaxEnemies-1] OF EnemyRec;
  enemyShots : ARRAY [0..MaxEnemyShots-1] OF EnemyShotRec;
  particles : ARRAY [0..MaxParticles-1] OF ParticleRec;
  powerups : ARRAY [0..MaxPowerups-1] OF PowerupRec;
  stars : ARRAY [0..MaxStars-1] OF StarRec;

  tick, score, bestScore : CARDINAL;
  wave, waveTimer, spawnTimer, sectorBanner : CARDINAL;
  combo, comboTimer : CARDINAL;
  shake, flash : CARDINAL;
  quitWanted : BOOLEAN;

  bossActive : BOOLEAN;
  bossX, bossY, bossVX : INTEGER;
  bossHealth, bossMaxHealth, bossFire : CARDINAL;
  bossKind, bossPhase, bossesDefeated : CARDINAL;
  selectedMode, gameMode : PlayMode;
  selectedShip, selectedModifier, selectedTrack, hangarRow : CARDINAL;
  timeRemaining : CARDINAL;
  modeIsHost : BOOLEAN;
  lanError : BOOLEAN;
  ipOctets : ARRAY [0..3] OF CARDINAL;
  ipCursor, ipTyping : CARDINAL;
  lanMusicStage : CARDINAL;

PROCEDURE AbsI(v : INTEGER) : INTEGER;
BEGIN
  IF v < 0 THEN RETURN -v END;
  RETURN v
END AbsI;

PROCEDURE DivideSigned(value, divisor : INTEGER) : INTEGER;
BEGIN
  IF value < 0 THEN RETURN -((-value + divisor - 1) DIV divisor) END;
  RETURN value DIV divisor
END DivideSigned;

PROCEDURE MinC(a, b : CARDINAL) : CARDINAL;
BEGIN
  IF a < b THEN RETURN a END;
  RETURN b
END MinC;

PROCEDURE DifficultyLevel() : CARDINAL;
BEGIN
  IF gameMode = BossRushMode THEN RETURN 3 END;
  IF gameMode = GauntletMode THEN RETURN MinC(3, 1 + wave DIV 3) END;
  IF gameMode = TimeAttackMode THEN RETURN MinC(3, 1 + wave DIV 5) END;
  IF wave <= 2 THEN RETURN 0 END;
  IF wave <= 7 THEN RETURN 1 END;
  IF wave <= 15 THEN RETURN 2 END;
  RETURN 3
END DifficultyLevel;

PROCEDURE ClampI(v, lo, hi : INTEGER) : INTEGER;
BEGIN
  IF v < lo THEN RETURN lo END;
  IF v > hi THEN RETURN hi END;
  RETURN v
END ClampI;

PROCEDURE Tri(phase, period, amplitude : CARDINAL) : INTEGER;
VAR p : CARDINAL; v : INTEGER;
BEGIN
  IF period = 0 THEN RETURN 0 END;
  p := phase MOD (period*2);
  IF p < period THEN
    v := VAL(INTEGER, p * amplitude DIV period)
  ELSE
    v := VAL(INTEGER, (period*2-p) * amplitude DIV period)
  END;
  RETURN v - VAL(INTEGER, amplitude DIV 2)
END Tri;

PROCEDURE ClearObjects;
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxShots-1 DO shots[i].active := FALSE END;
  FOR i := 0 TO MaxEnemies-1 DO enemies[i].active := FALSE END;
  FOR i := 0 TO MaxEnemyShots-1 DO enemyShots[i].active := FALSE END;
  FOR i := 0 TO MaxParticles-1 DO particles[i].active := FALSE END;
  FOR i := 0 TO MaxPowerups-1 DO powerups[i].active := FALSE END
END ClearObjects;

PROCEDURE InitStars;
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxStars-1 DO
    stars[i].x := VAL(INTEGER, RNG.Range(FrameBuffer.Width));
    stars[i].y := VAL(INTEGER, RNG.Range(FrameBuffer.Height)) * FP;
    stars[i].layer := i MOD 3;
    stars[i].speed := VAL(INTEGER, (stars[i].layer + 1) * 46)
  END
END InitStars;

PROCEDURE UpdateStars;
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxStars-1 DO
    stars[i].y := stars[i].y + stars[i].speed;
    IF stars[i].y >= FrameBuffer.Height*FP THEN
      stars[i].y := 0;
      stars[i].x := VAL(INTEGER, RNG.Range(FrameBuffer.Width));
      stars[i].layer := RNG.Range(3);
      stars[i].speed := VAL(INTEGER, (stars[i].layer + 1) * 46)
    END
  END
END UpdateStars;

PROCEDURE Burst(x, y : INTEGER; count, kind : CARDINAL);
VAR i, slot : CARDINAL; angle : INTEGER;
BEGIN
  slot := 0;
  FOR i := 0 TO count-1 DO
    LOOP
      IF slot = MaxParticles THEN EXIT END;
      IF NOT particles[slot].active THEN EXIT END;
      INC(slot)
    END;
    IF slot = MaxParticles THEN RETURN END;
    particles[slot].active := TRUE;
    particles[slot].x := x*FP;
    particles[slot].y := y*FP;
    particles[slot].vx := RNG.Between(-220, 220);
    particles[slot].vy := RNG.Between(-220, 220);
    angle := RNG.Between(0, 2);
    particles[slot].vx := particles[slot].vx + angle*20;
    particles[slot].life := 18 + RNG.Range(22);
    particles[slot].kind := kind;
    INC(slot)
  END
END Burst;

PROCEDURE SpawnPlayerShot(x, y, vx, vy : INTEGER; power : CARDINAL);
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxShots-1 DO
    IF NOT shots[i].active THEN
      shots[i].active := TRUE;
      shots[i].x := x*FP; shots[i].y := y*FP;
      shots[i].vx := vx; shots[i].vy := vy;
      shots[i].power := power;
      RETURN
    END
  END
END SpawnPlayerShot;

PROCEDURE SpawnEnemyShot(x, y : INTEGER; dx, dy : INTEGER);
VAR i, den : CARDINAL; adx, ady : INTEGER;
BEGIN
  FOR i := 0 TO MaxEnemyShots-1 DO
    IF NOT enemyShots[i].active THEN
      adx := AbsI(dx); ady := AbsI(dy);
      den := VAL(CARDINAL, adx + ady);
      IF den = 0 THEN den := 1 END;
      enemyShots[i].active := TRUE;
      enemyShots[i].x := x*FP; enemyShots[i].y := y*FP;
      enemyShots[i].vx := DivideSigned(dx * 340, VAL(INTEGER, den));
      enemyShots[i].vy := DivideSigned(dy * 340, VAL(INTEGER, den));
      RETURN
    END
  END
END SpawnEnemyShot;

PROCEDURE SpawnPowerup(x, y : INTEGER);
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxPowerups-1 DO
    IF NOT powerups[i].active THEN
      powerups[i].active := TRUE;
      powerups[i].kind := RNG.Range(7);
      powerups[i].x := x*FP; powerups[i].y := y*FP;
      powerups[i].vy := 72;
      powerups[i].life := 720;
      RETURN
    END
  END
END SpawnPowerup;

PROCEDURE EnemyDestroyed(index : CARDINAL);
VAR x, y, base : INTEGER;
BEGIN
  x := DivideSigned(enemies[index].x, FP);
  y := DivideSigned(enemies[index].y, FP);
  base := 100 + VAL(INTEGER, enemies[index].kind)*75;
  enemies[index].active := FALSE;
  Burst(x, y, 10 + enemies[index].kind*3, enemies[index].kind);
  Audio.Play(Audio.Explosion);

  IF comboTimer > 0 THEN
    IF combo < 8 THEN INC(combo) END
  ELSE combo := 1
  END;
  comboTimer := 180;
  score := score + VAL(CARDINAL, base) * combo;
  IF selectedModifier = 3 THEN
    player.pulseCharge := MinC(100, player.pulseCharge + 10 + enemies[index].kind)
  ELSIF selectedModifier = 5 THEN
    player.pulseCharge := MinC(100, player.pulseCharge + 2 + enemies[index].kind DIV 2)
  ELSIF selectedModifier = 6 THEN
    player.pulseCharge := MinC(100, player.pulseCharge + 3 + enemies[index].kind DIV 2)
  ELSE
    player.pulseCharge := MinC(100, player.pulseCharge + 5 + enemies[index].kind)
  END;
  IF selectedModifier = 4 THEN
    score := score + VAL(CARDINAL, base) * combo
  END;
  IF RNG.Range(10) = 0 THEN SpawnPowerup(x, y) END
END EnemyDestroyed;

PROCEDURE SpawnEnemy;
VAR i, k, tier, r, level : CARDINAL;
BEGIN
  FOR i := 0 TO MaxEnemies-1 DO
    IF NOT enemies[i].active THEN
      tier := DifficultyLevel();
      level := MinC(16, wave);
      r := RNG.Range(100);
      CASE tier OF
        0 : IF r < 64 THEN k := 0 ELSE k := 1 END
      | 1 : IF r < 42 THEN k := 0
            ELSIF r < 70 THEN k := 1
            ELSIF r < 88 THEN k := 2
            ELSE k := 3
            END
      | 2 : IF r < 26 THEN k := 0
            ELSIF r < 48 THEN k := 1
            ELSIF r < 66 THEN k := 2
            ELSIF r < 80 THEN k := 3
            ELSIF r < 92 THEN k := 4
            ELSE k := 5
            END
      ELSE
            IF r < 12 THEN k := 0
            ELSIF r < 23 THEN k := 1
            ELSIF r < 34 THEN k := 2
            ELSIF r < 45 THEN k := 3
            ELSIF r < 56 THEN k := 4
            ELSIF r < 67 THEN k := 5
            ELSIF r < 77 THEN k := 6
            ELSIF r < 86 THEN k := 7
            ELSIF r < 93 THEN k := 8
            ELSIF r < 97 THEN k := 9
            ELSE k := 10
            END
      END;

      enemies[i].active := TRUE;
      enemies[i].kind := k;
      enemies[i].x := VAL(INTEGER, 18 + RNG.Range(284))*FP;
      enemies[i].y := -12*FP;
      enemies[i].phase := RNG.Range(180);

      CASE k OF
        0 : enemies[i].vx := RNG.Between(-58, 58);
            enemies[i].vy := 100 + VAL(INTEGER, level*2);
            enemies[i].health := 1;
            enemies[i].fireTimer := 92 + RNG.Range(110)
      | 1 : enemies[i].vx := RNG.Between(-42, 42);
            enemies[i].vy := 132 + VAL(INTEGER, level*3);
            enemies[i].health := 1;
            enemies[i].fireTimer := 110 + RNG.Range(120)
      | 2 : enemies[i].vx := RNG.Between(-48, 48);
            enemies[i].vy := 78 + VAL(INTEGER, level*2);
            enemies[i].health := 3;
            enemies[i].fireTimer := 84 + RNG.Range(96)
      | 3 : enemies[i].vx := RNG.Between(-36, 36);
            enemies[i].vy := 88 + VAL(INTEGER, level*2);
            enemies[i].health := 2;
            enemies[i].fireTimer := 72 + RNG.Range(84)
      | 4 : enemies[i].vx := RNG.Between(-64, 64);
            enemies[i].vy := 86 + VAL(INTEGER, level*2);
            enemies[i].health := 2;
            enemies[i].fireTimer := 64 + RNG.Range(76)
      | 5 : enemies[i].vx := RNG.Between(-34, 34);
            enemies[i].vy := 62 + VAL(INTEGER, level);
            enemies[i].health := 5;
            enemies[i].fireTimer := 98 + RNG.Range(72)
      | 6 : enemies[i].vx := RNG.Between(-115, 115);
            enemies[i].vy := 150 + VAL(INTEGER, level*3);
            enemies[i].health := 2;
            enemies[i].fireTimer := 128 + RNG.Range(90)
      | 7 : enemies[i].vx := RNG.Between(-48, 48);
            enemies[i].vy := 112 + VAL(INTEGER, level*2);
            enemies[i].health := 2;
            enemies[i].fireTimer := 94 + RNG.Range(70)
      | 8 : enemies[i].vx := RNG.Between(-30, 30);
            enemies[i].vy := 64 + VAL(INTEGER, level);
            enemies[i].health := 4;
            enemies[i].fireTimer := 68 + RNG.Range(76)
      | 9 : enemies[i].vx := RNG.Between(-80, 80);
            enemies[i].vy := 126 + VAL(INTEGER, level*2);
            enemies[i].health := 2;
            enemies[i].fireTimer := 108 + RNG.Range(90)
      | 10: enemies[i].vx := RNG.Between(-20, 20);
            enemies[i].vy := 88 + VAL(INTEGER, level);
            enemies[i].health := 6;
            enemies[i].fireTimer := 80 + RNG.Range(70)
      ELSE enemies[i].vx := 0; enemies[i].vy := 100; enemies[i].health := 1;
           enemies[i].fireTimer := 120
      END;
      RETURN
    END
  END
END SpawnEnemy;

PROCEDURE SpawnBoss;
VAR base, encounter : CARDINAL;
BEGIN
  bossActive := TRUE;
  bossX := 160*FP; bossY := 30*FP;
  bossPhase := 0;

  IF gameMode = BossRushMode THEN
    bossKind := bossesDefeated MOD 8;
    encounter := bossesDefeated
  ELSIF gameMode = GauntletMode THEN
    encounter := wave DIV 2;
    IF encounter > 0 THEN DEC(encounter) END;
    bossKind := encounter MOD 8
  ELSE
    encounter := wave DIV 3;
    IF encounter > 0 THEN DEC(encounter) END;
    bossKind := encounter MOD 8
  END;

  CASE bossKind OF
    0 : base := 120; bossVX := 72; bossFire := 72
  | 1 : base := 145; bossVX := 58; bossFire := 82
  | 2 : base := 170; bossVX := 118; bossFire := 76
  | 3 : base := 200; bossVX := 42; bossFire := 68
  | 4 : base := 190; bossVX := 85; bossFire := 66
  | 5 : base := 210; bossVX := 75; bossFire := 70
  | 6 : base := 230; bossVX := 100; bossFire := 62
  ELSE base := 250; bossVX := 65; bossFire := 58
  END;

  bossMaxHealth := base + MinC(112, encounter*14);
  bossHealth := bossMaxHealth;
  sectorBanner := 150;
  Audio.Play(Audio.BossPulse);
  Audio.SetIntensity(3)
END SpawnBoss;

PROCEDURE EnterTitle;
BEGIN
  state := Title;
  Audio.SetMusic(TRUE);
  Audio.SetMusicMode(Audio.ThemeTrack);
  Audio.SetIntensity(0)
END EnterTitle;

PROCEDURE StartGame;
BEGIN
  ClearObjects;
  gameMode := selectedMode;
  player.x := 160*FP; player.y := 148*FP;
  player.vx := 0; player.vy := 0;
  player.cooldown := 0; player.invuln := 120;
  player.lives := 3; player.shield := FALSE; player.reserveShield := FALSE;
  CASE selectedShip OF
    1 : player.lives := 2
  | 2 : player.lives := 4; player.shield := TRUE
  | 3 : player.lives := 3
  | 4 : player.lives := 2
  ELSE
  END;
  IF selectedModifier = 1 THEN
    IF player.lives > 1 THEN DEC(player.lives) END
  ELSIF selectedModifier = 2 THEN
    IF player.shield THEN player.reserveShield := TRUE
    ELSE player.shield := TRUE END
  END;
  IF (gameMode = TimeAttackMode) AND (player.lives < 4) THEN
    INC(player.lives)
  END;
  player.rapidTimer := 0; player.tripleTimer := 0; player.pulseCharge := 0;
  IF selectedShip = 3 THEN player.pulseCharge := 45 END;
  IF selectedModifier = 5 THEN player.pulseCharge := 100 END;
  IF selectedModifier = 1 THEN player.rapidTimer := 18000 END;
  score := 0; bossesDefeated := 0;
  IF gameMode = BossRushMode THEN
    wave := 3; waveTimer := 0; spawnTimer := 9999; sectorBanner := 180
  ELSE
    wave := 1; waveTimer := 0; spawnTimer := 30; sectorBanner := 120
  END;
  IF gameMode = TimeAttackMode THEN timeRemaining := 14400 ELSE timeRemaining := 0 END;
  combo := 1; comboTimer := 0; shake := 0; flash := 0;
  bossActive := FALSE; bossHealth := 0; bossMaxHealth := 0; bossPhase := 0;
  state := Playing;
  Audio.SetMusic(TRUE);
  Audio.StartTrack(selectedTrack);
  IF gameMode = BossRushMode THEN Audio.SetIntensity(2) ELSE Audio.SetIntensity(1) END;
  Audio.Play(Audio.StartJingle)
END StartGame;

PROCEDURE DamagePlayer;
BEGIN
  IF player.invuln > 0 THEN RETURN END;
  IF player.shield THEN
    IF player.reserveShield THEN player.reserveShield := FALSE
    ELSE player.shield := FALSE END;
    player.invuln := 75;
    Burst(player.x DIV FP, player.y DIV FP, 18, 1);
    Audio.Play(Audio.Hurt);
    shake := 8; flash := 4;
    RETURN
  END;
  Audio.Play(Audio.Hurt);
  Burst(player.x DIV FP, player.y DIV FP, 26, 0);
  shake := 14; flash := 7;
  IF player.lives > 0 THEN DEC(player.lives) END;
  IF player.lives = 0 THEN
    state := GameOver;
    Audio.SetIntensity(0);
    IF score > bestScore THEN bestScore := score END
  ELSE
    player.x := 160*FP; player.y := 148*FP;
    player.vx := 0; player.vy := 0; player.invuln := 150
  END
END DamagePlayer;

PROCEDURE FirePlayer;
VAR px, py : INTEGER; cd, power : CARDINAL;
BEGIN
  IF player.cooldown # 0 THEN RETURN END;
  px := player.x DIV FP; py := player.y DIV FP;
  power := 1;
  IF selectedShip = 4 THEN power := 2 END;
  IF selectedModifier = 6 THEN INC(power) END;
  IF player.tripleTimer > 0 THEN
    SpawnPlayerShot(px-4, py-7, -55, -760, power);
    SpawnPlayerShot(px, py-9, 0, -810, power+1);
    SpawnPlayerShot(px+4, py-7, 55, -760, power)
  ELSE
    SpawnPlayerShot(px, py-8, 0, -820, power)
  END;
  IF player.rapidTimer > 0 THEN cd := 5 ELSE cd := 9 END;
  IF selectedShip = 1 THEN
    IF cd > 2 THEN DEC(cd, 2) END
  ELSIF selectedShip = 2 THEN INC(cd, 2)
  END;
  IF selectedModifier = 3 THEN INC(cd) END;
  IF selectedModifier = 1 THEN
    IF cd > 2 THEN DEC(cd) END
  ELSIF selectedModifier = 6 THEN INC(cd, 3)
  END;
  player.cooldown := cd;
  Audio.Play(Audio.Laser)
END FirePlayer;

PROCEDURE ActivatePulse;
VAR i : CARDINAL;
BEGIN
  IF player.pulseCharge < 100 THEN RETURN END;
  player.pulseCharge := 0;
  FOR i := 0 TO MaxEnemyShots-1 DO
    IF enemyShots[i].active THEN
      Burst(DivideSigned(enemyShots[i].x, FP),
            DivideSigned(enemyShots[i].y, FP), 2, 1);
      enemyShots[i].active := FALSE
    END
  END;
  FOR i := 0 TO MaxEnemies-1 DO
    IF enemies[i].active THEN
      DEC(enemies[i].health);
      IF enemies[i].health <= 0 THEN EnemyDestroyed(i) END
    END
  END;
  IF bossActive THEN
    IF bossHealth > 12 THEN bossHealth := bossHealth - 12 ELSE bossHealth := 0 END
  END;
  Burst(player.x DIV FP, player.y DIV FP, 40, 1);
  Audio.Play(Audio.Power);
  shake := 10; flash := 8
END ActivatePulse;

PROCEDURE UpdatePlayer;
VAR ax, ay, accel, maxSpeed : INTEGER;
BEGIN
  accel := 118; maxSpeed := 700;
  CASE selectedShip OF
    1 : accel := 145; maxSpeed := 850
  | 2 : accel := 94; maxSpeed := 570
  | 3 : accel := 132; maxSpeed := 760
  | 4 : accel := 125; maxSpeed := 740
  ELSE
  END;
  IF selectedModifier = 2 THEN
    accel := accel * 4 DIV 5;
    maxSpeed := maxSpeed * 4 DIV 5
  END;
  ax := 0; ay := 0;
  IF Input.Held(Input.Left) THEN ax := ax - accel END;
  IF Input.Held(Input.Right) THEN ax := ax + accel END;
  IF Input.Held(Input.Up) THEN ay := ay - accel END;
  IF Input.Held(Input.Down) THEN ay := ay + accel END;

  (* Snappy arcade movement, with just enough drift to not feel robotic. *)
  player.vx := player.vx + ax; player.vy := player.vy + ay;
  IF ax = 0 THEN player.vx := DivideSigned(player.vx, 2) END;
  IF ay = 0 THEN player.vy := DivideSigned(player.vy, 2) END;
  player.vx := ClampI(player.vx, -maxSpeed, maxSpeed);
  player.vy := ClampI(player.vy, -maxSpeed, maxSpeed);
  player.x := player.x + player.vx; player.y := player.y + player.vy;
  player.x := ClampI(player.x, 10*FP, 310*FP);
  player.y := ClampI(player.y, 18*FP, 169*FP);

  IF player.cooldown > 0 THEN DEC(player.cooldown) END;
  IF player.invuln > 0 THEN DEC(player.invuln) END;
  IF (player.rapidTimer > 0) AND (selectedModifier # 1) THEN DEC(player.rapidTimer) END;
  IF player.tripleTimer > 0 THEN DEC(player.tripleTimer) END;

  (* Quick taps count too. Losing a shot because it landed between ticks felt like crap. *)
  IF Input.Held(Input.Fire) OR Input.Pressed(Input.Fire) THEN FirePlayer END;
  IF Input.Pressed(Input.AltFire) THEN ActivatePulse END
END UpdatePlayer;

PROCEDURE UpdateShots;
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxShots-1 DO
    IF shots[i].active THEN
      shots[i].x := shots[i].x + shots[i].vx;
      shots[i].y := shots[i].y + shots[i].vy;
      IF (shots[i].y < -10*FP) OR (shots[i].x < -10*FP) OR
         (shots[i].x > 330*FP) THEN shots[i].active := FALSE END
    END
  END
END UpdateShots;

PROCEDURE UpdateEnemies;
VAR i : CARDINAL; ex, ey, px, py, hitX, hitY : INTEGER;
BEGIN
  px := player.x DIV FP; py := player.y DIV FP;
  FOR i := 0 TO MaxEnemies-1 DO
    IF enemies[i].active THEN
      INC(enemies[i].phase);
      enemies[i].y := enemies[i].y + enemies[i].vy;

      CASE enemies[i].kind OF
        0 : enemies[i].x := enemies[i].x + enemies[i].vx +
              Tri(enemies[i].phase, 48, 34)
      | 1 : enemies[i].x := enemies[i].x + enemies[i].vx
      | 2 : enemies[i].x := enemies[i].x + DivideSigned(enemies[i].vx, 2);
            IF (enemies[i].phase MOD 90) = 0 THEN enemies[i].vx := -enemies[i].vx END
      | 3 : enemies[i].x := enemies[i].x + Tri(enemies[i].phase, 30, 58)
      | 4 : IF DivideSigned(enemies[i].x, FP) < px THEN
              enemies[i].vx := ClampI(enemies[i].vx + 5, -120, 120)
            ELSE
              enemies[i].vx := ClampI(enemies[i].vx - 5, -120, 120)
            END;
            enemies[i].x := enemies[i].x + enemies[i].vx
      | 5 : enemies[i].x := enemies[i].x + DivideSigned(enemies[i].vx, 3) +
              Tri(enemies[i].phase, 70, 18)
      | 6 : enemies[i].x := enemies[i].x + enemies[i].vx +
              Tri(enemies[i].phase, 22, 44)
      | 7 : enemies[i].x := enemies[i].x + enemies[i].vx +
              Tri(enemies[i].phase, 19, 86)
      | 8 : enemies[i].x := enemies[i].x + DivideSigned(enemies[i].vx, 4);
            IF (enemies[i].phase MOD 90) = 0 THEN enemies[i].vx := -enemies[i].vx END
      | 9 : IF (enemies[i].phase MOD 100) < 42 THEN
              enemies[i].x := enemies[i].x + enemies[i].vx * 2
            ELSE enemies[i].x := enemies[i].x + DivideSigned(enemies[i].vx, 3) END
      | 10: enemies[i].x := enemies[i].x + Tri(enemies[i].phase, 56, 30);
            IF (enemies[i].phase MOD 210) = 0 THEN SpawnEnemy END
      ELSE enemies[i].x := enemies[i].x + enemies[i].vx
      END;

      ex := DivideSigned(enemies[i].x, FP);
      ey := DivideSigned(enemies[i].y, FP);
      IF enemies[i].fireTimer > 0 THEN DEC(enemies[i].fireTimer)
      ELSE
        IF ey > 5 THEN
          CASE enemies[i].kind OF
            3 : SpawnEnemyShot(ex, ey+4, px-ex-28, py-ey);
                SpawnEnemyShot(ex, ey+4, px-ex+28, py-ey)
          | 4 : SpawnEnemyShot(ex-3, ey+4, px-ex, py-ey);
                SpawnEnemyShot(ex+3, ey+4, px-ex, py-ey)
          | 5 : SpawnEnemyShot(ex-6, ey+5, px-ex-38, py-ey);
                SpawnEnemyShot(ex, ey+5, px-ex, py-ey);
                SpawnEnemyShot(ex+6, ey+5, px-ex+38, py-ey)
          | 7 : SpawnEnemyShot(ex, ey+5, px-ex, py-ey);
                SpawnEnemyShot(ex, ey+5, px-ex+42, py-ey)
          | 8 : SpawnEnemyShot(ex-8, ey+5, -72, 260);
                SpawnEnemyShot(ex, ey+5, 0, 280);
                SpawnEnemyShot(ex+8, ey+5, 72, 260)
          | 9 : SpawnEnemyShot(ex, ey+4, px-ex, py-ey)
          | 10: SpawnEnemyShot(ex-7, ey+6, px-ex-25, py-ey);
                SpawnEnemyShot(ex+7, ey+6, px-ex+25, py-ey)
          ELSE SpawnEnemyShot(ex, ey+4, px-ex, py-ey)
          END
        END;
        CASE enemies[i].kind OF
          0 : enemies[i].fireTimer := 104 + RNG.Range(90)
        | 1 : enemies[i].fireTimer := 122 + RNG.Range(90)
        | 2 : enemies[i].fireTimer := 92 + RNG.Range(80)
        | 3 : enemies[i].fireTimer := 86 + RNG.Range(74)
        | 4 : enemies[i].fireTimer := 74 + RNG.Range(66)
        | 5 : enemies[i].fireTimer := 108 + RNG.Range(74)
        | 6 : enemies[i].fireTimer := 136 + RNG.Range(84)
        | 7 : enemies[i].fireTimer := 92 + RNG.Range(68)
        | 8 : enemies[i].fireTimer := 80 + RNG.Range(58)
        | 9 : enemies[i].fireTimer := 110 + RNG.Range(62)
        | 10: enemies[i].fireTimer := 98 + RNG.Range(74)
        ELSE enemies[i].fireTimer := 120
        END
      END;

      hitX := 9; hitY := 8;
      IF (enemies[i].kind = 5) OR (enemies[i].kind = 10) THEN hitX := 12; hitY := 9
      ELSIF enemies[i].kind = 6 THEN hitX := 10; hitY := 8
      END;
      IF ey > 195 THEN enemies[i].active := FALSE
      ELSIF (player.invuln = 0) AND (AbsI(ex-px) < hitX) AND (AbsI(ey-py) < hitY) THEN
        enemies[i].active := FALSE;
        Burst(ex, ey, 12, 0);
        DamagePlayer
      END
    END
  END
END UpdateEnemies;

PROCEDURE UpdateEnemyShots;
VAR i : CARDINAL; x, y, px, py : INTEGER;
BEGIN
  px := player.x DIV FP; py := player.y DIV FP;
  FOR i := 0 TO MaxEnemyShots-1 DO
    IF enemyShots[i].active THEN
      enemyShots[i].x := enemyShots[i].x + enemyShots[i].vx;
      enemyShots[i].y := enemyShots[i].y + enemyShots[i].vy;
      x := DivideSigned(enemyShots[i].x, FP);
      y := DivideSigned(enemyShots[i].y, FP);
      IF (x < -8) OR (x > 328) OR (y < -8) OR (y > 188) THEN
        enemyShots[i].active := FALSE
      ELSIF (player.invuln = 0) AND (AbsI(x-px) < 5) AND (AbsI(y-py) < 5) THEN
        enemyShots[i].active := FALSE;
        DamagePlayer
      END
    END
  END
END UpdateEnemyShots;

PROCEDURE UpdateParticles;
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxParticles-1 DO
    IF particles[i].active THEN
      particles[i].x := particles[i].x + particles[i].vx;
      particles[i].y := particles[i].y + particles[i].vy;
      particles[i].vx := DivideSigned(particles[i].vx * 15, 16);
      particles[i].vy := DivideSigned(particles[i].vy * 15, 16);
      IF particles[i].life > 0 THEN DEC(particles[i].life) END;
      IF particles[i].life = 0 THEN particles[i].active := FALSE END
    END
  END
END UpdateParticles;

PROCEDURE UpdatePowerups;
VAR i : CARDINAL; x, y, px, py : INTEGER;
BEGIN
  px := player.x DIV FP; py := player.y DIV FP;
  FOR i := 0 TO MaxPowerups-1 DO
    IF powerups[i].active THEN
      powerups[i].y := powerups[i].y + powerups[i].vy;
      x := DivideSigned(powerups[i].x, FP);
      y := DivideSigned(powerups[i].y, FP);
      IF powerups[i].life > 0 THEN DEC(powerups[i].life) END;
      IF (powerups[i].life = 0) OR (y > 190) THEN powerups[i].active := FALSE
      ELSIF (AbsI(x-px) < 10) AND (AbsI(y-py) < 10) THEN
        powerups[i].active := FALSE;
        CASE powerups[i].kind OF
          0 : IF player.shield THEN player.reserveShield := TRUE
              ELSE player.shield := TRUE END
        | 1 : player.rapidTimer := 900
        | 2 : player.tripleTimer := 900
        | 3 : IF player.lives < 4 THEN INC(player.lives)
              ELSE player.pulseCharge := MinC(100, player.pulseCharge + 35)
              END
        | 4 : player.pulseCharge := MinC(100, player.pulseCharge + 55)
        | 5 : score := score + 1250
        | 6 : player.invuln := 300
        END;
        score := score + 250;
        Burst(x, y, 18, 1);
        Audio.Play(Audio.Power)
      END
    END
  END
END UpdatePowerups;

PROCEDURE CheckShotCollisions;
VAR s, e : CARDINAL; sx, sy, ex, ey, hitX, hitY : INTEGER;
BEGIN
  FOR s := 0 TO MaxShots-1 DO
    IF shots[s].active THEN
      sx := DivideSigned(shots[s].x, FP);
      sy := DivideSigned(shots[s].y, FP);
      e := 0;
      WHILE (e < MaxEnemies) AND shots[s].active DO
        IF enemies[e].active THEN
          ex := DivideSigned(enemies[e].x, FP);
          ey := DivideSigned(enemies[e].y, FP);
          hitX := 9; hitY := 7;
          IF (enemies[e].kind = 5) OR (enemies[e].kind = 10) THEN hitX := 12; hitY := 9
          ELSIF enemies[e].kind = 6 THEN hitX := 10; hitY := 7
          END;
          IF (AbsI(sx-ex) < hitX) AND (AbsI(sy-ey) < hitY) THEN
            shots[s].active := FALSE;
            enemies[e].health := enemies[e].health - VAL(INTEGER, shots[s].power);
            Burst(sx, sy, 4, 1);
            IF enemies[e].health <= 0 THEN EnemyDestroyed(e) ELSE Audio.Play(Audio.Hit) END
          END
        END;
        INC(e)
      END;

      IF shots[s].active AND bossActive THEN
        CASE bossKind OF
          0 : hitX := 27; hitY := 12
        | 1 : hitX := 27; hitY := 15
        | 2 : hitX := 28; hitY := 14
        ELSE hitX := 29; hitY := 16
        END;
        IF (AbsI(sx - bossX DIV FP) < hitX) AND (AbsI(sy - bossY DIV FP) < hitY) THEN
          shots[s].active := FALSE;
          IF bossHealth > shots[s].power THEN bossHealth := bossHealth - shots[s].power
          ELSE bossHealth := 0
          END;
          Burst(sx, sy, 3, bossKind MOD 4);
          Audio.Play(Audio.Hit)
        END
      END
    END
  END
END CheckShotCollisions;

PROCEDURE BossDestroyed;
BEGIN
  Burst(bossX DIV FP, bossY DIV FP, 80, bossKind MOD 4);
  Audio.Play(Audio.Explosion); Audio.Play(Audio.Power);
  score := score + (5000 + bossKind*1250)*combo;
  bossActive := FALSE;
  shake := 24; flash := 16;
  sectorBanner := 180;
  INC(bossesDefeated);

  IF gameMode = BossRushMode THEN
    player.pulseCharge := MinC(100, player.pulseCharge + 40);
    IF (bossesDefeated MOD 2) = 0 THEN
      IF player.shield THEN player.reserveShield := TRUE
      ELSE player.shield := TRUE END
    END;
    IF bossesDefeated >= 8 THEN
      state := Victory; sectorBanner := 0;
      Audio.SetMusicMode(Audio.ThemeTrack);
      Audio.SetIntensity(0)
    ELSE
      wave := 3 + bossesDefeated*3;
      waveTimer := 0;
      spawnTimer := 9999;
      Audio.ShuffleTrack;
      Audio.SetIntensity(MinC(3, 2 + bossesDefeated DIV 4))
    END
  ELSIF (gameMode = CampaignMode) AND (wave >= 24) THEN
    state := Victory; sectorBanner := 0;
    Audio.SetMusicMode(Audio.ThemeTrack);
    Audio.SetIntensity(0)
  ELSE
    INC(wave);
    waveTimer := 0;
    spawnTimer := 84;
    Audio.ShuffleTrack;
    IF (gameMode = TimeAttackMode) AND ((bossesDefeated MOD 2) = 0) AND
       (player.lives < 4) THEN INC(player.lives) END;
    Audio.SetIntensity(MinC(3, wave DIV 4))
  END
END BossDestroyed;

PROCEDURE UpdateBoss;
VAR bx, bossYScreen, px, py, d : INTEGER; speed : INTEGER;
BEGIN
  IF NOT bossActive THEN RETURN END;
  INC(bossPhase);
  px := player.x DIV FP; py := player.y DIV FP;

  CASE bossKind OF
    0 : bossX := bossX + bossVX;
        IF bossX < 42*FP THEN bossX := 42*FP; bossVX := AbsI(bossVX) END;
        IF bossX > 278*FP THEN bossX := 278*FP; bossVX := -AbsI(bossVX) END;
        bossY := 30*FP
  | 1 : bossX := bossX + bossVX;
        IF bossX < 58*FP THEN bossX := 58*FP; bossVX := AbsI(bossVX) END;
        IF bossX > 262*FP THEN bossX := 262*FP; bossVX := -AbsI(bossVX) END;
        bossY := (30 + Tri(bossPhase, 84, 14))*FP
  | 2 : speed := 92;
        IF (bossPhase MOD 240) < 72 THEN speed := 148 END;
        IF bossVX < 0 THEN bossVX := -speed ELSE bossVX := speed END;
        bossX := bossX + bossVX;
        IF bossX < 38*FP THEN bossX := 38*FP; bossVX := AbsI(bossVX) END;
        IF bossX > 282*FP THEN bossX := 282*FP; bossVX := -AbsI(bossVX) END;
        bossY := 34*FP
  | 3 :
        bossX := (160 + Tri(bossPhase, 118, 154))*FP;
        bossY := (30 + Tri(bossPhase+41, 74, 12))*FP
  | 4 : bossX := (160 + Tri(bossPhase, 92, 170))*FP;
        bossY := (33 + Tri(bossPhase+21, 48, 18))*FP
  | 5 : bossX := bossX + bossVX;
        IF bossX < 48*FP THEN bossX := 48*FP; bossVX := AbsI(bossVX) END;
        IF bossX > 272*FP THEN bossX := 272*FP; bossVX := -AbsI(bossVX) END;
        bossY := (28 + Tri(bossPhase, 68, 12))*FP
  | 6 : speed := 55;
        IF (bossPhase MOD 190) < 45 THEN speed := 220 END;
        IF bossVX < 0 THEN bossVX := -speed ELSE bossVX := speed END;
        bossX := bossX + bossVX;
        IF bossX < 38*FP THEN bossX := 38*FP; bossVX := AbsI(bossVX) END;
        IF bossX > 282*FP THEN bossX := 282*FP; bossVX := -AbsI(bossVX) END;
        bossY := (32 + Tri(bossPhase, 80, 16))*FP
  ELSE bossX := (160 + Tri(bossPhase, 140, 155))*FP;
       bossY := (28 + Tri(bossPhase+30, 58, 16))*FP
  END;

  bx := bossX DIV FP; bossYScreen := bossY DIV FP;

  IF (bossKind = 2) AND ((bossPhase MOD 300) = 1) THEN
    SpawnEnemy; SpawnEnemy
  END;

  IF bossFire > 0 THEN DEC(bossFire)
  ELSE
    CASE bossKind OF
      0 : SpawnEnemyShot(bx-13, bossYScreen+8, px-(bx-13), py-(bossYScreen+8));
          SpawnEnemyShot(bx+13, bossYScreen+8, px-(bx+13), py-(bossYScreen+8));
          IF (bossPhase MOD 240) < 80 THEN
            FOR d := -2 TO 2 DO SpawnEnemyShot(bx, bossYScreen+8, d*72, 320) END
          END;
          bossFire := 58 + RNG.Range(22)
    | 1 : FOR d := -2 TO 2 DO SpawnEnemyShot(bx, bossYScreen+8, d*62, 330) END;
          IF (bossPhase MOD 3) = 0 THEN
            SpawnEnemyShot(bx, bossYScreen+7, px-bx, py-bossYScreen)
          END;
          bossFire := 70 + RNG.Range(20)
    | 2 : SpawnEnemyShot(bx-15, bossYScreen+8, px-(bx-15), py-(bossYScreen+8));
          SpawnEnemyShot(bx, bossYScreen+10, px-bx, py-(bossYScreen+10));
          SpawnEnemyShot(bx+15, bossYScreen+8, px-(bx+15), py-(bossYScreen+8));
          bossFire := 64 + RNG.Range(22)
    | 3 :
          IF (bossPhase MOD 2) = 0 THEN
            FOR d := -3 TO 3 DO SpawnEnemyShot(bx, bossYScreen+7, d*52, 330) END
          ELSE
            SpawnEnemyShot(bx-10, bossYScreen+8, px-(bx-10), py-(bossYScreen+8));
            SpawnEnemyShot(bx+10, bossYScreen+8, px-(bx+10), py-(bossYScreen+8))
          END;
          bossFire := 52 + RNG.Range(16)
    | 4 : SpawnEnemyShot(bx-19, bossYScreen+9, px-(bx-19), py-bossYScreen);
          SpawnEnemyShot(bx+19, bossYScreen+9, px-(bx+19), py-bossYScreen);
          SpawnEnemyShot(bx, bossYScreen+8, 0, 340);
          bossFire := 62 + RNG.Range(20)
    | 5 : FOR d := -2 TO 2 DO
            SpawnEnemyShot(bx+d*9, bossYScreen+8, d*85, 340)
          END;
          bossFire := 66 + RNG.Range(20)
    | 6 : SpawnEnemyShot(bx-16, bossYScreen+10, px-bx-40, py-bossYScreen);
          SpawnEnemyShot(bx, bossYScreen+10, px-bx, py-bossYScreen);
          SpawnEnemyShot(bx+16, bossYScreen+10, px-bx+40, py-bossYScreen);
          bossFire := 58 + RNG.Range(16)
    ELSE FOR d := -3 TO 3 DO
            IF (d MOD 2) = 0 THEN
              SpawnEnemyShot(bx, bossYScreen+8, d*56, 340)
            END
          END;
          SpawnEnemyShot(bx, bossYScreen+8, px-bx, py-bossYScreen);
          bossFire := 54 + RNG.Range(16)
    END
  END;

  IF bossHealth = 0 THEN BossDestroyed END
END UpdateBoss;

PROCEDURE UpdateWave;
VAR rate, limit, tier : CARDINAL;
BEGIN
  IF bossActive THEN RETURN END;
  INC(waveTimer);

  IF gameMode = BossRushMode THEN
    IF waveTimer > 150 THEN SpawnBoss END;
    RETURN
  END;

  IF ((gameMode = GauntletMode) AND ((wave MOD 2) = 0)) OR
     ((gameMode # GauntletMode) AND ((wave MOD 3) = 0)) THEN
    IF waveTimer > 92 THEN SpawnBoss END;
    RETURN
  END;

  tier := DifficultyLevel();
  IF spawnTimer > 0 THEN DEC(spawnTimer)
  ELSE
    SpawnEnemy;
    IF (tier >= 2) AND (RNG.Range(5) = 0) THEN SpawnEnemy END;
    IF (tier >= 3) AND (RNG.Range(10) = 0) THEN SpawnEnemy END;

    IF gameMode = GauntletMode THEN
      CASE tier OF
        0 : rate := 38
      | 1 : rate := 34
      | 2 : rate := 29
      ELSE rate := 26
      END
    ELSIF gameMode = EndlessMode THEN
      CASE tier OF
        0 : rate := 45
      | 1 : rate := 37
      | 2 : rate := 30
      ELSE rate := 25
      END
    ELSE
      CASE tier OF
        0 : rate := 50
      | 1 : rate := 42
      | 2 : rate := 35
      ELSE rate := 29
      END
    END;
    spawnTimer := rate + RNG.Range(16);
    IF selectedModifier = 4 THEN spawnTimer := spawnTimer*4 DIV 5 END
  END;

  IF gameMode = EndlessMode THEN limit := 780
  ELSIF gameMode = GauntletMode THEN limit := 660
  ELSIF gameMode = TimeAttackMode THEN limit := 720
  ELSE limit := 840
  END;
  IF waveTimer >= limit THEN
    INC(wave); waveTimer := 0; spawnTimer := 64; sectorBanner := 120;
    Audio.SetIntensity(MinC(3, wave DIV 4));
    IF ((gameMode = GauntletMode) AND ((wave MOD 2) = 0)) OR
       ((gameMode # GauntletMode) AND ((wave MOD 3) = 0)) THEN
      spawnTimer := 9999
    END
  END
END UpdateWave;

PROCEDURE UpdatePlaying;
BEGIN
  IF Input.Pressed(Input.Menu) THEN
    EnterTitle; Audio.Play(Audio.MenuBlip); RETURN
  END;
  IF Input.Pressed(Input.Back) OR Input.Pressed(Input.Pause) THEN
    state := Paused; Audio.Play(Audio.MenuBlip); RETURN
  END;
  UpdatePlayer;
  UpdateShots;
  UpdateEnemies;
  UpdateEnemyShots;
  UpdateParticles;
  UpdatePowerups;
  UpdateBoss;
  CheckShotCollisions;
  UpdateWave;

  IF (gameMode = TimeAttackMode) AND (state = Playing) THEN
    IF timeRemaining > 0 THEN DEC(timeRemaining) END;
    IF timeRemaining = 0 THEN
      state := Victory;
      sectorBanner := 0;
      bossActive := FALSE;
      Audio.SetMusicMode(Audio.ThemeTrack)
    END
  END;

  IF comboTimer > 0 THEN DEC(comboTimer)
  ELSE combo := 1
  END;
  IF sectorBanner > 0 THEN DEC(sectorBanner) END;
  IF shake > 0 THEN DEC(shake) END;
  IF flash > 0 THEN DEC(flash) END
END UpdatePlaying;

PROCEDURE Init;
BEGIN
  RNG.Seed(918273);
  tick := 0; score := 0; bestScore := 0; wave := 1;
  combo := 1; comboTimer := 0; quitWanted := FALSE;
  shake := 0; flash := 0; sectorBanner := 0;
  bossActive := FALSE; bossKind := 0; bossPhase := 0; bossesDefeated := 0;
  selectedMode := CampaignMode; gameMode := CampaignMode;
  selectedShip := 0; selectedModifier := 0; selectedTrack := 6;
  hangarRow := 0; modeIsHost := TRUE; ipCursor := 0; ipTyping := 0;
  lanError := FALSE;
  ipOctets[0] := 192; ipOctets[1] := 168;
  ipOctets[2] := 1; ipOctets[3] := 2;
  ClearObjects; InitStars;
  EnterTitle
END Init;

PROCEDURE Update;
VAR digit : INTEGER; step, candidate : CARDINAL;
BEGIN
  INC(tick);
  UpdateStars;
  CASE state OF
    Title:
      UpdateParticles;
      IF (tick MOD 90) = 0 THEN Burst(VAL(INTEGER, 30+RNG.Range(260)), VAL(INTEGER, 20+RNG.Range(95)), 4, 1) END;
      IF Input.MenuStep(Input.Left) THEN
        selectedMode := VAL(PlayMode, (ORD(selectedMode)+6) MOD 7);
        Audio.Play(Audio.MenuBlip)
      ELSIF Input.MenuStep(Input.Right) THEN
        selectedMode := VAL(PlayMode, (ORD(selectedMode)+1) MOD 7);
        Audio.Play(Audio.MenuBlip)
      END;
      IF Input.MenuStep(Input.Up) THEN
        selectedShip := (selectedShip+4) MOD 5;
        Audio.Play(Audio.MenuBlip)
      ELSIF Input.MenuStep(Input.Down) THEN
        selectedShip := (selectedShip+1) MOD 5;
        Audio.Play(Audio.MenuBlip)
      END;
      IF Input.Pressed(Input.Cancel) THEN quitWanted := TRUE
      ELSIF Input.Pressed(Input.Menu) THEN
        state := Controls; Audio.Play(Audio.MenuBlip)
      ELSIF Input.Pressed(Input.AltFire) THEN
        state := Hangar; hangarRow := 0; Audio.Play(Audio.MenuBlip)
      ELSIF Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire) THEN
        IF (selectedMode = LanCoopMode) OR (selectedMode = LanVersusMode) THEN
          state := LanSetup; lanError := FALSE; Audio.Play(Audio.MenuBlip)
        ELSE StartGame
        END
      ELSIF Input.Pressed(Input.Back) OR Input.Pressed(Input.Cancel) THEN
        quitWanted := TRUE
      END
  | Controls:
      UpdateParticles;
      IF Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) OR
         Input.Pressed(Input.Cancel) OR Input.Pressed(Input.Start) OR
         Input.Pressed(Input.Fire) THEN
        state := Title; Audio.Play(Audio.MenuBlip)
      END
  | Hangar:
      UpdateParticles;
      IF Input.MenuStep(Input.Up) THEN
        hangarRow := (hangarRow+2) MOD 3; Audio.Play(Audio.MenuBlip)
      ELSIF Input.MenuStep(Input.Down) THEN
        hangarRow := (hangarRow+1) MOD 3; Audio.Play(Audio.MenuBlip)
      END;
      IF Input.MenuStep(Input.Left) OR Input.MenuStep(Input.Right) THEN
        IF hangarRow = 0 THEN
          IF Input.MenuStep(Input.Left) THEN selectedShip := (selectedShip+4) MOD 5
          ELSE selectedShip := (selectedShip+1) MOD 5 END
        ELSIF hangarRow = 1 THEN
          IF Input.MenuStep(Input.Left) THEN selectedModifier := (selectedModifier+6) MOD 7
          ELSE selectedModifier := (selectedModifier+1) MOD 7 END
        ELSE
          IF Input.MenuStep(Input.Left) THEN selectedTrack := (selectedTrack+6) MOD 7
          ELSE selectedTrack := (selectedTrack+1) MOD 7 END;
          IF selectedTrack = 6 THEN Audio.SetMusicMode(Audio.ThemeTrack)
          ELSE
            Audio.SetTrack(selectedTrack);
            IF selectedTrack = 5 THEN Audio.SetMusicMode(Audio.ThemeTrack)
            ELSE Audio.SetMusicMode(Audio.SynthTrack) END
          END;
          Audio.SetIntensity(1)
        END;
        Audio.Play(Audio.MenuBlip)
      END;
      IF Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire) OR
         Input.Pressed(Input.Back) OR Input.Pressed(Input.Cancel) OR
         Input.Pressed(Input.Menu) THEN
        EnterTitle; Audio.Play(Audio.MenuBlip)
      END
  | LanSetup:
      UpdateParticles;
      IF Input.MenuStep(Input.Left) THEN ipCursor := (ipCursor+3) MOD 4; ipTyping := 0
      ELSIF Input.MenuStep(Input.Right) THEN ipCursor := (ipCursor+1) MOD 4; ipTyping := 0
      END;
      step := 1;
      IF Input.Held(Input.FastEdit) THEN step := 10 END;
      IF Input.MenuStep(Input.Up) THEN
        ipOctets[ipCursor] := (ipOctets[ipCursor]+step) MOD 256;
        ipTyping := 0
      ELSIF Input.MenuStep(Input.Down) THEN
        ipOctets[ipCursor] := (ipOctets[ipCursor]+256-step) MOD 256;
        ipTyping := 0
      END;
      digit := Input.TypedDigit();
      IF digit >= 0 THEN
        IF ipTyping = 0 THEN candidate := VAL(CARDINAL, digit)
        ELSE candidate := ipOctets[ipCursor]*10 + VAL(CARDINAL, digit)
        END;
        IF candidate <= 255 THEN
          ipOctets[ipCursor] := candidate;
          INC(ipTyping);
          IF ipTyping >= 3 THEN ipTyping := 0; ipCursor := (ipCursor+1) MOD 4 END
        ELSE
          ipOctets[ipCursor] := VAL(CARDINAL, digit); ipTyping := 1
        END;
        lanError := FALSE
      ELSIF Input.TypedDot() THEN
        ipCursor := (ipCursor+1) MOD 4; ipTyping := 0
      ELSIF Input.TypedBackspace() THEN
        IF ipTyping > 0 THEN
          ipOctets[ipCursor] := ipOctets[ipCursor] DIV 10;
          DEC(ipTyping)
        ELSE
          ipCursor := (ipCursor+3) MOD 4;
          ipOctets[ipCursor] := ipOctets[ipCursor] DIV 10
        END
      END;
      IF Input.Pressed(Input.SwitchRole) THEN
        modeIsHost := NOT modeIsHost; lanError := FALSE
      END;
      IF Input.Pressed(Input.Back) OR Input.Pressed(Input.Cancel) OR
         Input.Pressed(Input.Menu) THEN state := Title
      ELSIF (Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire)) AND
            NOT Input.Held(Input.Up) AND NOT Input.Held(Input.Down) THEN
        IF Arena.Start(selectedMode = LanCoopMode, modeIsHost,
                       ipOctets[0], ipOctets[1], ipOctets[2], ipOctets[3],
                       selectedShip, selectedModifier) THEN
          state := LanPlaying;
          lanError := FALSE; flash := 0;
          lanMusicStage := Arena.MusicStage();
          Audio.StartTrack(selectedTrack);
          Audio.SetIntensity(2)
        ELSE lanError := TRUE END
      END
  | LanPlaying:
      IF Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) THEN
        Arena.Close; EnterTitle
      ELSE
        Arena.Update;
        IF Arena.MusicStage() # lanMusicStage THEN
          lanMusicStage := Arena.MusicStage();
          IF (NOT Arena.Finished()) AND
             ((selectedMode = LanVersusMode) OR ((lanMusicStage MOD 2) = 1)) THEN
            Audio.ShuffleTrack
          END
        END;
        IF Arena.Finished() AND
           (Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire)) THEN
          Arena.Close; EnterTitle
        END
      END
  | Playing:
      UpdatePlaying
  | Paused:
      UpdateParticles;
      IF Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) OR
         Input.Pressed(Input.Cancel) THEN
        EnterTitle; Audio.Play(Audio.MenuBlip)
      ELSIF Input.Pressed(Input.Pause) OR Input.Pressed(Input.Start) OR
            Input.Pressed(Input.Fire) THEN
        state := Playing; Audio.Play(Audio.MenuBlip)
      END
  | GameOver:
      UpdateParticles;
      IF Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire) THEN StartGame
      ELSIF Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) OR
            Input.Pressed(Input.Cancel) THEN
        EnterTitle; Audio.Play(Audio.MenuBlip)
      END
  | Victory:
      UpdateParticles;
      IF Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire) OR
         Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) OR
         Input.Pressed(Input.Cancel) THEN
        EnterTitle; Audio.Play(Audio.MenuBlip)
      END
  END
END Update;

PROCEDURE DrawStars;
VAR i : CARDINAL; c : CARDINAL; y : INTEGER;
BEGIN
  FOR i := 0 TO MaxStars-1 DO
    CASE stars[i].layer OF
      0 : c := 3
    | 1 : c := 5
    ELSE c := 7
    END;
    y := stars[i].y DIV FP;
    FrameBuffer.PutPixel(stars[i].x, y, c);
    IF stars[i].layer = 2 THEN
      IF y > 0 THEN FrameBuffer.PutPixel(stars[i].x, y-1, 4) END
    END
  END
END DrawStars;

PROCEDURE DrawNebula;
VAR x, y : INTEGER; phase : CARDINAL;
BEGIN
  phase := tick DIV 2;
  y := 18;
  WHILE y < 150 DO
    x := 12 + VAL(INTEGER, (VAL(CARDINAL, y*13) + phase) MOD 41);
    WHILE x < 310 DO
      IF ((x + y + VAL(INTEGER, phase)) MOD 7) = 0 THEN FrameBuffer.PutPixel(x, y, 2) END;
      x := x + 43
    END;
    y := y + 11
  END
END DrawNebula;

PROCEDURE CardText(n : CARDINAL; VAR out : ARRAY OF CHAR; minDigits : CARDINAL);
VAR temp : ARRAY [0..15] OF CHAR; i, j, digits : CARDINAL;
BEGIN
  FOR i := 0 TO HIGH(out) DO out[i] := CHR(0) END;
  i := 0;
  REPEAT
    temp[i] := CHR(ORD('0') + (n MOD 10));
    n := n DIV 10; INC(i)
  UNTIL (n = 0) OR (i > HIGH(temp));
  digits := i;
  WHILE (digits < minDigits) AND (i <= HIGH(temp)) DO temp[i] := '0'; INC(i); INC(digits) END;
  j := 0;
  WHILE (i > 0) AND (j < HIGH(out)) DO DEC(i); out[j] := temp[i]; INC(j) END;
  out[j] := CHR(0)
END CardText;

PROCEDURE CenterTextBox(x, w, y : INTEGER; text : ARRAY OF CHAR; colour, scale : CARDINAL);
VAR tw : CARDINAL; xx : INTEGER;
BEGIN
  tw := FrameBuffer.TextWidth(text, scale);
  xx := x + DivideSigned(w - VAL(INTEGER, tw), 2);
  IF xx < x THEN xx := x END;
  FrameBuffer.DrawText(xx, y, text, colour, scale)
END CenterTextBox;

PROCEDURE CenterText(y : INTEGER; text : ARRAY OF CHAR; colour, scale : CARDINAL);
BEGIN
  CenterTextBox(0, FrameBuffer.Width, y, text, colour, scale)
END CenterText;

PROCEDURE ShipLabel(x, y : INTEGER; colour : CARDINAL);
BEGIN
  CASE selectedShip OF
    0 : FrameBuffer.DrawText(x, y, "IRONWING", colour, 1)
  | 1 : FrameBuffer.DrawText(x, y, "KESTREL", colour, 1)
  | 2 : FrameBuffer.DrawText(x, y, "BASTION", colour, 1)
  | 3 : FrameBuffer.DrawText(x, y, "SPECTER", colour, 1)
  ELSE FrameBuffer.DrawText(x, y, "COMET", colour, 1)
  END
END ShipLabel;

PROCEDURE ModifierLabel(x, y : INTEGER; colour : CARDINAL);
BEGIN
  CASE selectedModifier OF
    0 : FrameBuffer.DrawText(x, y, "STANDARD", colour, 1)
  | 1 : FrameBuffer.DrawText(x, y, "OVERDRIVE", colour, 1)
  | 2 : FrameBuffer.DrawText(x, y, "FORTIFY", colour, 1)
  | 3 : FrameBuffer.DrawText(x, y, "SIPHON", colour, 1)
  | 4 : FrameBuffer.DrawText(x, y, "BOUNTY", colour, 1)
  | 5 : FrameBuffer.DrawText(x, y, "NOVA", colour, 1)
  ELSE FrameBuffer.DrawText(x, y, "FOCUS LENS", colour, 1)
  END
END ModifierLabel;

PROCEDURE TrackLabel(x, y : INTEGER; colour : CARDINAL);
BEGIN
  CASE selectedTrack OF
    0 : FrameBuffer.DrawText(x, y, "ION DRIFT", colour, 1)
  | 1 : FrameBuffer.DrawText(x, y, "NEON CHASE", colour, 1)
  | 2 : FrameBuffer.DrawText(x, y, "ASTER BLOOM", colour, 1)
  | 3 : FrameBuffer.DrawText(x, y, "EVENT HORIZON", colour, 1)
  | 4 : FrameBuffer.DrawText(x, y, "AFTERBURN", colour, 1)
  | 5 : FrameBuffer.DrawText(x, y, "ENDLESS ENDEAVOR", colour, 1)
  ELSE FrameBuffer.DrawText(x, y, "SHUFFLE ALL SIX", colour, 1)
  END
END TrackLabel;


PROCEDURE DrawHUD;
VAR buf : ARRAY [0..15] OF CHAR; i, bar, shownWave : CARDINAL;
BEGIN
  FrameBuffer.FillRect(0, 0, FrameBuffer.Width, 16, 1);
  FrameBuffer.HLine(0, FrameBuffer.Width-1, 16, 4);
  FrameBuffer.VLine(99, 2, 13, 2);
  FrameBuffer.VLine(160, 2, 13, 2);
  FrameBuffer.VLine(225, 2, 13, 2);
  FrameBuffer.VLine(257, 2, 13, 2);

  FrameBuffer.DrawText(5, 4, "SCORE", 6, 1);
  CardText(score, buf, 6); FrameBuffer.DrawText(34, 4, buf, 8, 1);

  IF gameMode = BossRushMode THEN
    FrameBuffer.DrawText(109, 4, "BOSS", 6, 1);
    shownWave := MinC(8, bossesDefeated + 1)
  ELSIF gameMode = TimeAttackMode THEN
    FrameBuffer.DrawText(106, 4, "TIME", 6, 1);
    shownWave := 0
  ELSE
    FrameBuffer.DrawText(109, 4, "WAVE", 6, 1);
    shownWave := wave
  END;
  IF gameMode = TimeAttackMode THEN
    CardText(timeRemaining DIV 3600, buf, 2);
    FrameBuffer.DrawText(126, 4, buf, 12, 1);
    FrameBuffer.DrawText(138, 4, ":", 12, 1);
    CardText((timeRemaining DIV 60) MOD 60, buf, 2);
    FrameBuffer.DrawText(144, 4, buf, 12, 1)
  ELSE
    CardText(shownWave, buf, 2);
    FrameBuffer.DrawText(134, 4, buf, 12, 1)
  END;

  FrameBuffer.DrawText(170, 4, "COMBO", 6, 1);
  CardText(combo, buf, 1); FrameBuffer.DrawText(207, 4, buf, 19, 1);

  FOR i := 0 TO 3 DO Visuals.DrawHeart(228+VAL(INTEGER, i*8), 5, i < player.lives) END;

  FrameBuffer.DrawText(262, 4, "PULSE", 6, 1);
  FrameBuffer.Rect(289, 4, 26, 7, 4);
  bar := player.pulseCharge * 24 DIV 100;
  IF bar > 0 THEN FrameBuffer.FillRect(290, 5, VAL(INTEGER, bar), 5, 12 + (tick MOD 3)) END
END DrawHUD;

PROCEDURE DrawObjects(sx, sy : INTEGER);
VAR i : CARDINAL; bank : INTEGER;
BEGIN
  FOR i := 0 TO MaxParticles-1 DO
    IF particles[i].active THEN
      Visuals.DrawParticle(DivideSigned(particles[i].x, FP) + sx,
                           DivideSigned(particles[i].y, FP) + sy,
                           particles[i].life, particles[i].kind)
    END
  END;

  FOR i := 0 TO MaxPowerups-1 DO
    IF powerups[i].active THEN
      Visuals.DrawPowerup(powerups[i].kind,
                          DivideSigned(powerups[i].x, FP) + sx,
                          DivideSigned(powerups[i].y, FP) + sy, tick)
    END
  END;

  FOR i := 0 TO MaxEnemies-1 DO
    IF enemies[i].active THEN
      Visuals.DrawEnemy(enemies[i].kind,
                        DivideSigned(enemies[i].x, FP) + sx,
                        DivideSigned(enemies[i].y, FP) + sy,
                        enemies[i].phase)
    END
  END;

  IF bossActive THEN
    Visuals.DrawBoss(bossKind, bossX DIV FP + sx, bossY DIV FP + sy, tick,
                     bossHealth, bossMaxHealth)
  END;

  FOR i := 0 TO MaxShots-1 DO
    IF shots[i].active THEN
      Visuals.DrawPlayerShot(DivideSigned(shots[i].x, FP) + sx,
                             DivideSigned(shots[i].y, FP) + sy,
                             tick+i, shots[i].power)
    END
  END;
  FOR i := 0 TO MaxEnemyShots-1 DO
    IF enemyShots[i].active THEN
      Visuals.DrawEnemyShot(DivideSigned(enemyShots[i].x, FP) + sx,
                            DivideSigned(enemyShots[i].y, FP) + sy, tick+i)
    END
  END;

  IF (state # GameOver) AND ((player.invuln = 0) OR ((tick MOD 6) < 3)) THEN
    bank := DivideSigned(player.vx, 180);
    Visuals.DrawShip(selectedShip, player.x DIV FP + sx, player.y DIV FP + sy,
                     tick, bank, player.shield);
    IF player.reserveShield THEN
      FrameBuffer.Rect(player.x DIV FP + sx - 15,
                       player.y DIV FP + sy - 16, 31, 32, 11)
    END
  END
END DrawObjects;

PROCEDURE DrawBossBar;
VAR bar : CARDINAL;
BEGIN
  IF NOT bossActive THEN RETURN END;
  CASE bossKind OF
    0 : CenterText(20, "NULL WARDEN", 17, 1)
  | 1 : CenterText(20, "PRISM SERAPH", 12, 1)
  | 2 : CenterText(20, "IRON REAVER", 19, 1)
  | 3 : CenterText(20, "ECLIPSE CORE", 16, 1)
  | 4 : CenterText(20, "MIRROR TWINS", 12, 1)
  | 5 : CenterText(20, "THORN MATRIX", 10, 1)
  | 6 : CenterText(20, "RIFT LEVIATHAN", 15, 1)
  ELSE CenterText(20, "STAR DEVOURER", 19, 1)
  END;
  FrameBuffer.Rect(64, 28, 193, 7, 4);
  IF bossMaxHealth > 0 THEN bar := bossHealth * 191 DIV bossMaxHealth ELSE bar := 0 END;
  IF bar > 0 THEN FrameBuffer.FillRect(65, 29, VAL(INTEGER, bar), 5, 16 + ((tick DIV 4) MOD 3)) END
END DrawBossBar;

PROCEDURE DrawChapterCard(y : INTEGER);
VAR chapter : CARDINAL; buf : ARRAY [0..15] OF CHAR;
BEGIN
  chapter := (wave-1) DIV 3;
  Visuals.DrawPanel(42, y, 236, 54, TRUE);
  CardText(chapter+1, buf, 2);
  FrameBuffer.DrawText(113, y+7, "CHAPTER", 19, 1);
  FrameBuffer.DrawText(162, y+7, buf, 8, 1);
  CASE chapter OF
    0 : CenterTextBox(42, 236, y+20, "THE QUIET REACH", 12, 2);
        CenterTextBox(42, 236, y+43, "TRACE THE NULL SIGNAL", 6, 1)
  | 1 : CenterTextBox(42, 236, y+20, "PRISM FRONT", 12, 2);
        CenterTextBox(42, 236, y+43, "BREACH THE FRACTURED LIGHT", 6, 1)
  | 2 : CenterTextBox(42, 236, y+20, "IRON GRAVE", 12, 2);
        CenterTextBox(42, 236, y+43, "BREAK THE FORGE LINE", 6, 1)
  | 3 : CenterTextBox(42, 236, y+20, "ECLIPSE GATE", 12, 2);
        CenterTextBox(42, 236, y+43, "SHUT THE DARK ENGINE", 6, 1)
  | 4 : CenterTextBox(42, 236, y+20, "TWIN MIRROR", 12, 2);
        CenterTextBox(42, 236, y+43, "SEVER THE MIRROR LINK", 6, 1)
  | 5 : CenterTextBox(42, 236, y+20, "THORN EXPANSE", 12, 2);
        CenterTextBox(42, 236, y+43, "BURN THROUGH THE THORNS", 6, 1)
  | 6 : CenterTextBox(42, 236, y+20, "RIFT CHASM", 12, 2);
        CenterTextBox(42, 236, y+43, "SEAL THE OPEN RIFT", 6, 1)
  ELSE CenterTextBox(42, 236, y+20, "DEVOURER WAKE", 12, 2);
       CenterTextBox(42, 236, y+43, "END THE STAR HUNGER", 6, 1)
  END
END DrawChapterCard;

PROCEDURE DrawBanner;
VAR buf : ARRAY [0..15] OF CHAR; y : INTEGER;
BEGIN
  IF sectorBanner = 0 THEN RETURN END;
  IF sectorBanner > 90 THEN y := 60 - VAL(INTEGER, (sectorBanner-90) DIV 3)
  ELSE y := 60
  END;
  IF (gameMode = CampaignMode) AND ((wave MOD 3) = 1) THEN
    DrawChapterCard(y-8);
    RETURN
  END;
  Visuals.DrawPanel(84, y, 152, 34, TRUE);
  IF (gameMode = BossRushMode) OR
     ((gameMode = GauntletMode) AND ((wave MOD 2) = 0)) OR
     ((gameMode # GauntletMode) AND ((wave MOD 3) = 0)) THEN
    CenterTextBox(84, 152, y+7, "BOSS ALERT", 19, 2);
    IF gameMode = BossRushMode THEN
      CardText(bossesDefeated + 1, buf, 2);
      CenterTextBox(84, 152, y+22, buf, 12, 1)
    ELSE
      CenterTextBox(84, 152, y+22, "DREAD SIGNATURE", 16, 1)
    END
  ELSE
    CenterTextBox(84, 152, y+8, "SECTOR", 12, 1);
    CardText(wave, buf, 2);
    CenterTextBox(84, 152, y+16, buf, 19, 2)
  END
END DrawBanner;

PROCEDURE DrawTitle;
VAR blink, low, lowMid, highMid, high : CARDINAL;
BEGIN
  Visuals.DrawLogo(tick);
  Visuals.DrawPanel(18, 81, 284, 83, TRUE);
  FrameBuffer.VLine(148, 91, 154, 4);

  CenterTextBox(23, 120, 91, "SELECT MODE", 6, 1);
  CASE selectedMode OF
    CampaignMode : CenterTextBox(23, 120, 104, "CAMPAIGN", 12, 2);
                   CenterTextBox(23, 120, 122, "24 SECTORS / 8 BOSSES", 5, 1)
  | EndlessMode : CenterTextBox(23, 120, 104, "ENDLESS", 12, 2);
                  CenterTextBox(23, 120, 122, "SURVIVE / SCORE ATTACK", 5, 1)
  | BossRushMode : CenterTextBox(23, 120, 104, "BOSS RUSH", 12, 2);
                   CenterTextBox(23, 120, 122, "8 UNIQUE ENCOUNTERS", 5, 1)
  | GauntletMode : CenterTextBox(23, 120, 104, "GAUNTLET", 12, 2);
                   CenterTextBox(23, 120, 122, "FAST WAVES / HARDER", 5, 1)
  | TimeAttackMode : CenterTextBox(23, 120, 104, "TIME ATTACK", 12, 2);
                     CenterTextBox(23, 120, 122, "4 MINUTE SCORE RUN", 5, 1)
  | LanCoopMode : CenterTextBox(23, 120, 104, "LAN CO-OP", 12, 2);
                  CenterTextBox(23, 120, 122, "TWO PILOT SURVIVAL", 5, 1)
  | LanVersusMode : CenterTextBox(23, 120, 104, "LAN VERSUS", 12, 2);
                    CenterTextBox(23, 120, 122, "PILOT DUEL / ROUNDS", 5, 1)
  END;

  FrameBuffer.HLine(30, 137, 136, 3);
  Visuals.DrawHint(31, 146, Visuals.NavigateHint, "MODE", 7);
  blink := (tick DIV 16) MOD 2;
  IF blink = 0 THEN
    Visuals.DrawHint(99, 146, Visuals.ConfirmHint, "PLAY", 19)
  ELSE
    Visuals.DrawHint(99, 146, Visuals.ConfirmHint, "PLAY", 8)
  END;

  FrameBuffer.DrawText(158, 91, "YOUR SHIP", 6, 1);
  ShipLabel(158, 103, 19);
  ModifierLabel(158, 115, 12);
  Visuals.DrawShipPreview(selectedShip, 267, 120, tick);
  Visuals.DrawHint(158, 138, Visuals.MoveHint, "SHIP", 5);
  Visuals.DrawHint(158, 151, Visuals.PulseHint, "HANGAR", 12);

  low := Audio.ThemeMeter(0);
  lowMid := Audio.ThemeMeter(1);
  highMid := Audio.ThemeMeter(2);
  high := Audio.ThemeMeter(3);
  Visuals.DrawMusicTag(14, 169, low, lowMid, highMid, high);
  FrameBuffer.DrawText(44, 169, "ENDLESS ENDEAVOR", 12, 1);
  Visuals.DrawHint(205, 169, Visuals.MenuHint, "HELP", 5);
  Visuals.DrawHint(263, 169, Visuals.CancelHint, "QUIT", 5)
END DrawTitle;

PROCEDURE DrawControls;
BEGIN
  Visuals.DrawLogo(tick);
  Visuals.DrawPanel(23, 72, 274, 94, TRUE);
  CenterTextBox(23, 274, 80, "FLIGHT CONTROLS", 12, 1);
  FrameBuffer.HLine(34, 286, 91, 4);
  Visuals.DrawHint(37, 98, Visuals.MoveHint, "MOVE", 12);
  Visuals.DrawHint(177, 98, Visuals.NavigateHint, "MENUS", 12);
  Visuals.DrawHint(37, 112, Visuals.FireHint, "FIRE", 19);
  Visuals.DrawHint(177, 112, Visuals.PulseHint, "PULSE", 19);
  Visuals.DrawHint(37, 126, Visuals.PauseHint, "PAUSE", 12);
  Visuals.DrawHint(177, 126, Visuals.MenuHint, "MENU", 12);
  Visuals.DrawHint(37, 140, Visuals.FullscreenHint, "FULL", 6);
  Visuals.DrawHint(177, 140, Visuals.CancelHint, "BACK", 6);
  CenterTextBox(23, 274, 154, "HINTS FOLLOW THE LAST DEVICE USED", 5, 1)
END DrawControls;

PROCEDURE DrawHangar;
BEGIN
  Visuals.DrawLogo(tick);
  Visuals.DrawPanel(18, 74, 284, 92, TRUE);
  CenterTextBox(18, 284, 81, "HANGAR / LOADOUT", 12, 1);
  FrameBuffer.HLine(28, 291, 92, 4);
  IF hangarRow = 0 THEN FrameBuffer.Rect(27, 98, 181, 12, 12) END;
  IF hangarRow = 1 THEN FrameBuffer.Rect(27, 116, 181, 12, 12) END;
  IF hangarRow = 2 THEN FrameBuffer.Rect(27, 134, 181, 12, 12) END;
  FrameBuffer.DrawText(34, 100, "SHIP", 6, 1);
  ShipLabel(100, 100, 19);
  FrameBuffer.DrawText(34, 118, "MOD", 6, 1);
  ModifierLabel(100, 118, 10);
  FrameBuffer.DrawText(34, 136, "MUSIC", 6, 1);
  TrackLabel(100, 136, 15);
  Visuals.DrawShipPreview(selectedShip, 258, 121, tick);
  CASE hangarRow OF
    0 : CASE selectedShip OF
          0 : FrameBuffer.DrawText(34, 153, "BALANCED / 3 HULL", 5, 1)
        | 1 : FrameBuffer.DrawText(34, 153, "FAST FIRE / 2 HULL", 5, 1)
        | 2 : FrameBuffer.DrawText(34, 153, "ARMORED / 4 HULL", 5, 1)
        | 3 : FrameBuffer.DrawText(34, 153, "PULSE ACE / 3 HULL", 5, 1)
        ELSE FrameBuffer.DrawText(34, 153, "HEAVY SHOTS / 2 HULL", 5, 1)
        END
  | 1 : CASE selectedModifier OF
          0 : FrameBuffer.DrawText(34, 153, "PURE FLIGHT / NO TRADEOFF", 5, 1)
        | 1 : FrameBuffer.DrawText(34, 153, "RAPID FIRE / LESS HULL", 5, 1)
        | 2 : FrameBuffer.DrawText(34, 153, "SHIELD / SLOWER FLIGHT", 5, 1)
        | 3 : FrameBuffer.DrawText(34, 153, "MORE PULSE / SLOW FIRE", 5, 1)
        | 4 : IF selectedMode = LanVersusMode THEN
                FrameBuffer.DrawText(34, 153, "MORE PULSE / LESS HULL", 5, 1)
              ELSE
                FrameBuffer.DrawText(34, 153, "DOUBLE SCORE / MORE FOES", 5, 1)
              END
        | 5 : FrameBuffer.DrawText(34, 153, "FULL PULSE / SLOW CHARGE", 5, 1)
        ELSE FrameBuffer.DrawText(34, 153, "MORE DAMAGE / SLOW FIRE", 5, 1)
        END
  ELSE IF selectedTrack = 6 THEN
         FrameBuffer.DrawText(34, 153, "RANDOM START / ROTATE AFTER BOSSES", 5, 1)
       ELSE
         FrameBuffer.DrawText(34, 153, "FIRST TRACK / THEN SHUFFLE ALL SIX", 5, 1)
       END
  END;
  Visuals.DrawHint(25, 169, Visuals.MoveHint, "ROW", 7);
  Visuals.DrawHint(114, 169, Visuals.NavigateHint, "CHANGE", 7);
  Visuals.DrawHint(247, 169, Visuals.ConfirmHint, "DONE", 12)
END DrawHangar;

PROCEDURE DrawLanSetup;
VAR buf : ARRAY [0..15] OF CHAR; i, x : CARDINAL;
BEGIN
  Visuals.DrawLogo(tick);
  Visuals.DrawPanel(28, 77, 264, 89, TRUE);
  IF selectedMode = LanCoopMode THEN
    CenterTextBox(28, 264, 84, "LAN CO-OP", 12, 2)
  ELSE CenterTextBox(28, 264, 84, "LAN VERSUS", 12, 2)
  END;
  IF modeIsHost THEN
    CenterTextBox(28, 264, 107, "HOST GAME", 19, 1);
    CenterTextBox(28, 264, 122, "SHARE YOUR LAN IP / PORT 37177", 6, 1)
  ELSE
    CenterTextBox(28, 264, 106, "JOIN HOST IP", 19, 1);
    FOR i := 0 TO 3 DO
      x := 71 + i*43;
      CardText(ipOctets[i], buf, 3);
      FrameBuffer.DrawText(VAL(INTEGER, x), 125, buf, 8, 1);
      IF i < 3 THEN FrameBuffer.DrawText(VAL(INTEGER, x+27), 125, ".", 12, 1) END;
      IF i = ipCursor THEN
        FrameBuffer.HLine(VAL(INTEGER, x)-2, VAL(INTEGER, x)+19, 135, 19)
      END
    END
  END;
  Visuals.CenterHint(28, 264, 143, Visuals.PulseHint, "HOST / JOIN", 12);
  IF lanError THEN
    CenterTextBox(28, 264, 155, "NETWORK UNAVAILABLE / PORT IN USE", 16, 1)
  ELSIF modeIsHost THEN
    CenterTextBox(28, 264, 155, "PRESS CONNECT / WAIT FOR OTHER PILOT", 5, 1)
  ELSE
    Visuals.CenterHint(28, 264, 154, Visuals.FastHint, "UP/DOWN BY 10", 5)
  END;
  Visuals.DrawHint(41, 169, Visuals.ConfirmHint, "CONNECT", 12);
  Visuals.DrawHint(203, 169, Visuals.CancelHint, "BACK", 6)
END DrawLanSetup;

PROCEDURE DrawPause;
BEGIN
  Visuals.DrawPanel(82, 50, 156, 80, TRUE);
  CenterTextBox(82, 156, 62, "MISSION PAUSED", 12, 1);
  Visuals.CenterHint(82, 156, 82, Visuals.PauseHint, "RESUME", 8);
  Visuals.CenterHint(82, 156, 96, Visuals.MenuHint, "MAIN MENU", 12);
  Visuals.CenterHint(82, 156, 110, Visuals.FullscreenHint, "FULLSCREEN", 5)
END DrawPause;

PROCEDURE DrawGameOver;
VAR buf : ARRAY [0..15] OF CHAR;
BEGIN
  Visuals.DrawPanel(68, 39, 184, 111, TRUE);
  CenterTextBox(68, 184, 52, "MISSION LOST", 16, 2);
  CenterTextBox(68, 184, 77, "FINAL SCORE", 6, 1);
  CardText(score, buf, 6); CenterTextBox(68, 184, 90, buf, 19, 2);
  IF score = bestScore THEN CenterTextBox(68, 184, 109, "NEW BEST!", 19, 1) END;
  Visuals.CenterHint(68, 184, 121, Visuals.ConfirmHint, "RETRY", 12);
  Visuals.CenterHint(68, 184, 133, Visuals.CancelHint, "MAIN MENU", 7)
END DrawGameOver;

PROCEDURE DrawVictory;
VAR buf : ARRAY [0..15] OF CHAR;
BEGIN
  Visuals.DrawPanel(56, 36, 208, 111, TRUE);
  IF gameMode = BossRushMode THEN
    CenterTextBox(56, 208, 49, "BOSS RUSH CLEARED", 10, 2);
    CenterTextBox(56, 208, 75, "EIGHT ENCOUNTERS DOWN", 7, 1)
  ELSIF gameMode = TimeAttackMode THEN
    CenterTextBox(56, 208, 49, "TIME ATTACK", 10, 2);
    CenterTextBox(56, 208, 75, "FOUR MINUTE RUN COMPLETE", 7, 1)
  ELSE
    CenterTextBox(56, 208, 49, "CAMPAIGN CLEARED", 10, 2);
    CenterTextBox(56, 208, 75, "TWENTY FOUR SECTORS COMPLETE", 7, 1)
  END;
  CenterTextBox(56, 208, 91, "FINAL SCORE", 5, 1);
  CardText(score, buf, 6); CenterTextBox(56, 208, 103, buf, 19, 2);
  Visuals.CenterHint(56, 208, 125, Visuals.ConfirmHint, "MAIN MENU", 12)
END DrawVictory;

PROCEDURE Draw;
VAR sx, sy, p : INTEGER; pulse, chapter : CARDINAL;
BEGIN
  pulse := (tick DIV 5) MOD 16;
  IF pulse > 8 THEN pulse := 16-pulse END;
  FrameBuffer.SetPalette(12, 55 + pulse*5, 190 + pulse*5, 245);
  FrameBuffer.SetPalette(19, 255, 205 + pulse*3, 80 + pulse*2);
  chapter := 0;
  IF (state # Title) AND (state # Controls) AND
     (state # Hangar) AND (state # LanSetup) AND
     (gameMode = CampaignMode) THEN chapter := (wave-1) DIV 3 END;
  CASE chapter OF
    0 : FrameBuffer.SetPalette(2, 18, 20, 52);
        FrameBuffer.SetPalette(3, 35, 38, 82)
  | 1 : FrameBuffer.SetPalette(2, 31, 16, 65);
        FrameBuffer.SetPalette(3, 59, 30, 98)
  | 2 : FrameBuffer.SetPalette(2, 51, 24, 35);
        FrameBuffer.SetPalette(3, 91, 44, 55)
  | 3 : FrameBuffer.SetPalette(2, 25, 17, 55);
        FrameBuffer.SetPalette(3, 48, 29, 94)
  | 4 : FrameBuffer.SetPalette(2, 12, 39, 57);
        FrameBuffer.SetPalette(3, 24, 68, 89)
  | 5 : FrameBuffer.SetPalette(2, 17, 43, 39);
        FrameBuffer.SetPalette(3, 31, 75, 62)
  | 6 : FrameBuffer.SetPalette(2, 49, 16, 46);
        FrameBuffer.SetPalette(3, 84, 28, 70)
  ELSE FrameBuffer.SetPalette(2, 48, 36, 24);
       FrameBuffer.SetPalette(3, 81, 62, 37)
  END;

  FrameBuffer.Clear(0);
  DrawNebula;
  DrawStars;

  IF state = Title THEN
    DrawTitle
  ELSIF state = Controls THEN
    DrawControls
  ELSIF state = Hangar THEN
    DrawHangar
  ELSIF state = LanSetup THEN
    DrawLanSetup
  ELSIF state = LanPlaying THEN
    Arena.Draw
  ELSE
    sx := 0; sy := 0;
    IF shake > 0 THEN
      sx := VAL(INTEGER, (tick*17) MOD (shake+1)) - VAL(INTEGER, shake DIV 2);
      sy := VAL(INTEGER, (tick*11) MOD (shake+1)) - VAL(INTEGER, shake DIV 2)
    END;
    DrawObjects(sx, sy);
    DrawHUD;
    DrawBossBar;
    DrawBanner;
    IF state = Paused THEN DrawPause
    ELSIF state = GameOver THEN DrawGameOver
    ELSIF state = Victory THEN DrawVictory
    END
  END;

  IF flash > 0 THEN
    p := VAL(INTEGER, flash MOD 3);
    FrameBuffer.Rect(p, p, FrameBuffer.Width-p*2, FrameBuffer.Height-p*2, 8)
  END
END Draw;

PROCEDURE WantsQuit() : BOOLEAN;
BEGIN
  RETURN quitWanted
END WantsQuit;

BEGIN
  state := Title;
  tick := 0; score := 0; bestScore := 0; wave := 1;
  quitWanted := FALSE; bossActive := FALSE
END Game.
