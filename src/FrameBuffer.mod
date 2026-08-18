IMPLEMENTATION MODULE FrameBuffer;

FROM SYSTEM IMPORT ADDRESS, ADR, CARDINAL8, CARDINAL32;

CONST
  PixelCount = Width * Height;

VAR
  pixels : ARRAY [0..PixelCount-1] OF CARDINAL8;
  rgba   : ARRAY [0..PixelCount-1] OF CARDINAL32;
  palR, palG, palB : ARRAY [0..255] OF CARDINAL8;
  palARGB : ARRAY [0..255] OF CARDINAL32;
  pow2 : ARRAY [0..23] OF CARDINAL;
  initI : CARDINAL;

PROCEDURE ClampByte(v : INTEGER) : CARDINAL8;
BEGIN
  IF v < 0 THEN RETURN 0 END;
  IF v > 255 THEN RETURN 255 END;
  RETURN VAL(CARDINAL8, v)
END ClampByte;

PROCEDURE SetPalette(index, r, g, b : CARDINAL);
VAR rr, gg, bb : CARDINAL8;
BEGIN
  IF index > 255 THEN RETURN END;
  rr := ClampByte(VAL(INTEGER, r));
  gg := ClampByte(VAL(INTEGER, g));
  bb := ClampByte(VAL(INTEGER, b));
  palR[index] := rr; palG[index] := gg; palB[index] := bb;
  palARGB[index] := VAL(CARDINAL32, 4278190080) + VAL(CARDINAL32, rr) * 65536 +
                    VAL(CARDINAL32, gg) * 256 + VAL(CARDINAL32, bb)
END SetPalette;

PROCEDURE PaletteRGB(index : CARDINAL; VAR r, g, b : CARDINAL);
BEGIN
  IF index > 255 THEN index := 0 END;
  r := VAL(CARDINAL, palR[index]);
  g := VAL(CARDINAL, palG[index]);
  b := VAL(CARDINAL, palB[index])
END PaletteRGB;

PROCEDURE Clear(colour : CARDINAL);
VAR i : CARDINAL; c : CARDINAL8;
BEGIN
  c := ClampByte(VAL(INTEGER, colour));
  FOR i := 0 TO PixelCount-1 DO pixels[i] := c END
END Clear;

PROCEDURE PutPixel(x, y : INTEGER; colour : CARDINAL);
BEGIN
  IF (x >= 0) AND (x < Width) AND (y >= 0) AND (y < Height) THEN
    pixels[VAL(CARDINAL, y * Width + x)] := ClampByte(VAL(INTEGER, colour))
  END
END PutPixel;

PROCEDURE GetPixel(x, y : INTEGER) : CARDINAL;
BEGIN
  IF (x < 0) OR (x >= Width) OR (y < 0) OR (y >= Height) THEN RETURN 0 END;
  RETURN VAL(CARDINAL, pixels[VAL(CARDINAL, y * Width + x)])
END GetPixel;

PROCEDURE HLine(x1, x2, y : INTEGER; colour : CARDINAL);
VAR x, a, b : INTEGER;
BEGIN
  IF (y < 0) OR (y >= Height) THEN RETURN END;
  a := x1; b := x2;
  IF a > b THEN x := a; a := b; b := x END;
  IF a < 0 THEN a := 0 END;
  IF b >= Width THEN b := Width-1 END;
  FOR x := a TO b DO PutPixel(x, y, colour) END
END HLine;

PROCEDURE VLine(x, y1, y2 : INTEGER; colour : CARDINAL);
VAR y, a, b : INTEGER;
BEGIN
  IF (x < 0) OR (x >= Width) THEN RETURN END;
  a := y1; b := y2;
  IF a > b THEN y := a; a := b; b := y END;
  IF a < 0 THEN a := 0 END;
  IF b >= Height THEN b := Height-1 END;
  FOR y := a TO b DO PutPixel(x, y, colour) END
END VLine;

PROCEDURE FillRect(x, y, w, h : INTEGER; colour : CARDINAL);
VAR yy : INTEGER;
BEGIN
  IF (w <= 0) OR (h <= 0) THEN RETURN END;
  FOR yy := y TO y+h-1 DO HLine(x, x+w-1, yy, colour) END
END FillRect;

PROCEDURE Rect(x, y, w, h : INTEGER; colour : CARDINAL);
BEGIN
  IF (w <= 0) OR (h <= 0) THEN RETURN END;
  HLine(x, x+w-1, y, colour);
  HLine(x, x+w-1, y+h-1, colour);
  VLine(x, y, y+h-1, colour);
  VLine(x+w-1, y, y+h-1, colour)
END Rect;

PROCEDURE Line(x0, y0, x1, y1 : INTEGER; colour : CARDINAL);
VAR dx, sx, dy, sy, err, e2 : INTEGER;
BEGIN
  dx := x1 - x0; IF dx < 0 THEN dx := -dx END;
  IF x0 < x1 THEN sx := 1 ELSE sx := -1 END;
  dy := y1 - y0; IF dy > 0 THEN dy := -dy END;
  IF y0 < y1 THEN sy := 1 ELSE sy := -1 END;
  err := dx + dy;
  LOOP
    PutPixel(x0, y0, colour);
    IF (x0 = x1) AND (y0 = y1) THEN EXIT END;
    e2 := err * 2;
    IF e2 >= dy THEN err := err + dy; x0 := x0 + sx END;
    IF e2 <= dx THEN err := err + dx; y0 := y0 + sy END
  END
END Line;

PROCEDURE Glyph(c : CHAR) : CARDINAL;
BEGIN
  CASE c OF
    | '0' : RETURN 15379118
    | '1' : RETURN 14959812
    | '2' : RETURN 15262254
    | '3' : RETURN 14820910
    | '4' : RETURN 2240170
    | '5' : RETURN 14823054
    | '6' : RETURN 15380102
    | '7' : RETURN 4473902
    | '8' : RETURN 15380142
    | '9' : RETURN 12725934
    | 'A' : RETURN 10090902
    | 'B' : RETURN 15310494
    | 'C' : RETURN 7899271
    | 'D' : RETURN 15309214
    | 'E' : RETURN 16289423
    | 'F' : RETURN 8949391
    | 'G' : RETURN 7969671
    | 'H' : RETURN 10067865
    | 'I' : RETURN 14959694
    | 'J' : RETURN 6918419
    | 'K' : RETURN 10071209
    | 'L' : RETURN 16287880
    | 'M' : RETURN 10067961
    | 'N' : RETURN 10206681
    | 'O' : RETURN 6920598
    | 'P' : RETURN 8972702
    | 'Q' : RETURN 8100246
    | 'R' : RETURN 10152350
    | 'S' : RETURN 14751367
    | 'T' : RETURN 4473935
    | 'U' : RETURN 6920601
    | 'V' : RETURN 6723993
    | 'W' : RETURN 10484121
    | 'X' : RETURN 10053273
    | 'Y' : RETURN 4474521
    | 'Z' : RETURN 16269855
    | '!' : RETURN 4211780
    | '?' : RETURN 4211230
    | '-' : RETURN 3584
    | '+' : RETURN 20032
    | '.' : RETURN 4194304
    | ':' : RETURN 262208
    | '/' : RETURN 8667681
    | '(' : RETURN 2376770
    | ')' : RETURN 4334116
    | '=' : RETURN 57568
    | '*' : RETURN 42144
    | ' ' : RETURN 0
  ELSE
    RETURN 0
  END
END Glyph;

PROCEDURE DrawChar(x, y : INTEGER; c : CHAR; colour : CARDINAL; scale : CARDINAL);
VAR bits, row, col, bit, s : CARDINAL; px, py : INTEGER;
BEGIN
  IF scale = 0 THEN scale := 1 END;
  bits := Glyph(c);
  FOR row := 0 TO 5 DO
    FOR col := 0 TO 3 DO
      bit := row*4 + (3-col);
      IF ((bits DIV pow2[bit]) MOD 2) # 0 THEN
        px := x + VAL(INTEGER, col*scale);
        py := y + VAL(INTEGER, row*scale);
        FOR s := 0 TO scale-1 DO
          HLine(px, px+VAL(INTEGER, scale)-1, py+VAL(INTEGER, s), colour)
        END
      END
    END
  END
END DrawChar;

PROCEDURE DrawText(x, y : INTEGER; text : ARRAY OF CHAR;
                   colour, scale : CARDINAL);
VAR i : CARDINAL; xx : INTEGER;
BEGIN
  IF scale = 0 THEN scale := 1 END;
  xx := x;
  i := 0;
  WHILE i <= HIGH(text) DO
    IF ORD(text[i]) = 0 THEN RETURN END;
    DrawChar(xx, y, text[i], colour, scale);
    xx := xx + VAL(INTEGER, 5*scale);
    INC(i)
  END
END DrawText;

PROCEDURE TextWidth(text : ARRAY OF CHAR; scale : CARDINAL) : CARDINAL;
VAR i, n : CARDINAL;
BEGIN
  IF scale = 0 THEN scale := 1 END;
  i := 0; n := 0;
  WHILE i <= HIGH(text) DO
    IF ORD(text[i]) = 0 THEN RETURN n*5*scale END;
    INC(n); INC(i)
  END;
  RETURN n*5*scale
END TextWidth;

PROCEDURE Convert;
VAR i : CARDINAL;
BEGIN
  FOR i := 0 TO PixelCount-1 DO
    rgba[i] := palARGB[VAL(CARDINAL, pixels[i])]
  END
END Convert;

PROCEDURE RGBAAddress() : ADDRESS;
BEGIN
  RETURN ADR(rgba)
END RGBAAddress;

PROCEDURE RGBAPitch() : INTEGER;
BEGIN
  RETURN Width * 4
END RGBAPitch;

PROCEDURE InitPalette;
BEGIN
  SetPalette(0,   4,   4,  12);
  SetPalette(1,   8,  10,  28);
  SetPalette(2,  18,  20,  52);
  SetPalette(3,  35,  38,  82);
  SetPalette(4,  64,  65, 110);
  SetPalette(5,  94,  96, 145);
  SetPalette(6, 140, 145, 190);
  SetPalette(7, 220, 225, 238);
  SetPalette(8, 255, 255, 255);
  SetPalette(9,  46, 204, 113);
  SetPalette(10, 98, 255, 180);
  SetPalette(11, 20, 145, 210);
  SetPalette(12, 65, 210, 255);
  SetPalette(13, 90, 115, 255);
  SetPalette(14, 162, 96, 255);
  SetPalette(15, 232, 110, 255);
  SetPalette(16, 255, 64, 104);
  SetPalette(17, 255, 105, 70);
  SetPalette(18, 255, 165, 60);
  SetPalette(19, 255, 225, 90);
  SetPalette(20, 180, 255, 100);
  SetPalette(21, 80, 220, 125);
  SetPalette(22, 40, 150, 125);
  SetPalette(23, 38, 92, 110);
  SetPalette(24, 90, 55, 90);
  SetPalette(25, 130, 68, 105);
  SetPalette(26, 185, 85, 115);
  SetPalette(27, 245, 130, 135);
  SetPalette(28, 88, 48, 34);
  SetPalette(29, 150, 78, 45);
  SetPalette(30, 220, 130, 55);
  SetPalette(31, 255, 205, 95)
END InitPalette;

BEGIN
  pow2[0] := 1;
  FOR initI := 1 TO 23 DO pow2[initI] := pow2[initI-1] * 2 END;
  InitPalette;
  Clear(0)
END FrameBuffer.
