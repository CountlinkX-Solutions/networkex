## What and why

<!-- What the change does, why, and the issue it closes, if any. -->

## Checklist

- [ ] Tests cover the change, and `mix test` and `cargo test --workspace` pass.
- [ ] `mix format --check-formatted`, `mix credo --strict`, `cargo fmt --all -- --check` and
      `cargo clippy --workspace --all-targets -- -D warnings` are clean.
- [ ] Public functions are documented; user-visible changes are in `CHANGELOG.md`.
- [ ] Behaviour that spaghetti also has is checked against a fixture, and any deliberate
      deviation is recorded in `docs/parity.md`.
- [ ] Commit messages follow Conventional Commits.
