require "./action"

class Molinillo::DependencyGraph
  class AddVertex(P, R) < Action(P, R)
    getter name : String
    getter payload : P
    getter root : Bool

    @existing : {payload: P, root: Bool}?

    def initialize(@name, @payload : P, @root)
    end

    def up(graph)
      if existing = graph.vertices[name]?
        @existing = {payload: existing.payload, root: existing.root}
      end
      vertex = existing || Vertex(P, R).new(name, payload)
      graph.vertices[vertex.name] = vertex
      vertex.payload ||= payload
      vertex.root ||= root
      vertex
    end

    def down(graph)
      if existing = @existing
        vertex = graph.vertices[name]
        vertex.payload = existing[:payload]
        vertex.root = existing[:root]
      else
        graph.vertices.delete(name)
      end
    end
  end
end
