require "./action"

class Molinillo::DependencyGraph
  class AddEdgeNoCircular(P, R) < Action(P, R)
    getter origin : String
    getter destination : String
    getter requirement : R

    def initialize(@origin : String, @destination : String, @requirement : R)
    end

    def up(graph)
      edge = make_edge(graph)
      edge.origin.outgoing_edges << edge
      edge.destination.incoming_edges << edge
      edge
    end

    def down(graph)
      edge = make_edge(graph)
      delete_first(edge.origin.outgoing_edges, edge)
      delete_first(edge.destination.incoming_edges, edge)
    end

    # @param  [DependencyGraph] graph the graph to find vertices from
    # @return [Edge] The edge this action adds
    def make_edge(graph)
      Edge(P, R).new(graph.vertex_named!(origin), graph.vertex_named!(destination), requirement)
    end

    private def delete_first(array, item)
      return unless index = array.index(item)
      array.delete_at(index)
    end
  end
end
