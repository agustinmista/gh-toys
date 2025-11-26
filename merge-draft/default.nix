{
  writeShellApplication,
  git,
  gh,
  jq,
}:
writeShellApplication {
  name = "merge-draft";
  runtimeInputs = [
    git
    gh
    jq
  ];
  text = builtins.readFile ./merge-draft.sh;
}
