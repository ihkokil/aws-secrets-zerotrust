# Multi-stage Dockerfile for Zero-Trust Application
# Stage 1: Build binary
FROM golang:1.22-alpine AS builder

RUN apk add --no-ca-certificates ca-certificates git

WORKDIR /src

COPY go.mod ./
# Copy go.sum if present, ignore if not
COPY go.mod go.sum* ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /server ./cmd/server

# Stage 2: Minimal scratch final runtime image
FROM scratch

# Copy root CA certificates for TLS AWS/Vault communication
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy compiled binary
COPY --from=builder /server /server

# Non-root user ID 10001
USER 10001:10001

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/server", "-health-check"]

ENTRYPOINT ["/server"]
