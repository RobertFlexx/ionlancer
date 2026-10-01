MODULE LanWire;

IMPORT Arena, SDL2;

VAR tick : CARDINAL;

BEGIN
  IF NOT Arena.Start(FALSE, TRUE, 127, 0, 0, 1, 0, 0) THEN HALT(2) END;
  FOR tick := 1 TO 600 DO
    Arena.Update;
    SDL2.SDL_Delay(16)
  END;
  Arena.Close
END LanWire.
