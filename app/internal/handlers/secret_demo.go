package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/example/aws-secrets-zerotrust/internal/secrets"
)

type SecretDemoHandler struct {
	provider secrets.Provider
}

func NewSecretDemoHandler(provider secrets.Provider) *SecretDemoHandler {
	return &SecretDemoHandler{provider: provider}
}

type dbSecretPayload struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Host     string `json:"host"`
	Port     string `json:"port"`
}

func (h *SecretDemoHandler) ServeDemo(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var payload dbSecretPayload

	err := h.provider.GetJSON(ctx, "database", &payload)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "Failed to retrieve database secret from provider",
			"details": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"database_host": payload.Host,
		"database_port": payload.Port,
		"username":      payload.Username,
		"password":      "[REDACTED]",
		"loaded_at":     time.Now().Format(time.RFC3339),
		"security_note": "Zero-trust model: secret retrieved live from secure memory cache without env var persistence",
	})
}
