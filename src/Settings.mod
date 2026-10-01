IMPLEMENTATION MODULE Settings;

FROM SYSTEM IMPORT ADR, ADDRESS, CARDINAL8;
IMPORT SDL2, CStdio, Audio;

CONST FileBytes = 14;

TYPE PathPointer = POINTER TO ARRAY [0..1023] OF CHAR;

VAR
  values : ARRAY Option OF CARDINAL;
  path : ARRAY [0..1023] OF CHAR;
  pathReady : BOOLEAN;

PROCEDURE Get(option : Option) : CARDINAL;
BEGIN RETURN values[option] END Get;

PROCEDURE Set(option : Option; value : CARDINAL);
BEGIN
  IF option <= Interface THEN
    IF value > 100 THEN value := 100 END;
    Audio.SetVolume(VAL(Audio.Channel, ORD(option)), value)
  ELSE
    IF value > 1 THEN value := 1 END
  END;
  values[option] := value
END Set;

PROCEDURE Defaults;
VAR option : Option;
BEGIN
  FOR option := Master TO Interface DO Set(option, 100) END;
  Set(Master, 68);
  Set(Fullscreen, 0); Set(PixelScale, 0);
  Set(ScreenShake, 1); Set(HitFlashes, 1)
END Defaults;

PROCEDURE Init;
VAR
  directory : PathPointer;
  org : ARRAY [0..9] OF CHAR;
  app : ARRAY [0..9] OF CHAR;
  name : ARRAY [0..12] OF CHAR;
  mode : ARRAY [0..2] OF CHAR;
  data : ARRAY [0..FileBytes] OF CARDINAL8;
  i, j, count : CARDINAL;
  status : INTEGER;
  file : CStdio.FILE;
  valid : BOOLEAN;
  option : Option;
BEGIN
  Defaults; pathReady := FALSE;
  org := 'ionlancer'; app := 'ionlancer'; name := 'settings.bin';
  directory := SDL2.SDL_GetPrefPath(ADR(org), ADR(app));
  IF directory = NIL THEN RETURN END;
  i := 0;
  WHILE (i < HIGH(path)-HIGH(name)) AND (directory^[i] # CHR(0)) DO
    path[i] := directory^[i]; INC(i)
  END;
  valid := directory^[i] = CHR(0);
  SDL2.SDL_free(VAL(ADDRESS, directory));
  IF NOT valid THEN RETURN END;
  j := 0;
  REPEAT path[i] := name[j]; INC(i); INC(j) UNTIL name[j-1] = CHR(0);
  pathReady := TRUE;
  mode := 'rb'; file := CStdio.fopen(ADR(path), ADR(mode));
  IF file = NIL THEN RETURN END;
  count := CStdio.fread(ADR(data), 1, FileBytes+1, file);
  status := CStdio.fclose(file);
  valid := (count = FileBytes) AND (status = 0);
  IF NOT valid THEN RETURN END;
  IF (data[0] # 73) OR (data[1] # 76) OR (data[2] # 83) OR (data[3] # 1) THEN RETURN END;
  FOR option := Master TO HitFlashes DO
    i := ORD(option)+4;
    IF option <= Interface THEN
      IF data[i] > 100 THEN RETURN END
    ELSE
      IF data[i] > 1 THEN RETURN END
    END
  END;
  FOR option := Master TO HitFlashes DO Set(option, VAL(CARDINAL, data[ORD(option)+4])) END
END Init;

PROCEDURE Save() : BOOLEAN;
VAR
  data : ARRAY [0..FileBytes-1] OF CARDINAL8;
  mode : ARRAY [0..2] OF CHAR;
  file : CStdio.FILE;
  count : CARDINAL;
  status : INTEGER;
  option : Option;
BEGIN
  IF NOT pathReady THEN RETURN FALSE END;
  data[0] := 73; data[1] := 76; data[2] := 83; data[3] := 1;
  FOR option := Master TO HitFlashes DO data[ORD(option)+4] := VAL(CARDINAL8, values[option]) END;
  mode := 'wb'; file := CStdio.fopen(ADR(path), ADR(mode));
  IF file = NIL THEN RETURN FALSE END;
  count := CStdio.fwrite(ADR(data), 1, FileBytes, file);
  status := CStdio.fclose(file);
  RETURN (count = FileBytes) AND (status = 0)
END Save;

BEGIN
  pathReady := FALSE
END Settings.
