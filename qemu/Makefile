iso:
	@echo "[+] Building CoreOS ISO..."
	@./build-iso.sh

ign:
	@podman run --rm -i -v ${PWD}:/pwd:Z -w /pwd quay.io/coreos/butane:release --pretty --strict ./butane.yaml -o config.ign 

