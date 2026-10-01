MODULE NoThemeProbe;
IMPORT Audio;
VAR track, i, j : CARDINAL; seen : ARRAY [0..Audio.TrackCount-1] OF BOOLEAN;
BEGIN
  (* Run from a directory without assets: fallback must preserve the shuffle. *)
  IF NOT Audio.Init() THEN HALT(2) END;
  Audio.StartTrack(Audio.ThemeSong);
  IF Audio.CurrentTrack() # 0 THEN HALT(3) END;
  FOR i := 0 TO Audio.TrackCount-1 DO seen[i] := FALSE END;
  seen[0] := TRUE;
  FOR i := 1 TO 80 DO
    Audio.ShuffleTrack; track := Audio.CurrentTrack();
    IF track = Audio.ThemeSong THEN HALT(4) END;
    IF seen[track] THEN
      FOR j := 0 TO Audio.TrackCount-1 DO
        IF (j # Audio.ThemeSong) AND NOT seen[j] THEN HALT(5) END
      END;
      FOR j := 0 TO Audio.TrackCount-1 DO seen[j] := FALSE END
    END;
    seen[track] := TRUE
  END;
  Audio.Shutdown
END NoThemeProbe.
