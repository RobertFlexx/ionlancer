MODULE QualityProbe;

IMPORT Audio, Settings, Platform, Game, Input, FrameBuffer, Runtime;

VAR i, j, track, previous, themes : CARDINAL;
    seen : ARRAY [0..Audio.TrackCount-1] OF BOOLEAN;
    saved : BOOLEAN; channel : Audio.Channel;

PROCEDURE Capture(slot : INTEGER);
BEGIN
  Game.Draw; FrameBuffer.Convert;
  Runtime.ion_test_frame(FrameBuffer.RGBAAddress(), slot)
END Capture;

PROCEDURE Key(code : INTEGER);
BEGIN
  Runtime.ion_test_key(code, 1); Input.Poll; Game.Update; Input.ClearPressed;
  Runtime.ion_test_key(code, 0); Input.Poll; Game.Update; Input.ClearPressed
END Key;

PROCEDURE Pad(button : INTEGER);
BEGIN
  Runtime.ion_test_pad(button, 1); Input.Poll; Game.Update; Input.ClearPressed;
  Runtime.ion_test_pad(button, 0); Input.Poll; Game.Update; Input.ClearPressed
END Pad;

PROCEDURE Settle;
VAR n : CARDINAL;
BEGIN
  FOR n := 1 TO 12 DO Runtime.ion_test_drain; Audio.Update END
END Settle;

BEGIN
  IF NOT Platform.Open() THEN HALT(2) END;
  Game.Init;
  Capture(0);
  (* Keyboard settings, clamping, display switches, reset, and persistence. *)
  Key(59); Capture(1);
  Key(80); IF Settings.Get(Settings.Master) # 63 THEN HALT(3) END;
  Key(81); Key(80); IF Settings.Get(Settings.Music) # 95 THEN HALT(4) END;
  FOR i := 1 TO 25 DO Key(80) END;
  IF Settings.Get(Settings.Music) # 0 THEN HALT(5) END;
  FOR i := 1 TO 25 DO Key(79) END;
  IF Settings.Get(Settings.Music) # 100 THEN HALT(6) END;
  Key(27); Key(81); Key(79);
  IF Settings.Get(Settings.PixelScale) # 1 THEN HALT(7) END;
  Key(81); Key(79); IF Settings.Get(Settings.ScreenShake) # 0 THEN HALT(8) END;
  Key(81); Key(79); IF Settings.Get(Settings.HitFlashes) # 0 THEN HALT(9) END;
  Capture(2); Key(81); Key(29);
  IF (Settings.Get(Settings.Master) # 68) OR (Settings.Get(Settings.ScreenShake) # 1) THEN HALT(10) END;
  Capture(3); Key(41);
  Settings.Set(Settings.Music, 35); saved := Settings.Save();
  IF NOT saved THEN HALT(11) END;
  Settings.Defaults; Settings.Init;
  IF Settings.Get(Settings.Music) # 35 THEN HALT(12) END;
  Settings.Defaults;
  (* Settings opened during a run return to the paused game. *)
  Key(40); Key(59); Key(41); Capture(4); Key(19);
  FOR i := 1 TO 180 DO Game.Update; Input.ClearPressed END;
  Capture(5); Key(16);
  (* All controller hints and controller settings controls use the same actions. *)
  Pad(7); Pad(2); Capture(6); Pad(14);
  IF Settings.Get(Settings.Master) # 73 THEN HALT(13) END;
  Pad(2); Capture(7); Pad(1);
  IF Game.WantsQuit() THEN HALT(14) END;
  (* Selected openers are consumed; every synth plays before the bag repeats.
     Menu previews must never consume or reset the active playlist. *)
  FOR track := 0 TO Audio.TrackCount-1 DO
    Audio.StartTrack(track);
    IF Audio.CurrentTrack() # track THEN HALT(15) END;
    FOR i := 0 TO Audio.TrackCount-1 DO seen[i] := FALSE END;
    seen[track] := TRUE;
    LOOP
      Audio.PreviewTrack(Audio.ShuffleChoice);
      Audio.ShuffleTrack; i := Audio.CurrentTrack();
      IF seen[i] THEN
        FOR j := 0 TO Audio.TrackCount-1 DO
          IF (j # Audio.ThemeSong) AND NOT seen[j] THEN HALT(16) END
        END;
        EXIT
      END;
      seen[i] := TRUE
    END
  END;
  Audio.StartTrack(Audio.ShuffleChoice); previous := Audio.CurrentTrack(); themes := 0;
  FOR i := 1 TO 400 DO
    Audio.ShuffleTrack; track := Audio.CurrentTrack();
    IF track = previous THEN HALT(17) END;
    IF track = Audio.ThemeSong THEN INC(themes) END;
    previous := track
  END;
  IF (themes < 8) OR (themes > 16) THEN HALT(18) END;
  (* Each bus can mute its own sounds while the other buses remain audible. *)
  Audio.SetMusic(FALSE);
  FOR channel := Audio.MasterChannel TO Audio.InterfaceChannel DO Audio.SetVolume(channel, 100) END;
  Settle;
  FOR i := 0 TO 7 DO
    CASE i OF
      0: channel := Audio.WeaponChannel
    | 1, 2, 5: channel := Audio.ImpactChannel
    | 7: channel := Audio.InterfaceChannel
    ELSE channel := Audio.AlertChannel
    END;
    Audio.SetVolume(channel, 0); Settle;
    Audio.Play(VAL(Audio.Effect,i)); Runtime.ion_test_drain; Audio.Update;
    IF Runtime.ion_test_energy() # 0 THEN HALT(19) END;
    Audio.SetVolume(channel,100); Settle;
    Audio.Play(VAL(Audio.Effect,i)); Runtime.ion_test_drain; Audio.Update;
    IF Runtime.ion_test_energy() = 0 THEN HALT(20) END;
    Settle
  END;
  Audio.SetMusic(TRUE); Audio.SetIntensity(3);
  FOR track := 0 TO Audio.TrackCount-1 DO
    Audio.PreviewTrack(track); Settle;
    Runtime.ion_test_record(VAL(INTEGER,track));
    FOR i := 1 TO 300 DO Runtime.ion_test_drain; Audio.Update END;
    Runtime.ion_test_record(-1)
  END;
  Audio.SetVolume(Audio.MusicChannel,0); Settle;
  IF Runtime.ion_test_energy() # 0 THEN HALT(21) END;
  Audio.Play(Audio.Laser); Runtime.ion_test_drain; Audio.Update;
  IF Runtime.ion_test_energy() = 0 THEN HALT(22) END;
  Audio.SetVolume(Audio.MasterChannel,0); Settle;
  Audio.Play(Audio.Explosion); Runtime.ion_test_drain; Audio.Update;
  IF Runtime.ion_test_energy() # 0 THEN HALT(23) END;
  (* Saved mute must apply before the first queued startup sample. *)
  Settings.Set(Settings.Master,0); Settings.Set(Settings.Music,80);
  Platform.Close; Runtime.ion_test_drain;
  IF NOT Platform.Open() THEN HALT(24) END;
  Audio.Update;
  IF Runtime.ion_test_energy() # 0 THEN HALT(25) END;
  Platform.Close
END QualityProbe.
