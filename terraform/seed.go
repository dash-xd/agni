// Package terraform exposes Agni's reusable Terraform implementation as
// embedded source for installation profiles and direct Go callers.
package terraform

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed modules/*/*.tf
var source embed.FS

// Modules reports the shared Terraform modules present in the embedded source
// tree. The directory tree is authoritative; do not maintain a second module
// inventory in Go.
func Modules() []string {
	entries, err := fs.ReadDir(source, "modules")
	if err != nil {
		return nil
	}
	out := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			out = append(out, entry.Name())
		}
	}
	sort.Strings(out)
	return out
}

// Seed reconciles Agni's complete shared Terraform module library beneath
// dst/modules. Profile HCL remains authoritative for which modules it actually
// imports, so callers do not maintain a second dependency manifest.
//
// dst/modules is profile-owned source. Reseeding replaces that directory so a
// module or *.tf file removed from the selected Agni revision cannot survive
// and continue influencing Terraform. Terraform runtime/state artifacts live
// outside this source directory and are not touched.
//
// This seed implementation is intentionally unrelated to Smoke ghxd/worktree
// seeding: it performs no Git operations, repository checkout, object sharing,
// authentication, ref handling, or worktree lifecycle.
func Seed(dst string) error {
	dst = strings.TrimSpace(dst)
	if dst == "" {
		return fmt.Errorf("destination is required")
	}
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	if err := os.RemoveAll(filepath.Join(dst, "modules")); err != nil {
		return fmt.Errorf("remove stale Terraform module source: %w", err)
	}

	return fs.WalkDir(source, "modules", func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		data, err := source.ReadFile(path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(target, data, 0o644); err != nil {
			return err
		}
		return nil
	})
}
