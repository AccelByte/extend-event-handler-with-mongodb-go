# Copyright (c) 2025 AccelByte Inc. All Rights Reserved.
# This is licensed software from AccelByte Inc, for limitations
# and restrictions contact your company contract manager.

# ----------------------------------------
# Stage 1: Protoc Code Generation
# ----------------------------------------
FROM golang:1.24-alpine AS proto-builder

# Install build dependencies and protoc
RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    protobuf \
    protobuf-dev

# Pin protoc Go plugin versions: protoc-gen-go-grpc v1.6.2+ requires Go >= 1.25,
# but this stage is on golang:1.24, which sets GOTOOLCHAIN=local (no auto-download).
ARG PROTOC_GEN_GO_VERSION=v1.36.11
ARG PROTOC_GEN_GO_GRPC_VERSION=v1.6.1

# Install protoc Go tools and plugins
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@${PROTOC_GEN_GO_VERSION} \
    && go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@${PROTOC_GEN_GO_GRPC_VERSION}

# Set working directory
WORKDIR /build

# Copy proto sources and generator script
COPY proto.sh .
COPY pkg/proto/ pkg/proto/

# Generate protobuf files.
RUN chmod +x proto.sh && \
    ./proto.sh



# ----------------------------------------
# Stage 2: gRPC Server Builder
# ----------------------------------------
FROM golang:1.24-alpine AS builder

ARG TARGETOS=linux
ARG TARGETARCH=amd64

ARG GOOS=$TARGETOS
ARG GOARCH=$TARGETARCH
ARG CGO_ENABLED=0

# Set working directory
WORKDIR /build

# Copy and download the dependencies for application
COPY go.mod go.sum ./
RUN go mod download

# Copy application code
COPY . .

# Copy generated protobuf files from stage 1
COPY --from=proto-builder /build/pkg/pb pkg/pb

# Build the Go application binary for the target OS and architecture
RUN go build -v -modcacherw -o /output/extend-event-handler-with-mongodb-go .


# ----------------------------------------
# Stage 3: Test Runner
# ----------------------------------------
# Jenkins agents running `make test` have no Go toolchain installed, so tests
# run inside this image instead. `RUN` fails the build (and `make test`) on
# any test failure.
FROM builder AS tester

RUN go test -v -cover ./...


# ----------------------------------------
# Stage 4: Runtime Container
# ----------------------------------------
FROM alpine:3.22

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    bash \
    curl

# Set working directory.
WORKDIR /app

# Copy build
COPY --from=builder /output/extend-event-handler-with-mongodb-go /app/main

# Plugin Arch gRPC Server Port.
EXPOSE 6565

# Prometheus /metrics Web Server Port.
EXPOSE 8080

# Entrypoint
ENTRYPOINT ["/app/main"]
