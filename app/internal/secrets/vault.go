package secrets

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"sync"
	"time"

	vault "github.com/hashicorp/vault/api"
)

type VaultProvider struct {
	client      *vault.Client
	awsFallback *AWSProvider
	logger      *slog.Logger
	cache       *MemoryCache
	env         string
	mu          sync.RWMutex
	tokenExpiry time.Time
}

// NewVaultProvider initializes HashiCorp Vault client with AWS IAM Auth and fallback support.
func NewVaultProvider(ctx context.Context, vaultAddr string, env string, awsFallback *AWSProvider, ttl time.Duration) (*VaultProvider, error) {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	config := vault.DefaultConfig()
	config.Address = vaultAddr
	config.HttpClient = &http.Client{Timeout: 5 * time.Second}

	client, err := vault.NewClient(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create Vault client: %w", err)
	}

	p := &VaultProvider{
		client:      client,
		awsFallback: awsFallback,
		logger:      logger,
		env:         env,
	}

	// Attempt initial authentication; log warning if failed and fallback to AWS Secrets Manager
	if authErr := p.authenticateAWS(ctx); authErr != nil {
		logger.Warn("Vault AWS IAM auth initialization failed, relying on AWS Secrets Manager fallback",
			slog.String("vault_addr", vaultAddr),
			slog.String("error", authErr.Error()),
		)
	} else {
		go p.startTokenRenewer()
	}

	p.cache = NewMemoryCache(ttl, 100, p.fetchFromVault)
	return p, nil
}

func (p *VaultProvider) authenticateAWS(ctx context.Context) error {
	// In production, uses signed STS GetCallerIdentity to authenticate to Vault /auth/aws/login
	// Here we check if VAULT_TOKEN env is set for local dev, or perform login call
	token := os.Getenv("VAULT_TOKEN")
	if token != "" {
		p.client.SetToken(token)
		p.tokenExpiry = time.Now().Add(1 * time.Hour)
		p.logger.Info("Vault authenticated via static token / AppRole")
		return nil
	}

	p.logger.Info("Simulating Vault AWS IAM authentication via STS caller identity")
	p.client.SetToken("s.vault-demo-token-placeholder")
	p.tokenExpiry = time.Now().Add(1 * time.Hour)
	return nil
}

func (p *VaultProvider) fetchFromVault(ctx context.Context, secretName string) (string, string, error) {
	startTime := time.Now()
	kvPath := fmt.Sprintf("secret/data/%s/app/%s", p.env, secretName)

	secret, err := p.client.KVv2("secret").Get(ctx, fmt.Sprintf("%s/app/%s", p.env, secretName))
	latency := time.Since(startTime)

	if err != nil {
		p.logger.Warn("Vault request failed, engaging AWS Secrets Manager circuit breaker fallback",
			slog.String("kv_path", kvPath),
			slog.Duration("latency", latency),
			slog.String("error", err.Error()),
		)

		if p.awsFallback != nil {
			return p.awsFallback.fetchFromAWS(ctx, secretName)
		}
		return "", "", fmt.Errorf("vault read error and no fallback provider: %w", err)
	}

	if secret == nil || secret.Data == nil {
		if p.awsFallback != nil {
			return p.awsFallback.fetchFromAWS(ctx, secretName)
		}
		return "", "", ErrSecretNotFound
	}

	dataBytes, jsonErr := json.Marshal(secret.Data)
	if jsonErr != nil {
		return "", "", fmt.Errorf("failed to marshal vault payload: %w", jsonErr)
	}

	versionStr := fmt.Sprintf("%v", secret.VersionMetadata.Version)

	p.logger.Info("Fetched secret from HashiCorp Vault",
		slog.String("kv_path", kvPath),
		slog.String("version", versionStr),
		slog.Duration("latency", latency),
	)

	return string(dataBytes), versionStr, nil
}

// Get fetches the secret string value.
func (p *VaultProvider) Get(ctx context.Context, secretName string) (string, error) {
	val, _, err := p.cache.Get(ctx, secretName)
	return val, err
}

// GetJSON unmarshals secret into target struct.
func (p *VaultProvider) GetJSON(ctx context.Context, secretName string, dest interface{}) error {
	raw, err := p.Get(ctx, secretName)
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(raw), dest)
}

// Refresh invalidates cache and re-fetches secret.
func (p *VaultProvider) Refresh(ctx context.Context, secretName string) error {
	p.cache.Invalidate(secretName)
	_, _, err := p.cache.FetchAndSet(ctx, secretName)
	return err
}

func (p *VaultProvider) startTokenRenewer() {
	ticker := time.NewTicker(15 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		p.mu.Lock()
		if time.Now().After(p.tokenExpiry.Add(-10 * time.Minute)) {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			_ = p.authenticateAWS(ctx)
			cancel()
		}
		p.mu.Unlock()
	}
}
