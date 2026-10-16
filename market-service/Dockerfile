FROM rust:1.96-bookworm AS build
ENV CARGO_BUILD_JOBS=1
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY templates ./templates
COPY assets ./assets
RUN cargo build --release --features s3
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/target/release/muse-plugin-market /usr/local/bin/muse-plugin-market
USER 65532:65532
ENV MARKET_LISTEN=0.0.0.0:8787
EXPOSE 8787
ENTRYPOINT ["muse-plugin-market"]
