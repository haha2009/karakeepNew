#!/bin/bash
cd /Users/claw/Projects/test/karakeep
script -q /tmp/build-arm64.log \
  docker buildx build \
    --builder colima \
    --build-arg TARGETARCH=arm64 \
    --build-arg SERVER_VERSION=custom \
    -t claw/karakeep-custom:arm64 \
    -f docker/Dockerfile \
    --load \
    --platform=linux/arm64 \
    .
echo "BUILD_EXIT=$?" >> /tmp/build-arm64.log