# NetBird Deployment Tasks

## Phase 1: Prerequisites & Cleanup
- [x] Check port 8080 usage and free if needed (was free)
- [x] Install jq if not present (already installed jq-1.7)
- [x] Stop/remove old NetBird containers (legacy setup removed)
- [x] Verify SSL certificates exist
- [x] Check port 3478 availability

## Phase 2: Run Official Getting-Started Script
- [x] Set NETBIRD_DOMAIN and run getting-started.sh
- [x] Select Nginx option [2]
- [x] Verify generated files (docker-compose.yml, config.yaml, nginx-netbird.conf, dashboard.env)

## Phase 3: Configure Nginx Reverse Proxy
- [x] Update SSL cert paths in nginx-netbird.conf
- [x] Install to /etc/nginx/sites-available/netbird
- [x] Test config (nginx -t passed)
- [x] Reload Nginx

## Phase 4: Start Services & Validate
- [x] docker compose up -d (both containers started)
- [x] Verify all containers running (Up 3+ hours, no restarts)
- [x] Test dashboard URL (HTTPS 200 ✅)
- [x] Test API endpoint (401 with JSON auth error ✅)
- [x] Test OAuth2 OIDC endpoint (200 ✅)

## Phase 5: Initial Admin Setup
- [ ] Access /setup page in browser
- [ ] Create admin account

## Phase 6: Azure AD Integration (post-deployment)
- [ ] Add Azure AD via Dashboard UI (Settings → Identity Providers)

## Phase 7: Client Onboarding
- [ ] Generate setup key
- [ ] Connect client with: netbird up --management-url https://netbirdtest.fincart.com --setup-key <KEY>
