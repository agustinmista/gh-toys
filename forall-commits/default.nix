{
  writeShellApplication,
  git,
  gh,
  jq,
}:
writeShellApplication {
  name = "forall-commits";
  runtimeInputs = [
    git
    gh
    jq
  ];
  text = builtins.readFile ./forall-commits.sh;
}
