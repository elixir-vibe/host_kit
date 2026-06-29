defmodule HostKit.DSL.Backup.Scope do
  @moduledoc "Process-local builder for backup metadata on existing services and jobs."

  alias HostKit.Backup
  alias HostKit.DSL.Scope
  alias HostKit.DSL.Systemd.Scope, as: SystemdScope

  @key {__MODULE__, :backup}

  def start(opts) do
    if SystemdScope.active?() do
      put(:job, Backup.job(opts))
    else
      Scope.service_name()
      put(:service, Backup.service(opts))
    end
  end

  def finish do
    case Process.delete(@key) do
      %{scope: :service, value: backup} ->
        Scope.update_current(:service, &put_in(&1.meta[:backup], backup))

      %{scope: :job, value: backup} ->
        SystemdScope.put_backup(backup)

      nil ->
        raise "no HostKit backup in scope"
    end
  end

  def consistency(strategy), do: update(:service, &Backup.put_consistency(&1, strategy))

  def verify(path), do: update(:service, &Backup.add_verify(&1, path))

  def verify(path, member), do: verify(Path.join(to_string(path), to_string(member)))

  def include(service_name) when is_atom(service_name) do
    update(:job, &Backup.include_service(&1, service_name))
  end

  def include(path) when is_binary(path) do
    update(:job, &Backup.include_path(&1, path))
  end

  def include(name, opts) when is_atom(name) and is_list(opts) do
    update(:job, &Backup.include_paths(&1, name, Keyword.fetch!(opts, :paths)))
  end

  def keep(opts), do: update(:job, &Backup.put_keep(&1, opts))

  defp put(scope, value) do
    Process.put(@key, %{scope: scope, value: value})
    :ok
  end

  defp update(expected_scope, fun) do
    case Process.get(@key) do
      %{scope: ^expected_scope, value: value} = state ->
        Process.put(@key, %{state | value: fun.(value)})
        :ok

      %{scope: scope} ->
        raise ArgumentError,
              "backup directive is only valid in #{expected_scope} backup scope, got #{scope}"

      nil ->
        raise "no HostKit backup in scope"
    end
  end
end
