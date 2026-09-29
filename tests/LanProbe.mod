MODULE LanProbe;

IMPORT Arena, FrameBuffer, SDL2, ProbeEnv;

VAR guest : BOOLEAN;

PROCEDURE Run(coop, shouldConnect : BOOLEAN; stage : CARDINAL);
VAR tick : CARDINAL; x, y : INTEGER; found : BOOLEAN;
BEGIN
  IF guest THEN
    IF NOT Arena.Start(coop, FALSE, 127, 0, 0, 1, 1, 0) THEN HALT(2) END
  ELSE
    IF NOT Arena.Start(coop, TRUE, 127, 0, 0, 1, 2, 0) THEN HALT(2) END
  END;

  FOR tick := 1 TO 100 DO
    Arena.Update;
    SDL2.SDL_Delay(16)
  END;
  IF Arena.Connected() # shouldConnect THEN HALT(10+stage) END;

  FrameBuffer.Clear(0);
  Arena.Draw;
  IF guest AND shouldConnect THEN
    IF (stage = 1) AND (FrameBuffer.GetPixel(299, 6) # 4) THEN HALT(21) END;
    IF (stage = 2) AND (FrameBuffer.GetPixel(299, 6) # 16) THEN HALT(22) END;
    IF (stage = 2) AND (FrameBuffer.GetPixel(79, 6) # 1) THEN HALT(23) END
  END;
  IF guest AND (stage = 3) THEN
    found := FALSE;
    FOR y := 72 TO 77 DO
      FOR x := 90 TO 230 DO
        IF FrameBuffer.GetPixel(x, y) = 16 THEN found := TRUE END
      END
    END;
    IF NOT found THEN HALT(24) END
  END;
  FOR tick := 101 TO 160 DO
    Arena.Update;
    SDL2.SDL_Delay(16)
  END;
  Arena.Close
END Run;

BEGIN
  guest := ProbeEnv.ion_probe_guest() # 0;
  IF guest THEN SDL2.SDL_Delay(100) END;
  Run(TRUE, TRUE, 1);
  Run(FALSE, TRUE, 2);
  IF guest THEN Run(FALSE, FALSE, 3)
  ELSE Run(TRUE, FALSE, 3) END
END LanProbe.
