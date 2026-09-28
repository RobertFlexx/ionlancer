IMPLEMENTATION MODULE Arena;

FROM SYSTEM IMPORT ADR, CARDINAL8;
IMPORT LanSocket, Input, FrameBuffer, Visuals, Audio, RNG;

CONST
  MaxBolts = 32;
  MaxFoes = 16;
  MaxHostile = 32;
  PacketCapacity = 600;
  LanPort = 37177;

TYPE
  Pilot = RECORD
    x, y : INTEGER;
    lives, invuln, cooldown, pulse, ship, modifier : CARDINAL;
    shield, reserveShield : BOOLEAN
  END;
  Bolt = RECORD
    active : BOOLEAN;
    x, y, vx, vy : INTEGER;
    owner, power : CARDINAL
  END;
  Foe = RECORD
    active : BOOLEAN;
    x, y, vy : INTEGER;
    kind, health, phase, fire : CARDINAL
  END;
  Hostile = RECORD
    active : BOOLEAN;
    x, y, vx, vy : INTEGER
  END;

VAR
  pilots : ARRAY [0..1] OF Pilot;
  bolts : ARRAY [0..MaxBolts-1] OF Bolt;
  foes : ARRAY [0..MaxFoes-1] OF Foe;
  hostile : ARRAY [0..MaxHostile-1] OF Hostile;
  tx, rx : ARRAY [0..PacketCapacity-1] OF CARDINAL8;
  txPos, rxPos : CARDINAL;
  coop, host, connected, everConnected, done : BOOLEAN;
  frame, lastPacket, lastSnapshot, wave, waveTimer, spawnTimer : CARDINAL;
  score, timeLeft, roundPause, winner : CARDINAL;
  rounds : ARRAY [0..1] OF CARDINAL;
  localShip, localModifier, remoteMask : CARDINAL;
  bossActive : BOOLEAN;
  bossX, bossY : INTEGER;
  bossHealth, bossMax, bossKind, bossPhase, bossFire : CARDINAL;

PROCEDURE AbsI(v : INTEGER) : INTEGER;
BEGIN IF v < 0 THEN RETURN -v END; RETURN v END AbsI;

PROCEDURE Clamp(v, low, high : INTEGER) : INTEGER;
BEGIN
  IF v < low THEN RETURN low END;
  IF v > high THEN RETURN high END;
  RETURN v
END Clamp;

PROCEDURE SignedDivide(value, divisor : INTEGER) : INTEGER;
BEGIN
  IF value < 0 THEN RETURN -((-value + divisor - 1) DIV divisor) END;
  RETURN value DIV divisor
END SignedDivide;

PROCEDURE Put8(n : CARDINAL);
BEGIN
  IF txPos < PacketCapacity THEN tx[txPos] := VAL(CARDINAL8, n MOD 256); INC(txPos) END
END Put8;

PROCEDURE Put16(n : CARDINAL);
BEGIN
  Put8(n MOD 256); Put8((n DIV 256) MOD 256)
END Put16;

PROCEDURE Get8() : CARDINAL;
VAR n : CARDINAL;
BEGIN
  IF rxPos >= PacketCapacity THEN RETURN 0 END;
  n := VAL(CARDINAL, rx[rxPos]); INC(rxPos); RETURN n
END Get8;

PROCEDURE Get16() : CARDINAL;
VAR lo, hi : CARDINAL;
BEGIN
  lo := Get8(); hi := Get8(); RETURN lo + hi*256
END Get16;

PROCEDURE PutX(x : INTEGER);
BEGIN Put16(VAL(CARDINAL, Clamp(x+32, 0, 65535))) END PutX;

PROCEDURE PutY(y : INTEGER);
BEGIN Put8(VAL(CARDINAL, Clamp(y+24, 0, 254))) END PutY;

PROCEDURE GetX() : INTEGER;
BEGIN RETURN VAL(INTEGER, Get16()) - 32 END GetX;

PROCEDURE GetY() : INTEGER;
BEGIN RETURN VAL(INTEGER, Get8()) - 24 END GetY;

PROCEDURE ClearObjects;
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO MaxBolts-1 DO bolts[i].active := FALSE END;
  FOR i := 0 TO MaxFoes-1 DO foes[i].active := FALSE END;
  FOR i := 0 TO MaxHostile-1 DO hostile[i].active := FALSE END
END ClearObjects;

PROCEDURE SetPilot(index, ship, modifier : CARDINAL);
BEGIN
  pilots[index].ship := ship MOD 5;
  pilots[index].modifier := modifier MOD 7;
  pilots[index].x := 94 + VAL(INTEGER, index)*132;
  pilots[index].y := 143;
  pilots[index].lives := 3;
  IF ship = 1 THEN pilots[index].lives := 2 END;
  IF ship = 2 THEN pilots[index].lives := 4 END;
  IF ship = 4 THEN pilots[index].lives := 2 END;
  IF modifier = 1 THEN
    IF pilots[index].lives > 1 THEN DEC(pilots[index].lives) END
  END;
  IF (modifier = 4) AND (NOT coop) THEN
    IF pilots[index].lives > 1 THEN DEC(pilots[index].lives) END
  END;
  pilots[index].shield := (ship = 2) OR (modifier = 2);
  pilots[index].reserveShield := (ship = 2) AND (modifier = 2);
  pilots[index].invuln := 90;
  pilots[index].cooldown := 0;
  pilots[index].pulse := 0;
  IF ship = 3 THEN pilots[index].pulse := 45 END;
  IF modifier = 5 THEN pilots[index].pulse := 100 END
END SetPilot;

PROCEDURE Start(cooperative, hosting : BOOLEAN;
                a, b, c, d, ship, modifier : CARDINAL) : BOOLEAN;
VAR result : INTEGER;
BEGIN
  host := hosting; coop := cooperative;
  result := LanSocket.ion_lan_open(ORD(hosting), VAL(INTEGER,a), VAL(INTEGER,b),
              VAL(INTEGER,c), VAL(INTEGER,d), LanPort);
  IF result = 0 THEN RETURN FALSE END;
  frame := 0; lastPacket := 0; lastSnapshot := 0;
  connected := FALSE; everConnected := FALSE; done := FALSE; winner := 0;
  wave := 1; waveTimer := 0; spawnTimer := 60;
  score := 0; timeLeft := 10800; roundPause := 90;
  rounds[0] := 0; rounds[1] := 0;
  bossActive := FALSE; bossX := 160; bossY := 35;
  bossHealth := 0; bossMax := 0; bossKind := 0; bossPhase := 0; bossFire := 70;
  localShip := ship MOD 5; localModifier := modifier MOD 7;
  remoteMask := 0;
  SetPilot(0, 0, 0); SetPilot(1, 0, 0);
  IF host THEN SetPilot(0, localShip, localModifier)
  ELSE SetPilot(1, localShip, localModifier) END;
  IF NOT coop THEN
    pilots[0].x := 70; pilots[1].x := 250;
    pilots[0].y := 102; pilots[1].y := 102
  END;
  ClearObjects;
  RETURN TRUE
END Start;

PROCEDURE Close;
VAR sent : INTEGER;
BEGIN
  txPos := 0;
  Put8(73); Put8(76); Put8(1); Put8(3);
  sent := LanSocket.ion_lan_send(ADR(tx), VAL(INTEGER, txPos));
  sent := LanSocket.ion_lan_send(ADR(tx), VAL(INTEGER, txPos));
  LanSocket.ion_lan_close();
  connected := FALSE
END Close;

PROCEDURE Finished() : BOOLEAN;
BEGIN RETURN done END Finished;

PROCEDURE Connected() : BOOLEAN;
BEGIN RETURN connected END Connected;

PROCEDURE LocalMask() : CARDINAL;
VAR mask : CARDINAL;
BEGIN
  mask := 0;
  IF Input.Held(Input.Left) THEN INC(mask, 1) END;
  IF Input.Held(Input.Right) THEN INC(mask, 2) END;
  IF Input.Held(Input.Up) THEN INC(mask, 4) END;
  IF Input.Held(Input.Down) THEN INC(mask, 8) END;
  IF Input.Held(Input.Fire) THEN INC(mask, 16) END;
  IF Input.Held(Input.AltFire) THEN INC(mask, 32) END;
  RETURN mask
END LocalMask;

PROCEDURE Has(mask, bit : CARDINAL) : BOOLEAN;
BEGIN RETURN ((mask DIV bit) MOD 2) # 0 END Has;

PROCEDURE SendInput;
VAR sent : INTEGER;
BEGIN
  txPos := 0;
  Put8(73); Put8(76); Put8(1); Put8(1);
  Put16(frame MOD 65536);
  Put8(LocalMask()); Put8(localShip); Put8(localModifier);
  sent := LanSocket.ion_lan_send(ADR(tx), VAL(INTEGER, txPos))
END SendInput;

PROCEDURE ReadInputs;
VAR n, count : INTEGER; ship, modifier : CARDINAL;
BEGIN
  count := 0;
  REPEAT
    n := LanSocket.ion_lan_recv(ADR(rx), PacketCapacity);
    IF (n >= 4) AND (rx[0] = 73) AND (rx[1] = 76) AND
       (rx[2] = 1) AND (rx[3] = 3) THEN
      connected := FALSE; remoteMask := 0;
      LanSocket.ion_lan_release_peer
    END;
    IF n >= 9 THEN
      IF (rx[0] = 73) AND (rx[1] = 76) AND (rx[2] = 1) AND (rx[3] = 1) THEN
        remoteMask := VAL(CARDINAL, rx[6]);
        ship := VAL(CARDINAL, rx[7]) MOD 5;
        modifier := VAL(CARDINAL, rx[8]) MOD 7;
        IF NOT everConnected THEN
          SetPilot(1, ship, modifier);
          IF NOT coop THEN pilots[1].x := 250; pilots[1].y := 102 END
        END;
        connected := TRUE; everConnected := TRUE;
        lastPacket := frame
      END
    END;
    INC(count)
  UNTIL (n <= 0) OR (count >= 24)
END ReadInputs;

PROCEDURE SendSnapshot;
VAR i, sent : INTEGER;
BEGIN
  txPos := 0;
  Put8(73); Put8(76); Put8(1); Put8(2);
  Put16(frame MOD 65536);
  Put8(ORD(coop)); Put8(ORD(done)); Put8(winner); Put8(wave MOD 256);
  Put16(score MOD 65536); Put16(score DIV 65536);
  Put16(timeLeft MOD 65536);
  Put8(rounds[0]); Put8(rounds[1]); Put8(roundPause);
  FOR i := 0 TO 1 DO
    PutX(pilots[i].x); PutY(pilots[i].y);
    Put8(pilots[i].lives); Put8(pilots[i].invuln);
    Put8(pilots[i].pulse); Put8(pilots[i].ship);
    Put8(pilots[i].modifier); Put8(ORD(pilots[i].shield));
    Put8(ORD(pilots[i].reserveShield))
  END;
  Put8(ORD(bossActive)); PutX(bossX); PutY(bossY);
  Put16(bossHealth); Put16(bossMax); Put8(bossKind);
  FOR i := 0 TO MaxBolts-1 DO
    Put8(ORD(bolts[i].active)); PutX(bolts[i].x); PutY(bolts[i].y);
    Put8(bolts[i].owner); Put8(bolts[i].power)
  END;
  FOR i := 0 TO MaxFoes-1 DO
    Put8(ORD(foes[i].active)); Put8(foes[i].kind);
    PutX(foes[i].x); PutY(foes[i].y); Put8(foes[i].health)
  END;
  FOR i := 0 TO MaxHostile-1 DO
    Put8(ORD(hostile[i].active)); PutX(hostile[i].x); PutY(hostile[i].y)
  END;
  sent := LanSocket.ion_lan_send(ADR(tx), VAL(INTEGER, txPos))
END SendSnapshot;

PROCEDURE ReadSnapshot;
VAR n, count, i : INTEGER; seq, delta, scoreLo, scoreHi : CARDINAL;
BEGIN
  count := 0;
  REPEAT
    n := LanSocket.ion_lan_recv(ADR(rx), PacketCapacity);
    IF (n >= 4) AND (rx[0] = 73) AND (rx[1] = 76) AND
       (rx[2] = 1) AND (rx[3] = 3) THEN connected := FALSE END;
    IF n >= 464 THEN
      IF (rx[0] = 73) AND (rx[1] = 76) AND (rx[2] = 1) AND (rx[3] = 2) THEN
        rxPos := 4;
        seq := Get16();
        delta := (seq + 65536 - lastSnapshot) MOD 65536;
        IF (NOT connected) OR ((delta > 0) AND (delta < 32768)) THEN
          lastSnapshot := seq;
          connected := TRUE; everConnected := TRUE; lastPacket := frame;
          coop := Get8() # 0; done := Get8() # 0;
          winner := Get8(); wave := Get8();
          scoreLo := Get16(); scoreHi := Get16();
          score := scoreLo + scoreHi*65536;
          timeLeft := Get16();
          rounds[0] := Get8(); rounds[1] := Get8(); roundPause := Get8();
          FOR i := 0 TO 1 DO
            pilots[i].x := GetX(); pilots[i].y := GetY();
            pilots[i].lives := Get8(); pilots[i].invuln := Get8();
            pilots[i].pulse := Get8(); pilots[i].ship := Get8();
            pilots[i].modifier := Get8(); pilots[i].shield := Get8() # 0;
            pilots[i].reserveShield := Get8() # 0
          END;
          bossActive := Get8() # 0; bossX := GetX(); bossY := GetY();
          bossHealth := Get16(); bossMax := Get16(); bossKind := Get8();
          FOR i := 0 TO MaxBolts-1 DO
            bolts[i].active := Get8() # 0;
            bolts[i].x := GetX(); bolts[i].y := GetY();
            bolts[i].owner := Get8(); bolts[i].power := Get8()
          END;
          FOR i := 0 TO MaxFoes-1 DO
            foes[i].active := Get8() # 0; foes[i].kind := Get8();
            foes[i].x := GetX(); foes[i].y := GetY();
            foes[i].health := Get8()
          END;
          FOR i := 0 TO MaxHostile-1 DO
            hostile[i].active := Get8() # 0;
            hostile[i].x := GetX(); hostile[i].y := GetY()
          END
        END
      END
    END;
    INC(count)
  UNTIL (n <= 0) OR (count >= 24)
END ReadSnapshot;

PROCEDURE SpawnBolt(owner : CARDINAL);
VAR i, cooldown, power : CARDINAL;
BEGIN
  IF pilots[owner].cooldown > 0 THEN RETURN END;
  FOR i := 0 TO MaxBolts-1 DO
    IF NOT bolts[i].active THEN
      bolts[i].active := TRUE;
      bolts[i].owner := owner;
      bolts[i].x := pilots[owner].x;
      bolts[i].y := pilots[owner].y-9;
      bolts[i].vx := 0; bolts[i].vy := -8;
      IF NOT coop THEN
        bolts[i].x := pilots[owner].x + 10 - VAL(INTEGER, owner)*20;
        bolts[i].y := pilots[owner].y;
        bolts[i].vx := 8 - VAL(INTEGER, owner)*16;
        bolts[i].vy := 0
      END;
      power := 1;
      IF pilots[owner].ship = 4 THEN INC(power) END;
      IF pilots[owner].modifier = 6 THEN INC(power) END;
      bolts[i].power := power;
      cooldown := 10;
      IF pilots[owner].ship = 1 THEN cooldown := 7 END;
      IF pilots[owner].ship = 2 THEN cooldown := 12 END;
      IF pilots[owner].modifier = 1 THEN cooldown := 5 END;
      IF pilots[owner].modifier = 3 THEN INC(cooldown) END;
      IF pilots[owner].modifier = 6 THEN INC(cooldown, 3) END;
      pilots[owner].cooldown := cooldown;
      Audio.Play(Audio.Laser);
      RETURN
    END
  END
END SpawnBolt;

PROCEDURE SpawnFoe;
VAR i, kind : CARDINAL;
BEGIN
  FOR i := 0 TO MaxFoes-1 DO
    IF NOT foes[i].active THEN
      kind := RNG.Range(11);
      IF wave < 3 THEN kind := kind MOD 4
      ELSIF wave < 5 THEN kind := kind MOD 8
      END;
      foes[i].active := TRUE;
      foes[i].kind := kind;
      foes[i].x := VAL(INTEGER, 15 + RNG.Range(290));
      foes[i].y := -12;
      foes[i].vy := 1 + VAL(INTEGER, kind MOD 2);
      foes[i].health := 1 + kind MOD 3;
      IF kind = 10 THEN foes[i].health := 5 END;
      foes[i].phase := RNG.Range(80);
      foes[i].fire := 65 + RNG.Range(90);
      RETURN
    END
  END
END SpawnFoe;

PROCEDURE SpawnHostile(x, y, dx, dy : INTEGER);
VAR i, den : CARDINAL;
BEGIN
  FOR i := 0 TO MaxHostile-1 DO
    IF NOT hostile[i].active THEN
      den := VAL(CARDINAL, AbsI(dx) + AbsI(dy));
      IF den = 0 THEN den := 1 END;
      hostile[i].active := TRUE;
      hostile[i].x := x; hostile[i].y := y;
      hostile[i].vx := SignedDivide(dx*3, VAL(INTEGER, den));
      hostile[i].vy := SignedDivide(dy*3, VAL(INTEGER, den));
      IF hostile[i].vy < 1 THEN hostile[i].vy := 1 END;
      RETURN
    END
  END
END SpawnHostile;

PROCEDURE ResetRound;
VAR i : CARDINAL; ship, modifier : CARDINAL;
BEGIN
  FOR i := 0 TO 1 DO
    ship := pilots[i].ship; modifier := pilots[i].modifier;
    SetPilot(i, ship, modifier);
    pilots[i].x := 70 + VAL(INTEGER, i)*180;
    pilots[i].y := 102
  END;
  ClearObjects;
  roundPause := 90
END ResetRound;

PROCEDURE DamagePilot(index : CARDINAL);
BEGIN
  IF done OR (pilots[index].lives = 0) OR (pilots[index].invuln > 0) THEN RETURN END;
  IF pilots[index].shield THEN
    IF pilots[index].reserveShield THEN pilots[index].reserveShield := FALSE
    ELSE pilots[index].shield := FALSE END;
    pilots[index].invuln := 60;
    Audio.Play(Audio.Hurt);
    RETURN
  END;
  DEC(pilots[index].lives);
  pilots[index].invuln := 95;
  Audio.Play(Audio.Hurt);
  IF pilots[index].lives = 0 THEN
    IF coop THEN
      IF pilots[1-index].lives = 0 THEN done := TRUE; winner := 0 END
    ELSE
      INC(rounds[1-index]);
      Audio.Play(Audio.Explosion);
      IF rounds[1-index] >= 5 THEN
        done := TRUE; winner := 2-index
      ELSE ResetRound
      END
    END
  END
END DamagePilot;

PROCEDURE Pulse(index : CARDINAL);
VAR i : CARDINAL;
BEGIN
  IF pilots[index].pulse < 100 THEN RETURN END;
  pilots[index].pulse := 0;
  Audio.Play(Audio.Power);
  IF coop THEN
    FOR i := 0 TO MaxHostile-1 DO hostile[i].active := FALSE END;
    FOR i := 0 TO MaxFoes-1 DO
      IF foes[i].active THEN
        IF foes[i].health > 2 THEN DEC(foes[i].health, 2)
        ELSE foes[i].active := FALSE; score := score + 100 END
      END
    END;
    IF bossActive THEN
      IF bossHealth > 12 THEN DEC(bossHealth, 12) ELSE bossHealth := 0 END
    END;
    IF pilots[1-index].lives = 0 THEN
      pilots[1-index].lives := 1;
      pilots[1-index].invuln := 150;
      pilots[1-index].x := 94 + VAL(INTEGER, 1-index)*132;
      pilots[1-index].y := 143
    END
  ELSE
    FOR i := 0 TO MaxBolts-1 DO
      IF bolts[i].active AND (bolts[i].owner # index) THEN bolts[i].active := FALSE END
    END;
    IF (AbsI(pilots[index].x-pilots[1-index].x) < 70) AND
       (AbsI(pilots[index].y-pilots[1-index].y) < 48) THEN
      DamagePilot(1-index)
    END
  END
END Pulse;

PROCEDURE MovePilot(index, mask : CARDINAL);
VAR speed : INTEGER;
BEGIN
  IF pilots[index].lives = 0 THEN RETURN END;
  speed := 3;
  IF (pilots[index].ship = 1) OR (pilots[index].ship = 3) THEN speed := 4 END;
  IF pilots[index].ship = 2 THEN speed := 2 END;
  IF pilots[index].modifier = 2 THEN speed := 2 END;
  IF Has(mask, 1) THEN DEC(pilots[index].x, speed) END;
  IF Has(mask, 2) THEN INC(pilots[index].x, speed) END;
  IF Has(mask, 4) THEN DEC(pilots[index].y, speed) END;
  IF Has(mask, 8) THEN INC(pilots[index].y, speed) END;
  IF coop THEN pilots[index].x := Clamp(pilots[index].x, 13, 307)
  ELSIF index = 0 THEN pilots[index].x := Clamp(pilots[index].x, 13, 151)
  ELSE pilots[index].x := Clamp(pilots[index].x, 169, 307)
  END;
  pilots[index].y := Clamp(pilots[index].y, 29, 166);
  IF pilots[index].cooldown > 0 THEN DEC(pilots[index].cooldown) END;
  IF pilots[index].invuln > 0 THEN DEC(pilots[index].invuln) END;
  IF Has(mask, 16) THEN SpawnBolt(index) END;
  IF Has(mask, 32) THEN Pulse(index) END
END MovePilot;

PROCEDURE KillFoe(index, owner : CARDINAL);
VAR gain : CARDINAL;
BEGIN
  foes[index].active := FALSE;
  score := score + 100 + foes[index].kind*40;
  IF pilots[owner].modifier = 4 THEN
    score := score + 100 + foes[index].kind*40
  END;
  gain := 8;
  IF pilots[owner].ship = 3 THEN gain := 12 END;
  IF pilots[owner].modifier = 3 THEN gain := gain + 8 END;
  IF pilots[owner].modifier = 5 THEN gain := 3 END;
  IF pilots[owner].modifier = 6 THEN gain := 4 END;
  IF pilots[owner].pulse + gain > 100 THEN pilots[owner].pulse := 100
  ELSE INC(pilots[owner].pulse, gain)
  END;
  Audio.Play(Audio.Explosion)
END KillFoe;

PROCEDURE UpdateBolts;
VAR i, f, other, gain : CARDINAL;
BEGIN
  FOR i := 0 TO MaxBolts-1 DO
    IF bolts[i].active THEN
      INC(bolts[i].x, bolts[i].vx);
      INC(bolts[i].y, bolts[i].vy);
      IF (bolts[i].x < -10) OR (bolts[i].x > 330) OR
         (bolts[i].y < -12) OR (bolts[i].y > 190) THEN
        bolts[i].active := FALSE
      ELSIF coop THEN
        FOR f := 0 TO MaxFoes-1 DO
          IF bolts[i].active AND foes[f].active AND
             (AbsI(bolts[i].x-foes[f].x) < 10) AND
             (AbsI(bolts[i].y-foes[f].y) < 9) THEN
            bolts[i].active := FALSE;
            IF foes[f].health > bolts[i].power THEN
              DEC(foes[f].health, bolts[i].power)
            ELSE KillFoe(f, bolts[i].owner)
            END
          END
        END;
        IF bolts[i].active AND bossActive AND
           (AbsI(bolts[i].x-bossX) < 27) AND
           (AbsI(bolts[i].y-bossY) < 15) THEN
          bolts[i].active := FALSE;
          IF bossHealth > bolts[i].power THEN DEC(bossHealth, bolts[i].power)
          ELSE bossHealth := 0 END;
          Audio.Play(Audio.Hit)
        END
      ELSE
        other := 1-bolts[i].owner;
        IF (pilots[other].lives > 0) AND
           (AbsI(bolts[i].x-pilots[other].x) < 10) AND
           (AbsI(bolts[i].y-pilots[other].y) < 9) THEN
          bolts[i].active := FALSE;
          IF pilots[other].invuln = 0 THEN
            gain := 15;
            IF pilots[bolts[i].owner].modifier = 3 THEN gain := 28 END;
            IF pilots[bolts[i].owner].modifier = 4 THEN gain := 30 END;
            IF pilots[bolts[i].owner].modifier = 5 THEN gain := 5 END;
            IF pilots[bolts[i].owner].modifier = 6 THEN gain := 8 END;
            IF pilots[bolts[i].owner].pulse + gain < 100 THEN
              INC(pilots[bolts[i].owner].pulse, gain)
            ELSE pilots[bolts[i].owner].pulse := 100
            END
          END;
          DamagePilot(other)
        END
      END
    END
  END
END UpdateBolts;

PROCEDURE UpdateFoes;
VAR i, target : CARDINAL; dx : INTEGER;
BEGIN
  FOR i := 0 TO MaxFoes-1 DO
    IF foes[i].active THEN
      INC(foes[i].phase);
      INC(foes[i].y, foes[i].vy);
      IF (foes[i].kind MOD 3) = 0 THEN
        IF (foes[i].phase MOD 60) < 30 THEN INC(foes[i].x)
        ELSE DEC(foes[i].x) END
      ELSIF (foes[i].kind MOD 3) = 1 THEN
        IF (foes[i].phase MOD 40) < 20 THEN INC(foes[i].x, 2)
        ELSE DEC(foes[i].x, 2) END
      END;
      IF foes[i].y > 190 THEN foes[i].active := FALSE
      ELSE
        IF foes[i].fire > 0 THEN DEC(foes[i].fire)
        ELSE
          target := RNG.Range(2);
          IF pilots[target].lives = 0 THEN target := 1-target END;
          dx := pilots[target].x - foes[i].x;
          SpawnHostile(foes[i].x, foes[i].y+5, dx,
                       pilots[target].y-foes[i].y);
          foes[i].fire := 75 + RNG.Range(95)
        END;
        FOR target := 0 TO 1 DO
          IF (pilots[target].lives > 0) AND
             (AbsI(foes[i].x-pilots[target].x) < 12) AND
             (AbsI(foes[i].y-pilots[target].y) < 10) THEN
            foes[i].active := FALSE;
            DamagePilot(target)
          END
        END
      END
    END
  END
END UpdateFoes;

PROCEDURE UpdateHostile;
VAR i, p : CARDINAL;
BEGIN
  FOR i := 0 TO MaxHostile-1 DO
    IF hostile[i].active THEN
      INC(hostile[i].x, hostile[i].vx);
      INC(hostile[i].y, hostile[i].vy);
      IF (hostile[i].y > 190) OR (hostile[i].x < -10) OR
         (hostile[i].x > 330) THEN hostile[i].active := FALSE
      ELSE
        FOR p := 0 TO 1 DO
          IF hostile[i].active AND (pilots[p].lives > 0) AND
             (AbsI(hostile[i].x-pilots[p].x) < 6) AND
             (AbsI(hostile[i].y-pilots[p].y) < 6) THEN
            hostile[i].active := FALSE;
            DamagePilot(p)
          END
        END
      END
    END
  END
END UpdateHostile;

PROCEDURE UpdateBoss;
VAR target, d : INTEGER; phaseX : CARDINAL;
BEGIN
  IF NOT bossActive THEN RETURN END;
  INC(bossPhase);
  phaseX := (bossPhase + 120) MOD 480;
  bossX := 40 + VAL(INTEGER, phaseX);
  IF bossX > 280 THEN bossX := 560-bossX END;
  bossY := 34 + VAL(INTEGER, (bossPhase DIV 16) MOD 5);
  IF bossFire > 0 THEN DEC(bossFire)
  ELSE
    target := VAL(INTEGER, RNG.Range(2));
    IF pilots[target].lives = 0 THEN target := 1-target END;
    FOR d := -1 TO 1 DO
      SpawnHostile(bossX+d*12, bossY+9,
                   pilots[target].x-bossX+d*34, pilots[target].y-bossY)
    END;
    bossFire := 58
  END;
  IF bossHealth = 0 THEN
    bossActive := FALSE;
    score := score + 5000;
    Audio.Play(Audio.Explosion);
    IF wave >= 8 THEN done := TRUE; winner := 3
    ELSE INC(wave); waveTimer := 0; spawnTimer := 60
    END
  END
END UpdateBoss;

PROCEDURE UpdateCoopWave;
BEGIN
  IF bossActive OR done THEN RETURN END;
  INC(waveTimer);
  IF (wave MOD 4) = 0 THEN
    IF waveTimer > 120 THEN
      bossActive := TRUE;
      bossKind := (wave DIV 4 + 4) MOD 8;
      bossX := 160; bossY := 34; bossPhase := 0; bossFire := 70;
      bossMax := 55 + wave*12; bossHealth := bossMax;
      Audio.Play(Audio.BossPulse)
    END;
    RETURN
  END;
  IF spawnTimer > 0 THEN DEC(spawnTimer)
  ELSE
    SpawnFoe;
    spawnTimer := 57 - wave*3 + RNG.Range(13);
    IF (pilots[0].modifier = 4) OR (pilots[1].modifier = 4) THEN
      spawnTimer := spawnTimer*4 DIV 5
    END
  END;
  IF waveTimer >= 600 THEN
    INC(wave); waveTimer := 0; spawnTimer := 45;
    Audio.SetIntensity(1 + wave DIV 3)
  END
END UpdateCoopWave;

PROCEDURE UpdateWorld;
VAR i, regenRate : CARDINAL;
BEGIN
  IF done THEN RETURN END;
  IF roundPause > 0 THEN
    DEC(roundPause);
    RETURN
  END;
  MovePilot(0, LocalMask());
  MovePilot(1, remoteMask);
  UpdateBolts;
  IF done THEN RETURN END;
  IF coop THEN
    UpdateFoes;
    UpdateHostile;
    UpdateBoss;
    UpdateCoopWave
  ELSE
    IF timeLeft > 0 THEN DEC(timeLeft) END;
    IF timeLeft = 0 THEN
      done := TRUE;
      IF rounds[0] > rounds[1] THEN winner := 1
      ELSIF rounds[1] > rounds[0] THEN winner := 2
      ELSE winner := 0 END
    END;
    FOR i := 0 TO 1 DO
      IF pilots[i].pulse < 100 THEN
        regenRate := 24;
        IF pilots[i].ship = 3 THEN regenRate := 18 END;
        IF pilots[i].modifier = 5 THEN regenRate := 48 END;
        IF (frame MOD regenRate) = 0 THEN INC(pilots[i].pulse) END
      END
    END
  END
END UpdateWorld;

PROCEDURE Update;
BEGIN
  INC(frame);
  IF host THEN
    ReadInputs;
    IF connected AND (frame-lastPacket > 600) THEN
      connected := FALSE;
      remoteMask := 0;
      LanSocket.ion_lan_release_peer
    END;
    IF connected THEN
      UpdateWorld;
      SendSnapshot
    END
  ELSE
    SendInput;
    ReadSnapshot;
    IF connected AND (frame-lastPacket > 600) THEN connected := FALSE END
  END
END Update;

PROCEDURE Digits(n : CARDINAL; VAR out : ARRAY OF CHAR; minDigits : CARDINAL);
VAR tmp : ARRAY [0..15] OF CHAR; i, j : CARDINAL;
BEGIN
  i := 0;
  REPEAT
    tmp[i] := CHR(ORD('0') + n MOD 10);
    n := n DIV 10; INC(i)
  UNTIL (n = 0) OR (i > HIGH(tmp));
  WHILE i < minDigits DO tmp[i] := '0'; INC(i) END;
  j := 0;
  WHILE i > 0 DO DEC(i); out[j] := tmp[i]; INC(j) END;
  out[j] := CHR(0)
END Digits;

PROCEDURE Center(y : INTEGER; label : ARRAY OF CHAR; colour, scale : CARDINAL);
VAR x : INTEGER;
BEGIN
  x := (FrameBuffer.Width-VAL(INTEGER,FrameBuffer.TextWidth(label,scale))) DIV 2;
  FrameBuffer.DrawText(x, y, label, colour, scale)
END Center;

PROCEDURE DrawHud;
VAR buf : ARRAY [0..15] OF CHAR; i : CARDINAL;
BEGIN
  FrameBuffer.FillRect(0, 0, 320, 17, 1);
  FrameBuffer.HLine(0, 319, 17, 4);
  IF host THEN
    FrameBuffer.DrawText(5, 4, "YOU", 12, 1);
    FrameBuffer.DrawText(226, 4, "GUEST", 15, 1)
  ELSE
    FrameBuffer.DrawText(5, 4, "HOST", 12, 1);
    FrameBuffer.DrawText(226, 4, "YOU", 15, 1)
  END;
  IF coop THEN
    Digits(score, buf, 6);
    FrameBuffer.DrawText(117, 4, buf, 19, 1)
  ELSE
    Digits(rounds[0], buf, 1); FrameBuffer.DrawText(75, 4, buf, 12, 1);
    Digits(timeLeft DIV 60, buf, 3); FrameBuffer.DrawText(150, 4, buf, 19, 1);
    Digits(rounds[1], buf, 1); FrameBuffer.DrawText(204, 4, buf, 15, 1)
  END;
  FOR i := 0 TO 3 DO
    Visuals.DrawHeart(43+VAL(INTEGER,i*8), 6, i < pilots[0].lives);
    Visuals.DrawHeart(270+VAL(INTEGER,i*8), 6, i < pilots[1].lives)
  END
END DrawHud;

PROCEDURE DrawWorld;
VAR i : CARDINAL; x, y : INTEGER; buf : ARRAY [0..15] OF CHAR;
BEGIN
  IF coop THEN
    Digits(wave, buf, 2);
    FrameBuffer.DrawText(5, 22, "WAVE", 5, 1);
    FrameBuffer.DrawText(30, 22, buf, 12, 1);
    IF bossActive THEN
      Visuals.DrawBoss(bossKind, bossX, bossY, frame, bossHealth, bossMax);
      FrameBuffer.Rect(77, 20, 167, 7, 5);
      IF bossMax > 0 THEN
        FrameBuffer.FillRect(78, 21, VAL(INTEGER,bossHealth*165 DIV bossMax), 5, 19)
      END
    END;
    FOR i := 0 TO MaxFoes-1 DO
      IF foes[i].active THEN Visuals.DrawEnemy(foes[i].kind, foes[i].x,
                                              foes[i].y, frame+i) END
    END;
    FOR i := 0 TO MaxHostile-1 DO
      IF hostile[i].active THEN
        Visuals.DrawEnemyShot(hostile[i].x, hostile[i].y, frame+i)
      END
    END
  ELSE
    FrameBuffer.VLine(160, 22, 177, 3);
    FrameBuffer.HLine(0, 319, 176, 3);
    IF roundPause > 0 THEN
      Digits(rounds[0]+rounds[1]+1, buf, 1);
      Center(28, "ROUND", 19, 1);
      Center(38, buf, 12, 2)
    END
  END;
  FOR i := 0 TO MaxBolts-1 DO
    IF bolts[i].active THEN
      x := bolts[i].x; y := bolts[i].y;
      IF coop THEN
        Visuals.DrawPlayerShot(x, y, frame+i, bolts[i].power)
      ELSE
        FrameBuffer.HLine(x-3, x+3, y, 12 + bolts[i].owner*3);
        FrameBuffer.PutPixel(x, y-1, 8); FrameBuffer.PutPixel(x, y+1, 8)
      END
    END
  END;
  FOR i := 0 TO 1 DO
    IF (pilots[i].lives > 0) AND
       ((pilots[i].invuln = 0) OR ((frame MOD 6) < 3)) THEN
      Visuals.DrawShip(pilots[i].ship, pilots[i].x, pilots[i].y,
                       frame, 0, pilots[i].shield);
      IF pilots[i].reserveShield THEN
        FrameBuffer.Rect(pilots[i].x-15, pilots[i].y-16, 31, 32, 11)
      END
    END;
    IF pilots[i].lives > 0 THEN
      FrameBuffer.Rect(pilots[i].x-10, pilots[i].y+13, 21, 3, 4);
      FrameBuffer.FillRect(pilots[i].x-9, pilots[i].y+14,
                           VAL(INTEGER,pilots[i].pulse*19 DIV 100), 1,
                           12 + i*3)
    END
  END
END DrawWorld;

PROCEDURE DrawOverlay;
VAR buf : ARRAY [0..15] OF CHAR;
BEGIN
  IF NOT connected THEN
    Visuals.DrawPanel(54, 61, 212, 62, TRUE);
    IF everConnected THEN Center(73, "LINK LOST / REJOINING", 16, 1)
    ELSIF host THEN Center(73, "WAITING FOR PILOT", 19, 1)
    ELSE Center(73, "CONNECTING TO HOST", 19, 1) END;
    Center(88, "UDP PORT 37177", 6, 1);
    Visuals.CenterHint(54, 212, 103, Visuals.MenuHint, "MAIN MENU", 12)
  ELSIF done THEN
    Visuals.DrawPanel(43, 53, 234, 83, TRUE);
    IF coop THEN
      IF winner = 3 THEN Center(64, "TEAM VICTORY", 10, 2)
      ELSE Center(64, "TEAM LOST", 16, 2) END;
      Digits(score, buf, 6); Center(94, buf, 19, 2)
    ELSE
      CASE winner OF
        1 : Center(64, "HOST WINS", 12, 2)
      | 2 : Center(64, "GUEST WINS", 15, 2)
      ELSE Center(64, "DRAW", 19, 2)
      END;
      Digits(rounds[0], buf, 1); FrameBuffer.DrawText(129, 94, buf, 12, 2);
      FrameBuffer.DrawText(151, 94, ":", 7, 2);
      Digits(rounds[1], buf, 1); FrameBuffer.DrawText(169, 94, buf, 15, 2)
    END;
    Visuals.CenterHint(43, 234, 120, Visuals.ConfirmHint, "MAIN MENU", 12)
  END
END DrawOverlay;

PROCEDURE Draw;
BEGIN
  DrawWorld;
  DrawHud;
  DrawOverlay
END Draw;

BEGIN
  connected := FALSE; done := FALSE; host := FALSE; coop := TRUE;
  frame := 0; score := 0; wave := 1
END Arena.
