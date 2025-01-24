require "./action"

class Molinillo::DependencyGraph
  class DetachVertexNamed(P, R) < Action(P, R)
    getter name : String
    @vertex : Vertex(P, R)?

    def initialize(@name)
    end

    def up(graph)
      return [] of Vertex(P, R) unless vertex = @vertex = graph.vertices.delete(name)

      removed_vertices = [vertex] of Vertex(P, R)
      vertex.outgoing_edges.each do |e|
        v = e.destination
        v.incoming_edges.delete(e)
        if !v.root && v.incoming_edges.empty?
          removed_vertices.concat graph.detach_vertex_named(v.name)
        end
      end

      vertex.incoming_edges.each do |e|
        v = e.origin
        v.outgoing_edges.delete(e)
      end

      removed_vertices
    end

    def down(graph)
      return unless vertex = @vertex
      graph.vertices[vertex.name] = vertex
      vertex.outgoing_edges.each do |e|
        e.destination.incoming_edges << e
      end
      vertex.incoming_edges.each do |e|
        e.origin.outgoing_edges << e
      end
    end
  end
end
