Perfect, thanks for pasting the outputs — this makes the problem **very clear now**.
Good news: **nothing is “mysteriously broken”**. This is a clean, explainable setup issue.

---

## Root cause (100% confirmed)

### 🚨 Cloudflare Error 521 happens because:

**Cloudflare only connects to ports `80` and `443`**, but your Docker Nginx is exposed on **port `8080`**.

From your output:

```
wp_nginx → 0.0.0.0:8080->80/tcp
```

But Cloudflare does:

```
Cloudflare → VPS_IP:80 or VPS_IP:443
```

So Cloudflare hits:

```
VPS_IP:80 ❌ (Docker nginx is NOT there)
VPS_IP:443 ❌ (nothing listening)
```

That’s why Cloudflare says **“Web server is down (521)”**.

---

## There is a SECOND issue (also important)

This line proves it:

```
Server: nginx/1.24.0 (Ubuntu)
```

That means:

👉 You have **system Nginx installed on the VPS**, listening on port **80**
👉 Docker Nginx is on **8080**

So right now you have **two Nginx servers**:

* System Nginx (port 80)
* Docker Nginx (port 8080)

Cloudflare reaches **system Nginx**, not Docker.

---

## Why curl works locally but Cloudflare fails

| Test                         | Result  | Why                        |
| ---------------------------- | ------- | -------------------------- |
| `curl http://127.0.0.1:8080` | ✅ works | Docker nginx               |
| `curl http://127.0.0.1`      | ✅ works | System nginx               |
| `https://www.zxss.site`      | ❌ 521   | Cloudflare → wrong backend |

---

## You have TWO valid ways to fix this

I’ll give you both — **Option A is recommended**.

---

# ✅ OPTION A (RECOMMENDED): Docker Nginx owns port 80/443

This is the **clean Docker-first architecture**.

### Step 1: Stop and disable system Nginx

```bash
sudo systemctl stop nginx
sudo systemctl disable nginx
```

(Optional but clean)

```bash
sudo apt remove nginx -y
```

---

### Step 2: Change Docker Nginx ports to 80/443

In `docker-compose.yml`:

```yaml
nginx:
  image: nginx:stable
  container_name: wp_nginx
  restart: always
  ports:
    - "80:80"
    - "443:443"
```

Remove `8080`.

---

### Step 3: Restart Docker stack

```bash
docker compose down
docker compose up -d
```

Verify:

```bash
ss -tulpn | grep :80
```

You should see **docker-proxy**, NOT Ubuntu nginx.

---

### Step 4: Test before Cloudflare

Temporarily set Cloudflare DNS to **DNS only (gray cloud)**.

Then:

```bash
curl http://YOUR_VPS_IP
```

Expected:

```
HTTP/1.1 302 Found
Server: nginx
```

Open in browser:

```
http://www.zxss.site
```

---

### Step 5: Enable Cloudflare proxy again

Turn 🟠 orange cloud back ON.

👉 **521 error will be gone.**

---

# ⚠️ OPTION B (Not recommended, but works): Keep 8080

Only use this if you **really want system nginx**.

You would need:

* System Nginx on port 80
* System Nginx → proxy_pass → Docker nginx:8080

This adds **unnecessary complexity** and no benefit for you.

---

## What about HTTPS / 443?

Right now:

```
ss -tulpn | grep :443
(no output)
```

So Cloudflare HTTPS will also fail **unless**:

* SSL mode = **Flexible** (temporary)
* OR you add HTTPS to Docker Nginx
* OR use Cloudflare Origin Cert / Nginx Proxy Manager

---

## Quick temporary Cloudflare setting (do this now)

Until HTTPS is ready:

```
Cloudflare → SSL/TLS → Encryption mode → Full
```

(Do NOT use Full (strict) yet.)

---

## Final diagnosis (plain English)

* DNS is correct ✅
* Firewall is not blocking ✅
* Docker is running fine ✅
* WordPress is working locally ✅
* **Cloudflare cannot reach your Docker nginx because it’s on port 8080 ❌**
* System nginx is interfering ❌

---

## TL;DR fix (fast)

```bash
sudo systemctl stop nginx
sudo systemctl disable nginx
# remove nginx if you want

# change docker nginx ports to 80/443
docker compose down
docker compose up -d
```

---

If you want, next I can:

* Add **Cloudflare Origin SSL** properly
* Convert this to **Nginx Proxy Manager**
* Lock ports to **Cloudflare IPs only**
* Clean WordPress redirects (`WP_HOME` / `WP_SITEURL`)
* Remove HTTPS redirect loops

Just say what you want next and we’ll finish this cleanly.
