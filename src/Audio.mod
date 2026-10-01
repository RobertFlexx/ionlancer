IMPLEMENTATION MODULE Audio;

FROM SYSTEM IMPORT ADR, CARDINAL8, CARDINAL32, INTEGER16;
IMPORT SDL2, CStdio;

CONST
  SampleRate = 44100;
  BlockSamples = 1024;
  QueueTarget = 4096;
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
  MusicFadeSamples = 11025;

TYPE
  Voice = RECORD
    active   : BOOLEAN;
    effect   : Effect;
    channel  : Channel;
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
  volumes, gains : ARRAY Channel OF CARDINAL;
  initChannel : Channel;
  playlist : ARRAY [0..TrackCount-1] OF CARDINAL;
  playlistSize, playlistPos, playlistCycle : CARDINAL;
  musicStep, musicPos, musicPhrase, leadPhase, bassPhase, arpPhase, padPhase, drumPhase : CARDINAL;
  noiseState : CARDINAL;
  leadPattern, bassPattern, arpPattern, padPattern : ARRAY [0..PatternLen-1] OF CARDINAL;
  sampleData : ARRAY [0..MaxCustomSamples-1] OF ARRAY [0..MaxCustomBytes-1] OF CARDINAL8;
  sampleLength : ARRAY [0..MaxCustomSamples-1] OF CARDINAL;
  sampleActive : ARRAY [0..MaxSampleVoices-1] OF BOOLEAN;
  sampleSlot, samplePos, sampleVolume : ARRAY [0..MaxSampleVoices-1] OF CARDINAL;
  musicMode : MusicMode;
  soundtrack : CARDINAL;
  trackStepSamples, cachedStep, cachedPhrase, musicSeed : CARDINAL;
  musicFadeRemaining : CARDINAL;
  cachedLead, cachedBass, cachedArp, cachedPad : CARDINAL;
  cachedLeadStep, cachedBassStep, cachedArpStep, cachedPadStep : CARDINAL;
  patternValid : BOOLEAN;
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
VAR magnitude : INTEGER;
BEGIN
  (* Leave ordinary levels untouched; ease loud drums and overlapping effects
     toward the limit instead of flattening their peaks into distortion. *)
  IF v < 0 THEN magnitude := -v ELSE magnitude := v END;
  IF magnitude > 24000 THEN
    magnitude := magnitude-24000;
    magnitude := 24000 + magnitude*8767 DIV (magnitude+8767);
    IF v < 0 THEN v := -magnitude ELSE v := magnitude END
  END;
  RETURN VAL(INTEGER16, v)
END ClampSample;

PROCEDURE Noise() : INTEGER;
BEGIN
  noiseState := (noiseState * 25173 + 13849) MOD 65536;
  RETURN VAL(INTEGER, noiseState MOD 255) - 127
END Noise;

PROCEDURE ScaleSigned(value, factor, divisor : INTEGER) : INTEGER;
VAR sample : INTEGER;
BEGIN
  sample := value * factor;
  IF sample < 0 THEN
    RETURN -((-sample + divisor - 1) DIV divisor)
  END;
  RETURN sample DIV divisor
END ScaleSigned;

PROCEDURE ScaledNoise(amp, divisor : INTEGER) : INTEGER;
BEGIN
  RETURN ScaleSigned(Noise(), amp, divisor)
END ScaledNoise;

PROCEDURE SquareStep(VAR phase : CARDINAL; step : CARDINAL; amp : INTEGER) : INTEGER;
VAR result : INTEGER;
BEGIN
  IF step = 0 THEN RETURN 0 END;
  IF phase < 32768 THEN result := amp ELSE result := -amp END;
  phase := (phase + step) MOD 65536;
  RETURN result
END SquareStep;

PROCEDURE TriangleStep(VAR phase : CARDINAL; step : CARDINAL; amp : INTEGER) : INTEGER;
VAR p : CARDINAL; value : INTEGER;
BEGIN
  IF step = 0 THEN RETURN 0 END;
  p := phase;
  IF p < 16384 THEN value := VAL(INTEGER, p)
  ELSIF p < 49152 THEN value := 32768 - VAL(INTEGER, p)
  ELSE value := VAL(INTEGER, p) - 65536
  END;
  phase := (phase + step) MOD 65536;
  RETURN ScaleSigned(value, amp, 16384)
END TriangleStep;

PROCEDURE PulseStep(VAR phase : CARDINAL; step : CARDINAL; amp : INTEGER) : INTEGER;
VAR value : INTEGER;
BEGIN
  IF step = 0 THEN RETURN 0 END;
  IF phase < 16384 THEN value := amp ELSE value := -(amp DIV 3) END;
  phase := (phase + step) MOD 65536;
  RETURN value
END PulseStep;

PROCEDURE Square(VAR phase : CARDINAL; freq : CARDINAL; amp : INTEGER) : INTEGER;
BEGIN
  RETURN SquareStep(phase, freq*65536 DIV SampleRate, amp)
END Square;

PROCEDURE NoteEnvelope(pos, length : CARDINAL; attack : CARDINAL) : INTEGER;
VAR remaining : CARDINAL;
BEGIN
  IF pos < attack THEN RETURN VAL(INTEGER, pos*100 DIV attack) END;
  remaining := length-pos;
  IF remaining < attack*2 THEN RETURN VAL(INTEGER, remaining*100 DIV (attack*2)) END;
  RETURN 100
END NoteEnvelope;

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
  CASE effect OF
    Laser: voices[slot].channel := WeaponChannel
  | Explosion, Hit, Hurt: voices[slot].channel := ImpactChannel
  | MenuBlip: voices[slot].channel := InterfaceChannel
  ELSE voices[slot].channel := AlertChannel
  END;
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
      value := ScaledNoise(amp, 127);
      IF (v.age MOD 320) < 160 THEN value := value + Square(v.phase, 55, amp DIV 3) END
  | Hit:
      value := ScaledNoise(amp, 180) + Square(v.phase, 180, amp DIV 2)
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
      value := Square(v.phase, freq, amp) + ScaledNoise(amp, 300)
  | BossPulse:
      freq := 70 + ((v.age DIV 500) MOD 2) * 24;
      value := Square(v.phase, freq, amp)
  | MenuBlip:
      value := Square(v.phase, 760, amp DIV 2 + 8)
  END;

  INC(v.age);
  IF v.age < 64 THEN value := ScaleSigned(value, VAL(INTEGER,v.age),64) END;
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
  RETURN ScaleSigned(VAL(INTEGER, menuTheme[menuThemePos-1]), 55, 100)
END ThemeSample;

PROCEDURE PatternAt(VAR pat : ARRAY OF CARDINAL; idx : CARDINAL) : CARDINAL;
BEGIN
  RETURN pat[idx MOD PatternLen]
END PatternAt;

PROCEDURE SynthMusicSample() : INTEGER;
VAR
  step, pos, phrase : CARDINAL;
  mix, drumAmp, leadAmp : INTEGER;
BEGIN
  step := musicStep; pos := musicPos; phrase := musicPhrase;

  IF (NOT patternValid) OR (step # cachedStep) OR (phrase # cachedPhrase) THEN
    cachedStep := step; cachedPhrase := phrase; patternValid := TRUE;
    CASE phrase OF
      0:
        cachedLead := PatternAt(leadPattern, step);
        cachedBass := PatternAt(bassPattern, step);
        cachedArp := PatternAt(arpPattern, step);
        cachedPad := PatternAt(padPattern, step)
    | 1:
        cachedLead := PatternAt(leadPattern, step + 8);
        cachedBass := PatternAt(bassPattern, step + 8);
        cachedArp := PatternAt(arpPattern, step + 4);
        cachedPad := PatternAt(padPattern, step + 8)
    | 2:
        cachedLead := PatternAt(leadPattern, step + 16);
        cachedBass := PatternAt(bassPattern, step + 16);
        cachedArp := PatternAt(arpPattern, step + 8);
        cachedPad := PatternAt(padPattern, step + 16)
    ELSE
        cachedLead := PatternAt(leadPattern, step + 24);
        cachedBass := PatternAt(bassPattern, step + 24);
        cachedArp := PatternAt(arpPattern, step + 12);
        cachedPad := PatternAt(padPattern, step + 24)
    END;
    cachedLeadStep := cachedLead*65536 DIV SampleRate;
    cachedBassStep := cachedBass*65536 DIV SampleRate;
    cachedArpStep := cachedArp*65536 DIV SampleRate;
    cachedPadStep := cachedPad*65536 DIV SampleRate
  END;

  mix := ScaleSigned(TriangleStep(bassPhase, cachedBassStep,
                       13 + VAL(INTEGER, intensity)), NoteEnvelope(pos, trackStepSamples, 96), 100);
  mix := mix + TriangleStep(padPhase, cachedPadStep, 3 + VAL(INTEGER, intensity DIV 2));

  IF intensity >= 1 THEN
    leadAmp := 7 + VAL(INTEGER, intensity);
    IF pos > trackStepSamples*3 DIV 4 THEN leadAmp := leadAmp DIV 3 END;
    mix := mix + ScaleSigned(PulseStep(leadPhase, cachedLeadStep, leadAmp),
                             NoteEnvelope(pos, trackStepSamples, 64), 100)
  END;
  IF intensity >= 2 THEN
    mix := mix + ScaleSigned(SquareStep(arpPhase, cachedArpStep,
                               3 + VAL(INTEGER, intensity DIV 2)),
                             NoteEnvelope(pos, trackStepSamples, 48), 100)
  END;

  IF ((step MOD 8) = 0) AND (pos < 980) THEN
    drumAmp := VAL(INTEGER, (980-pos) * (10 + intensity*2) DIV 980);
    mix := mix + Square(drumPhase, 42 + VAL(CARDINAL, (980-pos) DIV 28), drumAmp * 2);
    mix := mix + ScaledNoise(drumAmp, 12)
  END;
  IF ((step MOD 8) = 4) AND (pos < 680) THEN
    drumAmp := VAL(INTEGER, (680-pos) * (6 + intensity) DIV 680);
    mix := mix + ScaledNoise(drumAmp, 3)
  END;
  IF (((step MOD 8) = 6) OR
      ((soundtrack = 1) AND ((step MOD 8) = 2))) AND (pos < 320) THEN
    drumAmp := VAL(INTEGER, (320-pos) * (4 + intensity) DIV 320);
    mix := mix + ScaledNoise(drumAmp, 5)
  END;

  INC(musicPos);
  IF musicPos >= trackStepSamples THEN
    musicPos := 0; INC(musicStep);
    IF musicStep >= PatternLen THEN
      musicStep := 0; musicPhrase := (musicPhrase+1) MOD 4
    END
  END;
  RETURN mix * 125
END SynthMusicSample;

PROCEDURE MusicSample() : INTEGER;
VAR value : INTEGER;
BEGIN
  IF NOT musicEnabled THEN RETURN 0 END;
  CASE musicMode OF
    Silent: value := 0
  | SynthTrack: value := SynthMusicSample()
  | ThemeTrack: value := ThemeSample()
  END;
  IF musicFadeRemaining > 0 THEN
    value := ScaleSigned(value,
              VAL(INTEGER, MusicFadeSamples-musicFadeRemaining),
              MusicFadeSamples);
    DEC(musicFadeRemaining)
  END;
  RETURN value
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
        mix := mix + ScaleSigned((VAL(INTEGER, sampleData[slot][pos]) - 128) *
                                 VAL(INTEGER, sampleVolume[i]), 96, 100);
        INC(samplePos[i])
      END
    END
  END;
  RETURN mix
END CustomSampleMix;

PROCEDURE FillBlock;
VAR i, v : CARDINAL; mix : INTEGER; channel : Channel; target : CARDINAL;
BEGIN
  FOR i := 0 TO BlockSamples-1 DO
    FOR channel := MasterChannel TO InterfaceChannel DO
      target := volumes[channel]*256;
      IF gains[channel] < target THEN
        IF target-gains[channel] > 16 THEN INC(gains[channel], 16)
        ELSE gains[channel] := target END
      ELSIF gains[channel] > target THEN
        IF gains[channel]-target > 16 THEN DEC(gains[channel], 16)
        ELSE gains[channel] := target END
      END
    END;
    mix := ScaleSigned(MusicSample(), VAL(INTEGER, gains[MusicChannel]), 25600);
    FOR v := 0 TO MaxVoices-1 DO
      IF voices[v].active THEN
        mix := mix + ScaleSigned(VoiceSample(voices[v]),
                       VAL(INTEGER, gains[voices[v].channel]), 25600)
      END
    END;
    mix := mix + ScaleSigned(CustomSampleMix(), VAL(INTEGER, gains[ImpactChannel]), 25600);
    mix := ScaleSigned(mix, VAL(INTEGER, gains[MasterChannel]), 25600);
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

PROCEDURE SetTrack(track : CARDINAL);
VAR i, note, root : CARDINAL;
    scale : ARRAY [0..7] OF CARDINAL;
    roots : ARRAY [0..3] OF CARDINAL;
BEGIN
  IF track >= TrackCount THEN track := 0 END;
  soundtrack := track;
  CASE track OF
    1 : trackStepSamples := 3308
  | 2 : trackStepSamples := 5513
  | 3 : trackStepSamples := 4410
  | 4 : trackStepSamples := 3675
  | 6 : trackStepSamples := 4257
  | 7 : trackStepSamples := 3445
  | 8 : trackStepSamples := 4725
  ELSE trackStepSamples := 4009
  END;
  patternValid := FALSE;
  IF track = ThemeSong THEN RETURN END;
  InitPatterns;
  IF track # 0 THEN
    CASE track OF
      1 : (* Neon Chase: driving E minor, restless ascending answer. *)
          scale[0] := 330; scale[1] := 392; scale[2] := 440; scale[3] := 494;
          scale[4] := 587; scale[5] := 659; scale[6] := 784; scale[7] := 988;
          roots[0] := 165; roots[1] := 131; roots[2] := 147; roots[3] := 123
    | 2 : (* Aster Bloom: spacious A minor and suspended notes. *)
          scale[0] := 220; scale[1] := 262; scale[2] := 330; scale[3] := 392;
          scale[4] := 440; scale[5] := 523; scale[6] := 659; scale[7] := 784;
          roots[0] := 110; roots[1] := 87; roots[2] := 98; roots[3] := 131
    | 3 : (* Event Horizon: dark C minor, staggered low line. *)
          scale[0] := 262; scale[1] := 311; scale[2] := 392; scale[3] := 466;
          scale[4] := 523; scale[5] := 622; scale[6] := 784; scale[7] := 932;
          roots[0] := 131; roots[1] := 104; roots[2] := 116; roots[3] := 98
    | 6 : (* Solar Wake: D minor, warm rising lead over a rolling bass. *)
          scale[0] := 294; scale[1] := 330; scale[2] := 349; scale[3] := 440;
          scale[4] := 523; scale[5] := 587; scale[6] := 698; scale[7] := 880;
          roots[0] := 147; roots[1] := 116; roots[2] := 131; roots[3] := 110
    | 7 : (* Crystal Circuit: F minor, syncopated glassy arpeggios. *)
          scale[0] := 349; scale[1] := 415; scale[2] := 466; scale[3] := 523;
          scale[4] := 622; scale[5] := 698; scale[6] := 831; scale[7] := 1047;
          roots[0] := 175; roots[1] := 139; roots[2] := 156; roots[3] := 131
    | 8 : (* Starlight Relay: B minor, spacious call and response. *)
          scale[0] := 247; scale[1] := 294; scale[2] := 330; scale[3] := 370;
          scale[4] := 440; scale[5] := 494; scale[6] := 587; scale[7] := 740;
          roots[0] := 123; roots[1] := 98; roots[2] := 147; roots[3] := 110
    ELSE (* Afterburn: bright G major finale. *)
          scale[0] := 392; scale[1] := 440; scale[2] := 494; scale[3] := 587;
          scale[4] := 659; scale[5] := 784; scale[6] := 880; scale[7] := 988;
          roots[0] := 196; roots[1] := 147; roots[2] := 165; roots[3] := 131
    END;
    FOR i := 0 TO PatternLen-1 DO
      root := roots[i DIV 8];
      IF ((track = 2) AND ((i MOD 4) # 0)) OR
         ((track # 2) AND ((i MOD 2) = 1)) THEN
        bassPattern[i] := 0
      ELSE bassPattern[i] := root
      END;
      padPattern[i] := root*2;
      CASE i MOD 4 OF
        0 : arpPattern[i] := root*4
      | 1 : arpPattern[i] := root*5
      | 2 : arpPattern[i] := root*6
      ELSE arpPattern[i] := root*5
      END;
      CASE track OF
        1 : CASE i MOD 8 OF
              0 : note := 0
            | 1 : note := 2
            | 2 : note := 4
            | 3 : note := 0
            | 4 : note := 5
            | 5 : note := 4
            | 6 : note := 3
            ELSE note := 2
            END;
            IF (i MOD 8) = 3 THEN leadPattern[i] := 0
            ELSE leadPattern[i] := scale[(note + i DIV 8) MOD 8] END
      | 2 : CASE i MOD 8 OF
              0 : note := 0
            | 1 : note := 0
            | 2 : note := 2
            | 3 : note := 4
            | 4 : note := 5
            | 5 : note := 4
            | 6 : note := 2
            ELSE note := 1
            END;
            IF ((i MOD 8) = 1) OR ((i MOD 8) = 5) THEN leadPattern[i] := 0
            ELSE leadPattern[i] := scale[(note + i DIV 8) MOD 8] END
      | 3 : CASE i MOD 8 OF
              0 : note := 0
            | 1 : note := 0
            | 2 : note := 3
            | 3 : note := 2
            | 4 : note := 5
            | 5 : note := 4
            | 6 : note := 2
            ELSE note := 0
            END;
            IF (i MOD 8) = 1 THEN leadPattern[i] := 0
            ELSE leadPattern[i] := scale[(note + i DIV 8) MOD 8] END
      | 6 : CASE i MOD 8 OF
              0 : note := 0
            | 1 : note := 2
            | 2 : note := 3
            | 3 : note := 4
            | 4 : note := 5
            | 5 : note := 3
            | 6 : note := 2
            ELSE note := 1
            END;
            IF (i MOD 8) = 7 THEN leadPattern[i] := 0
            ELSE leadPattern[i] := scale[(note + i DIV 16) MOD 8] END
      | 7 : CASE i MOD 8 OF
              0 : note := 5
            | 1 : note := 2
            | 2 : note := 4
            | 3 : note := 3
            | 4 : note := 6
            | 5 : note := 4
            | 6 : note := 2
            ELSE note := 0
            END;
            IF (i MOD 8) = 2 THEN leadPattern[i] := 0
            ELSE leadPattern[i] := scale[note] END
      | 8 : CASE i MOD 8 OF
              0 : note := 0
            | 1 : note := 2
            | 2 : note := 4
            | 3 : note := 5
            | 4 : note := 6
            | 5 : note := 5
            | 6 : note := 3
            ELSE note := 1
            END;
            IF ((i MOD 8) = 1) OR ((i MOD 8) = 6) THEN leadPattern[i] := 0
            ELSE leadPattern[i] := scale[note] END
      ELSE CASE i MOD 8 OF
             0 : note := 0
           | 1 : note := 2
           | 2 : note := 4
           | 3 : note := 5
           | 4 : note := 7
           | 5 : note := 6
           | 6 : note := 4
           ELSE note := 2
           END;
           IF (i MOD 8) = 7 THEN leadPattern[i] := 0
           ELSE leadPattern[i] := scale[(note + i DIV 8) MOD 8] END
      END
    END
  END;
  musicStep := 0; musicPos := 0; musicPhrase := 0;
  leadPhase := 0; bassPhase := 0; arpPhase := 0; padPhase := 0; drumPhase := 0;
  IF available AND (musicMode = SynthTrack) THEN SDL2.SDL_ClearQueuedAudio(device) END
END SetTrack;

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
VAR desired, obtained : SDL2.SDL_AudioSpec; i : CARDINAL; channel : Channel;
BEGIN
  available := FALSE;
  device := 0;
  FOR i := 0 TO MaxVoices-1 DO voices[i].active := FALSE END;
  FOR i := 0 TO MaxCustomSamples-1 DO sampleLength[i] := 0 END;
  FOR i := 0 TO MaxSampleVoices-1 DO sampleActive[i] := FALSE END;
  musicStep := 0; musicPos := 0; musicPhrase := 0; leadPhase := 0; bassPhase := 0; arpPhase := 0; padPhase := 0; drumPhase := 0;
  menuThemeGenerated := 0;
  noiseState := 31741;
  intensity := 0;
  FOR channel := MasterChannel TO InterfaceChannel DO
    gains[channel] := volumes[channel]*256
  END;
  musicEnabled := TRUE;
  musicMode := SynthTrack;
  soundtrack := 0;
  trackStepSamples := 4009;
  patternValid := FALSE;
  musicSeed := VAL(CARDINAL, SDL2.SDL_GetTicks()) MOD 65521;
  musicFadeRemaining := 0;
  playlistSize := 0; playlistPos := 0; playlistCycle := musicSeed MOD 4;
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
  IF (mode = ThemeTrack) AND NOT menuThemeLoaded THEN
    IF soundtrack = ThemeSong THEN SetTrack(0) END;
    mode := SynthTrack
  END;
  IF musicMode # mode THEN
    IF available THEN SDL2.SDL_ClearQueuedAudio(device) END;
    musicMode := mode;
    IF mode = ThemeTrack THEN
      menuThemePos := 0;
      menuThemeGenerated := 0
    ELSIF mode = SynthTrack THEN
      musicStep := 0; musicPos := 0; musicPhrase := 0; leadPhase := 0; bassPhase := 0; arpPhase := 0; padPhase := 0; drumPhase := 0;
      patternValid := FALSE
    END
  END
END SetMusicMode;

PROCEDURE NextMusicNumber() : CARDINAL;
BEGIN
  musicSeed := (musicSeed*65 + 17) MOD 65521;
  RETURN musicSeed
END NextMusicNumber;

PROCEDURE BuildPlaylist;
VAR i, j, swap : CARDINAL;
BEGIN
  playlistSize := 0; playlistPos := 0;
  FOR i := 0 TO TrackCount-1 DO
    IF (i # ThemeSong) OR (menuThemeLoaded AND ((playlistCycle MOD 4) = 0)) THEN
      playlist[playlistSize] := i; INC(playlistSize)
    END
  END;
  INC(playlistCycle);
  FOR i := playlistSize-1 TO 1 BY -1 DO
    j := NextMusicNumber() MOD (i+1);
    swap := playlist[i]; playlist[i] := playlist[j]; playlist[j] := swap
  END;
  IF playlist[0] = soundtrack THEN
    swap := playlist[0]; playlist[0] := playlist[1]; playlist[1] := swap
  END
END BuildPlaylist;

PROCEDURE PreviewTrack(choice : CARDINAL);
BEGIN
  IF choice >= TrackCount THEN SetMusicMode(ThemeTrack); RETURN END;
  SetTrack(choice);
  IF choice = ThemeSong THEN SetMusicMode(ThemeTrack)
  ELSE SetMusicMode(SynthTrack) END;
  musicFadeRemaining := MusicFadeSamples
END PreviewTrack;

PROCEDURE ShuffleTrack;
VAR next : CARDINAL;
BEGIN
  IF playlistPos >= playlistSize THEN BuildPlaylist END;
  next := playlist[playlistPos]; INC(playlistPos);
  PreviewTrack(next)
END ShuffleTrack;

PROCEDURE StartTrack(choice : CARDINAL);
VAR i : CARDINAL;
BEGIN
  IF (choice = ThemeSong) AND NOT menuThemeLoaded THEN choice := 0 END;
  BuildPlaylist;
  IF choice >= TrackCount THEN ShuffleTrack; RETURN END;
  (* A chosen opener is consumed from this bag as well. *)
  FOR i := 0 TO playlistSize-1 DO
    IF playlist[i] = choice THEN
      playlist[i] := playlist[0]; playlist[0] := choice;
      playlistPos := 1
    END
  END;
  PreviewTrack(choice)
END StartTrack;

PROCEDURE CurrentTrack() : CARDINAL;
BEGIN RETURN soundtrack END CurrentTrack;

PROCEDURE SetIntensity(level : CARDINAL);
BEGIN
  IF level > 3 THEN level := 3 END;
  intensity := level
END SetIntensity;

PROCEDURE SetVolume(channel : Channel; volume : CARDINAL);
BEGIN
  IF volume > 100 THEN volume := 100 END;
  volumes[channel] := volume
END SetVolume;

PROCEDURE GetVolume(channel : Channel) : CARDINAL;
BEGIN RETURN volumes[channel] END GetVolume;

PROCEDURE SetMasterVolume(volume : CARDINAL);
BEGIN SetVolume(MasterChannel, volume) END SetMasterVolume;

PROCEDURE IsAvailable() : BOOLEAN;
BEGIN
  RETURN available
END IsAvailable;

PROCEDURE ThemeMeter(band : CARDINAL) : CARDINAL;
VAR
  queuedSamples, playedSamples, meterSamplePos, loopLength : CARDINAL;
  frame, index : CARDINAL;
BEGIN
  IF (band > 3) OR (NOT available) OR (NOT musicEnabled) OR
     (musicMode # ThemeTrack) OR (volumes[MasterChannel] = 0) OR
     (volumes[MusicChannel] = 0) OR (NOT menuThemeLoaded) OR
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
  FOR initChannel := MasterChannel TO InterfaceChannel DO
    volumes[initChannel] := 100; gains[initChannel] := 25600
  END;
  volumes[MasterChannel] := 68;
  musicMode := SynthTrack;
  soundtrack := 0;
  trackStepSamples := 4009;
  patternValid := FALSE;
  musicSeed := 371;
  playlistSize := 0; playlistPos := 0; playlistCycle := 0;
  musicFadeRemaining := 0;
  noiseState := 31741;
  menuThemeLength := 0;
  menuThemePos := 0;
  menuThemeGenerated := 0;
  menuThemeLoaded := FALSE;
  menuThemeVisLength := 0;
  menuThemeVisLoaded := FALSE
END Audio.
