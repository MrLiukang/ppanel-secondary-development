# Single Server Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the current PPanel backend, admin frontend, user frontend, and one node on `204.0.56.168` with Docker and HTTP-only Nginx origin routing for the two Cloudflare domains.

**Architecture:** PPanel, MySQL, and Redis run on an internal Docker network. Admin and user web containers bind only to localhost ports for Nginx, while the node uses host networking so newly created relay ports do not require Docker port-map edits. Nginx sends `fly.xexa1990.top` to admin, `user.xexa1990.top` to user, and `/v1` plus `/v2` on both hosts to the API.

**Tech Stack:** Docker Engine, Docker Compose, Go backend, Bun/Vite static frontends, Xray node, Nginx, Cloudflare Flexible SSL.

---

### Task 1: Prepare production container files

**Files:**
- Create: `docker-local/production/docker-compose.yml`
- Create: `docker-local/production/web.Dockerfile`
- Create: `docker-local/production/web-nginx.conf`
- Create: `docker-local/production/ppanel.yaml`
- Create: `docker-local/production/node.yml`

- [ ] Define internal MySQL, Redis, PPanel, admin web, user web, and host-network node services.
- [ ] Bind API to `127.0.0.1:18080`, admin to `127.0.0.1:13001`, and user to `127.0.0.1:13000`.
- [ ] Build both web apps as static Vite output and serve SPA fallback with Nginx.
- [ ] Configure the node to call `http://127.0.0.1:18080`.

### Task 2: Validate images locally

- [ ] Build backend, admin web, user web, and node images with Docker.
- [ ] Start the production compose stack locally using an isolated project name.
- [ ] Verify API, admin web, user web, and node health before upload.

### Task 3: Install and deploy on the target server

- [ ] Install `docker.io` and `docker-compose-v2` through Ubuntu packages.
- [ ] Upload the production bundle to `/opt/ppanel`.
- [ ] Start the stack and wait for MySQL health before starting PPanel.

### Task 4: Configure HTTP-only Nginx

- [ ] Add a dedicated Nginx site for `fly.xexa1990.top` and `user.xexa1990.top`.
- [ ] Proxy `/v1` and `/v2` to `127.0.0.1:18080` and web traffic to the matching frontend.
- [ ] Run `nginx -t` and reload Nginx without adding certificates.

### Task 5: Verify deployment

- [ ] Check local origin responses with Host headers for both domains.
- [ ] Check public HTTP responses through both DNS names.
- [ ] Confirm Docker containers are healthy and node can reach the API.
- [ ] Report Cloudflare requirements: web domains may be proxied, but AnyTLS relay ports must use the server IP or a DNS-only hostname.
