defmodule HostKit.Recipes.ElixirApp.Scope do
  @moduledoc "Process-local scope helpers for the Elixir app recipe DSL."

  use DSL

  scope(:elixir_app_recipe)

  scope :ecto do
    requires(:elixir_app_recipe)
  end

  def start_scope do
    push_elixir_app_recipe([])
  end

  def finish_scope do
    pop_elixir_app_recipe()
  end

  def put_scope(key, value) when is_atom(key) do
    update_elixir_app_recipe(&Keyword.put(&1, key, value))
  end

  def start_ecto(opts) do
    push_ecto(Keyword.put_new(opts, :repos, []))
  end

  def add_ecto_repo(name) do
    update_ecto(&Keyword.update!(&1, :repos, fn repos -> repos ++ [name] end))
  end

  def finish_ecto do
    opts = pop_ecto()
    put_scope(:ecto, opts)
  end
end
