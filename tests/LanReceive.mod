MODULE LanReceive;
IMPORT Arena, FrameBuffer, SDL2;
VAR tick : CARDINAL;
BEGIN
  IF NOT Arena.Start(FALSE, FALSE, 127, 0, 0, 1, 0, 0) THEN HALT(2) END;
  FOR tick := 1 TO 160 DO
    Arena.Update;
    IF (tick = 25) AND Arena.Connected() THEN HALT(30) END;
    IF tick = 60 THEN
      IF NOT Arena.Connected() OR NOT Arena.IsPaused() THEN HALT(31) END;
      FrameBuffer.Clear(0); Arena.Draw;
      IF FrameBuffer.GetPixel(299,6) # 16 THEN HALT(32) END
    END;
    IF (tick = 125) OR (tick = 155) THEN
      IF NOT Arena.Connected() OR Arena.IsPaused() THEN HALT(33) END;
      FrameBuffer.Clear(0); Arena.Draw;
      IF FrameBuffer.GetPixel(299,6) # 4 THEN HALT(34) END
    END;
    SDL2.SDL_Delay(16)
  END;
  Arena.Close
END LanReceive.
