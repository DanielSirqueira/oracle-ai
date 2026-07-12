# syntax=docker/dockerfile:1

# --- build stage: compile the Dart entrypoint to a native binary ---
FROM dart:stable AS build
WORKDIR /app
COPY . .
# This image ships the Dart CLI/MCP server only — drop the Flutter apps from the
# pub workspace (and the build context) so `dart pub get` doesn't require the
# Flutter SDK, which isn't present in the dart:stable image.
RUN sed -i '/apps\/oracle_studio/d; /apps\/oracle_setup/d' pubspec.yaml \
 && rm -rf apps \
 && dart pub get
RUN dart compile exe packages/oracle_server/bin/oracle_ai.dart -o /app/oracle_ai

# --- runtime stage: minimal image with the binary + migrations ---
FROM debian:bookworm-slim AS runtime
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -u 1000 -m oracle
WORKDIR /app
COPY --from=build /app/oracle_ai /app/oracle_ai
COPY --from=build /app/migrations /app/migrations
USER oracle
ENTRYPOINT ["/app/oracle_ai"]
