# ============================================================
# Multi-stage Dockerfile for the sample observability app
# ============================================================

# Stage 1: Build
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copy dependency files first for better layer caching
COPY go.mod go.sum* ./
RUN go mod download

# Copy source code and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /app/server \
    main.go

# Stage 2: Runtime (distroless for minimal attack surface)
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /app/server /server

# Run as non-root user
USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/server"]
