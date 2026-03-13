FROM rust:1.94-slim AS builder

RUN apt-get update && apt-get install -y \
    pkg-config \
    libasound2-dev \
    libssl-dev \
    cmake \
    clang \
    && rm -rf /var/lib/apt/lists/*

ENV CMAKE_POLICY_VERSION_MINIMUM=3.5

WORKDIR /app
COPY . .

RUN cargo build --release

FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    libasound2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*


COPY --from=builder /app/target/release/yo-client /usr/local/bin/yo-client
COPY --from=builder /app/target/release/yo-server /usr/local/bin/yo-server


ENTRYPOINT ["/usr/local/bin/yo-client"]
