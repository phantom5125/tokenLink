# Contributing to TokenLink

Thank you for helping build a small, auditable bridge between coding plans and
M5Stack devices.

## Development setup

```bash
swift build
bash scripts/test.sh
swift format lint --recursive --strict Sources Tests
bash scripts/privacy_scan.sh
```

Keep commits focused and include the failing test that motivated behavior changes.
Automated BLE tests use transport fakes; do not describe them as physical-device
validation.

## Adding or changing a provider

Every provider change should include all applicable items:

1. A stable provider ID and human-readable descriptor.
2. An adapter-specific official HTTPS host allowlist.
3. Synthetic response fixtures containing no real account data.
4. An explicit `Decodable` parser and normalization tests for every returned
   window, reset timestamp, percentage, and error envelope.
5. Authentication and HTTP-status mapping tests using injected clients.
6. Keychain use through the existing service and stable provider account; never
   serialize secrets into app configuration.
7. Last-known-good/stale behavior in the shared state model.
8. README setup and troubleshooting updates.
9. A passing privacy scan.

Do not add browser-cookie scraping, Full Disk Access, refresh-token handling, or a
general-purpose arbitrary endpoint setting as an incidental provider feature.
Those require a separate security design and maintainer approval.

## StopWatch protocol changes

Preserve the private GATT service and characteristic for firmware v1. New payloads
must be versioned and negotiated rather than overloading v1 keys. Keep HID/voice
interaction separate from quota transport. Document which statements are verified
by unit tests, a simulator, or a physical M5Stack device.

## UI contributions

`AppModel` is the UI state owner. SwiftUI views should not perform provider network
requests, read Keychain values, or connect to Bluetooth directly. Secret fields
must remain replacement-only and blank on every view appearance.

## Licenses and attribution

Contributions are accepted under the MIT License. Preserve `NOTICE.md` attribution
and add notices when code or response-shape knowledge is derived from another
project with attribution requirements.
