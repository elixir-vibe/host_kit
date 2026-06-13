use HostKit.DSL

project :hostkit_integration_hosts do
  host :integration do
    # Replace with the host you want integration tests to target.
    hostname("example.test")
    user("root")
    sudo(true)

    # Identity auth is preferred when available.
    ssh(
      port: 22,
      identity_file: Path.expand("~/.ssh/id_ed25519"),
      silently_accept_hosts: true
    )

    # For password-only hosts, use an environment-backed secret reference instead
    # of putting the password in config or shell history:
    #
    #   ssh password: secret_env("HOSTKIT_SSH_PASSWORD"),
    #       silently_accept_hosts: true
  end
end
