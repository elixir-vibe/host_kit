excluded = []

excluded =
  if System.get_env("HOSTKIT_INTEGRATION") == "1", do: excluded, else: [:integration | excluded]

ExUnit.start(exclude: excluded)
