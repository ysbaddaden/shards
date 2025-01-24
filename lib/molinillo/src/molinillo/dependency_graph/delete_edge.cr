require "./action"

class Molinillo::DependencyGraph
  class DeleteEdge(P, R) < Action(P, R)
    getter origin_name : String
    getter destination_name : String
    getter requirement : R

    def initialize(@origin_name, @destination_name, @requirement)
    end

    def up(graph)
      edge = make_edge(graph)
      edge.origin.outgoing_edges.delete(edge)
      edge.destination.incoming_edges.delete(edge)
    end

    def down(graph)
      edge = make_edge(graph)
      edge.origin.outgoing_edges << edge
      edge.destination.incoming_edges << edge
      edge
    end

    private def make_edge(graph)
      Edge(P, R).new(
        graph.vertex_named(origin_name),
        graph.vertex_named(destination_name),
        requirement
      )
    end
  end
end
