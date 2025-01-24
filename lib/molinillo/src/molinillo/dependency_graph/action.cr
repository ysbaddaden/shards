module Molinillo
  # An action that modifies a {DependencyGraph} that is reversible.
  # @abstract
  abstract class DependencyGraph::Action(P, R)
    # Performs the action on the given graph.
    # @param  [DependencyGraph] graph the graph to perform the action on.
    # @return [Void]
    abstract def up(graph : DependencyGraph(P, R))

    # Reverses the action on the given graph.
    # @param  [DependencyGraph] graph the graph to reverse the action on.
    # @return [Void]
    abstract def down(graph : DependencyGraph(P, R))

    # @return [Action,Nil] The previous action
    property previous : Action(P, R)?

    # @return [Action,Nil] The next action
    property next : Action(P, R)?
  end
end
