defmodule HostKit.Source.Git do
  @moduledoc false

  alias HostKit.Resources.Source
  alias HostKit.Runner
  alias HostKit.Runner.Ops

  def resolve(%Source{type: :git, revision: revision} = source) when is_binary(revision),
    do: {:ok, source}

  def resolve(%Source{type: :git, ref: ref} = source) do
    case System.cmd("git", ["ls-remote", source.uri, ref], stderr_to_stdout: true) do
      {output, 0} ->
        case parse_ls_remote(output, ref) do
          {:ok, revision, ref_kind} ->
            {:ok, %{source | ref_kind: ref_kind, revision: revision}}

          :error ->
            {:ok, %{source | ref_kind: :revision, revision: ref}}
        end

      {output, status} ->
        {:error, {:git_ls_remote_failed, source.uri, ref, status, output}}
    end
  end

  def read(%Source{} = desired, opts) do
    opts = source_opts(desired, opts)

    cond do
      not exists?(desired.checkout, opts) ->
        {:ok, nil}

      not exists?(Path.join(desired.checkout, ".git"), opts) ->
        {:error, {:source_checkout_not_git, desired.checkout}}

      true ->
        with {:ok, current_uri} <- git_output(desired, ["remote", "get-url", "origin"], opts),
             {:ok, revision} <- git_output(desired, ["rev-parse", "HEAD"], opts),
             {:ok, tree} <- git_output(desired, ["rev-parse", "HEAD^{tree}"], opts),
             {:ok, status} <- git_output(desired, ["status", "--porcelain"], opts) do
          revision = String.trim(revision)
          tree = String.trim(tree)

          {:ok,
           %{
             desired
             | uri: String.trim(current_uri),
               revision: revision,
               meta:
                 desired.meta
                 |> Map.put(:current_revision, revision)
                 |> Map.put(:tree, tree)
                 |> Map.put(:dirty, String.trim(status) != "")
                 |> Map.put(:status, status)
           }}
        end
    end
  end

  def apply(%Source{} = source, opts) do
    opts = source_opts(source, opts)

    if exists?(source.checkout, opts) do
      update(source, opts)
    else
      clone(source, opts)
    end
  end

  defp clone(source, opts) do
    opts = source_opts(source, opts)

    with :ok <- Runner.mkdir_p(Ops.runner(opts), Path.dirname(source.checkout), opts),
         :ok <- Ops.cmd(opts, "git", ["clone", source.uri, source.checkout]) do
      checkout(source, opts)
    end
  end

  defp update(source, opts) do
    opts = source_opts(source, opts)

    with :ok <- ensure_clean(source, opts),
         :ok <-
           Ops.cmd(opts, "git", ["-C", source.checkout, "remote", "set-url", "origin", source.uri]),
         :ok <- Ops.cmd(opts, "git", ["-C", source.checkout, "fetch", "--tags", "origin"]) do
      checkout(source, opts)
    end
  end

  defp checkout(%Source{revision: revision} = source, opts) when is_binary(revision) do
    with :ok <- Ops.cmd(opts, "git", ["-C", source.checkout, "checkout", "--detach", revision]) do
      maybe_clean(source, opts)
    end
  end

  defp checkout(source, opts) do
    with :ok <- Ops.cmd(opts, "git", ["-C", source.checkout, "checkout", source.ref]) do
      maybe_clean(source, opts)
    end
  end

  defp ensure_clean(%Source{dirty: :ignore}, _opts), do: :ok
  defp ensure_clean(%Source{dirty: :reset} = source, opts), do: reset_clean(source, opts)

  defp ensure_clean(%Source{dirty: :error} = source, opts) do
    case git_output(source, ["status", "--porcelain"], opts) do
      {:ok, ""} -> :ok
      {:ok, output} -> {:error, {:source_checkout_dirty, source.checkout, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_clean(%Source{dirty: :reset} = source, opts), do: reset_clean(source, opts)
  defp maybe_clean(_source, _opts), do: :ok

  defp reset_clean(source, opts) do
    case Ops.cmd(opts, "git", ["-C", source.checkout, "reset", "--hard"]) do
      :ok -> Ops.cmd(opts, "git", ["-C", source.checkout, "clean", "-fdx"])
      error -> error
    end
  end

  defp git_output(source, args, opts) do
    {command, command_args} = maybe_sudo("git", ["-C", source.checkout | args], opts)

    case Runner.cmd(Ops.runner(opts), command, command_args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim_trailing(output)}
      {output, status} -> {:error, {:git_failed, args, status, output}}
    end
  end

  defp exists?(path, opts), do: match?(:ok, Ops.cmd(opts, "test", ["-e", path]))

  defp source_opts(%Source{sudo: sudo}, opts), do: Keyword.put(opts, :sudo, sudo)

  defp maybe_sudo(command, args, opts) do
    if Keyword.get(opts, :sudo, false), do: {"sudo", [command | args]}, else: {command, args}
  end

  defp classify_remote_ref("refs/heads/" <> _), do: :branch
  defp classify_remote_ref("refs/tags/" <> _), do: :tag
  defp classify_remote_ref(_ref), do: :unknown

  defp parse_ls_remote(output, ref) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&String.split(&1, ~r/\s+/, parts: 2))
    |> pick_revision(ref)
  end

  defp pick_revision([], _ref), do: :error

  defp pick_revision(rows, ref) do
    preferred =
      Enum.find(rows, fn
        [_sha, remote_ref] ->
          remote_ref in ["refs/heads/#{ref}", "refs/tags/#{ref}^{}", "refs/tags/#{ref}"]

        _ ->
          false
      end) || hd(rows)

    case preferred do
      [sha, remote_ref] -> {:ok, sha, classify_remote_ref(remote_ref)}
      _ -> :error
    end
  end
end
