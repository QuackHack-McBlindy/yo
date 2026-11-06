{
  pkgs,
  helpers
} : let
  inherit (helpers) expandOptionalWords expandListInputVariants;
  sortStr = builtins.sort (a: b: a < b);
in {
  unit = {
    "expandOptionalWords - no optional" = {
      expr     = expandOptionalWords "hello world";
      expected = [ "hello world" ];
    };
    "expandOptionalWords - single optional" = {
      expr     = sortStr (expandOptionalWords "hello [world]");
      expected = sortStr [ "hello" "hello world" ];
    };
    "expandOptionalWords - required group" = {
      expr     = sortStr (expandOptionalWords "hello (a|b)");
      expected = sortStr [ "hello a" "hello b" ];
    };
    "expandOptionalWords - optional alternatives" = {
      expr     = sortStr (expandOptionalWords "hello [a|b]");
      expected = sortStr [ "hello" "hello a" "hello b" ];
    };

    "expandListInputVariants - plain" = {
      expr     = expandListInputVariants "hello";
      expected = [ "hello" ];
    };
    "expandListInputVariants - optional alternatives" = {
      expr     = sortStr (expandListInputVariants "foo [a|b]");
      expected = sortStr [ "foo a" "foo b" ];
    };

  };}
