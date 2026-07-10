# DSL scope predicates are process-local. Dialyzer narrows the generated
# predicates to true even though tests exercise both branches.
[
  {"lib/host_kit/dsl.ex", :pattern_match}
]
