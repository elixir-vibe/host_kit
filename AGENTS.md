# Agent Guidelines

## Development

```sh
mix deps.get
mix ci
```

## Conventions

- Use the project Mix aliases; prefer `mix ci` for the full validation suite.
- Keep changes small, tested, and formatted.
- Core owns systemd/systemdkit and unitctl primitives.
- Integrations like Caddy, Forgejo, object storage, and monitoring are providers.
- DSLs must compile to plain, inspectable structs; runtime API must be primary and Mix tasks should wrap it.
