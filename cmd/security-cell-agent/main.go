package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	configPath   = "/etc/agni/security-cell.json"
	quadletDir   = "/etc/containers/systemd"
	runtimeDir   = "/run/agni-security-cell"
	registryPath = runtimeDir + "/atman-registry.json"
	unitsPath    = "/var/lib/agni/security-cell.units"
)

type cellConfig struct {
	ID        string `json:"id"`
	Region    string `json:"region"`
	Isolation struct {
		Mode string `json:"mode"`
	} `json:"isolation"`
	Runtime struct {
		ServiceAccountEmail           string `json:"service_account_email"`
		ArtifactRepositoryLocation   string `json:"artifact_repository_location"`
		ArtifactRepositoryName       string `json:"artifact_repository_name"`
		AtmanImage                   string `json:"atman_image"`
		MaraiImage                   string `json:"marai_image"`
		TLSCertificateSecret         string `json:"tls_certificate_secret"`
		TLSPrivateKeySecret          string `json:"tls_private_key_secret"`
	} `json:"runtime"`
	Tenants []tenantConfig `json:"tenants"`
}

type tenantConfig struct {
	ID       string `json:"id"`
	Identity struct {
		Audiences             []string `json:"audiences"`
		CallerServiceAccounts []string `json:"caller_service_accounts"`
	} `json:"identity"`
	KMS *struct {
		Enabled          *bool `json:"enabled"`
		ProcessIsolation *bool `json:"process_isolation"`
	} `json:"kms"`
}

type registry struct {
	Tenants map[string]registryTenant `json:"tenants"`
}

type registryTenant struct {
	Audiences []string      `json:"audiences"`
	Callers   []string      `json:"callers"`
	Marai     registryMarai `json:"marai"`
}

type registryMarai struct {
	Socket       string `json:"socket"`
	User         string `json:"user"`
	PasswordFile string `json:"password_file"`
}

type metadataToken struct {
	AccessToken string `json:"access_token"`
}

type secretResponse struct {
	Payload struct {
		Data string `json:"data"`
	} `json:"payload"`
}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	if err := run(ctx); err != nil {
		fmt.Fprintln(os.Stderr, "security-cell-agent:", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	if err := cleanupOldUnits(ctx); err != nil {
		return err
	}
	data, err := os.ReadFile(configPath)
	if errors.Is(err, os.ErrNotExist) {
		return daemonReload(ctx)
	}
	if err != nil {
		return fmt.Errorf("read cell config: %w", err)
	}
	var cfg cellConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return fmt.Errorf("decode cell config: %w", err)
	}
	if err := validate(&cfg); err != nil {
		return err
	}
	if err := os.MkdirAll(runtimeDir, 0700); err != nil {
		return err
	}

	token, err := accessToken(ctx)
	if err != nil {
		return err
	}
	if err := registryLogin(ctx, token.AccessToken, cfg.Runtime.AtmanImage, cfg.Runtime.MaraiImage); err != nil {
		return err
	}
	projectID, err := metadataText(ctx, "/computeMetadata/v1/project/project-id")
	if err != nil {
		return err
	}
	cert, err := accessSecret(ctx, token.AccessToken, projectID, cfg.Runtime.TLSCertificateSecret)
	if err != nil {
		return fmt.Errorf("load TLS certificate: %w", err)
	}
	key, err := accessSecret(ctx, token.AccessToken, projectID, cfg.Runtime.TLSPrivateKeySecret)
	if err != nil {
		return fmt.Errorf("load TLS private key: %w", err)
	}
	if err := replaceSecret(ctx, "agni-security-tls-cert", cert); err != nil {
		return err
	}
	if err := replaceSecret(ctx, "agni-security-tls-key", key); err != nil {
		return err
	}

	reg := registry{Tenants: make(map[string]registryTenant)}
	unitNames := make([]string, 0, len(cfg.Tenants)*2+1)
	usedNames := make(map[string]string)
	maraiServices := make([]string, 0, len(cfg.Tenants))
	for _, tenant := range cfg.Tenants {
		if !kmsEnabled(tenant) {
			continue
		}
		safe := safeName(tenant.ID)
		if safe == "" {
			return fmt.Errorf("tenant %q has no usable runtime name", tenant.ID)
		}
		if previous, ok := usedNames[safe]; ok && previous != tenant.ID {
			return fmt.Errorf("tenant names %q and %q normalize to the same runtime name", previous, tenant.ID)
		}
		usedNames[safe] = tenant.ID

		adminPassword, err := randomPassword()
		if err != nil {
			return err
		}
		appPassword, err := randomPassword()
		if err != nil {
			return err
		}
		adminSecret := "agni-marai-" + safe + "-admin"
		appSecret := "agni-marai-" + safe + "-app"
		if err := replaceSecret(ctx, adminSecret, adminPassword); err != nil {
			return err
		}
		if err := replaceSecret(ctx, appSecret, appPassword); err != nil {
			return err
		}

		volumeFile := "agni-marai-" + safe + "-socket.volume"
		containerFile := "agni-marai-" + safe + ".container"
		if err := writeQuadlet(volumeFile, renderVolume(safe)); err != nil {
			return err
		}
		if err := writeQuadlet(containerFile, renderMarai(cfg.Runtime.MaraiImage, safe, adminSecret, appSecret)); err != nil {
			return err
		}
		unitNames = append(unitNames, volumeFile, containerFile)
		maraiServices = append(maraiServices, "agni-marai-"+safe+".service")
		reg.Tenants[tenant.ID] = registryTenant{
			Audiences: tenant.Identity.Audiences,
			Callers:   tenant.Identity.CallerServiceAccounts,
			Marai: registryMarai{
				Socket:       "/run/marai/" + safe + "/redis.sock",
				User:         "marai-app",
				PasswordFile: "/run/marai/" + safe + "/app.password",
			},
		}
	}
	if len(reg.Tenants) == 0 {
		return errors.New("security cell has no enabled KMS tenants")
	}

	registryBytes, err := json.MarshalIndent(reg, "", "  ")
	if err != nil {
		return err
	}
	registryBytes = append(registryBytes, '\n')
	if err := os.WriteFile(registryPath, registryBytes, 0644); err != nil {
		return err
	}

	atmanFile := "agni-security-atman.container"
	if err := writeQuadlet(atmanFile, renderAtman(cfg.Runtime.AtmanImage, maraiServices, reg)); err != nil {
		return err
	}
	unitNames = append(unitNames, atmanFile)
	if err := os.MkdirAll(filepath.Dir(unitsPath), 0755); err != nil {
		return err
	}
	sort.Strings(unitNames)
	if err := os.WriteFile(unitsPath, []byte(strings.Join(unitNames, "\n")+"\n"), 0600); err != nil {
		return err
	}
	if err := daemonReload(ctx); err != nil {
		return err
	}
	return command(ctx, nil, "systemctl", "start", "agni-security-atman.service")
}

func validate(cfg *cellConfig) error {
	if cfg.ID == "" || cfg.Region == "" {
		return errors.New("cell id and region are required")
	}
	mode := cfg.Isolation.Mode
	if mode == "" {
		mode = "isolated-cell"
	}
	if mode != "isolated-cell" && mode != "shared-host" {
		return fmt.Errorf("unsupported isolation mode %q", mode)
	}
	if mode == "isolated-cell" && len(cfg.Tenants) != 1 {
		return errors.New("isolated-cell requires exactly one tenant")
	}
	if len(cfg.Tenants) == 0 {
		return errors.New("cell has no tenants")
	}
	if cfg.Runtime.ServiceAccountEmail == "" || cfg.Runtime.AtmanImage == "" || cfg.Runtime.MaraiImage == "" || cfg.Runtime.TLSCertificateSecret == "" || cfg.Runtime.TLSPrivateKeySecret == "" {
		return errors.New("runtime service account, images, and TLS secrets are required")
	}
	seen := make(map[string]string)
	for _, tenant := range cfg.Tenants {
		if tenant.ID == "" || len(tenant.Identity.Audiences) == 0 || len(tenant.Identity.CallerServiceAccounts) == 0 {
			return fmt.Errorf("tenant %q has incomplete identity policy", tenant.ID)
		}
		if kmsEnabled(tenant) && !processIsolated(tenant) {
			return fmt.Errorf("tenant %q disables marai process isolation", tenant.ID)
		}
		for _, audience := range tenant.Identity.Audiences {
			for _, caller := range tenant.Identity.CallerServiceAccounts {
				key := audience + "\x00" + caller
				if previous, ok := seen[key]; ok && previous != tenant.ID {
					return fmt.Errorf("ambiguous identity mapping between %q and %q", previous, tenant.ID)
				}
				seen[key] = tenant.ID
			}
		}
	}
	return nil
}

func kmsEnabled(tenant tenantConfig) bool {
	return tenant.KMS == nil || tenant.KMS.Enabled == nil || *tenant.KMS.Enabled
}

func processIsolated(tenant tenantConfig) bool {
	return tenant.KMS == nil || tenant.KMS.ProcessIsolation == nil || *tenant.KMS.ProcessIsolation
}

func safeName(value string) string {
	var b strings.Builder
	lastDash := false
	for _, r := range strings.ToLower(value) {
		valid := r >= 'a' && r <= 'z' || r >= '0' && r <= '9'
		if valid {
			b.WriteRune(r)
			lastDash = false
			continue
		}
		if !lastDash {
			b.WriteByte('-')
			lastDash = true
		}
	}
	return strings.Trim(b.String(), "-")
}

func randomPassword() ([]byte, error) {
	value := make([]byte, 48)
	if _, err := rand.Read(value); err != nil {
		return nil, err
	}
	encoded := make([]byte, base64.StdEncoding.EncodedLen(len(value)))
	base64.StdEncoding.Encode(encoded, value)
	return encoded, nil
}

func replaceSecret(ctx context.Context, name string, value []byte) error {
	return command(ctx, value, "podman", "secret", "create", "--replace", name, "-")
}

func writeQuadlet(name, content string) error {
	return os.WriteFile(filepath.Join(quadletDir, name), []byte(content), 0644)
}

func renderVolume(safe string) string {
	return fmt.Sprintf(`[Volume]
VolumeName=agni-marai-%s-socket
`, safe)
}

func renderMarai(image, safe, adminSecret, appSecret string) string {
	return fmt.Sprintf(`[Unit]
Description=Marai KMS for security tenant %s
After=network-online.target
Wants=network-online.target

[Container]
Image=%s
ContainerName=agni-marai-%s
Network=none
Volume=agni-marai-%s-socket.volume:/run/shared:U
Secret=%s,target=/run/secrets/admin,mode=0444
Secret=%s,target=/run/secrets/app,mode=0444
Environment=MARAI_REDIS_PORT=0
Environment=MARAI_REDIS_SOCKET=/run/shared/redis.sock
Environment=MARAI_REDIS_SOCKET_MODE=777
Environment=MARAI_ADMIN_PASSWORD_FILE=/run/secrets/admin
Environment=MARAI_APP_PASSWORD_FILE=/run/secrets/app
ReadOnly=true
NoNewPrivileges=true

[Service]
Restart=always
RestartSec=2
`, safe, image, safe, safe, adminSecret, appSecret)
}

func renderAtman(image string, maraiServices []string, reg registry) string {
	var unit strings.Builder
	unit.WriteString("[Unit]\nDescription=Atman regional security gateway\nAfter=network-online.target\nWants=network-online.target\n")
	for _, service := range maraiServices {
		unit.WriteString("After=" + service + "\nRequires=" + service + "\n")
	}
	unit.WriteString("\n[Container]\n")
	unit.WriteString("Image=" + image + "\nContainerName=agni-security-atman\nNetwork=host\n")
	unit.WriteString("Volume=" + registryPath + ":/etc/atman/tenants.json:ro,Z\n")
	ids := make([]string, 0, len(reg.Tenants))
	for id := range reg.Tenants {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		safe := safeName(id)
		unit.WriteString("Volume=agni-marai-" + safe + "-socket.volume:/run/marai/" + safe + ":ro\n")
		unit.WriteString("Secret=agni-marai-" + safe + "-app,target=/run/marai/" + safe + "/app.password,uid=65532,gid=65532,mode=0400\n")
	}
	unit.WriteString("Secret=agni-security-tls-cert,target=/run/secrets/tls.crt,uid=65532,gid=65532,mode=0400\n")
	unit.WriteString("Secret=agni-security-tls-key,target=/run/secrets/tls.key,uid=65532,gid=65532,mode=0400\n")
	unit.WriteString("Environment=ATMAN_TENANT_REGISTRY_FILE=/etc/atman/tenants.json\n")
	unit.WriteString("Environment=ATMAN_TLS_CERT_FILE=/run/secrets/tls.crt\n")
	unit.WriteString("Environment=ATMAN_TLS_KEY_FILE=/run/secrets/tls.key\n")
	unit.WriteString("Environment=ATMAN_LISTEN=:8443\nReadOnly=true\nNoNewPrivileges=true\n\n[Service]\nRestart=always\nRestartSec=2\n")
	return unit.String()
}

func cleanupOldUnits(ctx context.Context) error {
	data, err := os.ReadFile(unitsPath)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if len(data) == 0 {
		return nil
	}
	for _, name := range strings.Fields(string(data)) {
		if strings.HasSuffix(name, ".container") {
			service := strings.TrimSuffix(name, ".container") + ".service"
			_ = command(ctx, nil, "systemctl", "stop", service)
		}
		_ = os.Remove(filepath.Join(quadletDir, name))
	}
	_ = os.Remove(unitsPath)
	return nil
}

func daemonReload(ctx context.Context) error {
	return command(ctx, nil, "systemctl", "daemon-reload")
}

func registryLogin(ctx context.Context, token string, images ...string) error {
	hosts := make(map[string]struct{})
	for _, image := range images {
		parts := strings.SplitN(image, "/", 2)
		if len(parts) != 2 || !strings.Contains(parts[0], ".") {
			return fmt.Errorf("image %q does not contain a registry host", image)
		}
		hosts[parts[0]] = struct{}{}
	}
	for host := range hosts {
		if err := command(ctx, []byte(token), "podman", "login", "-u", "oauth2accesstoken", "--password-stdin", host); err != nil {
			return fmt.Errorf("authenticate to %s: %w", host, err)
		}
	}
	return nil
}

func accessToken(ctx context.Context) (metadataToken, error) {
	body, err := metadata(ctx, "/computeMetadata/v1/instance/service-accounts/default/token")
	if err != nil {
		return metadataToken{}, err
	}
	var token metadataToken
	if err := json.Unmarshal(body, &token); err != nil {
		return token, err
	}
	if token.AccessToken == "" {
		return token, errors.New("metadata server returned an empty access token")
	}
	return token, nil
}

func metadataText(ctx context.Context, path string) (string, error) {
	body, err := metadata(ctx, path)
	if err != nil {
		return "", err
	}
	value := strings.TrimSpace(string(body))
	if value == "" {
		return "", errors.New("metadata value is empty")
	}
	return value, nil
}

func metadata(ctx context.Context, path string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://metadata.google.internal"+path, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Metadata-Flavor", "Google")
	return do(req)
}

func accessSecret(ctx context.Context, token, projectID, secretID string) ([]byte, error) {
	endpoint := "https://secretmanager.googleapis.com/v1/projects/" + url.PathEscape(projectID) + "/secrets/" + url.PathEscape(secretID) + "/versions/latest:access"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	body, err := do(req)
	if err != nil {
		return nil, err
	}
	var response secretResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, err
	}
	value, err := base64.StdEncoding.DecodeString(response.Payload.Data)
	if err != nil {
		return nil, err
	}
	if len(value) == 0 {
		return nil, errors.New("secret payload is empty")
	}
	return value, nil
}

func do(req *http.Request) ([]byte, error) {
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return body, nil
}

func command(ctx context.Context, stdin []byte, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	if stdin != nil {
		cmd.Stdin = bytes.NewReader(stdin)
	}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	return nil
}
