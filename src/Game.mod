IMPLEMENTATION MODULE Game;

IMPORT FrameBuffer, Visuals, Input, Audio, RNG;

CONST
  FP = 256;
  MaxShots = 56;
  MaxEnemies = 36;
  MaxEnemyShots = 72;
  MaxParticles = 128;
  MaxPowerups = 10;
  MaxStars = 72;

TYPE
  GameState = (Title, Playing, Paused, GameOver, Victory);
  PlayMode = (ArcadeMode, EndlessMode, BossRushMode);

  PlayerRec = RECORD
    x, y, vx, vy : INTEGER;
    cooldown, invuln : CARDINAL;
    lives : CARDINAL;
    shield : BOOLEAN;
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

PROCEDURE AbsI(v : INTEGER) : INTEGER;
BEGIN
  IF v < 0 THEN RETURN -v END;
  RETURN v
END AbsI;

PROCEDURE MinC(a, b : CARDINAL) : CARDINAL;
BEGIN
  IF a < b THEN RETURN a END;
  RETURN b
END MinC;

PROCEDURE DifficultyLevel() : CARDINAL;
BEGIN
  IF gameMode = BossRushMode THEN RETURN 3 END;
  IF wave <= 2 THEN RETURN 0 END;
  IF wave <= 5 THEN RETURN 1 END;
  IF wave <= 9 THEN RETURN 2 END;
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
VAR i, slot : CARDINAL; angle : INTEGER; found : BOOLEAN;
BEGIN
  FOR i := 0 TO count-1 DO
    slot := 0; found := FALSE;
    WHILE (slot < MaxParticles) AND NOT found DO
      IF NOT particles[slot].active THEN found := TRUE ELSE INC(slot) END
    END;
    IF found THEN
      particles[slot].active := TRUE;
      particles[slot].x := x*FP;
      particles[slot].y := y*FP;
      particles[slot].vx := RNG.Between(-220, 220);
      particles[slot].vy := RNG.Between(-220, 220);
      angle := RNG.Between(0, 2);
      particles[slot].vx := particles[slot].vx + angle*20;
      particles[slot].life := 18 + RNG.Range(22);
      particles[slot].kind := kind
    END
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
      enemyShots[i].vx := dx * 340 DIV VAL(INTEGER, den);
      enemyShots[i].vy := dy * 340 DIV VAL(INTEGER, den);
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
      powerups[i].kind := RNG.Range(4);
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
  x := enemies[index].x DIV FP; y := enemies[index].y DIV FP;
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
  player.pulseCharge := MinC(100, player.pulseCharge + 5 + enemies[index].kind);
  IF RNG.Range(9) = 0 THEN SpawnPowerup(x, y) END
END EnemyDestroyed;

PROCEDURE SpawnEnemy;
VAR i, k, tier, r, level : CARDINAL;
BEGIN
  FOR i := 0 TO MaxEnemies-1 DO
    IF NOT enemies[i].active THEN
      tier := DifficultyLevel();
      level := MinC(12, wave);
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
            IF r < 18 THEN k := 0
            ELSIF r < 34 THEN k := 1
            ELSIF r < 49 THEN k := 2
            ELSIF r < 62 THEN k := 3
            ELSIF r < 76 THEN k := 4
            ELSIF r < 90 THEN k := 5
            ELSE k := 6
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
    bossKind := bossesDefeated MOD 4;
    encounter := bossesDefeated
  ELSE
    encounter := wave DIV 5;
    IF encounter > 0 THEN DEC(encounter) END;
    bossKind := encounter MOD 4
  END;

  CASE bossKind OF
    0 : base := 120; bossVX := 72; bossFire := 72
  | 1 : base := 145; bossVX := 58; bossFire := 82
  | 2 : base := 170; bossVX := 118; bossFire := 76
  ELSE base := 200; bossVX := 42; bossFire := 68
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
  player.lives := 3; player.shield := FALSE;
  player.rapidTimer := 0; player.tripleTimer := 0; player.pulseCharge := 0;
  score := 0; bossesDefeated := 0;
  IF gameMode = BossRushMode THEN
    wave := 5; waveTimer := 0; spawnTimer := 9999; sectorBanner := 180
  ELSE
    wave := 1; waveTimer := 0; spawnTimer := 30; sectorBanner := 120
  END;
  combo := 1; comboTimer := 0; shake := 0; flash := 0;
  bossActive := FALSE; bossHealth := 0; bossMaxHealth := 0; bossPhase := 0;
  state := Playing;
  Audio.SetMusic(TRUE);
  Audio.SetMusicMode(Audio.SynthTrack);
  IF gameMode = BossRushMode THEN Audio.SetIntensity(2) ELSE Audio.SetIntensity(1) END;
  Audio.Play(Audio.StartJingle)
END StartGame;

PROCEDURE DamagePlayer;
BEGIN
  IF player.invuln > 0 THEN RETURN END;
  IF player.shield THEN
    player.shield := FALSE;
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
VAR px, py : INTEGER; cd : CARDINAL;
BEGIN
  IF player.cooldown # 0 THEN RETURN END;
  px := player.x DIV FP; py := player.y DIV FP;
  IF player.tripleTimer > 0 THEN
    SpawnPlayerShot(px-4, py-7, -55, -760, 2);
    SpawnPlayerShot(px, py-9, 0, -810, 2);
    SpawnPlayerShot(px+4, py-7, 55, -760, 2)
  ELSE
    SpawnPlayerShot(px, py-8, 0, -820, 1)
  END;
  IF player.rapidTimer > 0 THEN cd := 5 ELSE cd := 9 END;
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
      Burst(enemyShots[i].x DIV FP, enemyShots[i].y DIV FP, 2, 1);
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
CONST Accel = 118; MaxSpeed = 700;
VAR ax, ay : INTEGER;
BEGIN
  ax := 0; ay := 0;
  IF Input.Held(Input.Left) THEN ax := ax - Accel END;
  IF Input.Held(Input.Right) THEN ax := ax + Accel END;
  IF Input.Held(Input.Up) THEN ay := ay - Accel END;
  IF Input.Held(Input.Down) THEN ay := ay + Accel END;

  (* Snappy arcade movement, with just enough drift to not feel robotic. *)
  player.vx := player.vx + ax; player.vy := player.vy + ay;
  IF ax = 0 THEN player.vx := player.vx DIV 2 END;
  IF ay = 0 THEN player.vy := player.vy DIV 2 END;
  player.vx := ClampI(player.vx, -MaxSpeed, MaxSpeed);
  player.vy := ClampI(player.vy, -MaxSpeed, MaxSpeed);
  player.x := player.x + player.vx; player.y := player.y + player.vy;
  player.x := ClampI(player.x, 10*FP, 310*FP);
  player.y := ClampI(player.y, 18*FP, 169*FP);

  IF player.cooldown > 0 THEN DEC(player.cooldown) END;
  IF player.invuln > 0 THEN DEC(player.invuln) END;
  IF player.rapidTimer > 0 THEN DEC(player.rapidTimer) END;
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
      | 2 : enemies[i].x := enemies[i].x + enemies[i].vx DIV 2;
            IF (enemies[i].phase MOD 90) = 0 THEN enemies[i].vx := -enemies[i].vx END
      | 3 : enemies[i].x := enemies[i].x + Tri(enemies[i].phase, 30, 58)
      | 4 : IF enemies[i].x DIV FP < px THEN
              enemies[i].vx := ClampI(enemies[i].vx + 5, -120, 120)
            ELSE
              enemies[i].vx := ClampI(enemies[i].vx - 5, -120, 120)
            END;
            enemies[i].x := enemies[i].x + enemies[i].vx
      | 5 : enemies[i].x := enemies[i].x + enemies[i].vx DIV 3 +
              Tri(enemies[i].phase, 70, 18)
      | 6 : enemies[i].x := enemies[i].x + enemies[i].vx +
              Tri(enemies[i].phase, 22, 44)
      ELSE enemies[i].x := enemies[i].x + enemies[i].vx
      END;

      ex := enemies[i].x DIV FP; ey := enemies[i].y DIV FP;
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
        ELSE enemies[i].fireTimer := 120
        END
      END;

      hitX := 9; hitY := 8;
      IF enemies[i].kind = 5 THEN hitX := 12; hitY := 9
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
      x := enemyShots[i].x DIV FP; y := enemyShots[i].y DIV FP;
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
      particles[i].vx := particles[i].vx * 15 DIV 16;
      particles[i].vy := particles[i].vy * 15 DIV 16;
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
      x := powerups[i].x DIV FP; y := powerups[i].y DIV FP;
      IF powerups[i].life > 0 THEN DEC(powerups[i].life) END;
      IF (powerups[i].life = 0) OR (y > 190) THEN powerups[i].active := FALSE
      ELSIF (AbsI(x-px) < 10) AND (AbsI(y-py) < 10) THEN
        powerups[i].active := FALSE;
        CASE powerups[i].kind OF
          0 : player.shield := TRUE
        | 1 : player.rapidTimer := 900
        | 2 : player.tripleTimer := 900
        | 3 : IF player.lives < 3 THEN INC(player.lives)
              ELSE player.pulseCharge := MinC(100, player.pulseCharge + 35)
              END
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
      sx := shots[s].x DIV FP; sy := shots[s].y DIV FP;
      e := 0;
      WHILE (e < MaxEnemies) AND shots[s].active DO
        IF enemies[e].active THEN
          ex := enemies[e].x DIV FP; ey := enemies[e].y DIV FP;
          hitX := 9; hitY := 7;
          IF enemies[e].kind = 5 THEN hitX := 12; hitY := 9
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
    IF (bossesDefeated MOD 2) = 0 THEN player.shield := TRUE END;
    IF bossesDefeated >= 8 THEN
      state := Victory; sectorBanner := 0;
      Audio.SetMusicMode(Audio.ThemeTrack);
      Audio.SetIntensity(0)
    ELSE
      wave := 5 + bossesDefeated*5;
      waveTimer := 0;
      spawnTimer := 9999;
      Audio.SetIntensity(MinC(3, 2 + bossesDefeated DIV 4))
    END
  ELSIF (gameMode = ArcadeMode) AND (wave >= 20) THEN
    state := Victory; sectorBanner := 0;
    Audio.SetMusicMode(Audio.ThemeTrack);
    Audio.SetIntensity(0)
  ELSE
    INC(wave);
    waveTimer := 0;
    spawnTimer := 84;
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
  ELSE
        bossX := (160 + Tri(bossPhase, 118, 154))*FP;
        bossY := (30 + Tri(bossPhase+41, 74, 12))*FP
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
    ELSE
          IF (bossPhase MOD 2) = 0 THEN
            FOR d := -3 TO 3 DO SpawnEnemyShot(bx, bossYScreen+7, d*52, 330) END
          ELSE
            SpawnEnemyShot(bx-10, bossYScreen+8, px-(bx-10), py-(bossYScreen+8));
            SpawnEnemyShot(bx+10, bossYScreen+8, px-(bx+10), py-(bossYScreen+8))
          END;
          bossFire := 52 + RNG.Range(16)
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

  IF (wave MOD 5) = 0 THEN
    IF waveTimer > 92 THEN SpawnBoss END;
    RETURN
  END;

  tier := DifficultyLevel();
  IF spawnTimer > 0 THEN DEC(spawnTimer)
  ELSE
    SpawnEnemy;
    IF (tier >= 2) AND (RNG.Range(5) = 0) THEN SpawnEnemy END;
    IF (tier >= 3) AND (RNG.Range(10) = 0) THEN SpawnEnemy END;

    IF gameMode = EndlessMode THEN
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
    spawnTimer := rate + RNG.Range(16)
  END;

  IF gameMode = EndlessMode THEN limit := 780 ELSE limit := 840 END;
  IF waveTimer >= limit THEN
    INC(wave); waveTimer := 0; spawnTimer := 64; sectorBanner := 120;
    Audio.SetIntensity(MinC(3, wave DIV 4));
    IF (wave MOD 5) = 0 THEN spawnTimer := 9999 END
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
  selectedMode := ArcadeMode; gameMode := ArcadeMode;
  ClearObjects; InitStars;
  EnterTitle
END Init;

PROCEDURE Update;
BEGIN
  INC(tick);
  UpdateStars;
  CASE state OF
    Title:
      UpdateParticles;
      IF (tick MOD 90) = 0 THEN Burst(VAL(INTEGER, 30+RNG.Range(260)), VAL(INTEGER, 20+RNG.Range(95)), 4, 1) END;
      IF Input.Pressed(Input.Left) OR Input.Pressed(Input.Up) THEN
        CASE selectedMode OF
          ArcadeMode : selectedMode := BossRushMode
        | EndlessMode : selectedMode := ArcadeMode
        | BossRushMode : selectedMode := EndlessMode
        END;
        Audio.Play(Audio.MenuBlip)
      ELSIF Input.Pressed(Input.Right) OR Input.Pressed(Input.Down) THEN
        CASE selectedMode OF
          ArcadeMode : selectedMode := EndlessMode
        | EndlessMode : selectedMode := BossRushMode
        | BossRushMode : selectedMode := ArcadeMode
        END;
        Audio.Play(Audio.MenuBlip)
      END;
      IF Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire) THEN StartGame
      ELSIF Input.Pressed(Input.Back) THEN quitWanted := TRUE
      END
  | Playing:
      UpdatePlaying
  | Paused:
      UpdateParticles;
      IF Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) THEN
        EnterTitle; Audio.Play(Audio.MenuBlip)
      ELSIF Input.Pressed(Input.Pause) OR Input.Pressed(Input.Start) THEN
        state := Playing; Audio.Play(Audio.MenuBlip)
      END
  | GameOver:
      UpdateParticles;
      IF Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire) THEN StartGame
      ELSIF Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) THEN
        EnterTitle; Audio.Play(Audio.MenuBlip)
      END
  | Victory:
      UpdateParticles;
      IF Input.Pressed(Input.Start) OR Input.Pressed(Input.Fire) OR
         Input.Pressed(Input.Menu) OR Input.Pressed(Input.Back) THEN
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
  xx := x + (w - VAL(INTEGER, tw)) DIV 2;
  IF xx < x THEN xx := x END;
  FrameBuffer.DrawText(xx, y, text, colour, scale)
END CenterTextBox;

PROCEDURE CenterText(y : INTEGER; text : ARRAY OF CHAR; colour, scale : CARDINAL);
BEGIN
  CenterTextBox(0, FrameBuffer.Width, y, text, colour, scale)
END CenterText;


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
  ELSE
    FrameBuffer.DrawText(109, 4, "WAVE", 6, 1);
    shownWave := wave
  END;
  CardText(shownWave, buf, 2); FrameBuffer.DrawText(134, 4, buf, 12, 1);

  FrameBuffer.DrawText(170, 4, "COMBO", 6, 1);
  CardText(combo, buf, 1); FrameBuffer.DrawText(207, 4, buf, 19, 1);

  FOR i := 0 TO 2 DO Visuals.DrawHeart(230+VAL(INTEGER, i*10), 5, i < player.lives) END;

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
      Visuals.DrawParticle(particles[i].x DIV FP + sx, particles[i].y DIV FP + sy,
                           particles[i].life, particles[i].kind)
    END
  END;

  FOR i := 0 TO MaxPowerups-1 DO
    IF powerups[i].active THEN
      Visuals.DrawPowerup(powerups[i].kind, powerups[i].x DIV FP + sx,
                          powerups[i].y DIV FP + sy, tick)
    END
  END;

  FOR i := 0 TO MaxEnemies-1 DO
    IF enemies[i].active THEN
      Visuals.DrawEnemy(enemies[i].kind, enemies[i].x DIV FP + sx,
                        enemies[i].y DIV FP + sy, enemies[i].phase)
    END
  END;

  IF bossActive THEN
    Visuals.DrawBoss(bossKind, bossX DIV FP + sx, bossY DIV FP + sy, tick,
                     bossHealth, bossMaxHealth)
  END;

  FOR i := 0 TO MaxShots-1 DO
    IF shots[i].active THEN
      Visuals.DrawPlayerShot(shots[i].x DIV FP + sx, shots[i].y DIV FP + sy,
                             tick+i, shots[i].power)
    END
  END;
  FOR i := 0 TO MaxEnemyShots-1 DO
    IF enemyShots[i].active THEN
      Visuals.DrawEnemyShot(enemyShots[i].x DIV FP + sx,
                            enemyShots[i].y DIV FP + sy, tick+i)
    END
  END;

  IF (state # GameOver) AND ((player.invuln = 0) OR ((tick MOD 6) < 3)) THEN
    bank := player.vx DIV 180;
    Visuals.DrawPlayer(player.x DIV FP + sx, player.y DIV FP + sy,
                       tick, bank, player.shield)
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
  ELSE CenterText(20, "ECLIPSE CORE", 16, 1)
  END;
  FrameBuffer.Rect(64, 28, 193, 7, 4);
  IF bossMaxHealth > 0 THEN bar := bossHealth * 191 DIV bossMaxHealth ELSE bar := 0 END;
  IF bar > 0 THEN FrameBuffer.FillRect(65, 29, VAL(INTEGER, bar), 5, 16 + ((tick DIV 4) MOD 3)) END
END DrawBossBar;

PROCEDURE DrawBanner;
VAR buf : ARRAY [0..15] OF CHAR; y : INTEGER;
BEGIN
  IF sectorBanner = 0 THEN RETURN END;
  IF sectorBanner > 90 THEN y := 60 - VAL(INTEGER, (sectorBanner-90) DIV 3)
  ELSE y := 60
  END;
  Visuals.DrawPanel(84, y, 152, 34, TRUE);
  IF (gameMode = BossRushMode) OR ((wave MOD 5) = 0) THEN
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
  Visuals.DrawPanel(14, 86, 136, 75, TRUE);
  Visuals.DrawPanel(170, 86, 136, 75, FALSE);

  CenterTextBox(14, 136, 94, "SELECT MODE", 6, 1);
  CASE selectedMode OF
    ArcadeMode : CenterTextBox(14, 136, 104, "ARCADE", 12, 2);
                 CenterTextBox(14, 136, 119, "20 SECTORS / 4 BOSSES", 5, 1)
  | EndlessMode : CenterTextBox(14, 136, 104, "ENDLESS", 12, 2);
                  CenterTextBox(14, 136, 119, "SURVIVE / SCORE ATTACK", 5, 1)
  | BossRushMode : CenterTextBox(14, 136, 104, "BOSS RUSH", 12, 2);
                   CenterTextBox(14, 136, 119, "8 BOSSES / NO WAVES", 5, 1)
  END;

  CenterTextBox(14, 136, 130, "LEFT / RIGHT SELECT", 7, 1);
  blink := (tick DIV 16) MOD 2;
  IF blink = 0 THEN
    CenterTextBox(14, 136, 140, "Z / ENTER START", 19, 1)
  ELSE
    CenterTextBox(14, 136, 140, "Z / ENTER START", 8, 1)
  END;
  CenterTextBox(14, 136, 148, "WASD MOVE  X PULSE", 5, 1);

  (* Same ship in the menu and the game. No fake showroom version. *)
  Visuals.DrawPlayerPreview(238, 123, tick);
  CenterTextBox(170, 136, 94, "YOUR SHIP", 6, 1);
  CenterTextBox(170, 136, 104, "IRONWING MK-I", 19, 1);

  low := Audio.ThemeMeter(0);
  lowMid := Audio.ThemeMeter(1);
  highMid := Audio.ThemeMeter(2);
  high := Audio.ThemeMeter(3);
  Visuals.DrawMusicTag(12, 169, low, lowMid, highMid, high);
  FrameBuffer.DrawText(42, 169, "ENDLESS ENDEAVOR", 12, 1);
  FrameBuffer.DrawText(238, 169, "F11 FULLSCREEN", 4, 1)
END DrawTitle;

PROCEDURE DrawPause;
BEGIN
  Visuals.DrawPanel(82, 54, 156, 72, TRUE);
  CenterTextBox(82, 156, 66, "MISSION PAUSED", 12, 1);
  CenterTextBox(82, 156, 84, "P / ENTER  RESUME", 7, 1);
  CenterTextBox(82, 156, 96, "ESC / M     MAIN MENU", 12, 1);
  CenterTextBox(82, 156, 108, "F11         FULLSCREEN", 5, 1)
END DrawPause;

PROCEDURE DrawGameOver;
VAR buf : ARRAY [0..15] OF CHAR;
BEGIN
  Visuals.DrawPanel(68, 44, 184, 92, TRUE);
  CenterTextBox(68, 184, 57, "MISSION LOST", 16, 2);
  CenterTextBox(68, 184, 81, "FINAL SCORE", 6, 1);
  CardText(score, buf, 6); CenterTextBox(68, 184, 93, buf, 19, 2);
  IF score = bestScore THEN CenterTextBox(68, 184, 111, "NEW BEST!", 19, 1) END;
  IF ((tick DIV 20) MOD 2) = 0 THEN CenterTextBox(68, 184, 122, "ENTER RETRY   ESC MENU", 12, 1) END
END DrawGameOver;

PROCEDURE DrawVictory;
VAR buf : ARRAY [0..15] OF CHAR;
BEGIN
  Visuals.DrawPanel(56, 40, 208, 96, TRUE);
  IF gameMode = BossRushMode THEN
    CenterTextBox(56, 208, 53, "BOSS RUSH CLEARED", 10, 2);
    CenterTextBox(56, 208, 78, "EIGHT ENCOUNTERS DOWN", 7, 1)
  ELSE
    CenterTextBox(56, 208, 53, "CAMPAIGN CLEARED", 10, 2);
    CenterTextBox(56, 208, 78, "TWENTY SECTORS COMPLETE", 7, 1)
  END;
  CenterTextBox(56, 208, 94, "FINAL SCORE", 5, 1);
  CardText(score, buf, 6); CenterTextBox(56, 208, 105, buf, 19, 2);
  CenterTextBox(56, 208, 124, "ENTER / ESC  MAIN MENU", 12, 1)
END DrawVictory;

PROCEDURE Draw;
VAR sx, sy, p : INTEGER; pulse : CARDINAL;
BEGIN
  pulse := (tick DIV 5) MOD 16;
  IF pulse > 8 THEN pulse := 16-pulse END;
  FrameBuffer.SetPalette(12, 55 + pulse*5, 190 + pulse*5, 245);
  FrameBuffer.SetPalette(19, 255, 205 + pulse*3, 80 + pulse*2);

  FrameBuffer.Clear(0);
  DrawNebula;
  DrawStars;

  IF state = Title THEN
    DrawTitle
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
