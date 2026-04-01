# NetBird Self-Hosted VPN Deployment on Azure VM

## Background

Deploy a production-ready self-hosted NetBird VPN on Ubuntu 22.04 Azure VM at `netbirdtest.fincart.com` with existing Nginx + SSL.

## Key Research Findings

> [!IMPORTANT]
> **NetBird architecture has changed significantly.** Based on the latest official documentation:
> 
> 1. **Combined container (v0.65.0+)**: New installations use a single `netbirdio/netbird-server` container that merges Management, Signal, and Relay into one service. **Separate containers for management/signal/relay/coturn are the legacy approach.**
> 2. **Embedded IdP**: NetBird now ships with a built-in identity provider (embedded Dex). You **do NOT need to pre-configure Azure AD** during initial deployment. You first deploy with the embedded IdP, create an admin account, then add Azure AD as an external identity provider via the Dashboard UI.
> 3. **`management.json` is deprecated**: The new architecture uses `config.yaml` instead.
> 4. **STUN is embedded**: The combined container includes an embedded STUN server. Separate Coturn is no longer required for new deployments.

## Recommended Approach: Official Quickstart Script + Nginx Option

Instead of manually crafting docker-compose.yml and config files (which are complex and version-sensitive), the **official recommended approach** is to use the `getting-started.sh` script with Nginx reverse proxy option `[2]`.

### Why this approach:
- Generates **correct, version-matched** `docker-compose.yml`, `config.yaml`, `dashboard.env`, and `nginx-netbird.conf`
- Handles secret generation, relay tokens, etc. automatically
- Produces a config compatible with your existing Nginx + SSL setup
- Avoids the #1 cause of broken NetBird deployments: hand-crafted configs with wrong formats

## User Review Required

> [!IMPORTANT]
> **Azure AD Setup Timing**: You asked for Azure AD OIDC from the start. However, per current NetBird architecture, Azure AD is configured **AFTER** the initial deployment via the Dashboard UI (Settings → Identity Providers → Add → Microsoft Entra ID). This is the **officially supported and secure** approach. The embedded IdP handles initial admin authentication. Azure AD SSO is added afterwards so all users can log in with their Azure AD credentials.

> [!WARNING] 
> **Port 8080 Conflict**: You have port 8080 listed as open. The NetBird dashboard container maps to host port 8080. Your VM already has a `Tomcat-001` directory — if Tomcat is running on port 8080, we need to either stop Tomcat or use a different port for the dashboard. Please confirm.

> [!WARNING]
> **Nginx Port 80/443**: The quickstart script's Nginx option generates config but does NOT include Traefik in docker-compose. Your existing Nginx handles SSL. However, we need to ensure your current Nginx config doesn't conflict — we'll add a new site-specific config for NetBird.

## Proposed Changes

### Phase 1: Prerequisites & Cleanup

#### On the Azure VM (via SSH)
1. Install `jq` if not present
2. Stop and remove any existing NetBird containers/volumes
3. Check port conflicts (especially 8080, 3478)
4. Verify SSL certificates are in place for Nginx

---

### Phase 2: Run Official Getting-Started Script

1. Set environment variable: `export NETBIRD_DOMAIN=netbirdtest.fincart.com`
2. Download and run: `curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh | bash`
3. When prompted for reverse proxy, select **option [2] Nginx**
4. When prompted for NetBird Proxy, select **N** (not needed initially)
5. Script generates:
   - `docker-compose.yml` (combined netbird-server container + dashboard)
   - `config.yaml` (replaces old management.json)
   - `dashboard.env`
   - `nginx-netbird.conf` (template for our Nginx)

---

### Phase 3: Configure Nginx Reverse Proxy

#### [MODIFY] `/etc/nginx/sites-available/netbird` (or `/etc/nginx/conf.d/netbird.conf`)
- Use the generated `nginx-netbird.conf` as base
- Update SSL cert paths to match your existing certificates (likely the `cert.pem`/`chain.pem` files in home dir, or paths from your existing Nginx SSL config)
- Key routing:
  - `/relay*`, `/ws-proxy/*` → WebSocket to netbird-server (127.0.0.1:8081)
  - `/signalexchange.SignalExchange/*`, `/management.ManagementService/*` → gRPC to netbird-server (127.0.0.1:8081)
  - `/api/*`, `/oauth2/*` → HTTP to netbird-server (127.0.0.1:8081)
  - `/*` (catch-all) → dashboard (127.0.0.1:8080)

---

### Phase 4: Start Services & Validate

1. `docker compose up -d`
2. `docker compose ps` — verify all containers healthy
3. `curl https://netbirdtest.fincart.com` — should return dashboard HTML
4. `curl https://netbirdtest.fincart.com/api/accounts` — should return auth error (proving API is routed)

---

### Phase 5: Initial Admin Setup

1. Open `https://netbirdtest.fincart.com` in browser
2. Redirected to `/setup` page (first-time setup)
3. Create admin account (email + password)
4. Log in to Dashboard

---

### Phase 6: Add Azure AD (Microsoft Entra ID) as External IdP

1. In NetBird Dashboard: Settings → Identity Providers → Add → Microsoft Entra ID
2. NetBird provides a **Redirect URL** — copy this
3. In Azure Portal:
   - Go to Azure Active Directory → App Registrations → New Registration
   - Name: `NetBird VPN`
   - Redirect URI: Paste the URL from NetBird (type: Web)
   - Create a Client Secret under Certificates & Secrets
   - Copy Client ID and Client Secret
   - Note the Tenant ID for the Issuer URL: `https://login.microsoftonline.com/<TenantID>/v2.0`
4. Back in NetBird Dashboard: Enter Client ID, Client Secret, Issuer URL
5. Save — Azure AD login button appears on login page

---

### Phase 7: Setup Keys & Client Connection

1. In Dashboard: Go to Setup Keys → Create Key
2. On client machine: `netbird up --management-url https://netbirdtest.fincart.com --setup-key <KEY>`
3. Verify: `netbird status` shows connected
4. Dashboard shows peer online

---

## Open Questions

> [!IMPORTANT]
> 1. **Port 8080**: Is anything currently running on port 8080 (e.g., Tomcat)? If yes, should we stop it or use a different port?
> 2. **SSL Certificate Paths**: What are the exact paths to your SSL certificate and key files for `netbirdtest.fincart.com` on the VM? (The `cert.pem` and `chain.pem` in home directory, or different paths used by your current Nginx?)
> 3. **UDP Port 3478**: Is this port open in your Azure NSG? The embedded STUN server needs UDP 3478 to be publicly accessible.

## Verification Plan

### Automated Tests
1. `docker compose ps` — all containers running
2. `curl -k https://netbirdtest.fincart.com` — returns HTML
3. `curl -k https://netbirdtest.fincart.com/api/accounts` — returns JSON (401 or 200)
4. `docker compose logs netbird-server` — no crash loops
5. `netbird up --management-url https://netbirdtest.fincart.com --setup-key <KEY>` — client connects

### Manual Verification
1. Open dashboard in browser → login page loads
2. Create admin account on `/setup`
3. Add Azure AD → SSO button appears
4. Login via Azure AD works
5. Generate setup key → onboard a client → peer visible in dashboard
