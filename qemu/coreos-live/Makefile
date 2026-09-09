.PHONY: ign iso gcp production production-prepare production-compose production-qemu

ign:
	@podman run --rm -i -v ${PWD}:/pwd:Z -w /pwd quay.io/coreos/butane:release --pretty --strict ./butane.yaml -o config.ign

# The legacy target name now builds the live ISO from the custom rpm-ostree/COSA
# compose rather than customizing a stock Fedora CoreOS ISO.
iso:
	@./build-iso.sh

gcp:
	@./build-gcp-image.sh

production:
	@./production/build.sh all

production-prepare:
	@./production/build.sh prepare

production-compose:
	@./production/build.sh compose

production-qemu:
	@./production/build.sh qemu
