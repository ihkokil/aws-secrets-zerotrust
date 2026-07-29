package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"sync/atomic"
	"time"

	"github.com/example/aws-secrets-zerotrust/internal/config"
	"github.com/example/aws-secrets-zerotrust/internal/handlers"
	"github.com/example/aws-secrets-zerotrust/internal/secrets"
)

func main() {
	healthCheckFlag := flag.Bool("health-check", false, "Run health check query and exit")
	flag.Parse()

	cfg := config.LoadConfig()

	// Handle Docker HEALTHCHECK command line execution
	if *healthCheckFlag {
		resp, err := http.Get(fmt.Sprintf("http://127.0.0.1:%s/health", cfg.Port))
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	logger.Info("Starting zero-trust secrets demo server",
		slog.String("env", cfg.AppEnv),
		slog.String("provider", cfg.SecretProvider),
		slog.String("port", cfg.Port),
	)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// Initialize secrets provider
	awsProv, err := secrets.NewAWSProvider(ctx, cfg.AWSRegion, cfg.SecretPathPrefix, cfg.CacheTTL)
	if err != nil {
		logger.Error("Failed to initialize AWS Secrets Manager provider", slog.String("error", err.Error()))
		os.Exit(1)
	}

	var provider secrets.Provider = awsProv
	if cfg.SecretProvider == "vault" {
		vaultProv, vErr := secrets.NewVaultProvider(ctx, cfg.VaultAddr, cfg.AppEnv, awsProv, cfg.CacheTTL)
		if vErr != nil {
			logger.Warn("Failed to initialize Vault provider, falling back to AWS Secrets Manager", slog.String("error", vErr.Error()))
		} else {
			provider = vaultProv
		}
	}

	// Pre-fetch secrets and validate on startup (Fail Fast)
	var secretsLoaded atomic.Bool
	logger.Info("Validating secret connectivity and pre-fetching initial payload...")

	var dummyMap map[string]interface{}
	if err := provider.GetJSON(ctx, "database", &dummyMap); err != nil {
		logger.Warn("Initial secret fetch pre-check returned warning (will retry on incoming requests)",
			slog.String("error", err.Error()),
		)
	} else {
		secretsLoaded.Store(true)
		logger.Info("✓ Startup secret pre-fetch successful - zero trust verification passed.")
	}

	// Setup HTTP Handlers
	healthH := handlers.NewHealthHandler(cfg, provider, &secretsLoaded)
	demoH := handlers.NewSecretDemoHandler(provider)

	mux := http.NewServeMux()
	mux.HandleFunc("/", healthH.ServeRoot)
	mux.HandleFunc("/health", healthH.ServeHealth)
	mux.HandleFunc("/ready", healthH.ServeReady)
	mux.HandleFunc("/metrics", healthH.ServeMetrics)
	mux.HandleFunc("/demo", demoH.ServeDemo)

	server := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	logger.Info("HTTP server running", slog.String("address", server.Addr))
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Error("Server terminated unexpectedly", slog.String("error", err.Error()))
		os.Exit(1)
	}
}
