{
  redis = { memoryMiB = 40; };
  # Replace null with qualified OCI digest references via an reviewed commit.
  # The build deliberately fails until each reference is supplied.
  images = {
    redis = null;
    logma = null;
    skymill = null;
  };
}
