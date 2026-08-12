Absolutely. Let's move to **Phase 3 — Multi-Stage Docker + Image Optimization**.

In Phase 2, we created a basic Nginx container. Now we'll improve it so the Docker setup is cleaner and ready for **ECR, Kubernetes, and CI/CD**.

## Phase 3 goal

We'll move from:

```text
Phase 2

Project
   ↓
Dockerfile
   ↓
Nginx
   ↓
Container
```

to:

```text
Phase 3

Application
    ↓
Build Stage
    ↓
Production Stage
    ↓
Nginx
    ↓
Optimized Docker Image
    ↓
Ready for ECR
```

### What we'll implement

1. Organize the application
2. Create a proper multi-stage Dockerfile
3. Create `nginx.conf`
4. Add Docker health check
5. Create `.dockerignore`
6. Build the image
7. Compare image sizes
8. Run the optimized container
9. Test health
10. Test application pages
11. Commit changes to Git

---

# Step 1 — Create the Phase 3 branch

First check your current branch:

```bash
git branch
```

You should currently be on:

```text
feature/docker
```

First make sure your Phase 2 work is pushed:

```bash
git status
```

If everything is clean:

```bash
git checkout develop
git pull origin develop
```

Then create the Phase 3 branch:

```bash
git checkout -b feature/multistage-docker
```

Verify:

```bash
git branch
```

You should see:

```text
* feature/multistage-docker
  develop
  feature/docker
  main
```

---

# Step 2 — Organize the application

Currently your repository contains the application files at the root.

We want this structure:

```text
Hospital-Management-System/
│
├── application/
│   ├── index.html
│   ├── about.html
│   ├── doctors.html
│   ├── appointment.html
│   ├── contact.html
│   ├── gallery.html
│   ├── blog.html
│   ├── login.html
│   ├── registration.html
│   ├── privacy.html
│   ├── terms.html
│   └── assets/
│
├── docker/
│   ├── Dockerfile
│   └── nginx.conf
│
├── kubernetes/
│
├── terraform/
│
├── scripts/
│
└── .github/
    └── workflows/
```

This separation is important because eventually:

```text
application/
```

contains your actual application, while:

```text
docker/
kubernetes/
terraform/
.github/
```

contain your DevOps infrastructure.

---

# Step 3 — Before moving files

Because your HTML files may reference paths such as:

```html
assets/css/style.css
```

we need to preserve the directory structure.

From the project root, run:

```bash
find . -maxdepth 2 -type f | sort
```

Also check your assets:

```bash
find assets -type f | head -30
```

If your application is structured normally, we can move the application files while keeping their relative paths unchanged.

---

# Step 4 — Create application directory

Create:

```bash
mkdir application
```

Now move the application files.

**Do not move** these DevOps files/directories:

```text
.git
.github
docker
kubernetes
terraform
scripts
```

For a typical version of your repository, the application move would look like:

```bash
mv index.html application/
mv about.html application/
mv doctors.html application/
mv appointment.html application/
mv contact.html application/
mv gallery.html application/
mv blog.html application/
mv login.html application/
mv registration.html application/
mv privacy.html application/
mv terms.html application/
mv assets application/
```

If your repository contains additional HTML files, move those into `application/` as well.

Check:

```bash
ls -la application
```

You should now have something like:

```text
application/
├── index.html
├── about.html
├── doctors.html
├── appointment.html
├── contact.html
├── gallery.html
├── blog.html
├── login.html
├── registration.html
├── privacy.html
├── terms.html
└── assets/
```

---

# Step 5 — Verify HTML asset paths

This is important.

Run:

```bash
grep -R "assets/" application/*.html | head -20
```

You should see paths such as:

```text
assets/css/...
assets/js/...
assets/img/...
```

That's good.

We haven't changed anything inside the application, so those relative paths should continue to work.

---

# Step 6 — Create the multi-stage Dockerfile

Now edit:

```bash
nano docker/Dockerfile
```

For this project, because the application is currently a static HTML/CSS/JavaScript application with no compilation step, we can demonstrate a **real two-stage Docker build** while keeping the final image minimal.

Use:

```dockerfile
# =========================
# Stage 1: Build Stage
# =========================
FROM alpine:3.22 AS builder

WORKDIR /build

COPY application/ .

# =========================
# Stage 2: Production Stage
# =========================
FROM nginx:alpine

LABEL maintainer="Farhan Shaikh"
LABEL description="Hospital Management System"

COPY --from=builder /build/ /usr/share/nginx/html/

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

---

# Step 7 — Understand the multi-stage Dockerfile

The important part is:

```dockerfile
FROM alpine:3.22 AS builder
```

This is our **build stage**.

We copy the application into:

```text
/build
```

Then the second stage starts:

```dockerfile
FROM nginx:alpine
```

This is the **production stage**.

The important command is:

```dockerfile
COPY --from=builder /build/ /usr/share/nginx/html/
```

Docker copies only the required output from the builder stage.

The final image doesn't contain the builder stage itself.

---

# Step 8 — Why multi-stage builds?

Imagine a real frontend application such as:

```text
React
Angular
Vue
Next.js
```

You might need:

```text
Node.js
npm
dependencies
source code
build tools
```

during the build.

But production only needs:

```text
Nginx
+
compiled frontend files
```

So:

```text
Builder image
------------------
Node
npm
source
dependencies
build tools
        |
        v
     Build
        |
        v
dist/
------------------

Production image
------------------
Nginx
dist/
------------------
```

This reduces unnecessary content in the production image.

Your current application doesn't have a frontend compilation step, but we're setting up the architecture so the same pattern can be extended later.

---

# Step 9 — Create nginx.conf

Create:

```bash
nano docker/nginx.conf
```

Use:

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /health {
        access_log off;
        default_type text/plain;
        return 200 'healthy\n';
    }

    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|webp)$ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
    }
}
```

---

# Step 10 — Understand nginx.conf

The most important section is:

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

It tells Nginx how to handle requests.

We also added:

```text
/health
```

So:

```bash
curl http://localhost:8080/health
```

should eventually return:

```text
healthy
```

This becomes very useful when we move to Kubernetes.

Kubernetes will be able to ask:

```text
Is the application healthy?
```

---

# Step 11 — Test Nginx configuration

Before building the image, we'll eventually test Nginx from inside the container.

But first build the image.

From the project root:

```bash
docker build \
  -f docker/Dockerfile \
  -t hospital-management:v2 .
```

---

# Step 12 — Check the image

Run:

```bash
docker images | grep hospital-management
```

You should have:

```text
hospital-management   v1
hospital-management   v2
```

Now compare:

```bash
docker image ls hospital-management
```

You can see the difference between the Phase 2 image and Phase 3 image.

---

# Step 13 — Run the new container

Remove the old container if it exists:

```bash
docker rm -f hospital-app 2>/dev/null || true
```

Run:

```bash
docker run -d \
  --name hospital-app \
  -p 8080:80 \
  hospital-management:v2
```

Check:

```bash
docker ps
```

---

# Step 14 — Test the website

Open:

```text
http://localhost:8080
```

Your Hospital Management System should load.

Now test some pages:

```text
http://localhost:8080/doctors.html
```

```text
http://localhost:8080/appointment.html
```

```text
http://localhost:8080/contact.html
```

```text
http://localhost:8080/login.html
```

Make sure CSS and JavaScript are loading correctly.

---

# Step 15 — Test the health endpoint

Run:

```bash
curl http://localhost:8080/health
```

Expected:

```text
healthy
```

This endpoint will become important in Phase 7 when we configure Kubernetes probes.

---

# Step 16 — Check Docker health

Run:

```bash
docker inspect --format='{{json .State.Health}}' hospital-app
```

You should eventually see:

```text
"Status":"healthy"
```

You can make it easier to read with:

```bash
docker inspect hospital-app | grep -A 20 Health
```

The health check runs:

```dockerfile
HEALTHCHECK ...
```

and Docker periodically checks:

```text
http://127.0.0.1/
```

---

# Step 17 — Test Nginx from inside the container

Run:

```bash
docker exec -it hospital-app /bin/sh
```

Inside:

```bash
nginx -t
```

Expected:

```text
syntax is ok
test is successful
```

Then:

```bash
ls -la /usr/share/nginx/html
```

You should see:

```text
index.html
about.html
doctors.html
...
assets/
```

Check the health endpoint:

```bash
wget -qO- http://127.0.0.1/health
```

Expected:

```text
healthy
```

Exit:

```bash
exit
```

---

# Step 18 — Create a better `.dockerignore`

Update:

```bash
nano .dockerignore
```

Use:

```text
.git
.github
.gitignore

terraform/.terraform
terraform/*.tfstate
terraform/*.tfstate.*
terraform/*.tfvars

kubernetes
scripts

README.md

.env
.env.*

*.log

.vscode
.idea

Dockerfile
docker-compose.yml
```

The important thing is that:

```text
application/
```

is **not** ignored.

---

# Step 19 — Inspect the Docker build

Build again:

```bash
docker build \
  --no-cache \
  -f docker/Dockerfile \
  -t hospital-management:v2 .
```

You should see two stages:

```text
[builder ...]
...
[stage-1 ...]
...
```

That's how you can identify the multi-stage build in the Docker output.

---

# Step 20 — Test the container after rebuilding

Remove the old container:

```bash
docker rm -f hospital-app
```

Run the new image:

```bash
docker run -d \
  --name hospital-app \
  -p 8080:80 \
  hospital-management:v2
```

Then:

```bash
curl http://localhost:8080/health
```

Expected:

```text
healthy
```

And:

```bash
curl -I http://localhost:8080
```

You should receive an HTTP response such as:

```text
HTTP/1.1 200 OK
```

---

# Step 21 — Test failure/recovery

Stop the container:

```bash
docker stop hospital-app
```

Start it:

```bash
docker start hospital-app
```

Then:

```bash
curl http://localhost:8080/health
```

Expected:

```text
healthy
```

This is only a basic Docker recovery test.

Later Kubernetes will provide much more powerful recovery:

```text
Pod failure
    ↓
Kubernetes detects failure
    ↓
Pod recreated
    ↓
Readiness check
    ↓
Traffic restored
```

---

# Step 22 — Git status

Now check:

```bash
git status
```

You should see changes similar to:

```text
modified:
docker/Dockerfile

new:
docker/nginx.conf
application/
```

Check:

```bash
git diff --stat
```

---

# Step 23 — Commit Phase 3

Add the changes:

```bash
git add application docker/Dockerfile docker/nginx.conf .dockerignore
```

Commit:

```bash
git commit -m "feat: add optimized multi-stage docker build"
```

Push:

```bash
git push -u origin feature/multistage-docker
```

---

# Phase 3 checkpoint ✅

Before we move to AWS, we want this entire workflow working:

```text
GitHub
   |
   v
Application
   |
   v
Multi-stage Docker Build
   |
   +------ Builder Stage
   |          |
   |          v
   |      Application
   |
   +------ Production Stage
              |
              v
           Nginx
              |
              v
       Docker Container
              |
              v
       localhost:8080
```

And these commands should work:

```bash
docker images
```

```bash
docker ps
```

```bash
curl http://localhost:8080
```

```bash
curl http://localhost:8080/health
```

```bash
docker exec -it hospital-app nginx -t
```

```bash
docker inspect hospital-app
```

---

## What comes next: Phase 4 — Amazon ECR

Once Phase 3 is working, we'll move the Docker image from your machine into AWS:

```text
Your Computer
     |
     | docker push
     v
Amazon ECR
     |
     v
hospital-management
     |
     ├── v1
     ├── v2
     └── later: Git SHA / release tags
```

Then we'll introduce **Terraform for AWS infrastructure**, followed by EKS.

One important change for Phase 4: **we'll stop manually creating AWS resources wherever possible and start managing them with Terraform**, so the project follows proper Infrastructure-as-Code practices.
