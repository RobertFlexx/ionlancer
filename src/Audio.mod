IMPLEMENTATION MODULE Audio;

FROM SYSTEM IMPORT ADR, CARDINAL8, CARDINAL32, INTEGER16;
IMPORT SDL2, CStdio;

CONST
  SampleRate = 44100;
  BlockSamples = 1024;
  QueueTarget = 8192;
  AudioS16LSB = 32784;
  MaxVoices = 10;
  MaxCustomSamples = 8;
  MaxCustomBytes = 32768;
  MaxSampleVoices = 4;
  MaxThemeSamples = 6500000;
  ThemeLoopStart = 44100;
  ThemeVisSamplesPerFrame = 735;
  MaxThemeVisBytes = 40000;
  PatternLen = 32;

TYPE
  Voice = RECORD
    active   : BOOLEAN;
    effect   : Effect;
    age      : CARDINAL;
    duration : CARDINAL;
    phase    : CARDINAL;
    seed     : CARDINAL
  END;

VAR
  device : SDL2.SDL_AudioDeviceID;
  voices : ARRAY [0..MaxVoices-1] OF Voice;
  buffer : ARRAY [0..BlockSamples-1] OF INTEGER16;
  musicEnabled : BOOLEAN;
  available : BOOLEAN;
  intensity : CARDINAL;
  masterVolume : CARDINAL;
  musicClock, leadPhase, bassPhase, arpPhase, padPhase, drumPhase : CARDINAL;
  noiseState : CARDINAL;
  leadPattern, bassPattern, arpPattern, padPattern : ARRAY [0..PatternLen-1] OF CARDINAL;
  sampleData : ARRAY [0..MaxCustomSamples-1] OF ARRAY [0..MaxCustomBytes-1] OF CARDINAL8;
  sampleLength : ARRAY [0..MaxCustomSamples-1] OF CARDINAL;
  sampleActive : ARRAY [0..MaxSampleVoices-1] OF BOOLEAN;
  sampleSlot, samplePos, sampleVolume : ARRAY [0..MaxSampleVoices-1] OF CARDINAL;
  musicMode : MusicMode;
  menuTheme : ARRAY [0..MaxThemeSamples-1] OF INTEGER16;
  menuThemeLength, menuThemePos, menuThemeGenerated : CARDINAL;
  menuThemeLoaded : BOOLEAN;
  menuThemeVis : ARRAY [0..MaxThemeVisBytes-1] OF CARDINAL8;
  menuThemeVisLength : CARDINAL;
  menuThemeVisLoaded : BOOLEAN;

PROCEDURE CopyZ(VAR dst : ARRAY OF CHAR; src : ARRAY OF CHAR);
VAR i : CARDINAL;
BEGIN
  i := 0;
  LOOP
    IF (i >= HIGH(dst)) OR (i > HIGH(src)) THEN EXIT END;
    IF ORD(src[i]) = 0 THEN EXIT END;
    dst[i] := src[i];
    INC(i)
  END;
  dst[i] := CHR(0);
  WHILE i < HIGH(dst) DO INC(i); dst[i] := CHR(0) END
END CopyZ;

PROCEDURE ClampSample(v : INTEGER) : INTEGER16;
BEGIN
  IF v < -32768 THEN RETURN -32768 END;
  IF v > 32767 THEN RETURN 32767 END;
  RETURN VAL(INTEGER16, v)
END ClampSample;

PROCEDURE Noise() : INTEGER;
BEGIN
  noiseState := (noiseState * 25173 + 13849) MOD 65536;
  RETURN VAL(INTEGER, noiseState MOD 255) - 127
END Noise;

PROCEDURE Square(VAR phase : CARDINAL; freq : CARDINAL; amp : INTEGER) : INTEGER;
VAR step : CARDINAL; result : INTEGER;
BEGIN
  IF freq = 0 THEN RETURN 0 END;
  IF phase < 32768 THEN result := amp ELSE result := -amp END;
  step := (freq * 65536) DIV SampleRate;
  phase := (phase + step) MOD 65536;
  RETURN result
END Square;

PROCEDURE DurationFor(effect : Effect) : CARDINAL;
BEGIN
  CASE effect OF
    Laser       : RETURN 4800
  | Explosion   : RETURN 18000
  | Hit         : RETURN 3600
  | Power       : RETURN 11200
  | StartJingle : RETURN 14400
  | Hurt        : RETURN 7600
  | BossPulse   : RETURN 15200
  | MenuBlip    : RETURN 2400
  END
END DurationFor;

PROCEDURE Play(effect : Effect);
VAR i, slot : CARDINAL;
BEGIN
  IF NOT available THEN RETURN END;
  slot := MaxVoices;
  i := 0;
  WHILE (i < MaxVoices) AND (slot = MaxVoices) DO
    IF NOT voices[i].active THEN slot := i END;
    INC(i)
  END;
  IF slot = MaxVoices THEN
    slot := 0;
    FOR i := 1 TO MaxVoices-1 DO
      IF voices[i].age > voices[slot].age THEN slot := i END
    END
  END;
  voices[slot].active := TRUE;
  voices[slot].effect := effect;
  voices[slot].age := 0;
  voices[slot].duration := DurationFor(effect);
  voices[slot].phase := 0;
  voices[slot].seed := noiseState + slot * 97
END Play;

PROCEDURE VoiceSample(VAR v : Voice) : INTEGER;
VAR amp, value : INTEGER; freq, segment : CARDINAL;
BEGIN
  IF NOT v.active THEN RETURN 0 END;
  IF v.age >= v.duration THEN v.active := FALSE; RETURN 0 END;

  amp := VAL(INTEGER, (v.duration - v.age) * 42 DIV v.duration);
  value := 0;

  CASE v.effect OF
    Laser:
      freq := 1300 - (v.age * 980 DIV v.duration);
      value := Square(v.phase, freq, amp)
  | Explosion:
      value := Noise() * amp DIV 127;
      IF (v.age MOD 320) < 160 THEN value := value + Square(v.phase, 55, amp DIV 3) END
  | Hit:
      value := Noise() * amp DIV 180 + Square(v.phase, 180, amp DIV 2)
  | Power:
      segment := (v.age * 4) DIV v.duration;
      CASE segment OF
        0 : freq := 523
      | 1 : freq := 659
      | 2 : freq := 784
      ELSE freq := 1047
      END;
      value := Square(v.phase, freq, amp)
  | StartJingle:
      segment := (v.age * 4) DIV v.duration;
      CASE segment OF
        0 : freq := 262
      | 1 : freq := 392
      | 2 : freq := 523
      ELSE freq := 784
      END;
      value := Square(v.phase, freq, amp DIV 2 + 8)
  | Hurt:
      freq := 220 + ((v.duration - v.age) * 180 DIV v.duration);
      value := Square(v.phase, freq, amp) + Noise() * amp DIV 300
  | BossPulse:
      freq := 70 + ((v.age DIV 500) MOD 2) * 24;
      value := Square(v.phase, freq, amp)
  | MenuBlip:
      value := Square(v.phase, 760, amp DIV 2 + 8)
  END;

  INC(v.age);
  RETURN value * 160
END VoiceSample;

PROCEDURE ThemeSample() : INTEGER;
BEGIN
  IF (NOT menuThemeLoaded) OR (menuThemeLength = 0) THEN RETURN 0 END;
  IF menuThemePos >= menuThemeLength THEN
    IF menuThemeLength > ThemeLoopStart THEN menuThemePos := ThemeLoopStart
    ELSE menuThemePos := 0
    END
  END;
  INC(menuThemePos);
  INC(menuThemeGenerated);
  RETURN VAL(INTEGER, menuTheme[menuThemePos-1]) * 55 DIV 100
END ThemeSample;

PROCEDURE PatternAt(VAR pat : ARRAY OF CARDINAL; idx : CARDINAL) : CARDINAL;
BEGIN
  RETURN pat[idx MOD PatternLen]
END PatternAt;

PROCEDURE SynthMusicSample() : INTEGER;
CONST
  StepSamples = 3675;
VAR
  step, pos, phrase : CARDINAL;
  lf, bf, af, pf : CARDINAL;
  mix, drumAmp : INTEGER;
BEGIN
  step := (musicClock DIV StepSamples) MOD PatternLen;
  pos := musicClock MOD StepSamples;
  phrase := (musicClock DIV (StepSamples * PatternLen)) MOD 4;

  CASE phrase OF
    0:
      lf := PatternAt(leadPattern, step);
      bf := PatternAt(bassPattern, step);
      af := PatternAt(arpPattern, step);
      pf := PatternAt(padPattern, step)
  | 1:
      lf := PatternAt(leadPattern, step + 8);
      bf := PatternAt(bassPattern, step + 8);
      af := PatternAt(arpPattern, step + 4);
      pf := PatternAt(padPattern, step + 8)
  | 2:
      lf := PatternAt(leadPattern, step + 16);
      bf := PatternAt(bassPattern, step + 16);
      af := PatternAt(arpPattern, step + 8);
      pf := PatternAt(padPattern, step + 16)
  ELSE
      lf := PatternAt(leadPattern, step + 24);
      bf := PatternAt(bassPattern, step + 24);
      af := PatternAt(arpPattern, step + 12);
      pf := PatternAt(padPattern, step + 24)
  END;

  mix := Square(bassPhase, bf, 10 + VAL(INTEGER, intensity));
  mix := mix + Square(padPhase, pf, 2 + VAL(INTEGER, intensity DIV 2));

  IF intensity >= 1 THEN
    mix := mix + Square(leadPhase, lf, 6 + VAL(INTEGER, intensity))
  END;
  IF intensity >= 2 THEN
    mix := mix + Square(arpPhase, af, 3 + VAL(INTEGER, intensity DIV 2))
  END;
  IF (intensity >= 3) AND ((step MOD 8) >= 4) THEN
    mix := mix + Square(leadPhase, lf, 2)
  END;

  IF ((step MOD 8) = 0) AND (pos < 980) THEN
    drumAmp := VAL(INTEGER, (980-pos) * (10 + intensity*2) DIV 980);
    mix := mix + Square(drumPhase, 42 + VAL(CARDINAL, (980-pos) DIV 28), drumAmp * 2);
    mix := mix + Noise() * drumAmp DIV 12
  END;
  IF ((step MOD 8) = 4) AND (pos < 680) THEN
    drumAmp := VAL(INTEGER, (680-pos) * (6 + intensity) DIV 680);
    mix := mix + Noise() * drumAmp DIV 3
  END;
  IF ((step MOD 8) = 6) AND (pos < 320) THEN
    drumAmp := VAL(INTEGER, (320-pos) * (4 + intensity) DIV 320);
    mix := mix + Noise() * drumAmp DIV 5
  END;

  INC(musicClock);
  RETURN mix * 125
END SynthMusicSample;

PROCEDURE MusicSample() : INTEGER;
BEGIN
  IF NOT musicEnabled THEN RETURN 0 END;
  CASE musicMode OF
    Silent: RETURN 0
  | SynthTrack: RETURN SynthMusicSample()
  | ThemeTrack: RETURN ThemeSample()
  END
END MusicSample;

PROCEDURE RegisterSample(slot : CARDINAL; data : ARRAY OF CARDINAL8; length : CARDINAL);
VAR i, n : CARDINAL;
BEGIN
  IF slot >= MaxCustomSamples THEN RETURN END;
  n := length;
  IF n > MaxCustomBytes THEN n := MaxCustomBytes END;
  IF n > HIGH(data)+1 THEN n := HIGH(data)+1 END;
  IF n = 0 THEN sampleLength[slot] := 0; RETURN END;
  FOR i := 0 TO n-1 DO sampleData[slot][i] := data[i] END;
  sampleLength[slot] := n
END RegisterSample;

PROCEDURE PlaySample(slot, volume : CARDINAL);
VAR i : CARDINAL;
BEGIN
  IF (slot >= MaxCustomSamples) OR (sampleLength[slot] = 0) THEN RETURN END;
  IF volume > 100 THEN volume := 100 END;
  FOR i := 0 TO MaxSampleVoices-1 DO
    IF NOT sampleActive[i] THEN
      sampleActive[i] := TRUE; sampleSlot[i] := slot; samplePos[i] := 0; sampleVolume[i] := volume;
      RETURN
    END
  END;
  sampleActive[0] := TRUE; sampleSlot[0] := slot; samplePos[0] := 0; sampleVolume[0] := volume
END PlaySample;

PROCEDURE CustomSampleMix() : INTEGER;
VAR i, slot, pos : CARDINAL; mix : INTEGER;
BEGIN
  mix := 0;
  FOR i := 0 TO MaxSampleVoices-1 DO
    IF sampleActive[i] THEN
      slot := sampleSlot[i]; pos := samplePos[i];
      IF pos >= sampleLength[slot] THEN sampleActive[i] := FALSE
      ELSE
        mix := mix + (VAL(INTEGER, sampleData[slot][pos]) - 128) * VAL(INTEGER, sampleVolume[i]) * 96 DIV 100;
        INC(samplePos[i])
      END
    END
  END;
  RETURN mix
END CustomSampleMix;

PROCEDURE FillBlock;
VAR i, v : CARDINAL; mix : INTEGER;
BEGIN
  FOR i := 0 TO BlockSamples-1 DO
    mix := MusicSample();
    FOR v := 0 TO MaxVoices-1 DO
      mix := mix + VoiceSample(voices[v])
    END;
    mix := mix + CustomSampleMix();
    mix := mix * VAL(INTEGER, masterVolume) DIV 100;
    buffer[i] := ClampSample(mix)
  END
END FillBlock;

PROCEDURE InitPatterns;
BEGIN
  leadPattern[0] := 659; leadPattern[1] := 0;   leadPattern[2] := 784; leadPattern[3] := 0;
  leadPattern[4] := 880; leadPattern[5] := 784; leadPattern[6] := 659; leadPattern[7] := 587;
  leadPattern[8] := 523; leadPattern[9] := 0;   leadPattern[10] := 659; leadPattern[11] := 0;
  leadPattern[12] := 784; leadPattern[13] := 659; leadPattern[14] := 523; leadPattern[15] := 494;
  leadPattern[16] := 587; leadPattern[17] := 0;   leadPattern[18] := 698; leadPattern[19] := 0;
  leadPattern[20] := 880; leadPattern[21] := 698; leadPattern[22] := 587; leadPattern[23] := 523;
  leadPattern[24] := 659; leadPattern[25] := 0;   leadPattern[26] := 784; leadPattern[27] := 0;
  leadPattern[28] := 988; leadPattern[29] := 880; leadPattern[30] := 784; leadPattern[31] := 659;

  bassPattern[0] := 165; bassPattern[1] := 0; bassPattern[2] := 165; bassPattern[3] := 0;
  bassPattern[4] := 196; bassPattern[5] := 0; bassPattern[6] := 196; bassPattern[7] := 0;
  bassPattern[8] := 131; bassPattern[9] := 0; bassPattern[10] := 131; bassPattern[11] := 0;
  bassPattern[12] := 196; bassPattern[13] := 0; bassPattern[14] := 196; bassPattern[15] := 0;
  bassPattern[16] := 147; bassPattern[17] := 0; bassPattern[18] := 147; bassPattern[19] := 0;
  bassPattern[20] := 196; bassPattern[21] := 0; bassPattern[22] := 196; bassPattern[23] := 0;
  bassPattern[24] := 165; bassPattern[25] := 0; bassPattern[26] := 165; bassPattern[27] := 0;
  bassPattern[28] := 247; bassPattern[29] := 0; bassPattern[30] := 247; bassPattern[31] := 0;

  arpPattern[0] := 659; arpPattern[1] := 784; arpPattern[2] := 988; arpPattern[3] := 784;
  arpPattern[4] := 698; arpPattern[5] := 880; arpPattern[6] := 1047; arpPattern[7] := 880;
  arpPattern[8] := 523; arpPattern[9] := 659; arpPattern[10] := 784; arpPattern[11] := 659;
  arpPattern[12] := 659; arpPattern[13] := 784; arpPattern[14] := 988; arpPattern[15] := 784;
  arpPattern[16] := 587; arpPattern[17] := 698; arpPattern[18] := 880; arpPattern[19] := 698;
  arpPattern[20] := 659; arpPattern[21] := 784; arpPattern[22] := 988; arpPattern[23] := 784;
  arpPattern[24] := 659; arpPattern[25] := 784; arpPattern[26] := 988; arpPattern[27] := 784;
  arpPattern[28] := 784; arpPattern[29] := 988; arpPattern[30] := 1175; arpPattern[31] := 988;

  padPattern[0] := 330; padPattern[1] := 330; padPattern[2] := 330; padPattern[3] := 330;
  padPattern[4] := 392; padPattern[5] := 392; padPattern[6] := 392; padPattern[7] := 392;
  padPattern[8] := 262; padPattern[9] := 262; padPattern[10] := 262; padPattern[11] := 262;
  padPattern[12] := 392; padPattern[13] := 392; padPattern[14] := 392; padPattern[15] := 392;
  padPattern[16] := 294; padPattern[17] := 294; padPattern[18] := 294; padPattern[19] := 294;
  padPattern[20] := 392; padPattern[21] := 392; padPattern[22] := 392; padPattern[23] := 392;
  padPattern[24] := 330; padPattern[25] := 330; padPattern[26] := 330; padPattern[27] := 330;
  padPattern[28] := 494; padPattern[29] := 494; padPattern[30] := 494; padPattern[31] := 494
END InitPatterns;

PROCEDURE LoadTheme;
VAR
  f : CStdio.FILE;
  path : ARRAY [0..63] OF CHAR;
  mode : ARRAY [0..3] OF CHAR;
  n : CARDINAL32;
  closeStatus : INTEGER;
BEGIN
  menuThemeLoaded := FALSE;
  menuThemeLength := 0;
  menuThemePos := 0;
  CopyZ(path, "assets/ionlancer_theme.s16");
  CopyZ(mode, "rb");
  f := CStdio.fopen(ADR(path), ADR(mode));
  IF f = NIL THEN RETURN END;
  n := CStdio.fread(ADR(menuTheme), 2, MaxThemeSamples, f);
  closeStatus := CStdio.fclose(f);
  IF (closeStatus = 0) AND (n > 0) THEN
    menuThemeLength := VAL(CARDINAL, n);
    menuThemeLoaded := TRUE
  END
END LoadTheme;

PROCEDURE LoadThemeVisualizer;
VAR
  f : CStdio.FILE;
  path : ARRAY [0..63] OF CHAR;
  mode : ARRAY [0..3] OF CHAR;
  n : CARDINAL32;
  closeStatus : INTEGER;
BEGIN
  menuThemeVisLoaded := FALSE;
  menuThemeVisLength := 0;
  CopyZ(path, "assets/ionlancer_theme.vis");
  CopyZ(mode, "rb");
  f := CStdio.fopen(ADR(path), ADR(mode));
  IF f = NIL THEN RETURN END;
  n := CStdio.fread(ADR(menuThemeVis), 1, MaxThemeVisBytes, f);
  closeStatus := CStdio.fclose(f);
  IF (closeStatus = 0) AND (n > 0) THEN
    menuThemeVisLength := VAL(CARDINAL, n);
    menuThemeVisLoaded := TRUE
  END
END LoadThemeVisualizer;

PROCEDURE Init() : BOOLEAN;
VAR desired, obtained : SDL2.SDL_AudioSpec; i : CARDINAL;
BEGIN
  available := FALSE;
  device := 0;
  FOR i := 0 TO MaxVoices-1 DO voices[i].active := FALSE END;
  FOR i := 0 TO MaxCustomSamples-1 DO sampleLength[i] := 0 END;
  FOR i := 0 TO MaxSampleVoices-1 DO sampleActive[i] := FALSE END;
  musicClock := 0; leadPhase := 0; bassPhase := 0; arpPhase := 0; padPhase := 0; drumPhase := 0;
  menuThemeGenerated := 0;
  noiseState := 31741;
  intensity := 0;
  masterVolume := 68;
  musicEnabled := TRUE;
  musicMode := SynthTrack;
  InitPatterns;
  LoadTheme;
  LoadThemeVisualizer;

  desired.freq := SampleRate;
  desired.format := AudioS16LSB;
  desired.channels := 1;
  desired.silence := 0;
  desired.samples := BlockSamples;
  desired.padding := 0;
  desired.size := 0;
  desired.callback := NIL;
  desired.userdata := NIL;

  device := SDL2.SDL_OpenAudioDevice(NIL, 0, desired, obtained, 0);
  IF device = 0 THEN RETURN FALSE END;
  available := TRUE;
  SDL2.SDL_PauseAudioDevice(device, 0);
  Update;
  RETURN TRUE
END Init;

PROCEDURE Shutdown;
BEGIN
  IF available THEN
    SDL2.SDL_ClearQueuedAudio(device);
    SDL2.SDL_CloseAudioDevice(device)
  END;
  available := FALSE
END Shutdown;

PROCEDURE Update;
BEGIN
  IF NOT available THEN RETURN END;
  WHILE SDL2.SDL_GetQueuedAudioSize(device) < QueueTarget DO
    FillBlock;
    IF SDL2.SDL_QueueAudio(device, ADR(buffer), VAL(CARDINAL32, BlockSamples * 2)) # 0 THEN RETURN END
  END
END Update;

PROCEDURE SetMusic(enabled : BOOLEAN);
BEGIN
  musicEnabled := enabled
END SetMusic;

PROCEDURE SetMusicMode(mode : MusicMode);
BEGIN
  IF musicMode # mode THEN
    IF available THEN SDL2.SDL_ClearQueuedAudio(device) END;
    musicMode := mode;
    IF mode = ThemeTrack THEN
      menuThemePos := 0;
      menuThemeGenerated := 0
    ELSIF mode = SynthTrack THEN
      musicClock := 0; leadPhase := 0; bassPhase := 0; arpPhase := 0; padPhase := 0; drumPhase := 0
    END
  END
END SetMusicMode;

PROCEDURE SetIntensity(level : CARDINAL);
BEGIN
  IF level > 3 THEN level := 3 END;
  intensity := level
END SetIntensity;

PROCEDURE SetMasterVolume(volume : CARDINAL);
BEGIN
  IF volume > 100 THEN volume := 100 END;
  masterVolume := volume
END SetMasterVolume;

PROCEDURE IsAvailable() : BOOLEAN;
BEGIN
  RETURN available
END IsAvailable;

PROCEDURE ThemeMeter(band : CARDINAL) : CARDINAL;
VAR
  queuedSamples, playedSamples, meterSamplePos, loopLength : CARDINAL;
  frame, index : CARDINAL;
BEGIN
  IF (band > 3) OR (NOT available) OR (NOT menuThemeLoaded) OR
     (NOT menuThemeVisLoaded) OR (menuThemeLength = 0) THEN RETURN 0 END;

  queuedSamples := VAL(CARDINAL, SDL2.SDL_GetQueuedAudioSize(device)) DIV 2;
  IF menuThemeGenerated > queuedSamples THEN
    playedSamples := menuThemeGenerated - queuedSamples
  ELSE
    playedSamples := 0
  END;

  IF playedSamples < menuThemeLength THEN
    meterSamplePos := playedSamples
  ELSIF menuThemeLength > ThemeLoopStart THEN
    loopLength := menuThemeLength - ThemeLoopStart;
    meterSamplePos := ThemeLoopStart + ((playedSamples - menuThemeLength) MOD loopLength)
  ELSE
    meterSamplePos := 0
  END;

  frame := meterSamplePos DIV ThemeVisSamplesPerFrame;
  index := frame * 4 + band;
  IF index >= menuThemeVisLength THEN RETURN 0 END;
  RETURN VAL(CARDINAL, menuThemeVis[index])
END ThemeMeter;

BEGIN
  available := FALSE;
  device := 0;
  musicEnabled := TRUE;
  intensity := 0;
  masterVolume := 68;
  musicMode := SynthTrack;
  noiseState := 31741;
  menuThemeLength := 0;
  menuThemePos := 0;
  menuThemeGenerated := 0;
  menuThemeLoaded := FALSE;
  menuThemeVisLength := 0;
  menuThemeVisLoaded := FALSE
END Audio.
