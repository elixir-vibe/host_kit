# DSLCore

`HostKit.DSLCore` is the internal substrate for HostKit-shaped DSL modules. It keeps the public DSL human-shaped while centralizing repeated process-local scope plumbing.

It is intentionally small and layered. Use only the pieces a DSL module needs.

## Internal layers

`HostKit.DSLCore` is the public macro/runtime facade. The implementation is split by concern:

- `HostKit.DSLCore.Scope.Builder` parses `scope` declarations and emits generated helpers.
- `HostKit.DSLCore.Options.Builder` parses `options` declarations into option schema structs.
- `HostKit.DSLCore.Options` validates option schemas through schemaless `Ecto.Changeset` casting.
- `HostKit.DSLCore.Attach` resolves nearest accepting scopes and applies attach strategies.
- `HostKit.DSLCore.Source` is the source-location struct used by DSL diagnostics.
- `HostKit.DSLCore.Stack` owns process-local scope stacks.

Keep domain behavior out of these modules. They should remain generic enough to extract after more HostKit surfaces have dogfooded them.

## Use

```elixir
defmodule HostKit.DSL.Scope do
  use HostKit.DSLCore

  setting :default_providers, default: []

  scope :project do
    accepts :host
    accepts :service
    accepts :resource
  end

  scope :service do
    accepts :resource
  end

  scope :ssh, value: true, start: false do
    requires :host
  end
end
```

## Settings

Use `setting/2` for ambient DSL state that is not a block scope.

```elixir
setting :default_providers, default: []
```

Generated helpers:

```elixir
default_providers()
put_default_providers(value)
reset_default_providers()
```

Settings are process-local and namespaced to the declaring module.

## Scopes

Use `scope/2` for block-local state.

```elixir
scope :service
```

Generated helpers include:

```elixir
push_service(state)
pop_service()
current_service()
current_service!()
current_service_scope!()
update_service(fun)
service_active?()
attach_service(value)
```

`push_*` helpers are macros so they can capture the caller location. The active scope stores that source metadata in `HostKit.DSLCore.Scope.location`.

For boolean scopes, provide a value:

```elixir
scope :inside, value: true
```

This also generates:

```elixir
start_inside()
finish_inside()
```

Use `start: false` or other helper flags when the DSL needs a custom public entry point:

```elixir
scope :ssh, value: true, start: false do
  requires :host
end
```

Selected helpers can be disabled:

```elixir
scope :project, current: false, update: false do
  accepts :host
end
```

## Options

Use `options/2` for module-local option validation without defining one module per option set.
The field DSL mirrors Ecto's `field/3` shape while DSLCore stores a small struct schema and validates through schemaless `Ecto.Changeset` casting.

```elixir
options :proxy_opts do
  field :provider, :atom, required: true, in: [:gatehouse]
  field :path, :string, default: "/etc/gatehouse/config.exs"
  field :meta, :map, default: %{}
end
```

Generated helpers:

```elixir
validate_proxy_opts(opts)
validate_proxy_opts!(opts)
```

The bang helper returns atom-keyed normalized data with defaults applied. `in: [...]` adds inclusion validation after casting.

```elixir
opts = validate_proxy_opts!(provider: :gatehouse)
opts.provider
opts.path
```

Use `return: :keyword` when the downstream API naturally consumes keyword options:

```elixir
options :command_opts, return: :keyword do
  field :phase, :atom, default: :apply, in: [:plan, :apply]
  field :timeout, :integer, default: 5_000
end
```

Keyword output omits nil optional fields. This prevents absent optional DSL values from overriding defaults in downstream keyword-based constructors.

DSLCore rejects unknown options before casting and raises DSL-oriented messages. Callers can pass a source location when validating options:

```elixir
source = HostKit.DSLCore.Source.from_caller(__CALLER__)
validate_proxy_opts!(opts, location: source)
```

Messages include the location when present:

```text
unknown option :bad for proxy_opts at config.hostkit:12
invalid options for proxy_opts: provider can't be blank at config.hostkit:12
```

## Requirements

Use `requires/1` when a scope can only be started inside another active scope.

```elixir
scope :section do
  requires :config_file
end
```

The generated `push_section/1` enforces this before pushing state and raises readable DSL errors such as:

```text
section must be declared inside config_file
```

Requirements are not parent-tree declarations. They only assert that a named scope is active somewhere in the current DSL stack.

## Attachments

Use `accepts/1` when a scope can receive child values.

```elixir
scope :project do
  accepts :host
  accepts :service
  accepts :resource
end

scope :service do
  accepts :resource
end
```

Then attach values to the nearest active accepting scope:

```elixir
attach(:resource, resource)
attach_service(service)
```

`accepts :host` defaults to calling `add_host(parent, child)` on the parent struct module.

Override the callback name when the child name does not map cleanly:

```elixir
scope :proxy do
  accepts :proxy_service, via: :add_service
end
```

For less domain-shaped parents, attach directly into a list field:

```elixir
scope :menu do
  accepts :item, into: :items
end
```

For callbacks outside the parent struct module, pass a module/function tuple:

```elixir
scope :menu do
  accepts :item, via: {MenuBuilder, :add_item}
end
```

This keeps topology implicit. Runtime nesting determines whether a child attaches to `project`, `instance`, `service`, or another accepting scope.

## Dogfood status

Current HostKit dogfood coverage:

- Scope stacks: project, host, instance, service, proxy, workspace, lifecycle, file resources, readiness, ingress, systemd.
- Attachments: resources into project/instance/service, proxy services into proxies, ingress servers/routes, generic list-field attach tests.
- Settings: default providers.
- Options: proxy, firewall, readiness, readiness checks, ingress, ingress server/route/proxy/tls.
- Source diagnostics: generated scope pushes capture callsites; option validation accepts explicit source locations from public DSL macros.

API shape that has held up so far:

```elixir
scope :parent do
  requires :grandparent
  accepts :child
  accepts :item, into: :items
  accepts :proxy_service, via: :add_service
end

options :thing_opts, return: :keyword do
  field :mode, :atom, default: :auto, in: [:auto, :manual]
end
```

Known rough edges before extraction:

- Public DSL macros still need to pass source locations manually into option validators.
- `options` uses Ecto field syntax but is intentionally much smaller than Ecto.Schema; relationships/embeds/custom validations are out of scope for now.
- `return: :keyword` nil omission is useful, but should be documented as part of the contract if extracted.
- `accepts ... via: {Module, :function}` is generic, but anonymous function callbacks are only viable when directly stored in runtime metadata, not macro-escaped across arbitrary module attributes.

## Diagnostics

Generated helpers raise scope-name-oriented errors instead of process-key errors:

```text
no active service scope
service directive used outside service block
resource must be declared inside project, instance, or service
```

Attach diagnostics are derived from declared `accepts` metadata. Requirement diagnostics are derived from declared `requires` metadata.

## When not to use DSLCore

Do not force ordinary data transformation into a scope. Use `scope` for nested DSL block state and `setting` for ambient DSL state. Plain functions and structs are still preferable for normal domain logic.

Do not use `accepts` just to avoid writing clear domain code. It is useful when a child can attach to the nearest active parent from a set of possible scopes.

## Current limitations

- Option schemas intentionally cover simple field casting/defaults/required validation only. Complex domain invariants still belong in domain code.
- Diagnostics are string-based and do not yet include source snippets.
- `accepts` supports default parent-struct callbacks, module/function callbacks, and list-field append. More advanced attach strategies should stay explicit until repeated consumers appear.
- `setting` is process-local only; there is no setting stack.
- Extraction outside HostKit should wait until more HostKit surfaces dogfood the primitives.
