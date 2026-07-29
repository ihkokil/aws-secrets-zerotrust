package handlers

import (
	"encoding/json"
	"net/http"
	"sync/atomic"

	"github.com/example/aws-secrets-zerotrust/internal/config"
	"github.com/example/aws-secrets-zerotrust/internal/secrets"
)

type HealthHandler struct {
	cfg           *config.Config
	provider      secrets.Provider
	secretsLoaded *atomic.Bool
}

func NewHealthHandler(cfg *config.Config, provider secrets.Provider, secretsLoaded *atomic.Bool) *HealthHandler {
	return &HealthHandler{
		cfg:           cfg,
		provider:      provider,
		secretsLoaded: secretsLoaded,
	}
}

func (h *HealthHandler) ServeRoot(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status":   "ok",
		"provider": h.cfg.SecretProvider,
		"env":      h.cfg.AppEnv,
	})
}

func (h *HealthHandler) ServeHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	loaded := h.secretsLoaded.Load()

	status := http.StatusOK
	if !loaded {
		status = http.StatusServiceUnavailable
	}

	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"healthy":         loaded,
		"secrets_loaded":  loaded,
		"vault_connected": h.cfg.SecretProvider == "vault" || h.cfg.SecretProvider == "aws-secrets-manager",
	})
}

func (h *HealthHandler) ServeReady(w http.ResponseWriter, r *http.Request) {
	if !h.secretsLoaded.Load() {
		http.Error(w, `{"ready":false, "reason":"secrets not loaded"}`, http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"ready":true}`))
}

func (h *HealthHandler) ServeMetrics(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var cacheMetrics secrets.Metrics
	if awsProv, ok := h.provider.(*secrets.AWSProvider); ok {
		cacheMetrics = awsProv.GetMetrics()
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"cache": cacheMetrics,
		"config": map[string]interface{}{
			"env":       h.cfg.AppEnv,
			"provider":  h.cfg.SecretProvider,
			"ttl_mins": h.cfg.CacheTTL.Minutes(),
		},
	})
}
