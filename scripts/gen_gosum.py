import urllib.request
import sys

mods = [
    ("github.com/aws/aws-sdk-go-v2", "v1.26.0"),
    ("github.com/aws/aws-sdk-go-v2/config", "v1.27.9"),
    ("github.com/aws/aws-sdk-go-v2/credentials", "v1.17.9"),
    ("github.com/aws/aws-sdk-go-v2/feature/ec2/imds", "v1.16.0"),
    ("github.com/aws/aws-sdk-go-v2/internal/configsources", "v1.3.4"),
    ("github.com/aws/aws-sdk-go-v2/internal/endpoints/v2", "v2.6.4"),
    ("github.com/aws/aws-sdk-go-v2/internal/ini", "v1.8.0"),
    ("github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding", "v1.11.1"),
    ("github.com/aws/aws-sdk-go-v2/service/internal/presigned-url", "v1.11.6"),
    ("github.com/aws/aws-sdk-go-v2/service/secretsmanager", "v1.28.5"),
    ("github.com/aws/aws-sdk-go-v2/service/sso", "v1.20.3"),
    ("github.com/aws/aws-sdk-go-v2/service/ssooidc", "v1.23.3"),
    ("github.com/aws/aws-sdk-go-v2/service/sts", "v1.28.5"),
    ("github.com/aws/smithy-go", "v1.20.1"),
    ("github.com/cenkalti/backoff/v3", "v3.0.0"),
    ("github.com/go-jose/go-jose/v3", "v3.0.3"),
    ("github.com/hashicorp/errwrap", "v1.1.0"),
    ("github.com/hashicorp/go-cleanhttp", "v0.5.2"),
    ("github.com/hashicorp/go-multierror", "v1.1.1"),
    ("github.com/hashicorp/go-retryablehttp", "v0.7.5"),
    ("github.com/hashicorp/go-rootcerts", "v1.0.2"),
    ("github.com/hashicorp/go-secure-stdlib/parseutil", "v0.1.6"),
    ("github.com/hashicorp/go-secure-stdlib/strutil", "v0.1.2"),
    ("github.com/hashicorp/go-sockaddr", "v1.0.2"),
    ("github.com/hashicorp/hcl", "v1.0.0"),
    ("github.com/hashicorp/vault/api", "v1.12.0"),
    ("github.com/mitchellh/go-homedir", "v1.1.0"),
    ("github.com/mitchellh/mapstructure", "v1.5.0"),
    ("github.com/ryanuber/go-glob", "v1.0.0"),
    ("golang.org/x/crypto", "v0.19.0"),
    ("golang.org/x/net", "v0.21.0"),
    ("golang.org/x/text", "v0.14.0"),
    ("golang.org/x/time", "v0.3.0"),
]

gosum_lines = []

for mod, ver in mods:
    url = f"https://sum.golang.org/lookup/{mod}@{ver}"
    try:
        req = urllib.request.urlopen(url)
        lines = req.read().decode("utf-8").strip().split("\n")
        for line in lines:
            if line.startswith("github.com") or line.startswith("golang.org"):
                gosum_lines.append(line)
    except Exception as e:
        print(f"Warning for {mod}@{ver}: {e}", file=sys.stderr)

with open("app/go.sum", "w", encoding="utf-8") as f:
    for line in sorted(set(gosum_lines)):
        f.write(line + "\n")

print(f"Successfully generated app/go.sum with {len(gosum_lines)} authentic checksum records.")
