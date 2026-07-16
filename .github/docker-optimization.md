# Docker Image Optimization Guide

Quick reference for reducing Docker image sizes.

## Key Techniques

| Technique | Impact |
|-----------|--------|
| Multi-stage builds | 50–80% |
| Alpine base image | 30–50% |
| Remove build tools | 20–40% |
| .dockerignore | 5–20% |

## Multi-Stage Example

```dockerfile
# Stage 1: Build
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y gcc make
COPY . /app
WORKDIR /app
RUN make build

# Stage 2: Runtime (minimal)
FROM alpine:3.21
COPY --from=builder /app/app /app/app
CMD ["/app/app"]
```

## .dockerignore

```
.git/
.github/
README.md
*.md
.env
```

## ZeroTier-Specific Notes

This project uses a custom `zerotier-moon` image (see `Dockerfile`) based on Alpine 3.21
with stability and diagnostic packages included. Minimum viable example:

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache zerotier-one iproute2 iptables ip6tables bash jq iputils
VOLUME /var/lib/zerotier-one
EXPOSE 9993/udp
CMD ["zerotier-one"]
```

## Checklist

- [ ] Lightweight base image?
- [ ] .dockerignore created?
- [ ] Only necessary packages installed?
- [ ] Specific versions (not :latest)?
