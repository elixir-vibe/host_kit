excluded = []

excluded =
  if System.get_env("HOSTKIT_INTEGRATION") == "1", do: excluded, else: [:integration | excluded]

limactl = System.get_env("LIMACTL", "limactl")
excluded = if System.find_executable(limactl), do: excluded, else: [:lima | excluded]

ExUnit.start(exclude: excluded)
