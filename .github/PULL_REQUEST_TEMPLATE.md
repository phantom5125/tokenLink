# Pull request

## Summary

<!-- What problem does this pull request solve? Keep it to one problem. -->

## Related issue

<!-- Link the issue. Small verified fixes may use "Not required — small fix." -->

## Scope

- [ ] Small bug fix
- [ ] Tests or documentation
- [ ] Approved feature
- [ ] Provider adapter
- [ ] Hardware, firmware, transport, or protocol adapter

## Verification

<!-- List exact commands and results. State why any check was not run. -->

- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift format lint --recursive --strict Sources Tests`
- [ ] `bash scripts/privacy_scan.sh`

## Real-world evidence

<!--
Required for provider and hardware adapters. Attach redacted screenshots,
recordings, or checkpoint logs. Include provider region/plan or hardware/firmware
version, validation date, and tested commit. Never include credentials, private
payloads, account identifiers, personal paths, exact device UUIDs, or other
secrets.
-->

Not applicable.

## Security and privacy

<!--
Describe new endpoints, credentials, local files, network access, or
persistent data.
-->

- [ ] No secret, private payload, personal path, or device ID is included.
- [ ] New credential-bearing endpoints use an explicit HTTPS host allowlist.
- [ ] User-facing or contributor documentation is updated when needed.

## AI or agent assistance

<!--
Name material AI/agent assistance and what you personally reviewed and
verified.
-->

None.

## Contributor checklist

- [ ] I read and will follow the Code of Conduct and contributing guide.
- [ ] I understand every submitted change and have the right to license it.
- [ ] The change is focused and avoids unrelated refactoring or formatting.
- [ ] Tests or evidence demonstrate the behavior claimed in this pull request.
