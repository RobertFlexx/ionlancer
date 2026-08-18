IMPLEMENTATION MODULE RNG;

CONST
  Modulus = 2147483647;
  Multiplier = 16807;
  Quotient = 127773;
  Remainder = 2836;

VAR state : INTEGER;

PROCEDURE Seed(value : CARDINAL);
BEGIN
  state := VAL(INTEGER, value MOD 2147483646) + 1
END Seed;

PROCEDURE Next() : CARDINAL;
VAR hi, lo, test : INTEGER;
BEGIN
  hi := state DIV Quotient;
  lo := state MOD Quotient;
  test := Multiplier * lo - Remainder * hi;
  IF test > 0 THEN state := test ELSE state := test + Modulus END;
  RETURN VAL(CARDINAL, state)
END Next;

PROCEDURE Range(limit : CARDINAL) : CARDINAL;
BEGIN
  IF limit = 0 THEN RETURN 0 END;
  RETURN Next() MOD limit
END Range;

PROCEDURE Between(lo, hi : INTEGER) : INTEGER;
VAR span : CARDINAL;
BEGIN
  IF hi <= lo THEN RETURN lo END;
  span := VAL(CARDINAL, hi - lo + 1);
  RETURN lo + VAL(INTEGER, Range(span))
END Between;

BEGIN
  state := 1357911
END RNG.
