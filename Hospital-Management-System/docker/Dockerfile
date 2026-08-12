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