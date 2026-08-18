MODULE Main;

IMPORT Platform, Game, Input;

CONST
  MaxUpdatesPerFrame = 5;

VAR
  lastTick, nowTick, elapsed, accumulator, updates : CARDINAL;

BEGIN
  IF NOT Platform.Open() THEN HALT(1) END;
  Game.Init;

  lastTick := Platform.Ticks();
  accumulator := 0;

  WHILE NOT Platform.ShouldQuit() DO
    Platform.Poll;
    IF Game.WantsQuit() THEN Platform.RequestQuit END;

    nowTick := Platform.Ticks();
    elapsed := nowTick - lastTick;
    lastTick := nowTick;
    IF elapsed > 250 THEN elapsed := 250 END;

    accumulator := accumulator + elapsed * 60;
    updates := 0;
    WHILE (accumulator >= 1000) AND (updates < MaxUpdatesPerFrame) DO
      Game.Update;
      Input.ClearPressed;
      accumulator := accumulator - 1000;
      INC(updates)
    END;

    (* A resize can stall for a bit. Don't repay that debt with a stupid pile of catch-up ticks. *)
    IF accumulator >= 1000 THEN accumulator := accumulator MOD 1000 END;

    Game.Draw;
    Platform.Present;

    IF elapsed < 2 THEN Platform.Sleep(1) END
  END;

  Platform.Close
END Main.
