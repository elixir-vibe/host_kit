use HostKit.DSL

project :hostkit_integration_hosts do
  host :integration, at: "example.test" do
    # Identity auth is preferred when available.
    ssh do
      user("root")
      sudo(true)
      port(22)
      identity_file(Path.expand("~/.ssh/id_ed25519"))
      accept_hosts(true)
    end

    # For password-only hosts, use an environment-backed secret reference instead
    # of putting the password in config or shell history:
    #
    #   ssh do
    #     user "root"
    #     password secret_env("HOSTKIT_SSH_PASSWORD")
    #     accept_hosts true
    #   end
  end
end
