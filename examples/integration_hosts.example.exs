use HostKit.DSL

project :hostkit_integration_hosts do
  host :integration do
    hostname "example.test"
    user "root"
    sudo true

    ssh port: 22,
        identity_file: Path.expand("~/.ssh/id_ed25519"),
        silently_accept_hosts: true
  end
end
