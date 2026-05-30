# sdk-core-dart

> [!WARNING]
> **Work in progress, not production-ready.** APIs and on-disk layouts
> are unstable and may change without notice before the first stable
> release. External pull requests are not accepted yet while the
> foundations stabilise. Issues are welcome: open one before sending
> code if you spot a bug or want a feature.

Layer 2 interceptors and primitives for Pinguteca SDKs in Dart.

## Repository layout

This repo is a Dart pub workspace plus Melos: pub resolves intra-repo
`path:` dependencies and shares a single root `pubspec.lock`; Melos
runs scripts, versioning, and publishing across packages.

```
packages/
  core/        # sdk_core_dart -- published to pub.dev
```

## Stack

- **mise** for tool versions and tasks (`mise.toml`, `mise.ci.toml`)
- **Cocogitto** for conventional commits and semantic versioning
- **prek** for pre-commit hooks (secrets, lockfiles, formatting)
- **Renovate** consuming `github>Pinguteca/renovate-config`
- **Octo STS** for short-lived per-workflow OIDC tokens

## Getting started

```bash
mise install                # installs every tool defined in mise.toml
prek install                # installs git hooks
mise run build              # build everything
mise run test               # run tests
```

## Common tasks

| Task | Alias | Description |
|------|-------|-------------|
| `mise run build` | `b` | Build the project |
| `mise run test` | `t` | Run tests |
| `mise run lint` |  | Run all linters |
| `mise run secret:scan` | `ss` | Kingfisher secret scan |
| `mise run release:sbom` | `rsbom` | Generate CycloneDX SBOM |
| `mise run bump` |  | Tag the next semver version |

## Release

Push a conventional commit, then `mise run bump`. The release workflow
takes over: SBOM, signatures,
and a GitHub Release with SLSA L3 provenance.

## License

See [LICENSE](./LICENSE). Pinguteca holds copyright.
