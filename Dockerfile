# ---------- Stage 1: build ----------
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Download dependencies first
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build a static binary
COPY . .
RUN CGO_ENABLED=0 go build -o muchtodo ./cmd/api

# ---------- Stage 2: run ----------
FROM alpine:3.20

WORKDIR /app

# Create a non-root user
RUN adduser -D appuser

# Copy only the binary, plus .env.example as .env so the app
# knows which config keys to read from environment variables
COPY --from=builder /app/muchtodo .
COPY --from=builder /app/.env.example .env

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["./muchtodo"]
