Absolutely. Let's start **Phase 2 — Dockerize the Hospital Management System**.

The goal is to take your existing HTML/CSS/JavaScript application and run it inside an **Nginx Docker container**.

![Image](https://images.openai.com/static-rsc-4/9Asa5mqOLCxRirkzElrsSDJ_a2jZhL3zVFtdCQYR-_3pvJdVJN4-TWoHJZXiStJP3Xvy_wFT4-oYwlU6WcU54UDdGxcVxGzHz_zl4-AxkhMO7bmpd76zwhwE8JYq2kkIsZnCrF4H7FTmXKEn90_nakS7TyLOxIqhWMCebImpAB8fhTIcwxKYd_qcIm9-YZMM?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/DkbZyDJ8U9srGMfjdJHjGMHG86Htd1RK8f-ZBCuwBQidW4BKn39xn_Vrb0-oM4P9_uRU_RmvRvL226dwPL9J7OhasOq1DMSRSxoSe16OTiuuRugNMucqXqD6Zfe4g70c_D0MjlsKM1-0ics-6q0d2FH5FInAdn3HClEJl0Pf9n6ufVHS4it9J6vgzjrINhbu?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/QjjJHaBlw1Onk19_EZ9KJBDzNT-bfdGmzPDdesj4TKmOpyDhzDjPdfgngJMSAasq3dc5_c2GYpIqsz4RvjCAs5wc2wENJCwzDm1VyXv7iMplvWgFCxeqSNDRfbTWI5Bn2SswC0LC_SEzxdLUTG04ohksMcYhRVlDt_e2SCjjuP7WJWQ_diwTEwJZwtKg3cqd?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/ClYqkbTnIG-52uYC5ZlQkxcQi1Ld4LCm8E-CRMdwnY2NU1nqalsF73uHR6WFmpkGEA2m1STtEg5XJ3V_ViPn9PxcMZ4Cvi8W5HQSVcOnsnp_rv3tztAylsEj2D-1xNePowyDyK-hadIGKacaidC9fbMxRID3Q-pp2RAe2TiDzi8gTnik2gKqaN9q6DYAHcHc?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/eVNbwISS96D8sZDXcQIJ7epkDk-CZOVRTVwuPuBz4LsN1mt0XdVxBaIYhQx_BajqI02FTo3d_gsXy2A48RcU3qTXur1ccvfE72blbdYu6zw33Ql_RluUXLgdA8ZOu6_yoLehMB90CHxW9sHijNR0_fg8X4qnMVPYzwd4DKqxeDaH6aSa1POh5TnEJHWX1UB3?purpose=fullsize)

## Phase 2 architecture

We'll build:

```text
Hospital Management System
          |
          v
      Dockerfile
          |
          v
     Docker Image
          |
          v
    Docker Container
          |
          v
        Nginx
          |
          v
    http://localhost:8080
```

At the end of Phase 2, you should be able to open:

```text
http://localhost:8080
```

and see your Hospital Management System.

---

# Step 1 — Create Docker branch

From your project directory:

```bash
cd Hospital-Management-System
```

Check your branch:

```bash
git branch
```

You should currently be on:

```text
develop
```

Create the Docker feature branch:

```bash
git checkout -b feature/docker
```

Verify:

```bash
git branch
```

You should see:

```text
* feature/docker
  develop
  main
```

---

# Step 2 — Check your application

Before creating the Dockerfile, let's understand what we're containerizing.

Run:

```bash
ls -la
```

You should see your HTML files and directories.

Then:

```bash
find . -maxdepth 2 -type f | sort
```

We want to identify things such as:

```text
index.html
about.html
doctors.html
appointment.html
contact.html
login.html
registration.html
assets/
```

Don't move or rename your existing application files yet.

---

# Step 3 — Create Docker directory

Create:

```bash
mkdir -p docker
```

Our structure will become:

```text
Hospital-Management-System/
│
├── index.html
├── ...
├── assets/
│
├── docker/
│   └── Dockerfile
│
├── kubernetes/
├── terraform/
├── scripts/
└── .github/
```

---

# Step 4 — Create Dockerfile

Create:

```bash
nano docker/Dockerfile
```

For Phase 2, use this simple production-style Nginx container:

```dockerfile
FROM nginx:alpine

LABEL maintainer="Farhan Shaikh"
LABEL description="Hospital Management System"

COPY . /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### What does this mean?

### `FROM`

```dockerfile
FROM nginx:alpine
```

We're using Nginx as our web server.

`alpine` gives us a relatively small Linux-based image.

---

### `COPY`

```dockerfile
COPY . /usr/share/nginx/html
```

This copies your website into Nginx's default web directory.

For example:

```text
Your project:

index.html
about.html
assets/
```

becomes:

```text
/usr/share/nginx/html/

index.html
about.html
assets/
```

inside the container.

---

### `EXPOSE`

```dockerfile
EXPOSE 80
```

Nginx listens on port 80 inside the container.

---

### `CMD`

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

This keeps Nginx running in the foreground, which is required for the Docker container to stay alive.

---

# Step 5 — Create `.dockerignore`

This is important.

We don't want to send unnecessary files to Docker during the build.

Create:

```bash
nano .dockerignore
```

Add:

```text
.git
.gitignore
.github
terraform/.terraform
terraform/*.tfstate
terraform/*.tfstate.*
terraform/*.tfvars
kubernetes
scripts
README.md
*.log
.env
.env.*
.vscode
.idea
```

However, there's an important point here.

Because we're currently using:

```dockerfile
COPY . /usr/share/nginx/html
```

the Docker build context is the whole repository.

That's okay for now because we're learning the basic containerization workflow.

In **Phase 3**, we'll improve this considerably when we implement the proper multi-stage/optimized build.

---

# Step 6 — Build the Docker image

From the **root of your project**, run:

```bash
docker build -f docker/Dockerfile -t hospital-management:v1 .
```

Breakdown:

```text
docker build
```

Build a Docker image.

```text
-f docker/Dockerfile
```

Use our Dockerfile.

```text
-t hospital-management:v1
```

Give the image the name:

```text
hospital-management
```

and version:

```text
v1
```

`.`

means:

> Use the current project directory as the Docker build context.

---

# Step 7 — Check the image

Run:

```bash
docker images
```

You should see something similar to:

```text
REPOSITORY             TAG       IMAGE ID       CREATED
hospital-management   v1        xxxxxxxxxxxx   ...
nginx                 alpine    xxxxxxxxxxxx   ...
```

You can also run:

```bash
docker image ls hospital-management
```

---

# Step 8 — Run the container

Now:

```bash
docker run -d \
  --name hospital-app \
  -p 8080:80 \
  hospital-management:v1
```

Explanation:

```text
-p 8080:80
```

means:

```text
Host              Container

localhost:8080 →  port 80
                    |
                    v
                  Nginx
```

So the user accesses:

```text
http://localhost:8080
```

while Nginx internally listens on:

```text
port 80
```

---

# Step 9 — Check the container

Run:

```bash
docker ps
```

You should see:

```text
CONTAINER ID   IMAGE                     PORTS
xxxxxxxx       hospital-management:v1   0.0.0.0:8080->80/tcp
```

---

# Step 10 — Open the application

On your local Ubuntu/Windows machine, open:

```text
http://localhost:8080
```

You should see your:

**Hospital Management System**

---

# Step 11 — Test using curl

You can also test without a browser:

```bash
curl http://localhost:8080
```

You should receive HTML output beginning with something similar to:

```html
<!DOCTYPE html>
<html>
...
```

---

# Step 12 — Check container logs

Run:

```bash
docker logs hospital-app
```

You should see Nginx startup information.

You can follow logs:

```bash
docker logs -f hospital-app
```

Press:

```text
Ctrl+C
```

to stop following the logs.

---

# Step 13 — Check inside the container

This is a useful Docker skill.

Run:

```bash
docker exec -it hospital-app /bin/sh
```

Now you're inside the container.

Run:

```bash
ls
```

Then:

```bash
cd /usr/share/nginx/html
```

Run:

```bash
ls -la
```

You should see your hospital application files.

For example:

```text
index.html
about.html
doctors.html
appointment.html
assets/
...
```

Check Nginx:

```bash
nginx -v
```

Exit:

```bash
exit
```

---

# Step 14 — Test container restart

Let's simulate a simple failure/recovery scenario.

Stop the container:

```bash
docker stop hospital-app
```

Check:

```bash
docker ps
```

It shouldn't appear in the running container list.

Start it again:

```bash
docker start hospital-app
```

Check:

```bash
docker ps
```

Then:

```bash
curl http://localhost:8080
```

Your application should work again.

---

# Step 15 — Test automatic restart

Later, Kubernetes will handle application recovery for us.

But we can demonstrate Docker's restart policy now.

Remove the current container:

```bash
docker rm -f hospital-app
```

Run it again:

```bash
docker run -d \
  --name hospital-app \
  --restart unless-stopped \
  -p 8080:80 \
  hospital-management:v1
```

Check:

```bash
docker ps
```

The important part is:

```text
--restart unless-stopped
```

Docker will automatically restart the container if it exits unexpectedly.

---

# Step 16 — Check the Docker image size

Run:

```bash
docker image ls hospital-management:v1
```

You'll probably notice that the image is fairly small because we're using:

```text
nginx:alpine
```

But there's still an important issue with our current Dockerfile.

We're copying the **entire repository**:

```dockerfile
COPY . /usr/share/nginx/html
```

That's not ideal.

Our repository eventually contains:

```text
application
terraform
kubernetes
.github
scripts
docker
```

We don't want all of that inside our production web container.

---

# Step 17 — Improve the Docker build context

For the final architecture, I recommend moving the application itself into:

```text
application/
```

so that we have:

```text
Hospital-Management-System/
│
├── application/
│   ├── index.html
│   ├── about.html
│   ├── doctors.html
│   ├── appointment.html
│   ├── ...
│   └── assets/
│
├── docker/
│   └── Dockerfile
│
├── kubernetes/
├── terraform/
├── scripts/
└── .github/
```

Then our Dockerfile becomes:

```dockerfile
FROM nginx:alpine

COPY application/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

This is much cleaner.

**But don't move your files yet if you're following this step-by-step.** We should first confirm exactly what is currently in your repository so we don't accidentally break paths used by your HTML/CSS/JS.

---

# Step 18 — Git commit

Once the Docker container is working:

```bash
git status
```

Then:

```bash
git add docker/Dockerfile .dockerignore
```

Commit:

```bash
git commit -m "feat: dockerize hospital management application"
```

Push:

```bash
git push -u origin feature/docker
```

---

# Phase 2 checkpoint ✅

At this point, we want all of these commands to work:

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
docker logs hospital-app
```

and:

```bash
docker exec -it hospital-app /bin/sh
```

Most importantly:

```text
Browser
   |
   v
localhost:8080
   |
   v
Docker
   |
   v
Nginx
   |
   v
Hospital Management System
```

---

## ⚠️ One thing before Phase 3

Our current Dockerfile is intentionally **Phase 2 simple**:

```dockerfile
FROM nginx:alpine
COPY . /usr/share/nginx/html
```

Don't worry that it isn't truly multi-stage yet.

**Phase 3 will specifically address that.**

We'll create an optimized Docker architecture:

```text
                Multi-stage Docker
                       |
             +---------+---------+
             |                   |
             v                   v
        Build Stage        Production Stage
             |                   |
             |                   v
             |                Nginx
             |                   |
             +-------------------+
                       |
                       v
                Small Image
                       |
                       v
                  ECR Ready
```

We'll also make the application directory clean, add a proper Nginx configuration, add health-check support, compare **before vs. after image size**, and then push the final image to Git/ECR in the next stages.
