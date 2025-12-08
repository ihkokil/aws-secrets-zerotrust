package secrets

import (
	"context"
	"errors"
)

var (
	ErrSecretNotFound = errors.New("secret key not found")
	ErrVaultUnavailable = errors.New("vault service unavailable")
)

// Provider abstracts secret operations across AWS Secrets Manager and HashiCorp Vault.
type Provider interface {
	// Get retrieves a string secret value by key or secret name/field path.
	Get(ctx context.Context, key string) (string, error)

	// GetJSON retrieves a JSON secret object and unmarshals it into dest.
	GetJSON(ctx context.Context, key string, dest interface{}) error

	// Refresh forces an immediate invalidation and re-fetch of the cached secret.
	Refresh(ctx context.Context, key string) error
}
