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

var moduleNames = []string{
	"cloud-function-v1-http",
	"cloud-function-v2-http",
	"coreos-node",
	"regional-cell",
	"regional-internal-addresses",
	"regional-network",
}

func Modules() []string {
	out := append([]string(nil), moduleNames...)
	sort.Strings(out)
	return out
}

// Seed copies Agni's complete shared Terraform module library beneath
// dst/modules. Profile HCL remains authoritative for which of those modules it
// actually imports, so callers do not maintain a second dependency manifest.
//
// This seed implementation is intentionally unrelated to Smoke ghxd/worktree
// seeding: it performs no Git operations, repository checkout, object sharing,
// authentication, ref handling, or worktree lifecycle.
func Seed(dst string) error {
	dst = strings.TrimSpace(dst)
	if dst == "" {
		return fmt.Errorf("destination is required")
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
