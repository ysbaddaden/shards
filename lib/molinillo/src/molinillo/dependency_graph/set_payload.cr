require "./action"

class Molinillo::DependencyGraph
  class SetPayload(P, R) < Action(P, R)
    getter name : String
    getter payload : P
    @old_payload : P?

    def initialize(@name, @payload)
    end

    def up(graph)
      vertex = graph.vertex_named!(name)
      @old_payload = vertex.payload
      vertex.payload = payload
    end

    def down(graph)
      graph.vertex_named!(name).payload = @old_payload
    end
  end
end
