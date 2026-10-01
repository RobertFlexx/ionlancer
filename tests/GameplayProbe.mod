MODULE GameplayProbe;
IMPORT Game, Input, FrameBuffer, Runtime, Platform;
VAR mode, ship, modifier, n, tick, slot : CARDINAL;

PROCEDURE Key(code : INTEGER);
BEGIN
  IF NOT Platform.Open() THEN HALT(2) END;
  Runtime.ion_test_key(code,1); Input.Poll; Game.Update; Input.ClearPressed;
  Runtime.ion_test_key(code,0); Input.Poll; Game.Update; Input.ClearPressed
END Key;

BEGIN
  slot := 100;
  FOR mode := 0 TO 4 DO
    FOR ship := 0 TO 4 DO
      Input.Init; Game.Init;
      FOR n := 1 TO mode DO Key(79) END;
      FOR n := 1 TO ship DO Key(81) END;
      modifier := (mode*5+ship) MOD 7;
      Key(27); Key(81);
      FOR n := 1 TO modifier DO Key(79) END;
      Key(41); Key(40);
      FOR tick := 1 TO 900 DO
        Runtime.ion_test_key(44,1);
        Runtime.ion_test_key(80,ORD((tick MOD 240) < 60));
        Runtime.ion_test_key(79,ORD((tick MOD 240) >= 120));
        Runtime.ion_test_key(82,ORD((tick MOD 180) < 30));
        Runtime.ion_test_key(81,ORD((tick MOD 180) >= 150));
        Runtime.ion_test_key(27,ORD((tick MOD 180) = 100));
        Input.Poll; Game.Update; Input.ClearPressed;
        IF (tick MOD 300) = 0 THEN
          Game.Draw; FrameBuffer.Convert;
          Runtime.ion_test_frame(FrameBuffer.RGBAAddress(),VAL(INTEGER,slot)); INC(slot)
        END
      END;
      Runtime.ion_test_key(44,0); Runtime.ion_test_key(80,0);
      Runtime.ion_test_key(79,0); Runtime.ion_test_key(82,0);
      Runtime.ion_test_key(81,0); Runtime.ion_test_key(27,0);
      Input.Shutdown
    END
  END;
  Platform.Close
END GameplayProbe.
