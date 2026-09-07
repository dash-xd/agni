package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSeedSelectedModule(t *testing.T) {
	dir := t.TempDir()
	if err := seed([]string{"--module", "regional-network", dir}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "modules", "regional-network", "main.tf")); err != nil {
		t.Fatalf("seeded module missing: %v", err)
	}
}

func TestSeedRequiresModule(t *testing.T) {
	if err := seed([]string{t.TempDir()}); err == nil {
		t.Fatal("expected missing module error")
	}
}
