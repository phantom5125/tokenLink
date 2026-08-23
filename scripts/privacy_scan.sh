#!/usr/bin/env bash
# 隐私扫描：阻止密钥、个人路径和真实蓝牙 UUID 进入 Git。
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
report() { echo "privacy_scan: $1"; fail=1; }

# 允许清单：文档化的服务 UUID 与全零合成 UUID。
allowed_uuids="7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01|7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C02|00000000-0000-0000-0000-000000000000"

tracked=$(git ls-files)

# 1. 真实 CoreBluetooth UUID（测试与文档 fixture 之外的 36 位 UUID）
while IFS= read -r file; do
  case "$file" in Tests/*|docs/*) continue ;; esac
  while IFS= read -r uuid; do
    [ -z "$uuid" ] && continue
    if ! echo "$uuid" | grep -qE "^($allowed_uuids)$"; then
      report "UUID outside allowlist in $file: $uuid"
    fi
  done < <(grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$file" 2>/dev/null || true)
done <<< "$tracked"

# 2. 个人绝对路径
while IFS= read -r file; do
  case "$file" in docs/*|.local/*) continue ;; esac
  if grep -qE '/Users/[A-Za-z0-9._-]+' "$file" 2>/dev/null; then
    report "absolute user path in $file"
  fi
done <<< "$tracked"

# 3. 非占位的 Bearer 令牌
while IFS= read -r file; do
  if grep -qE 'Authorization: Bearer [A-Za-z0-9_-]{8,}' "$file" 2>/dev/null \
     && ! grep -qE 'Authorization: Bearer (<|\$|\{|\[|example|placeholder)' "$file" 2>/dev/null; then
    report "possible bearer token in $file"
  fi
done <<< "$tracked"

# 4. 常见密钥前缀
while IFS= read -r file; do
  if grep -qE '(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "$file" 2>/dev/null; then
    report "secret-like pattern in $file"
  fi
done <<< "$tracked"

if [ "$fail" -ne 0 ]; then
  echo "privacy_scan: FAILED"
  exit 1
fi
echo "privacy_scan: OK"
