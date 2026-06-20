# Release design notes

This note records the intended boundary for HostKit `release` work before adding artifact download, activation, cleanup, or rollback behavior. For BEAM applications, [ReleaseKit](https://hex.pm/packages/release_kit) produces the deployment-neutral OTP release tarball and ETF manifest consumed by `HostKit.Recipes.OTPRelease`. Applications configure ReleaseKit prebuild steps, such as `ReleaseKit.Step.Volt`, in application config and run `mix release_kit.artifact` directly; HostKit consumes the resulting manifest.

## Current scope

Today `release/2` is intentionally small. It is a DSL helper that emits plain, inspectable resources:

- a versions directory, by default `path(:opt, "releases/<name>")`,
- a current symlink, by default `path(:opt, "current/<name>")`,
- the symlink target `<versions_dir>/<version>`.

It does not fetch artifacts, build application artifacts, manage services, restart daemons, run readiness checks, prune old versions, or hide apply-time behavior.

```elixir
service :gatus do
  release :gatus, version: "5.36.0", owner: "deploy", group: "deploy"

  daemon "gatus" do
    service(exec_start: path(:opt, "current/gatus/gatus"))
  end
end
```

The release declaration owns the filesystem pointer. Runtime declarations own how a daemon uses that pointer.

## Boundary rules

Keep these concerns separate:

1. **Release/artifact concerns**
   - version identity,
   - artifact source and checksum,
   - unpack/build output path,
   - active pointer path,
   - provenance manifest,
   - retention/garbage collection of inactive versions.

2. **Runtime concerns**
   - systemd units,
   - users/groups for processes,
   - environment files,
   - working directories,
   - hardening/isolation,
   - restarts and reloads.

3. **Verification and monitoring concerns**
   - apply-time readiness resources,
   - external monitor metadata,
   - Gatus or other provider rendering,
   - health checks.

`release` must not define systemd/readiness/monitoring behavior. A release may expose paths or produce resources, but consumers such as `daemon`, `ready`, and providers remain separate declarations.

## Future shape

A fuller release declaration may grow into artifact preparation and activation, but it should still compile to plain resources and commands. For OTP release manifests, this needs a design that respects planning: `HostKit.Recipes.OTPRelease` currently decodes the manifest while evaluating the project DSL, so a producer that creates the manifest during apply cannot be consumed by the same already-built plan without a first-class producer/consumer model.

A fuller release declaration for downloadable artifacts may look like:

```elixir
service :gatus do
  release :gatus, version: "5.36.0" do
    artifact github: "TwiN/gatus",
      asset: "gatus-linux-amd64.tar.gz",
      checksum: "sha256:..."

    unpack strip_components: 1
    activate :symlink, atomic: true
    keep 3
  end

  daemon "gatus" do
    service(exec_start: path(:opt, "current/gatus/gatus"))
  end
end
```

This future shape should still produce inspectable plan data: directories, files, symlinks, commands, manifests, and cleanup actions. It should not introduce an opaque deployment engine hidden behind the DSL.

## Activation model

When HostKit eventually manages activation, prefer a prepare-then-flip model:

1. prepare the new version under an inactive path,
2. verify artifact checksum/provenance before activation,
3. optionally write a manifest for the prepared version,
4. atomically update the active pointer where the target platform supports it,
5. leave inactive versions available for rollback until explicit retention cleanup.

Activation should be modeled as plan/apply data. If an atomic symlink swap needs a command, that command should be visible in the plan and should have explicit down-plan behavior.

## Down-plan expectations

Rollback remains a down plan, not a release-specific rollback entity.

For future release actions:

- current symlink changes are reversible when the previous target was read into the up plan,
- artifact preparation may be irreversible unless HostKit has enough prior state or a backup/source-bundle strategy,
- retention cleanup should be conservative and must not delete the active version,
- cleanup of old versions should be explicit and inspectable,
- applying a down plan should use the same `HostKit.Apply` engine as any other plan.

## Shared paths

Traditional deployment tools often include `shared/` paths for mutable state across versions. HostKit already has separate primitives for state/config/cache/data roots, storage, env files, and systemd writable paths. A future release API may help describe shared paths, but it must not automatically wire them into runtime behavior. Runtime declarations should still make writable paths and process behavior explicit.

## Naming guidance

Use `release` for user-facing declarations. Avoid helper namespaces like `release_path/2` unless dogfooding proves they are necessary. Prefer existing generic path conventions such as:

```elixir
path(:opt, "current/gatus/gatus")
```

If repeated current/version roots become noisy, consider generic convention roots such as `:current` or `:versions` rather than release-specific helper names.
