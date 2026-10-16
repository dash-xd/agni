package probe

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSeedWritesCompleteProfileTree(t *testing.T) {
	dst := t.TempDir()
	if err := Seed(dst); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{
		"main.tf",
		"variables.tf",
		"outputs.tf",
		"config/nginx.conf",
		"config/squid.conf",
		"config/lifecycle.env",
		"modules/regional-cell/main.tf",
		"modules/cloud-function-v1-http/main.tf",
		"modules/cloud-function-v2-http/main.tf",
	} {
		if _, err := os.Stat(filepath.Join(dst, filepath.FromSlash(path))); err != nil {
			t.Fatalf("missing seeded profile file %s: %v", path, err)
		}
	}
}

func TestSeedReconcilesProfileOwnedSourceAndPreservesTerraformState(t *testing.T) {
	dst := t.TempDir()
	staleTF := filepath.Join(dst, "removed.tf")
	staleConfig := filepath.Join(dst, "config", "removed.conf")
	staleModule := filepath.Join(dst, "modules", "removed-module", "main.tf")
	state := filepath.Join(dst, "terraform.tfstate")
	for path, body := range map[string]string{
		staleTF:     "stale\n",
		staleConfig: "stale\n",
		staleModule: "stale\n",
		state:       "{}\n",
	} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	if err := Seed(dst); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{staleTF, staleConfig, staleModule} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("stale profile source %s still exists: %v", path, err)
		}
	}
	if _, err := os.Stat(state); err != nil {
		t.Fatalf("Terraform state was not preserved: %v", err)
	}
}

func TestProbeSourceDoesNotDependOnSmokeEnvironmentIdentity(t *testing.T) {
	dst := t.TempDir()
	if err := Seed(dst); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{
		"main.tf",
		"variables.tf",
		"outputs.tf",
		"config/nginx.conf",
		"config/squid.conf",
		"config/lifecycle.env",
	} {
		body, err := os.ReadFile(filepath.Join(dst, filepath.FromSlash(path)))
		if err != nil {
			t.Fatal(err)
		}
		text := string(body)
		if strings.Contains(text, "smoke-") || strings.Contains(text, "Astrochicken") {
			t.Fatalf("Probe-owned source %s leaks Smoke/Astrochicken identity: %s", path, text)
		}
	}
}
