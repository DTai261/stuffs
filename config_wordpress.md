Yes — **that is exactly how a proper production setup should look**, and yes, it’s absolutely possible.

You want:

* Secrets loaded from `.env`
* WordPress **not exposed publicly**
* Nginx handling `www.example.com`
* Nginx ↔ WordPress **only on an internal Docker network**
* Optional `WP_SITEURL` / `WP_HOME` done correctly

Below is a **clean, correct, and production-grade `docker-compose.yml`** that matches your requirements.

---

## 1. About `WP_SITEURL` and `WP_HOME` (important)

**Is it necessary?**

* ❌ Not strictly required (WordPress can auto-detect)
* ✅ **Strongly recommended** when:

  * Using reverse proxy (Cloudflare, Nginx)
  * Avoiding redirect loops
  * Preventing mixed HTTP/HTTPS issues

Since you’re using:

```
Cloudflare → Nginx → WordPress (local)
```

You **should set them**.

We will set:

```
https://www.example.com
```

---

## 2. Directory layout

```
/opt/wordpress/
├── .env
├── docker-compose.yml
├── wordpress/
├── db/
└── nginx/
    └── conf.d/
        └── wordpress.conf
```

---

## 3. Updated `docker-compose.yml`

This setup:

* Uses your `.env`
* WordPress is **internal only**
* Nginx is the **only exposed service**
* Clean Docker networking

```yaml
version: "3.8"

services:
  db:
    image: mariadb:11
    container_name: wp_db
    restart: always
    env_file:
      - .env
    volumes:
      - ./db:/var/lib/mysql
    networks:
      - wp_internal

  wordpress:
    image: wordpress:php8.2-fpm
    container_name: wp_app
    restart: always
    depends_on:
      - db
    env_file:
      - .env
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      WP_SITEURL: https://www.example.com
      WP_HOME: https://www.example.com
    volumes:
      - ./wordpress:/var/www/html
    networks:
      - wp_internal

  nginx:
    image: nginx:stable
    container_name: wp_nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./wordpress:/var/www/html:ro
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/certs:/etc/nginx/certs
    depends_on:
      - wordpress
    networks:
      - wp_internal

networks:
  wp_internal:
    driver: bridge
```

### Key points

* **No ports exposed on WordPress**
* Nginx talks to WordPress via `wordpress:9000`
* Secrets come from `.env`
* WordPress is PHP-FPM (best practice with Nginx)

---

## 4. Nginx config for WordPress (`nginx/conf.d/wordpress.conf`)

```nginx
server {
    listen 80;
    server_name www.example.com example.com;

    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass wordpress:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires max;
        log_not_found off;
    }
}
```

Later, Cloudflare or certbot can terminate HTTPS — this config is compatible with both.

---

## 5. Start everything

```bash
docker compose up -d
```

Check:

```bash
docker ps
```

You should see:

* wp_db
* wp_app
* wp_nginx

---

## 6. Cloudflare compatibility notes (very important)

### SSL mode

Set in Cloudflare:

```
SSL/TLS → Full (strict)
```

### Fix real visitor IP (recommended)

Add this to `wp-config.php`:

```php
if (isset($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_CF_CONNECTING_IP'];
}
```

---

## 7. Security verification checklist

✔ WordPress not publicly accessible
✔ Only Nginx exposes ports
✔ Secrets not hardcoded
✔ Reverse proxy compatible
✔ Cloudflare-safe
✔ No IP leakage

---

## Final answer (direct)

> Yes, it is possible — and your requested design is the **correct architecture**.
>
> * `WP_SITEURL` and `WP_HOME` **should be set**
> * WordPress can run **local-only**
> * Nginx can safely proxy requests from `www.example.com`
> * Docker internal networking handles communication cleanly

---

If you want next steps, I can:

* Add **Cloudflare Origin SSL**
* Convert Nginx → **Nginx Proxy Manager**
* Add **auto-renew HTTPS**
* Lock VPS to **Cloudflare IPs only**
* Add **fail2ban / rate limits**
* Add **backups + updates**

Tell me what you want to harden next.
