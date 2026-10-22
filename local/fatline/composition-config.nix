{
  redis = { memoryMiB = 40; };
  # Canonical CalVer references (YYYY.0M.0D[.MICRO], UTC). Published tags are immutable.
  # These initial date tags are RESERVED, not qualified or published yet.
  # Smoke must verify and publish the exact image IDs before activation.
  images = {
    redis = "localhost/fatline/redis:2026.10.21";
    nginx = "localhost/fatline/nginx:2026.10.21";
    logma = "localhost/fatline/logma:2026.10.21";
    skymill = "localhost/fatline/skymill:2026.10.21";
  };
}
