{
  writeShellApplication,
  git,
  gh,
  jq,
}:
writeShellApplication {
  name = "stack-pull-requests";
  runtimeInputs = [
    git
    gh
    jq
  ];
  text = builtins.readFile ./stack-pull-requests.sh;
}
