#!/bin/bash
set -e
cd "$(dirname "$0")"
exec ./tools/run.sh --dev
