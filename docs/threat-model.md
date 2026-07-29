# Threat Model & Attack Vector Mitigation

## Threat Matrix

| Threat Vector | Attack Description | Mitigation in This Architecture | Security Mechanism |
| :--- | :--- | :--- | :--- |
| **Credential Stuffing / Git Leaks** | Developer accidentally commits AWS access keys or DB passwords to public GitHub repository. | **Zero Static Credentials**: No access keys exist in code, configs, environment variables, or docker images. TruffleHog secret scanning runs in CI. | OIDC / IRSA + TruffleHog CI scan |
| **Container Break-Out / Image Exfiltration** | Attacker compromises app container filesystem or inspects environment variables (`/proc/1/environ`). | **Scratch Base Image + Non-Root**: Read-only root filesystem, no shell in container (`scratch`), non-root user (UID 10001), no secrets stored in environment variables. | Kubernetes SecurityContext + Scratch Image |
| **Public Network Interception (MITM)** | Attacker intercepts plaintext or API calls between application and secrets provider. | **VPC Endpoints**: Secrets traffic is routed exclusively over private AWS VPC Interface Endpoints via TLS 1.3, bypassing the public internet entirely. | AWS Interface VPC Endpoints |
| **CI/CD Pipeline Exfiltration** | Malicious pull request or compromised GitHub runner attempts to print secrets from CI environment. | **CI Role Explicit Deny**: CI role is assigned explicit `Deny` on `secretsmanager:GetSecretValue`. CI can write secret metadata structure but can never read secret contents. | IAM Policy Explicit Deny |
| **Rogue / Non-MFA Auditor Access** | Human auditor or compromised employee account attempts to view production database passwords. | **MFA Condition + Explicit Deny**: Human auditor role requires `aws:MultiFactorAuthPresent=true` and is explicitly `Deny` on `GetSecretValue` (can only describe metadata). | IAM Resource Policy + MFA |
| **Stale Token Replay Attacks** | Compromised bearer token replayed past session lifetime. | **Short Token TTLs**: IRSA tokens expire in 1 hour; Vault tokens auto-renew and expire in 1 hour. | Short Token Lifetimes & Auto-Renewal |

---

## Defensive Boundary Architecture

```
                                  [ Attack Boundaries ]
                                            │
   ┌────────────────────────────────────────┼──────────────────────────────────────┐
   │ PRIVATE VPC BOUNDARY                   │                                      │
   │                                        ▼                                      │
   │  ┌───────────────────┐    HTTPS/TLS 1.3    ┌─────────────────────────────────┐ │
   │  │ Application Pod   │ ──────────────────► │ Secrets Manager VPC Endpoint    │ │
   │  │ (IRSA Identity)   │                     └─────────────────────────────────┘ │
   │  └─────────┬─────────┘                                      │                  │
   │            │                                                ▼                  │
   │            │ Encrypted Memory                         ┌───────────┐            │
   │            ▼                                          │ AWS KMS   │            │
   │  ┌───────────────────┐                                │ (CMK)     │            │
   │  │ In-Memory TTL     │                                └───────────┘            │
   │  │ Cache (RWMutex)   │                                                         │
   │  └───────────────────┘                                                         │
   └────────────────────────────────────────────────────────────────────────────────┘
```
