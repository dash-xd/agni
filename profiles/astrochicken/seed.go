// Package astrochicken owns the Astrochicken installation profile.
//
// The profile contains its Terraform root. That HCL is authoritative for which
// shared Agni modules it imports; callers do not maintain a second dependency
// manifest or enumerate modules on the command line.
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

// Seed writes a complete Astrochicken Terraform source tree into dst. The root
// HCL is copied unchanged, then Agni's shared Terraform library is made
// available beneath modules/. Terraform itself remains authoritative for which
// modules the root imports and uses.
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
	if err := agnitf.Seed(dst); err != nil {
		return fmt.Errorf("seed Astrochicken shared Terraform library: %w", err)
	}
	return nil
}
