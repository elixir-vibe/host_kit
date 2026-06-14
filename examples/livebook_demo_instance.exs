use HostKit.DSL

project :livebook_demo do
  instance :hostkit_livebook_demo do
    backend(:incus)
    image("images:ubuntu/24.04")
    kind(:container)
    lifecycle(:ephemeral)

    expose(:ssh, host: 2222, guest: 22)
    expose(:caddy_demo, host: 18_080, guest: 18_080)
    expose(:phoenix_demo, host: 18_081, guest: 18_081)

    host :guest, at: "127.0.0.1" do
      ssh do
        user("root")
        password("hostkit-demo")
        port(2222)
        accept_hosts(true)
      end
    end
  end
end
