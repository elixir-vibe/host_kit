defmodule HostKit.Backup do
  @moduledoc "Backup contracts and job metadata attached to existing HostKit services and jobs."

  alias HostKit.Systemd

  defmodule Service do
    @moduledoc "Backup consistency and verification metadata for an existing service."

    @type consistency :: :online | :stop
    @type t :: %__MODULE__{consistency: consistency(), verify: [String.t()]}

    defstruct consistency: :online, verify: []
  end

  defmodule Job do
    @moduledoc "Backup execution metadata attached to an existing HostKit job."

    @type include :: {:service, atom()} | {:path, String.t()} | {:paths, atom(), [String.t()]}
    @type t :: %__MODULE__{
            name: String.t() | nil,
            destination: String.t(),
            config: String.t(),
            cwd: String.t() | nil,
            includes: [include()],
            keep: keyword()
          }

    defstruct name: nil, destination: nil, config: nil, cwd: nil, includes: [], keep: []
  end

  @spec service(keyword()) :: Service.t()
  def service(opts \\ []) do
    %Service{}
    |> put_consistency(Keyword.get(opts, :consistency, :online))
    |> then(fn backup -> Enum.reduce(List.wrap(opts[:verify]), backup, &add_verify(&2, &1)) end)
  end

  @spec job(keyword()) :: Job.t()
  def job(opts) do
    %Job{
      destination: opts |> Keyword.fetch!(:destination) |> to_string(),
      config: opts |> Keyword.fetch!(:config) |> to_string(),
      cwd: opts[:cwd] && to_string(opts[:cwd]),
      keep: Keyword.get(opts, :keep, [])
    }
  end

  @spec put_consistency(Service.t(), Service.consistency()) :: Service.t()
  def put_consistency(%Service{} = backup, consistency) when consistency in [:online, :stop] do
    %{backup | consistency: consistency}
  end

  @spec add_verify(Service.t(), String.t()) :: Service.t()
  def add_verify(%Service{} = backup, path) do
    %{backup | verify: backup.verify ++ [to_string(path)]}
  end

  @spec include_service(Job.t(), atom()) :: Job.t()
  def include_service(%Job{} = job, service) when is_atom(service) do
    %{job | includes: job.includes ++ [{:service, service}]}
  end

  @spec include_path(Job.t(), String.t()) :: Job.t()
  def include_path(%Job{} = job, path) do
    %{job | includes: job.includes ++ [{:path, to_string(path)}]}
  end

  @spec include_paths(Job.t(), atom(), [String.t()]) :: Job.t()
  def include_paths(%Job{} = job, name, paths) when is_atom(name) do
    %{job | includes: job.includes ++ [{:paths, name, Enum.map(paths, &to_string/1)}]}
  end

  @spec put_keep(Job.t(), keyword()) :: Job.t()
  def put_keep(%Job{} = job, opts), do: %{job | keep: opts}

  @spec attach_to_job(Systemd.Service.t(), Job.t()) :: Systemd.Service.t()
  def attach_to_job(%Systemd.Service{} = unit, %Job{} = job) do
    job = %{job | name: unit.name}

    service =
      unit.service
      |> Keyword.put(:type, :oneshot)
      |> Keyword.put(:exec_start, exec_start(job))
      |> maybe_put_working_directory(job.cwd)

    %{unit | service: service, meta: Map.put(unit.meta, :backup, job)}
  end

  defp exec_start(%Job{} = job) do
    HostKit.Systemd.Directives.coerce_value(:exec_start, [
      "mix",
      "host_kit.backup.run",
      String.replace_suffix(job.name, ".service", ""),
      job.config
    ])
  end

  defp maybe_put_working_directory(service, nil), do: service

  defp maybe_put_working_directory(service, cwd),
    do: Keyword.put(service, :working_directory, cwd)
end
