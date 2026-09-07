// Package smoke composes Agni into Smoke as an optional provider.
//
// The provider remains generic: it materializes only caller-selected Agni
// Terraform modules and invokes Terraform unchanged. Smoke owns higher-level
// domain recipes such as Astrochicken.
package smoke

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/dash-xd/agni/nativeexec"
	terraformassets "github.com/dash-xd/agni/terraform"
	smokeagni "github.com/xd-dash/smoke/agni"
	_ "github.com/xd-dash/smoke/cmd/agni"
)

type provider struct{}

func init() {
	smokeagni.Register("agni", provider{})
}

func (provider) RunTerraform(ctx context.Context, request smokeagni.TerraformRequest) error {
	workspace := strings.TrimSpace(request.Workspace)
	if workspace == "" {
		return fmt.Errorf("Terraform workspace is required")
	}
	if len(request.Args) == 0 {
		return fmt.Errorf("Terraform arguments are required")
	}
	if err := prepareWorkspace(workspace, request.Modules, request.Files); err != nil {
		return err
	}
	args := append([]string{"-chdir=" + workspace}, request.Args...)
	return nativeexec.Run(ctx, "terraform", args...)
}

func prepareWorkspace(workspace string, modules []string, files map[string][]byte) error {
	if err := os.MkdirAll(workspace, 0o755); err != nil {
		return fmt.Errorf("create Terraform workspace: %w", err)
	}
	if err := terraformassets.MaterializeModules(workspace, modules...); err != nil {
		return err
	}
	for name, data := range files {
		if err := writeRootFile(workspace, name, data); err != nil {
			return err
		}
	}
	return nil
}

func writeRootFile(workspace, name string, data []byte) error {
	name = filepath.Clean(strings.TrimSpace(name))
	if name == "." || name == "" || filepath.IsAbs(name) || name == ".." || strings.HasPrefix(name, ".."+string(filepath.Separator)) {
		return fmt.Errorf("invalid Terraform root file %q", name)
	}
	path := filepath.Join(workspace, name)
	rel, err := filepath.Rel(workspace, path)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return fmt.Errorf("Terraform root file escapes workspace: %q", name)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create Terraform root directory: %w", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".agni-tf-*")
	if err != nil {
		return fmt.Errorf("create temporary Terraform root file: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(0o644); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return fmt.Errorf("write Terraform root file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close Terraform root file: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("install Terraform root file: %w", err)
	}
	return nil
}
