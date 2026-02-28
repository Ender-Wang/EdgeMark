#!/bin/bash
# Bundle CodeMirror 6 editor into a single JS file
set -euo pipefail
cd "$(dirname "$0")"
npx esbuild src/editor.js \
  --bundle \
  --outfile=dist/editor-bundle.js \
  --format=iife \
  --target=es2020 \
  --minify

# Copy styles to dist (loaded by editor.html)
cp src/styles.css dist/styles.css

# Copy runtime files into Xcode app target so they are bundled into the .app
XCODE_DIR="../../EdgeMark/Resources/Editor"
mkdir -p "$XCODE_DIR"
cp dist/editor-bundle.js dist/editor.html dist/styles.css "$XCODE_DIR/"

echo "✓ Built dist/ and copied to EdgeMark/Resources/Editor/"
