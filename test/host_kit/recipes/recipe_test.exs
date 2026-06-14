defmodule HostKit.RecipeTest do
  use ExUnit.Case, async: true

  defmodule DemoRecipe do
    use HostKit.Recipe

    defrecipe demo_app(name, opts) do
      assigns = __MODULE__.assigns(name, opts)

      service assigns.name do
        package(:curl)
        file(assigns.path, content: assigns.content)
      end
    end

    def assigns(name, opts) do
      %{
        name: name,
        path: Keyword.fetch!(opts, :path),
        content: Keyword.fetch!(opts, :content)
      }
    end
  end

  test "recipes expand to ordinary HostKit DSL resources" do
    defmodule DemoProject do
      use HostKit.DSL, recipes: [DemoRecipe]

      def project do
        project :demo do
          demo_app(:hello, path: "/tmp/hello", content: "hello")
        end
      end
    end

    resources = HostKit.Project.resources(DemoProject.project())

    assert Enum.any?(resources, &match?(%HostKit.Resources.Package{name: :curl}, &1))

    assert Enum.any?(
             resources,
             &match?(%HostKit.Resources.File{path: "/tmp/hello", content: "hello"}, &1)
           )
  end
end
