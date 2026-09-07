// Package astrochicken owns the Astrochicken installation profile.
//
// The profile contains its Terraform root and selects the exact shared Agni
// Terraform modules that root imports. Callers seed one complete profile; they
// do not restate the profile's module dependency graph.
package astrochicken

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	agnitf "github.com/dash-xd/agni/terraform"
)

//go:embed terraform/*.tf
var rootFS embed.FS

var modules = []string{
	"regional-network",
	"regional-internal-addresses",
	"coreos-node",
	"regional-cell",
	"cloud-function-v1-http",
	"cloud-function-v2-http",
}

// Seed writes a complete Astrochicken Terraform root into dst, including the
// shared Agni modules imported by the profile. Astrochicken owns this selection.
func Seed(dst string) error {
	dst = strings.TrimSpace(dst)
	if dst == "" {
		return fmt.Errorf("destination is required")
	}
	root, err := fs.Sub(rootFS, "terraform")
	if err != nil {
		return fmt.Errorf("open Astrochicken root: %w", err)
	}
	if err := fs.WalkDir(root, ".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		data, err := fs.ReadFile(root, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		return os.WriteFile(target, data, 0o644)
	}); err != nil {
		return fmt.Errorf("seed Astrochicken root: %w", err)
	}
	if err := agnitf.SeedModules(dst, modules...); err != nil {
		return fmt.Errorf("seed Astrochicken shared modules: %w", err)
	}
	return nil
}
