package secrets

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

type AWSProvider struct {
	client *secretsmanager.Client
	cache  *MemoryCache
	logger *slog.Logger
	prefix string
}

// NewAWSProvider initializes AWS Secrets Manager client with default IRSA / credential chain.
func NewAWSProvider(ctx context.Context, region string, prefix string, ttl time.Duration) (*AWSProvider, error) {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS SDK config: %w", err)
	}

	smClient := secretsmanager.NewFromConfig(cfg)

	p := &AWSProvider{
		client: smClient,
		logger: logger,
		prefix: prefix,
	}

	p.cache = NewMemoryCache(ttl, 100, p.fetchFromAWS)
	return p, nil
}

func (p *AWSProvider) fetchFromAWS(ctx context.Context, secretName string) (string, string, error) {
	startTime := time.Now()

	fullSecretName := secretName
	if p.prefix != "" {
		fullSecretName = fmt.Sprintf("%s/%s", p.prefix, secretName)
	}

	out, err := p.client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(fullSecretName),
	})

	latency := time.Since(startTime)

	if err != nil {
		p.logger.Error("AWS Secrets Manager fetch failed",
			slog.String("secret_name", fullSecretName),
			slog.Duration("latency", latency),
			slog.String("error", err.Error()),
		)
		return "", "", fmt.Errorf("failed to retrieve secret %s: %w", fullSecretName, err)
	}

	versionID := ""
	if out.VersionId != nil {
		versionID = *out.VersionId
	}

	p.logger.Info("Fetched secret from AWS Secrets Manager",
		slog.String("secret_name", fullSecretName),
		slog.String("version_id", versionID),
		slog.Duration("latency", latency),
	)

	secretVal := ""
	if out.SecretString != nil {
		secretVal = *out.SecretString
	}

	return secretVal, versionID, nil
}

// Get fetches the string secret content.
func (p *AWSProvider) Get(ctx context.Context, secretName string) (string, error) {
	val, _, err := p.cache.Get(ctx, secretName)
	return val, err
}

// GetJSON retrieves secret and parses JSON payload into dest struct.
func (p *AWSProvider) GetJSON(ctx context.Context, secretName string, dest interface{}) error {
	raw, errorVal := p.Get(ctx, secretName)
	if errorVal != nil {
		return errorVal
	}
	return json.Unmarshal([]byte(raw), dest)
}

// Refresh forces cache invalidation and fresh secret retrieval.
func (p *AWSProvider) Refresh(ctx context.Context, secretName string) error {
	p.cache.Invalidate(secretName)
	_, _, err := p.cache.FetchAndSet(ctx, secretName)
	return err
}

// GetMetrics exposes cache metrics.
func (p *AWSProvider) GetMetrics() Metrics {
	return p.cache.GetMetrics()
}
