# leVPN

A multi-region HTTP CONNECT forward proxy written from scratch in Go and deployed on AWS with Terraform.

## Context

My day job is designing SASE/SSE egress controls for enterprise clients. leVPN is the other end of that pipe: a minimal proxy I run myself, to see what those controls observe from the client side and what it takes to operate one safely: TLS, PAC distribution, metrics, and hardening against SSRF.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MANAGEMENT PLANE                     │
│                                                         │
│  CloudFront ──► S3 (portal)     S3 (PAC files)         │
│  aguenonnvpn.com                /pac/proxy-{region}.pac │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                      DATA PLANE                         │
│                                                         │
│  Browser ──PAC──► EC2 :8080 (HTTP CONNECT + Basic Auth) │
│  curl    ──TLS──► EC2 :443  (HTTPS CONNECT + Basic Auth)│
│                       │                                 │
│                   Go server                             │
│                   ┌──────────┐                          │
│                   │ Auth 407 │                          │
│                   │ Hijack   │                          │
│                   │ TCP Dial │                          │
│                   │ io.Copy  │◄──► Internet             │
│                   └──────────┘                          │
│                                                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │ us-east-1│ │eu-west-1 │ │ap-se-1   │ │sa-east-1 │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
│         Terraform modules — activate/deactivate each    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                       MONITORING                        │
│                                                         │
│  GET :8080/metrics ──► JSON (conns, bytes, uptime)      │
│  React dashboard   ──► polls all regions every 5s       │
└─────────────────────────────────────────────────────────┘
```

## Execution & Technical ROI

### 1. From-scratch CONNECT relay

The Go server relies solely on the standard `net` and `net/http` libraries, avoiding third-party proxy frameworks. It handles HTTP CONNECT requests, hijacks the underlying TCP connection, and relays bidirectional data optimally using `io.Copy`. On port 443 the proxy serves a valid TLS certificate. Unauthorized scanners or bots receive an immediate 407 rejection via Basic Auth, effectively turning the nodes into black holes.

### 2. Hardening

Every `CONNECT` destination is resolved before dialing and refused (`403`) if any address is loopback, private, link-local (which covers the EC2 metadata endpoint) or CGNAT; the proxy then dials the checked IP, so a second DNS answer cannot redirect it (DNS rebinding). Only ports 80 and 443 are allowed, plain-HTTP forward requests get a `405`, `/metrics` requires the proxy credentials, an empty configured password rejects every request, and the password check runs in constant time.

### 3. The Chromium PAC Workaround (Dual-Listener)

Chromium-based browsers inherently fail to route traffic through HTTPS proxies configured via PAC files. To maintain a zero-install UX without breaking security, leVPN implements a dual-listener. Port 8080 handles plain HTTP CONNECT with Basic Auth specifically for browsers, while port 443 enforces full TLS for system clients and tools like `curl`.

### 4. DRY Infrastructure-as-Code

The infrastructure is fully managed by a custom Terraform module deployed across four AWS regions on t3.micro instances (~$10/region/month). I bypassed the classic DNS-vs-TLS chicken-and-egg problem (where the Certbot HTTP-01 challenge requires DNS resolution, which in turn requires the EC2 Elastic IP) by using sequenced `null_resource` provisioners and explicit dependencies. Activating or decommissioning a region requires toggling a single boolean flag in HCL.

### 4. Zero-Install Distribution

leVPN eliminates client-side friction by using Proxy Auto-Configuration (PAC) files hosted on S3 behind CloudFront. Any device (Windows, macOS, Linux, iOS, Android) connects via a single configuration URL — no agent, no binary, no installation.

### 5. In-Process Telemetry

To keep the t3.micro footprint minimal without depending on external monitoring agents, leVPN embeds its own metrics system: atomic counters (active connections, total bytes in/out, auth failures), a thread-safe ring buffer storing the last 200 connections, and a `/metrics` JSON endpoint consumed in real-time by a React dashboard polling every 5 seconds. Management plane traffic (portal, PAC files, monitoring) is strictly separated from the data plane — the dashboard must bypass the proxy to avoid routing observability traffic through the tunnel it's monitoring.

## Tech Stack

`Go` · `Terraform` · `AWS (EC2, Route 53, S3, CloudFront, ACM)` · `TLS / certbot` · `React` · `systemd`

## Project Structure

```
levpn/
├── cmd/server/main.go              # dual-port Go proxy server
├── internal/
│   ├── tunnel/tunnel.go            # HTTP CONNECT handler + TCP relay
│   └── metrics/metrics.go          # atomic counters + ring buffer
├── infra/
│   ├── main.tf                     # providers, module calls per region
│   ├── variables.tf
│   └── modules/tunnel-node/        # reusable EC2+EIP+SG+DNS+TLS module
├── portal/                         # React web portal (Vite + Tailwind)
├── extension/                      # Chrome extension (proxy toggle)
├── pac/                            # Proxy Auto-Configuration files
├── scripts/
│   ├── up.sh / down.sh             # region lifecycle
│   ├── deploy-server.sh            # redeploy Go binary to active nodes
│   ├── status.sh                   # health check across all regions
│   └── loadtest.sh                 # concurrent load testing
└── test-nodes.sh
```

## Quick Start

**Prerequisites:** Go 1.21+, Terraform 1.5+, AWS CLI configured

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Set: password, SSH key path, enabled regions

cd infra && terraform init && terraform apply
./scripts/status.sh
```

**Node Lifecycle:**

```bash
./scripts/up.sh asia          # activate a region
./scripts/down.sh asia        # tear it down
./scripts/deploy-server.sh    # redeploy Go binary to all active nodes
./scripts/status.sh           # health check the fleet
```
