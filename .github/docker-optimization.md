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
FROM alpine:3.19
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

The official ZeroTier Docker image (`zyclonite/zerotier`) is already optimized.
For custom builds, use Alpine as the base and install only `zerotier-one`.

```dockerfile
FROM alpine:3.19
RUN apk add --no-cache zerotier-one
VOLUME /var/lib/zerotier-one
EXPOSE 9993/udp
CMD ["zerotier-one"]
```

## Checklist

- [ ] Lightweight base image?
- [ ] .dockerignore created?
- [ ] Only necessary packages installed?
- [ ] Specific versions (not :latest)?
