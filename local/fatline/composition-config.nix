{
  redis = { memoryMiB = 40; };
  # These IDs were observed after loading Nix-built archives into rootless
  # Podman. They are local image identities, not registry manifest digests.
  # Deployment must verify the corresponding pinned Nix outputs before use.
  images = {
    redis = null; # Remains blocked pending Redis image qualification.
    nginx = null; # Remains blocked pending Nginx image qualification.
    logma = "sha256:c1ca5959025e2f2f2baba48d13a630be4b5d8c8da09b59feb3a116095836d92a";
    skymill = "sha256:ede3f9c784b126dda968b4b41724cdbe6ff6c887f1eee17363bac22863e1fdf2";
  };
}
