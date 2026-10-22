{
  redis = { memoryMiB = 40; };
  # These IDs were observed after loading Nix-built archives into rootless
  # Podman. They are local image identities, not registry manifest digests.
  # Deployment must verify the corresponding pinned Nix outputs before use.
  images = {
    redis = "sha256:7e17a2a70c6b5ff3923b2ddb3b8a2f2f5d4507e5806e66499a56ac53f988d1ac";
    nginx = "sha256:8d604c11d48e577f5dc2dedb855038f2f0622fdbbc2fd45963fbb3fb9086dbc3";
    logma = "sha256:c1ca5959025e2f2f2baba48d13a630be4b5d8c8da09b59feb3a116095836d92a";
    skymill = "sha256:ede3f9c784b126dda968b4b41724cdbe6ff6c887f1eee17363bac22863e1fdf2";
  };
}
