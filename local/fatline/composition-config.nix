{
  redis = { memoryMiB = 40; };
  # Canonical version references. A v0.0.x tag is immutable once published.
  # These first versions are RESERVED, not qualified or published yet.
  # Smoke must verify and publish the exact image IDs before activation.
  images = {
    redis = "localhost/fatline/redis:v0.0.1";
    nginx = "localhost/fatline/nginx:v0.0.1";
    logma = "localhost/fatline/logma:v0.0.1";
    skymill = "localhost/fatline/skymill:v0.0.1";
  };
}
