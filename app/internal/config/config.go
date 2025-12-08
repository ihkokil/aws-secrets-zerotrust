package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	AppEnv           string        `json:"app_env"`
	SecretProvider   string        `json:"secret_provider"`
	AWSRegion        string        `json:"aws_region"`
	SecretPathPrefix string        `json:"secret_path_prefix"`
	VaultAddr        string        `json:"vault_addr"`
	Port             string        `json:"port"`
	CacheTTL         time.Duration `json:"cache_ttl"`
}

// LoadConfig reads configuration from environment variables without hardcoded defaults.
func LoadConfig() *Config {
	env := getEnv("APP_ENV", "dev")
	provider := getEnv("SECRET_PROVIDER", "aws-secrets-manager")
	region := getEnv("AWS_REGION", "us-east-1")
	prefix := getEnv("SECRET_PATH_PREFIX", "myapp/"+env+"/app")
	vaultAddr := getEnv("VAULT_ADDR", "http://127.0.0.1:8200")
	port := getEnv("PORT", "8080")

	defaultTTL := 5 * time.Minute
	if env == "prod" {
		defaultTTL = 1 * time.Minute
	}

	ttlStr := os.Getenv("CACHE_TTL_MINUTES")
	if ttlStr != "" {
		if ttlVal, err := strconv.Atoi(ttlStr); err == nil && ttlVal > 0 {
			defaultTTL = time.Duration(ttlVal) * time.Minute
		}
	}

	return &Config{
		AppEnv:           env,
		SecretProvider:   provider,
		AWSRegion:        region,
		SecretPathPrefix: prefix,
		VaultAddr:        vaultAddr,
		Port:             port,
		CacheTTL:         defaultTTL,
	}
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}
