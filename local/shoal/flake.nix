{
  description = "Agni-owned one-Farcaster/one-World placement contract";

  outputs = { self }: {
    lib.plan = builtins.fromJSON (builtins.readFile ./plan.json);
  };
}
