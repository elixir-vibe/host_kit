[
  layers: [
    cli: "Mix.Tasks.HostKit.*",
    library: "HostKit.*"
  ],
  deps: [
    forbidden: [
      {:library, :cli}
    ]
  ],
  smells: [strict: true]
]
