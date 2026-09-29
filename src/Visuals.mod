IMPLEMENTATION MODULE Visuals;

IMPORT FrameBuffer, Input;

PROCEDURE SPoint(cx, cy, dx, dy : INTEGER; colour, scale : CARDINAL);
BEGIN
  FrameBuffer.FillRect(cx + dx*VAL(INTEGER, scale),
                       cy + dy*VAL(INTEGER, scale),
                       VAL(INTEGER, scale), VAL(INTEGER, scale), colour)
END SPoint;

PROCEDURE SHLine(cx, cy, x1, x2, yy : INTEGER; colour, scale : CARDINAL);
VAR a, b, s : INTEGER;
BEGIN
  a := x1; b := x2;
  IF a > b THEN s := a; a := b; b := s END;
  s := VAL(INTEGER, scale);
  FrameBuffer.FillRect(cx + a*s, cy + yy*s, (b-a+1)*s, s, colour)
END SHLine;

PROCEDURE SVLine(cx, cy, xx, y1, y2 : INTEGER; colour, scale : CARDINAL);
VAR a, b, s : INTEGER;
BEGIN
  a := y1; b := y2;
  IF a > b THEN s := a; a := b; b := s END;
  s := VAL(INTEGER, scale);
  FrameBuffer.FillRect(cx + xx*s, cy + a*s, s, (b-a+1)*s, colour)
END SVLine;

PROCEDURE DrawIronwing(x, y : INTEGER; frame : CARDINAL; bank : INTEGER;
                       shield : BOOLEAN; scale : CARDINAL);
VAR flare, wing, glow : INTEGER; c : CARDINAL;
BEGIN
  flare := VAL(INTEGER, frame MOD 4);
  wing := 0;
  IF bank < 0 THEN wing := -1 ELSIF bank > 0 THEN wing := 1 END;
  glow := 16 + VAL(INTEGER, (frame DIV 2) MOD 3);

  SHLine(x, y, -2, 2, 8, 18, scale);
  SHLine(x, y, -1, 1, 9, 17, scale);
  IF flare >= 1 THEN
    SPoint(x, y, -1, 10, 19, scale); SPoint(x, y, 1, 10, 19, scale)
  END;
  IF flare >= 2 THEN SPoint(x, y, 0, 11, 16, scale) END;

  SHLine(x, y, -10+wing, 10+wing, 1, 24, scale);
  SHLine(x, y, -8+wing, 8+wing, 2, 25, scale);
  SHLine(x, y, -6+wing, 6+wing, 3, 26, scale);
  SHLine(x, y, -4, 4, 4, 7, scale);
  SPoint(x, y, -9+wing, 0, 8, scale); SPoint(x, y, 9+wing, 0, 8, scale);
  SPoint(x, y, -7+wing, 2, VAL(CARDINAL, glow), scale);
  SPoint(x, y, 7+wing, 2, VAL(CARDINAL, glow), scale);
  SPoint(x, y, -5+wing, 3, 12, scale); SPoint(x, y, 5+wing, 3, 12, scale);

  SVLine(x, y, 0, -10, 6, 7, scale);
  SVLine(x, y, -1, -7, 5, 6, scale);
  SVLine(x, y, 1, -7, 5, 6, scale);
  SHLine(x, y, -2, 2, -3, 7, scale);
  SHLine(x, y, -2, 2, -1, 12, scale);
  SPoint(x, y, 0, -11, 8, scale);
  SPoint(x, y, 0, -9, 14, scale);
  SPoint(x, y, 0, -8, 14, scale);
  SPoint(x, y, 0, -6, 11, scale);
  SPoint(x, y, -2, 6, 18, scale); SPoint(x, y, 2, 6, 18, scale);

  IF shield THEN
    c := 12 + ((frame DIV 2) MOD 2);
    SHLine(x, y, -9, 9, -12, c, scale);
    SHLine(x, y, -9, 9, 12, c, scale);
    SVLine(x, y, -12, -5, 5, c, scale);
    SVLine(x, y, 12, -5, 5, c, scale);
    SPoint(x, y, -11, -8, c, scale); SPoint(x, y, 11, -8, c, scale);
    SPoint(x, y, -11, 8, c, scale); SPoint(x, y, 11, 8, c, scale);
    SPoint(x, y, -9, -11, c, scale); SPoint(x, y, 9, -11, c, scale);
    SPoint(x, y, -9, 11, c, scale); SPoint(x, y, 9, 11, c, scale)
  END
END DrawIronwing;

PROCEDURE DrawPlayer(x, y : INTEGER; frame : CARDINAL; bank : INTEGER;
                     shield : BOOLEAN);
BEGIN
  DrawIronwing(x, y, frame, bank, shield, 1)
END DrawPlayer;

PROCEDURE ShipBody(kind : CARDINAL; x, y : INTEGER; frame : CARDINAL;
                   bank : INTEGER; shield : BOOLEAN; scale : CARDINAL);
VAR c, bright : CARDINAL; wing : INTEGER;
BEGIN
  IF kind = 0 THEN
    DrawIronwing(x, y, frame, bank, shield, scale);
    RETURN
  END;
  wing := 0;
  IF bank < 0 THEN wing := -1 ELSIF bank > 0 THEN wing := 1 END;
  CASE kind OF
    1 : c := 11; bright := 12;
        SHLine(x, y, -1, 1, -11, 4, scale);
        SHLine(x, y, -2, 2, -9, 4, scale);
        SHLine(x, y, -4, 4, -6, 3, scale);
        SHLine(x, y, -6, 6, -3, 4, scale);
        SHLine(x, y, -9+wing, 9+wing, -1, 3, scale);
        SHLine(x, y, -12+wing, 12+wing, 1, 4, scale);
        SHLine(x, y, -12+wing, -4+wing, 3, 4, scale);
        SHLine(x, y, 4+wing, 12+wing, 3, 4, scale);
        SHLine(x, y, -9+wing, -4+wing, 5, 3, scale);
        SHLine(x, y, 4+wing, 9+wing, 5, 3, scale);
        SHLine(x, y, -2, 2, -6, 7, scale);
        SHLine(x, y, -3, 3, -4, 6, scale);
        SHLine(x, y, -5+wing, 5+wing, -1, 11, scale);
        SHLine(x, y, -8+wing, 8+wing, 0, 13, scale);
        SHLine(x, y, -11+wing, 11+wing, 1, c, scale);
        SHLine(x, y, -12+wing, -4+wing, 2, bright, scale);
        SHLine(x, y, 4+wing, 12+wing, 2, bright, scale);
        SHLine(x, y, -11+wing, -5+wing, 3, c, scale);
        SHLine(x, y, 5+wing, 11+wing, 3, c, scale);
        SHLine(x, y, -9+wing, -6+wing, 4, 7, scale);
        SHLine(x, y, 6+wing, 9+wing, 4, 7, scale);
        SHLine(x, y, -3, 3, 5, 6, scale);
        SVLine(x, y, 0, -11, 5, 7, scale);
        SVLine(x, y, -3, -3, 4, 5, scale);
        SVLine(x, y, 3, -3, 4, 5, scale);
        SHLine(x, y, -10+wing, -7+wing, 1, 8, scale);
        SHLine(x, y, 7+wing, 10+wing, 1, 8, scale);
        SPoint(x, y, 0, -12, 8, scale);
        SPoint(x, y, 0, -7, 12, scale);
        SPoint(x, y, -3, 7, 18, scale);
        SPoint(x, y, 3, 7, 18, scale)
  | 2 : c := 22; bright := 10;
        SHLine(x, y, -3, 3, -9, 4, scale);
        SHLine(x, y, -6, 6, -7, 23, scale);
        SHLine(x, y, -8, 8, -5, 4, scale);
        SHLine(x, y, -10, 10, -3, 23, scale);
        SHLine(x, y, -12+wing, 12+wing, -1, 4, scale);
        SHLine(x, y, -14+wing, 14+wing, 1, 23, scale);
        SHLine(x, y, -14+wing, -6+wing, 3, 4, scale);
        SHLine(x, y, 6+wing, 14+wing, 3, 4, scale);
        SHLine(x, y, -14+wing, -7+wing, 5, 23, scale);
        SHLine(x, y, 7+wing, 14+wing, 5, 23, scale);
        SHLine(x, y, -4, 4, -7, 20, scale);
        SHLine(x, y, -6, 6, -5, 22, scale);
        SHLine(x, y, -8, 8, -3, 23, scale);
        SHLine(x, y, -9+wing, 9+wing, -1, c, scale);
        SHLine(x, y, -11+wing, 11+wing, 1, 21, scale);
        SHLine(x, y, -13+wing, -7+wing, 2, 22, scale);
        SHLine(x, y, 7+wing, 13+wing, 2, 22, scale);
        SHLine(x, y, -13+wing, -7+wing, 4, bright, scale);
        SHLine(x, y, 7+wing, 13+wing, 4, bright, scale);
        SHLine(x, y, -12+wing, -8+wing, 6, 23, scale);
        SHLine(x, y, 8+wing, 12+wing, 6, 23, scale);
        SHLine(x, y, -7, 7, 6, 22, scale);
        SHLine(x, y, -2, 2, -2, 9, scale);
        SHLine(x, y, -2, 2, 0, 10, scale);
        SVLine(x, y, 0, -9, 3, 7, scale);
        SVLine(x, y, -10+wing, -2, 5, 21, scale);
        SVLine(x, y, 10+wing, -2, 5, 21, scale);
        SPoint(x, y, -12+wing, 1, 10, scale);
        SPoint(x, y, 12+wing, 1, 10, scale);
        SPoint(x, y, 0, -10, 8, scale);
        SPoint(x, y, -5, 8, 19, scale);
        SPoint(x, y, 5, 8, 19, scale)
  | 3 : c := 14; bright := 15;
        SHLine(x, y, -1, 1, -10, 4, scale);
        SHLine(x, y, -3, 3, -8, 24, scale);
        SHLine(x, y, -5, 5, -5, 4, scale);
        SHLine(x, y, -8+wing, -3+wing, -3, 24, scale);
        SHLine(x, y, 3+wing, 8+wing, -3, 24, scale);
        SHLine(x, y, -11+wing, -3+wing, -1, 4, scale);
        SHLine(x, y, 3+wing, 11+wing, -1, 4, scale);
        SHLine(x, y, -13+wing, -5+wing, 3, 24, scale);
        SHLine(x, y, 5+wing, 13+wing, 3, 24, scale);
        SHLine(x, y, -12+wing, -6+wing, 5, 4, scale);
        SHLine(x, y, 6+wing, 12+wing, 5, 4, scale);
        SHLine(x, y, -2, 2, -7, 7, scale);
        SHLine(x, y, -4, 4, -4, 24, scale);
        SHLine(x, y, -7+wing, -3+wing, -2, c, scale);
        SHLine(x, y, 3+wing, 7+wing, -2, c, scale);
        SHLine(x, y, -9+wing, -3+wing, 0, 15, scale);
        SHLine(x, y, 3+wing, 9+wing, 0, 15, scale);
        SHLine(x, y, -11+wing, -4+wing, 2, c, scale);
        SHLine(x, y, 4+wing, 11+wing, 2, c, scale);
        SHLine(x, y, -12+wing, -6+wing, 4, 13, scale);
        SHLine(x, y, 6+wing, 12+wing, 4, 13, scale);
        SHLine(x, y, -10+wing, -7+wing, 6, bright, scale);
        SHLine(x, y, 7+wing, 10+wing, 6, bright, scale);
        SHLine(x, y, -3, 3, 5, 24, scale);
        SVLine(x, y, 0, -11, 6, 7, scale);
        SVLine(x, y, -8+wing, -2, 5, 13, scale);
        SVLine(x, y, 8+wing, -2, 5, 13, scale);
        SPoint(x, y, -11+wing, 0, 8, scale);
        SPoint(x, y, 11+wing, 0, 8, scale);
        SPoint(x, y, 0, -12, 8, scale);
        SPoint(x, y, 0, -6, 15, scale);
        SPoint(x, y, -4, 8, 18, scale);
        SPoint(x, y, 4, 8, 18, scale)
  ELSE c := 17; bright := 19;
       SHLine(x, y, -2, 2, -11, 28, scale);
       SHLine(x, y, -4, 4, -9, 28, scale);
       SHLine(x, y, -5, 5, -6, 29, scale);
       SHLine(x, y, -7+wing, 7+wing, -3, 28, scale);
       SHLine(x, y, -9+wing, 9+wing, 0, 29, scale);
       SHLine(x, y, -11+wing, 11+wing, 2, 28, scale);
       SHLine(x, y, -12+wing, -5+wing, 4, 29, scale);
       SHLine(x, y, 5+wing, 12+wing, 4, 29, scale);
       SHLine(x, y, -10+wing, -5+wing, 6, 28, scale);
       SHLine(x, y, 5+wing, 10+wing, 6, 28, scale);
       SHLine(x, y, -2, 2, -8, 31, scale);
       SHLine(x, y, -3, 3, -6, 30, scale);
       SHLine(x, y, -5, 5, -3, 29, scale);
       SHLine(x, y, -7+wing, 7+wing, -1, c, scale);
       SHLine(x, y, -9+wing, 9+wing, 1, 18, scale);
       SHLine(x, y, -11+wing, 11+wing, 3, 30, scale);
       SHLine(x, y, -10+wing, -5+wing, 4, bright, scale);
       SHLine(x, y, 5+wing, 10+wing, 4, bright, scale);
       SHLine(x, y, -8+wing, -5+wing, 5, c, scale);
       SHLine(x, y, 5+wing, 8+wing, 5, c, scale);
       SHLine(x, y, -5, 5, 6, c, scale);
       SVLine(x, y, 0, -12, 6, 8, scale);
       SVLine(x, y, -9+wing, -2, 5, 30, scale);
       SVLine(x, y, 9+wing, -2, 5, 30, scale);
       SPoint(x, y, -9+wing, -3, 8, scale);
       SPoint(x, y, 9+wing, -3, 8, scale);
       SPoint(x, y, 0, -13, bright, scale);
       SPoint(x, y, 0, -6, 19, scale);
       SPoint(x, y, -8, 7, 12, scale);
       SPoint(x, y, 8, 7, 12, scale)
  END;
  IF (frame MOD 4) < 2 THEN
    SPoint(x, y, -2, 9, bright, scale);
    SPoint(x, y, 2, 9, bright, scale)
  ELSE
    SPoint(x, y, -2, 10, bright, scale);
    SPoint(x, y, 2, 10, bright, scale)
  END;
  IF shield THEN
    SHLine(x, y, -10, 10, -14, 12, scale);
    SHLine(x, y, -10, 10, 13, 12, scale);
    SVLine(x, y, -13, -10, 9, 12, scale);
    SVLine(x, y, 13, -10, 9, 12, scale)
  END
END ShipBody;

PROCEDURE DrawShip(kind : CARDINAL; x, y : INTEGER; frame : CARDINAL;
                   bank : INTEGER; shield : BOOLEAN);
BEGIN
  ShipBody(kind, x, y, frame, bank, shield, 1)
END DrawShip;

PROCEDURE DrawPlayerPreview(x, y : INTEGER; frame : CARDINAL);
VAR bob : INTEGER;
BEGIN
  bob := VAL(INTEGER, (frame DIV 10) MOD 4);
  IF bob >= 2 THEN bob := 3-bob END;
  DrawIronwing(x, y+bob, frame, 0, FALSE, 2)
END DrawPlayerPreview;

PROCEDURE DrawShipPreview(kind : CARDINAL; x, y : INTEGER; frame : CARDINAL);
VAR bob : INTEGER;
BEGIN
  bob := VAL(INTEGER, (frame DIV 10) MOD 4);
  IF bob >= 2 THEN bob := 3-bob END;
  ShipBody(kind, x, y+bob, frame, 0, FALSE, 2)
END DrawShipPreview;

PROCEDURE DrawMusicTag(x, y : INTEGER; low, lowMid, highMid, high : CARDINAL);
VAR bounce, b0, b1, b2, b3 : INTEGER; energy, c : CARDINAL;
BEGIN
  IF low > 7 THEN low := 7 END;
  IF lowMid > 7 THEN lowMid := 7 END;
  IF highMid > 7 THEN highMid := 7 END;
  IF high > 7 THEN high := 7 END;

  energy := low + lowMid + highMid + high;
  IF energy >= 21 THEN bounce := 2
  ELSIF energy >= 13 THEN bounce := 1
  ELSE bounce := 0
  END;
  IF energy >= 18 THEN c := 12 ELSE c := 5 END;

  (* Big enough to read, small enough to stay out of the damn way. *)
  FrameBuffer.VLine(x+4, y+1-bounce, y+8-bounce, c);
  FrameBuffer.HLine(x+4, x+8, y+1-bounce, c);
  FrameBuffer.VLine(x+8, y+1-bounce, y+6-bounce, c);
  FrameBuffer.FillRect(x+1, y+7-bounce, 4, 3, 19);
  FrameBuffer.FillRect(x+6, y+5-bounce, 4, 3, 19);

  b0 := 1 + VAL(INTEGER, low DIV 2);
  b1 := 1 + VAL(INTEGER, lowMid DIV 2);
  b2 := 1 + VAL(INTEGER, highMid DIV 2);
  b3 := 1 + VAL(INTEGER, high DIV 2);
  FrameBuffer.FillRect(x+13, y+10-b0, 2, b0, 18);
  FrameBuffer.FillRect(x+17, y+10-b1, 2, b1, 19);
  FrameBuffer.FillRect(x+21, y+10-b2, 2, b2, 15);
  FrameBuffer.FillRect(x+25, y+10-b3, 2, b3, 12)
END DrawMusicTag;

PROCEDURE DrawDrone(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 15 + (frame MOD 2);
  FrameBuffer.HLine(x-7, x+7, y+1, 24);
  FrameBuffer.HLine(x-5, x+5, y, 25);
  FrameBuffer.HLine(x-3, x+3, y-1, 26);
  FrameBuffer.FillRect(x-1, y-1, 3, 3, c);
  FrameBuffer.PutPixel(x-8, y, 18); FrameBuffer.PutPixel(x+8, y, 18);
  FrameBuffer.PutPixel(x-6, y+2, 12); FrameBuffer.PutPixel(x+6, y+2, 12);
  FrameBuffer.PutPixel(x, y+3, 19)
END DrawDrone;

PROCEDURE DrawSpear(x, y : INTEGER; frame : CARDINAL);
BEGIN
  FrameBuffer.VLine(x, y-8, y+6, 17);
  FrameBuffer.HLine(x-1, x+1, y+4, 18);
  FrameBuffer.HLine(x-3, x+3, y+2, 24);
  FrameBuffer.HLine(x-5, x+5, y, 25);
  FrameBuffer.HLine(x-7, x+7, y-3, 26);
  FrameBuffer.PutPixel(x, y-9, 8);
  FrameBuffer.PutPixel(x, y+7, 19);
  IF (frame MOD 2) = 0 THEN
    FrameBuffer.PutPixel(x-6, y-1, 8); FrameBuffer.PutPixel(x+6, y-1, 8)
  ELSE
    FrameBuffer.PutPixel(x-5, y-2, 8); FrameBuffer.PutPixel(x+5, y-2, 8)
  END
END DrawSpear;

PROCEDURE DrawBomber(x, y : INTEGER; frame : CARDINAL);
VAR pulse : CARDINAL;
BEGIN
  pulse := 17 + ((frame DIV 4) MOD 3);
  FrameBuffer.FillRect(x-8, y-3, 17, 8, 24);
  FrameBuffer.HLine(x-6, x+6, y-4, 25);
  FrameBuffer.HLine(x-6, x+6, y+4, 26);
  FrameBuffer.FillRect(x-2, y-2, 5, 5, pulse);
  FrameBuffer.PutPixel(x-9, y-2, 14); FrameBuffer.PutPixel(x+9, y-2, 14);
  FrameBuffer.PutPixel(x-10, y, 15); FrameBuffer.PutPixel(x+10, y, 15);
  FrameBuffer.PutPixel(x-5, y+5, 18); FrameBuffer.PutPixel(x+5, y+5, 18)
END DrawBomber;

PROCEDURE DrawSpinner(x, y : INTEGER; frame : CARDINAL);
VAR p : CARDINAL;
BEGIN
  p := frame MOD 4;
  FrameBuffer.FillRect(x-2, y-2, 5, 5, 14);
  FrameBuffer.PutPixel(x, y, 8);
  IF (p = 0) OR (p = 2) THEN
    FrameBuffer.HLine(x-7, x+7, y, 13);
    FrameBuffer.PutPixel(x-7, y-1, 12); FrameBuffer.PutPixel(x+7, y+1, 12)
  ELSE
    FrameBuffer.Line(x-5, y-5, x+5, y+5, 13);
    FrameBuffer.Line(x-5, y+5, x+5, y-5, 13)
  END;
  FrameBuffer.PutPixel(x, y-6, 18); FrameBuffer.PutPixel(x, y+6, 18)
END DrawSpinner;

PROCEDURE DrawHunter(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 12 + ((frame DIV 4) MOD 2);
  FrameBuffer.VLine(x, y-7, y+5, 7);
  FrameBuffer.HLine(x-2, x+2, y-3, 26);
  FrameBuffer.HLine(x-5, x+5, y, 25);
  FrameBuffer.HLine(x-8, x-3, y+2, 24);
  FrameBuffer.HLine(x+3, x+8, y+2, 24);
  FrameBuffer.PutPixel(x-8, y+1, 8); FrameBuffer.PutPixel(x+8, y+1, 8);
  FrameBuffer.FillRect(x-1, y-2, 3, 4, c);
  FrameBuffer.PutPixel(x-3, y+4, 18); FrameBuffer.PutPixel(x+3, y+4, 18)
END DrawHunter;

PROCEDURE DrawBulwark(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 16 + ((frame DIV 5) MOD 3);
  FrameBuffer.FillRect(x-7, y-4, 15, 9, 24);
  FrameBuffer.HLine(x-5, x+5, y-5, 25);
  FrameBuffer.HLine(x-5, x+5, y+5, 26);
  FrameBuffer.FillRect(x-2, y-2, 5, 5, c);
  FrameBuffer.FillRect(x-10, y-2, 3, 5, 14);
  FrameBuffer.FillRect(x+8, y-2, 3, 5, 14);
  FrameBuffer.PutPixel(x-9, y+4, 18); FrameBuffer.PutPixel(x+9, y+4, 18);
  FrameBuffer.PutPixel(x-4, y+6, 17); FrameBuffer.PutPixel(x+4, y+6, 17)
END DrawBulwark;

PROCEDURE DrawSkimmer(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 10 + (frame MOD 3);
  FrameBuffer.VLine(x, y-6, y+5, 7);
  FrameBuffer.HLine(x-2, x+2, y-2, 26);
  FrameBuffer.Line(x-2, y-1, x-9, y+3, 24);
  FrameBuffer.Line(x+2, y-1, x+9, y+3, 24);
  FrameBuffer.HLine(x-8, x-4, y+4, 25);
  FrameBuffer.HLine(x+4, x+8, y+4, 25);
  FrameBuffer.FillRect(x-1, y-3, 3, 3, c);
  FrameBuffer.PutPixel(x-9, y+4, 18); FrameBuffer.PutPixel(x+9, y+4, 18);
  FrameBuffer.PutPixel(x, y+6, 19)
END DrawSkimmer;

PROCEDURE DrawLancer(x, y : INTEGER; frame : CARDINAL);
BEGIN
  FrameBuffer.VLine(x, y-10, y+7, 12);
  FrameBuffer.HLine(x-7, x+7, y-2, 13);
  FrameBuffer.HLine(x-4, x+4, y+1, 11);
  FrameBuffer.Line(x-7, y-2, x-10, y+5, 14);
  FrameBuffer.Line(x+7, y-2, x+10, y+5, 14);
  FrameBuffer.FillRect(x-2, y-4, 5, 6, 8);
  FrameBuffer.PutPixel(x-9, y+5, 19); FrameBuffer.PutPixel(x+9, y+5, 19)
END DrawLancer;

PROCEDURE DrawAegis(x, y : INTEGER; frame : CARDINAL);
BEGIN
  FrameBuffer.FillRect(x-8, y-6, 17, 12, 23);
  FrameBuffer.Rect(x-10, y-8, 21, 16, 10);
  FrameBuffer.HLine(x-5, x+5, y-6, 7);
  FrameBuffer.FillRect(x-3, y-3, 7, 7, 21);
  FrameBuffer.PutPixel(x, y, 8);
  FrameBuffer.VLine(x-11, y-3, y+4, 12);
  FrameBuffer.VLine(x+11, y-3, y+4, 12)
END DrawAegis;

PROCEDURE DrawPhantom(x, y : INTEGER; frame : CARDINAL);
BEGIN
  FrameBuffer.Line(x, y-8, x-10, y+4, 14);
  FrameBuffer.Line(x, y-8, x+10, y+4, 14);
  FrameBuffer.HLine(x-10, x+10, y+4, 15);
  FrameBuffer.HLine(x-5, x+5, y+1, 24);
  FrameBuffer.FillRect(x-2, y-4, 5, 5, 16 + ((frame DIV 4) MOD 3));
  FrameBuffer.PutPixel(x-10, y+5, 8); FrameBuffer.PutPixel(x+10, y+5, 8)
END DrawPhantom;

PROCEDURE DrawHive(x, y : INTEGER; frame : CARDINAL);
BEGIN
  FrameBuffer.FillRect(x-8, y-7, 17, 15, 28);
  FrameBuffer.Rect(x-11, y-9, 23, 19, 30);
  FrameBuffer.HLine(x-9, x+9, y-4, 31);
  FrameBuffer.HLine(x-9, x+9, y+5, 29);
  FrameBuffer.FillRect(x-3, y-3, 7, 7, 18 + ((frame DIV 5) MOD 2));
  FrameBuffer.PutPixel(x, y, 8)
END DrawHive;

PROCEDURE DrawEnemy(kind : CARDINAL; x, y : INTEGER; frame : CARDINAL);
BEGIN
  CASE kind MOD 11 OF
    0 : DrawDrone(x, y, frame)
  | 1 : DrawSpear(x, y, frame)
  | 2 : DrawBomber(x, y, frame)
  | 3 : DrawSpinner(x, y, frame)
  | 4 : DrawHunter(x, y, frame)
  | 5 : DrawBulwark(x, y, frame)
  | 6 : DrawSkimmer(x, y, frame)
  | 7 : DrawLancer(x, y, frame)
  | 8 : DrawAegis(x, y, frame)
  | 9 : DrawPhantom(x, y, frame)
  | 10: DrawHive(x, y, frame)
  END
END DrawEnemy;

PROCEDURE DrawNullWarden(x, y : INTEGER; frame : CARDINAL);
VAR pulse, wing : INTEGER;
BEGIN
  pulse := VAL(INTEGER, (frame DIV 3) MOD 3);
  wing := VAL(INTEGER, (frame DIV 8) MOD 3) - 1;
  FrameBuffer.HLine(x-26-wing, x+26+wing, y-3, 24);
  FrameBuffer.HLine(x-24-wing, x+24+wing, y-5, 25);
  FrameBuffer.HLine(x-19, x+19, y-8, 26);
  FrameBuffer.FillRect(x-14, y-10, 29, 19, 24);
  FrameBuffer.FillRect(x-10, y-7, 21, 13, 25);
  FrameBuffer.FillRect(x-4, y-3, 9, 7, VAL(CARDINAL, 16+pulse));
  FrameBuffer.PutPixel(x, y-1, 8);
  FrameBuffer.FillRect(x-24-wing, y, 8, 6, 14);
  FrameBuffer.FillRect(x+17+wing, y, 8, 6, 14);
  FrameBuffer.HLine(x-12, x-7, y+9, 17);
  FrameBuffer.HLine(x+7, x+12, y+9, 17);
  FrameBuffer.PutPixel(x-25-wing, y+6, 18);
  FrameBuffer.PutPixel(x+25+wing, y+6, 18)
END DrawNullWarden;

PROCEDURE DrawPrismSeraph(x, y : INTEGER; frame : CARDINAL);
VAR pulse : CARDINAL;
BEGIN
  pulse := 10 + ((frame DIV 3) MOD 4);
  FrameBuffer.VLine(x, y-13, y+10, 7);
  FrameBuffer.HLine(x-3, x+3, y-9, 26);
  FrameBuffer.FillRect(x-5, y-7, 11, 15, 24);
  FrameBuffer.FillRect(x-2, y-4, 5, 8, pulse);
  FrameBuffer.Line(x-5, y-4, x-25, y+7, 25);
  FrameBuffer.Line(x+5, y-4, x+25, y+7, 25);
  FrameBuffer.Line(x-7, y, x-22, y+11, 24);
  FrameBuffer.Line(x+7, y, x+22, y+11, 24);
  FrameBuffer.HLine(x-25, x-18, y+8, 14);
  FrameBuffer.HLine(x+18, x+25, y+8, 14);
  FrameBuffer.PutPixel(x-25, y+9, 18); FrameBuffer.PutPixel(x+25, y+9, 18);
  FrameBuffer.PutPixel(x-4, y+10, 17); FrameBuffer.PutPixel(x+4, y+10, 17)
END DrawPrismSeraph;

PROCEDURE DrawIronReaver(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 16 + ((frame DIV 4) MOD 3);
  FrameBuffer.FillRect(x-17, y-9, 35, 19, 24);
  FrameBuffer.FillRect(x-12, y-7, 25, 15, 25);
  FrameBuffer.HLine(x-25, x+25, y-4, 26);
  FrameBuffer.HLine(x-22, x+22, y+6, 24);
  FrameBuffer.FillRect(x-4, y-4, 9, 8, c);
  FrameBuffer.FillRect(x-25, y-1, 8, 7, 14);
  FrameBuffer.FillRect(x+18, y-1, 8, 7, 14);
  FrameBuffer.VLine(x-13, y-12, y-3, 7);
  FrameBuffer.VLine(x+13, y-12, y-3, 7);
  FrameBuffer.PutPixel(x-13, y-13, 8); FrameBuffer.PutPixel(x+13, y-13, 8);
  FrameBuffer.HLine(x-11, x-6, y+10, 17);
  FrameBuffer.HLine(x+6, x+11, y+10, 17)
END DrawIronReaver;

PROCEDURE DrawEclipseCore(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 16 + ((frame DIV 3) MOD 4);
  FrameBuffer.Line(x, y-14, x-16, y, 25);
  FrameBuffer.Line(x-16, y, x, y+14, 25);
  FrameBuffer.Line(x, y+14, x+16, y, 25);
  FrameBuffer.Line(x+16, y, x, y-14, 25);
  FrameBuffer.Line(x, y-11, x-26, y, 24);
  FrameBuffer.Line(x-26, y, x, y+11, 24);
  FrameBuffer.Line(x, y+11, x+26, y, 24);
  FrameBuffer.Line(x+26, y, x, y-11, 24);
  FrameBuffer.FillRect(x-7, y-7, 15, 15, 26);
  FrameBuffer.FillRect(x-4, y-4, 9, 9, c);
  FrameBuffer.FillRect(x-1, y-1, 3, 3, 8);
  FrameBuffer.PutPixel(x-27, y, 18); FrameBuffer.PutPixel(x+27, y, 18);
  FrameBuffer.PutPixel(x, y-15, 12); FrameBuffer.PutPixel(x, y+15, 17)
END DrawEclipseCore;

PROCEDURE DrawMirrorTwins(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 12 + ((frame DIV 6) MOD 3);
  FrameBuffer.Line(x-6, y-9, x-28, y+2, 13);
  FrameBuffer.Line(x+6, y-9, x+28, y+2, 13);
  FrameBuffer.Line(x-28, y+2, x-8, y+10, 14);
  FrameBuffer.Line(x+28, y+2, x+8, y+10, 14);
  FrameBuffer.FillRect(x-25, y-5, 13, 12, 24);
  FrameBuffer.FillRect(x+13, y-5, 13, 12, 24);
  FrameBuffer.FillRect(x-22, y-3, 7, 7, c);
  FrameBuffer.FillRect(x+16, y-3, 7, 7, c);
  FrameBuffer.HLine(x-8, x+8, y+2, 7);
  FrameBuffer.PutPixel(x, y+2, 8)
END DrawMirrorTwins;

PROCEDURE DrawThornMatrix(x, y : INTEGER; frame : CARDINAL);
VAR d : INTEGER;
BEGIN
  FrameBuffer.FillRect(x-19, y-8, 39, 17, 22);
  FrameBuffer.Rect(x-22, y-11, 45, 23, 10);
  FOR d := -2 TO 2 DO
    FrameBuffer.Line(x+d*8, y-9, x+d*8-3, y-15, 20);
    FrameBuffer.Line(x+d*8, y+8, x+d*8+3, y+14, 21)
  END;
  FrameBuffer.FillRect(x-6, y-5, 13, 11, 9);
  FrameBuffer.FillRect(x-3, y-3, 7, 7, 20);
  FrameBuffer.PutPixel(x, y, 8)
END DrawThornMatrix;

PROCEDURE DrawRiftLeviathan(x, y : INTEGER; frame : CARDINAL);
VAR d : INTEGER;
BEGIN
  FrameBuffer.FillRect(x-13, y-11, 27, 21, 23);
  FrameBuffer.HLine(x-28, x+28, y-4, 14);
  FrameBuffer.HLine(x-25, x+25, y+7, 15);
  FrameBuffer.Line(x-28, y-4, x-19, y-13, 12);
  FrameBuffer.Line(x+28, y-4, x+19, y-13, 12);
  FOR d := -1 TO 1 DO
    FrameBuffer.FillRect(x+d*9-2, y-8, 5, 7, 12 + ((frame DIV 5) MOD 2))
  END;
  FrameBuffer.FillRect(x-4, y+1, 9, 7, 16);
  FrameBuffer.PutPixel(x, y+3, 8)
END DrawRiftLeviathan;

PROCEDURE DrawStarDevourer(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 16 + ((frame DIV 3) MOD 4);
  FrameBuffer.Line(x, y-17, x-26, y, 25);
  FrameBuffer.Line(x-26, y, x, y+17, 25);
  FrameBuffer.Line(x, y+17, x+26, y, 25);
  FrameBuffer.Line(x+26, y, x, y-17, 25);
  FrameBuffer.Line(x-30, y-8, x-13, y+13, 14);
  FrameBuffer.Line(x+30, y-8, x+13, y+13, 14);
  FrameBuffer.Rect(x-10, y-10, 21, 21, 19);
  FrameBuffer.FillRect(x-7, y-7, 15, 15, 24);
  FrameBuffer.FillRect(x-4, y-4, 9, 9, c);
  FrameBuffer.PutPixel(x, y, 8)
END DrawStarDevourer;

PROCEDURE DrawBoss(kind : CARDINAL; x, y : INTEGER; frame, health, maxHealth : CARDINAL);
BEGIN
  CASE kind MOD 8 OF
    0 : DrawNullWarden(x, y, frame)
  | 1 : DrawPrismSeraph(x, y, frame)
  | 2 : DrawIronReaver(x, y, frame)
  | 3 : DrawEclipseCore(x, y, frame)
  | 4 : DrawMirrorTwins(x, y, frame)
  | 5 : DrawThornMatrix(x, y, frame)
  | 6 : DrawRiftLeviathan(x, y, frame)
  | 7 : DrawStarDevourer(x, y, frame)
  END
END DrawBoss;

PROCEDURE DrawPlayerShot(x, y : INTEGER; frame, power : CARDINAL);
BEGIN
  IF power >= 2 THEN
    FrameBuffer.VLine(x, y-3, y+2, 12);
    FrameBuffer.PutPixel(x-1, y, 7); FrameBuffer.PutPixel(x+1, y, 7)
  ELSE
    FrameBuffer.VLine(x, y-2, y+1, 10 + (frame MOD 3))
  END
END DrawPlayerShot;

PROCEDURE DrawEnemyShot(x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 16 + (frame MOD 4);
  FrameBuffer.PutPixel(x, y-1, c);
  FrameBuffer.HLine(x-1, x+1, y, c);
  FrameBuffer.PutPixel(x, y+1, 8)
END DrawEnemyShot;

PROCEDURE DrawPowerup(kind : CARDINAL; x, y : INTEGER; frame : CARDINAL);
VAR c : CARDINAL;
BEGIN
  c := 10 + ((frame DIV 3) MOD 4);
  FrameBuffer.Rect(x-5, y-5, 11, 11, c);
  FrameBuffer.HLine(x-3, x+3, y-6, 8);
  FrameBuffer.HLine(x-3, x+3, y+6, 8);
  IF (frame MOD 6) < 3 THEN
    FrameBuffer.PutPixel(x-6, y, 8); FrameBuffer.PutPixel(x+6, y, 8);
    FrameBuffer.PutPixel(x, y-6, 8); FrameBuffer.PutPixel(x, y+6, 8)
  END;
  CASE kind MOD 7 OF
    0 : FrameBuffer.HLine(x-2, x+2, y, 19); FrameBuffer.VLine(x, y-2, y+2, 19)
  | 1 : FrameBuffer.VLine(x-2, y-2, y+2, 12); FrameBuffer.VLine(x+2, y-2, y+2, 12)
  | 2 : FrameBuffer.PutPixel(x, y-2, 15); FrameBuffer.HLine(x-2, x+2, y-1, 15);
        FrameBuffer.HLine(x-3, x+3, y, 15); FrameBuffer.HLine(x-2, x+2, y+1, 15);
        FrameBuffer.PutPixel(x, y+2, 15)
  | 3 : FrameBuffer.HLine(x-2, x+2, y, 16); FrameBuffer.VLine(x, y-2, y+2, 16);
        FrameBuffer.Rect(x-3, y-3, 7, 7, 8)
  | 4 : FrameBuffer.HLine(x-3, x+3, y, 12); FrameBuffer.VLine(x, y-3, y+3, 8)
  | 5 : FrameBuffer.DrawText(x-2, y-3, "$", 19, 1)
  | 6 : FrameBuffer.Rect(x-3, y-3, 7, 7, 15); FrameBuffer.PutPixel(x, y, 8)
  END
END DrawPowerup;

PROCEDURE DrawParticle(x, y : INTEGER; life, kind : CARDINAL);
VAR c : CARDINAL;
BEGIN
  CASE kind MOD 4 OF
    0 : c := 16 + (life MOD 4)
  | 1 : c := 10 + (life MOD 4)
  | 2 : c := 6 + (life MOD 3)
  | 3 : c := 27 + (life MOD 4)
  END;
  IF life > 10 THEN
    FrameBuffer.PutPixel(x, y, c)
  ELSE
    FrameBuffer.PutPixel(x, y, c);
    IF (life MOD 2) = 0 THEN
      FrameBuffer.PutPixel(x-1, y, c); FrameBuffer.PutPixel(x+1, y, c)
    END
  END
END DrawParticle;

PROCEDURE DrawLogo(tick : CARDINAL);
VAR c, glow : CARDINAL; y : INTEGER;
BEGIN
  c := 12 + ((tick DIV 5) MOD 4);
  glow := 19 - ((tick DIV 7) MOD 3);
  y := 24 + VAL(INTEGER, (tick DIV 20) MOD 2);
  FrameBuffer.DrawText(35, y+4, "IONLANCER", 3, 4);
  FrameBuffer.DrawText(33, y+2, "IONLANCER", 14, 4);
  FrameBuffer.DrawText(31, y,   "IONLANCER", c, 4);
  FrameBuffer.DrawText(95, y+33, "RETRO ARCADE STRIKE", glow, 1)
END DrawLogo;

PROCEDURE DrawTitleArt(x, y : INTEGER; frame : CARDINAL);
VAR plume : INTEGER;
BEGIN
  plume := VAL(INTEGER, frame MOD 3);
  FrameBuffer.Line(x-28, y+13, x+24, y-8, 3);
  FrameBuffer.Line(x-29, y+18, x+20, y+6, 2);

  FrameBuffer.HLine(x-18, x+18, y+1, 24);
  FrameBuffer.HLine(x-15, x+15, y-1, 25);
  FrameBuffer.HLine(x-10, x+10, y-3, 26);
  FrameBuffer.HLine(x-3, x+3, y-5, 7);
  FrameBuffer.VLine(x, y-10, y+8, 6);
  FrameBuffer.VLine(x+1, y-10, y+7, 7);
  FrameBuffer.PutPixel(x+1, y-11, 8);
  FrameBuffer.PutPixel(x+1, y-8, 14);
  FrameBuffer.PutPixel(x+1, y-7, 14);
  FrameBuffer.PutPixel(x, y-5, 11);

  FrameBuffer.HLine(x-25, x-9, y+4, 24);
  FrameBuffer.HLine(x+9, x+26, y+4, 24);
  FrameBuffer.HLine(x-20, x-10, y+6, 25);
  FrameBuffer.HLine(x+10, x+21, y+6, 25);
  FrameBuffer.PutPixel(x-25, y+3, 18); FrameBuffer.PutPixel(x+26, y+3, 18);
  FrameBuffer.PutPixel(x-16, y+6, 12); FrameBuffer.PutPixel(x+17, y+6, 12);

  FrameBuffer.HLine(x-8, x-3, y+11, 18);
  FrameBuffer.HLine(x+3, x+8, y+11, 18);
  FrameBuffer.PutPixel(x-5, y+13, 17); FrameBuffer.PutPixel(x+5, y+13, 17);
  IF plume >= 1 THEN FrameBuffer.PutPixel(x-1, y+12, 16); FrameBuffer.PutPixel(x+1, y+12, 16) END;
  IF plume = 2 THEN FrameBuffer.PutPixel(x, y+14, 19) END
END DrawTitleArt;

PROCEDURE DrawPanel(x, y, w, h : INTEGER; bright : BOOLEAN);
VAR accent, inner, outer : CARDINAL;
BEGIN
  IF bright THEN accent := 12; inner := 5; outer := 3
  ELSE accent := 4; inner := 3; outer := 2
  END;
  FrameBuffer.FillRect(x, y, w, h, 1);
  FrameBuffer.Rect(x, y, w, h, outer);
  FrameBuffer.HLine(x+3, x+w-4, y+2, inner);
  FrameBuffer.HLine(x+8, x+w-9, y+2, accent);
  FrameBuffer.PutPixel(x+2, y+h-3, inner);
  FrameBuffer.PutPixel(x+w-3, y+h-3, inner)
END DrawPanel;

PROCEDURE DrawHeart(x, y : INTEGER; filled : BOOLEAN);
VAR c : CARDINAL;
BEGIN
  IF filled THEN c := 16 ELSE c := 4 END;
  FrameBuffer.PutPixel(x-2, y-1, c); FrameBuffer.PutPixel(x+2, y-1, c);
  FrameBuffer.HLine(x-3, x+3, y, c);
  FrameBuffer.HLine(x-2, x+2, y+1, c);
  FrameBuffer.HLine(x-1, x+1, y+2, c);
  FrameBuffer.PutPixel(x, y+3, c)
END DrawHeart;

PROCEDURE KeyWidth(hint : ControlHint) : INTEGER;
BEGIN
  CASE hint OF
    NavigateHint : RETURN 18
  | MoveHint : RETURN 30
  | FastHint : RETURN 30
  | CancelHint : RETURN 24
  | FullscreenHint : IF Input.IsMac() THEN RETURN 42 ELSE RETURN 24 END
  ELSE RETURN 12
  END
END KeyWidth;

PROCEDURE PadWidth(hint : ControlHint) : INTEGER;
BEGIN
  IF (hint = PauseHint) OR (hint = MenuHint) OR (hint = FullscreenHint) OR
     (hint = FastHint) THEN
    RETURN 16
  END;
  RETURN 12
END PadWidth;

PROCEDURE HintWidth(hint : ControlHint; label : ARRAY OF CHAR) : CARDINAL;
VAR iconWidth : INTEGER;
BEGIN
  IF Input.UsingController() THEN iconWidth := PadWidth(hint)
  ELSE iconWidth := KeyWidth(hint)
  END;
  RETURN VAL(CARDINAL, iconWidth + 4) + FrameBuffer.TextWidth(label, 1)
END HintWidth;

PROCEDURE DrawKeycap(x, y : INTEGER; hint : ControlHint);
VAR w : INTEGER;
BEGIN
  w := KeyWidth(hint);
  FrameBuffer.FillRect(x+1, y+2, w, 9, 2);
  FrameBuffer.FillRect(x, y, w, 10, 3);
  FrameBuffer.Rect(x, y, w, 10, 6);
  FrameBuffer.HLine(x+2, x+w-3, y+2, 5);
  CASE hint OF
    NavigateHint :
      FrameBuffer.Line(x+4, y+5, x+7, y+3, 8);
      FrameBuffer.Line(x+4, y+5, x+7, y+7, 8);
      FrameBuffer.HLine(x+5, x+8, y+5, 8);
      FrameBuffer.Line(x+13, y+5, x+10, y+3, 8);
      FrameBuffer.Line(x+13, y+5, x+10, y+7, 8);
      FrameBuffer.HLine(x+9, x+12, y+5, 8)
  | MoveHint : FrameBuffer.DrawText(x+3, y+2, "WASD", 8, 1)
  | ConfirmHint, FireHint : FrameBuffer.DrawText(x+3, y+2, "Z", 8, 1)
  | CancelHint : FrameBuffer.DrawText(x+3, y+2, "ESC", 8, 1)
  | PulseHint : FrameBuffer.DrawText(x+3, y+2, "X", 8, 1)
  | FastHint : FrameBuffer.DrawText(x+3, y+2, "CTRL", 8, 1)
  | PauseHint : FrameBuffer.DrawText(x+3, y+2, "P", 8, 1)
  | MenuHint : FrameBuffer.DrawText(x+3, y+2, "M", 8, 1)
  | FullscreenHint :
      IF Input.IsMac() THEN FrameBuffer.DrawText(x+3, y+2, "CMD+ENT", 8, 1)
      ELSE FrameBuffer.DrawText(x+3, y+2, "F11", 8, 1)
      END
  END
END DrawKeycap;

PROCEDURE DrawFace(x, y, which : INTEGER);
VAR colour : CARDINAL; family : Input.PadFamily;
BEGIN
  family := Input.ControllerFamily();
  colour := 12;
  IF family = Input.XboxPad THEN
    CASE which OF
      0 : colour := 10
    | 1 : colour := 16
    ELSE colour := 12
    END
  ELSIF family = Input.PlayStationPad THEN
    CASE which OF
      0 : colour := 12
    | 1 : colour := 16
    ELSE colour := 15
    END
  ELSIF family = Input.NintendoPad THEN
    CASE which OF
      0 : colour := 12
    | 1 : colour := 16
    ELSE colour := 19
    END
  END;
  FrameBuffer.FillRect(x+2, y+2, 8, 8, 1);
  FrameBuffer.HLine(x+3, x+8, y, 5);
  FrameBuffer.HLine(x+3, x+8, y+10, 3);
  FrameBuffer.VLine(x, y+3, y+7, 5);
  FrameBuffer.VLine(x+11, y+3, y+7, 3);
  FrameBuffer.PutPixel(x+1, y+2, 5); FrameBuffer.PutPixel(x+10, y+2, 5);
  FrameBuffer.PutPixel(x+1, y+8, 3); FrameBuffer.PutPixel(x+10, y+8, 3);
  IF family = Input.PlayStationPad THEN
    CASE which OF
      0 : FrameBuffer.Line(x+4, y+3, x+7, y+7, colour);
          FrameBuffer.Line(x+7, y+3, x+4, y+7, colour)
    | 1 : FrameBuffer.HLine(x+4, x+7, y+3, colour);
          FrameBuffer.HLine(x+4, x+7, y+7, colour);
          FrameBuffer.PutPixel(x+3, y+4, colour); FrameBuffer.PutPixel(x+8, y+4, colour);
          FrameBuffer.PutPixel(x+3, y+6, colour); FrameBuffer.PutPixel(x+8, y+6, colour)
    ELSE FrameBuffer.Rect(x+3, y+3, 6, 5, colour)
    END
  ELSIF family = Input.NintendoPad THEN
    CASE which OF
      0 : FrameBuffer.DrawText(x+3, y+2, "B", colour, 1)
    | 1 : FrameBuffer.DrawText(x+3, y+2, "A", colour, 1)
    ELSE FrameBuffer.DrawText(x+3, y+2, "Y", colour, 1)
    END
  ELSE
    CASE which OF
      0 : FrameBuffer.DrawText(x+3, y+2, "A", colour, 1)
    | 1 : FrameBuffer.DrawText(x+3, y+2, "B", colour, 1)
    ELSE FrameBuffer.DrawText(x+3, y+2, "X", colour, 1)
    END
  END
END DrawFace;

PROCEDURE DrawPadIcon(x, y : INTEGER; hint : ControlHint);
BEGIN
  CASE hint OF
    NavigateHint :
      FrameBuffer.FillRect(x+4, y+1, 4, 9, 3);
      FrameBuffer.FillRect(x+1, y+4, 10, 3, 3);
      FrameBuffer.VLine(x+5, y+2, y+8, 12);
      FrameBuffer.HLine(x+2, x+9, y+5, 12);
      FrameBuffer.PutPixel(x+5, y+5, 8)
  | MoveHint :
      FrameBuffer.Rect(x+1, y+1, 10, 10, 5);
      FrameBuffer.FillRect(x+3, y+3, 6, 6, 3);
      FrameBuffer.FillRect(x+5, y+4, 2, 3, 12)
  | ConfirmHint, FireHint : DrawFace(x, y, 0)
  | CancelHint : DrawFace(x, y, 1)
  | PulseHint : DrawFace(x, y, 2)
  | PauseHint, MenuHint, FullscreenHint, FastHint :
      FrameBuffer.FillRect(x+1, y+2, 15, 9, 2);
      FrameBuffer.FillRect(x, y, 16, 10, 3);
      FrameBuffer.Rect(x, y, 16, 10, 6);
      IF hint = PauseHint THEN
        FrameBuffer.VLine(x+6, y+3, y+7, 12);
        FrameBuffer.VLine(x+9, y+3, y+7, 12)
      ELSIF hint = MenuHint THEN
        FrameBuffer.Line(x+4, y+5, x+7, y+3, 12);
        FrameBuffer.Line(x+4, y+5, x+7, y+7, 12);
        FrameBuffer.HLine(x+7, x+11, y+5, 12)
      ELSIF hint = FastHint THEN
        IF Input.ControllerFamily() = Input.PlayStationPad THEN
          FrameBuffer.DrawText(x+2, y+2, "R1", 19, 1)
        ELSIF Input.ControllerFamily() = Input.NintendoPad THEN
          FrameBuffer.DrawText(x+5, y+2, "R", 19, 1)
        ELSE
          FrameBuffer.DrawText(x+2, y+2, "RB", 19, 1)
        END
      ELSE
        FrameBuffer.DrawText(x+2, y+2, "R3", 12, 1)
      END
  END
END DrawPadIcon;

PROCEDURE DrawHint(x, y : INTEGER; hint : ControlHint;
                   label : ARRAY OF CHAR; colour : CARDINAL);
VAR iconWidth : INTEGER;
BEGIN
  IF Input.UsingController() THEN
    DrawPadIcon(x, y, hint);
    iconWidth := PadWidth(hint)
  ELSE
    DrawKeycap(x, y, hint);
    iconWidth := KeyWidth(hint)
  END;
  FrameBuffer.DrawText(x+iconWidth+4, y+2, label, colour, 1)
END DrawHint;

PROCEDURE CenterHint(x, w, y : INTEGER; hint : ControlHint;
                     label : ARRAY OF CHAR; colour : CARDINAL);
VAR width, xx : INTEGER;
BEGIN
  width := VAL(INTEGER, HintWidth(hint, label));
  xx := x + (w-width) DIV 2;
  IF xx < x THEN xx := x END;
  DrawHint(xx, y, hint, label, colour)
END CenterHint;

END Visuals.
