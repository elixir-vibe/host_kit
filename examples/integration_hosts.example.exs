use HostKit.DSL

project :hostkit_integration_hosts do
  host :integration do
    hostname "example.test"
    user "root"
    sudo true

    ssh port: 22,
        identity_file: Path.expand("~/.ssh/id_ed25519"),
        password: secret_env("HOSTKIT_SSH_PASSWORD"),
        silently_accept_hosts: true
  end
end
