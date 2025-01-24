# require "./resolution"

module Molinillo
  # This class encapsulates a dependency resolver.
  # The resolver is responsible for determining which set of dependencies to
  # activate, with feedback from the {#specification_provider}
  #
  #
  class Resolver(R, S)
    # @return [SpecificationProvider] the specification provider used
    #   in the resolution process
    getter specification_provider : SpecificationProvider(R, S)

    # @return [UI] the UI module used to communicate back to the user
    #   during the resolution process
    getter resolver_ui : UI

    # Initializes a new resolver.
    # @param  [SpecificationProvider] specification_provider
    #   see {#specification_provider}
    # @param  [UI] resolver_ui
    #   see {#resolver_ui}
    def initialize(@specification_provider, @resolver_ui)
    end

    # Resolves the requested dependencies into a {DependencyGraph},
    # locking to the base dependency graph (if specified)
    # @param [Array] requested an array of 'requested' dependencies that the
    #   {#specification_provider} can understand
    # @param [DependencyGraph,nil] base the base dependency graph to which
    #   dependencies should be 'locked'
    def resolve(requested : Array(R), base = DependencyGraph(R, R).new)
      Resolution(R, S).new(
        specification_provider,
        resolver_ui,
        requested,
        base)
        .resolve
    end
  end
end
