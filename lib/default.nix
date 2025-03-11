let
  resolveMorphRecursive =
    history: morphs: x: fn:
    if x.follows == null then
      x
    else
      let
        parent =
          assert morphs ? "${x.follows}" || throw ''Could not follow morph "${x.follows}"'';
          assert
            !(builtins.any (y: y == x.follows) history)
            || throw ''Infinite recursion detected in morph follow to "${x.follows}"'';
          morphs.${x.follows};
      in
      resolveMorphRecursive (history ++ [ x.follows ]) morphs (
        (fn parent x) // { follows = parent.follows; }
      ) fn;
in
{
  resolveMorph = resolveMorphRecursive [ ];
}
