#!/bin/bash

mkdir -p bin

for region in us eu asia sa; do
  echo "Building $region..."

  # macOS
  GOOS=darwin GOARCH=amd64 go build \
    -ldflags "-X main.defaultRegion=$region" \
    -o bin/levpn-$region-macos \
    ./cmd/client/

  # Windows
  GOOS=windows GOARCH=amd64 go build \
    -ldflags "-X main.defaultRegion=$region" \
    -o bin/levpn-$region-windows.exe \
    ./cmd/client/

  echo "$region done ✅"
done

echo "All builds complete"
ls -lh bin/
