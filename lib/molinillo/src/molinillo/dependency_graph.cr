class Molinillo::DependencyGraph(P, R)
end

require "./dependency_graph/log"
require "./dependency_graph/vertex"

class Molinillo::DependencyGraph(P, R)
  # Enumerates through the vertices of the graph.
  # @return [Array<Vertex>] The graph's vertices.
  def each
    # return vertices.values.each unless block_given?
    vertices.values.each { |v| yield v }
  end

  getter log : Log(P, R)
  getter vertices : Hash(String, Vertex(P, R))

  # A directed edge of a {DependencyGraph}
  # @attr [Vertex] origin The origin of the directed edge
  # @attr [Vertex] destination The destination of the directed edge
  # @attr [Object] requirement The requirement the directed edge represents
  record Edge(P, R), origin : Vertex(P, R), destination : Vertex(P, R), requirement : R

  def initialize
    @vertices = {} of String => Vertex(P, R)
    @log = Log(P, R).new
  end

  # Tags the current state of the dependency as the given tag
  # @param  [Object] tag an opaque tag for the current state of the graph
  # @return [Void]
  def tag(tag : Symbol | Reference)
    log.tag(self, tag)
  end

  # Rewinds the graph to the state tagged as `tag`
  # @param  [Object] tag the tag to rewind to
  # @return [Void]
  def rewind_to(tag)
    log.rewind_to(self, tag)
  end

  def inspect
    "#<Molinillo::DependencyGraph:0x#{object_id.to_s(16)} vertices=#{vertices.size}>"
  end

  def to_dot
    dot_vertices = [] of String
    dot_edges = [] of String
    vertices.each do |n, v|
      dot_vertices << "  #{n} [label=\"{#{n}|#{v.payload}}\"]"
      v.outgoing_edges.each do |e|
        label = e.requirement
        dot_edges << "  #{e.origin.name} -> #{e.destination.name} [label=#{label.to_s.dump}]"
      end
    end

    dot_vertices.uniq!
    dot_vertices.sort!
    dot_edges.uniq!
    dot_edges.sort!

    dot = dot_vertices.unshift("digraph G {").push("") + dot_edges.push("}")
    dot.join("\n")
  end

  def ==(other)
    super || begin
      return false unless vertices.keys.to_set == other.vertices.keys.to_set
      vertices.each do |name, vertex|
        other_vertex = other.vertex_named(name)
        return false unless other_vertex
        return false unless vertex.payload == other_vertex.payload
        return false unless other_vertex.successors.to_set == vertex.successors.to_set
      end
      true
    end
  end

  # @param [String] name
  # @param [Object] payload
  # @param [Array<String>] parent_names
  # @param [Object] requirement the requirement that is requiring the child
  # @return [void]
  def add_child_vertex(name : String, payload : P, parent_names : Array(String?), requirement : R)
    root = !(parent_names.delete(nil) || true)
    vertex = add_vertex(name, payload, root)
    vertex.explicit_requirements << requirement if root
    parent_names.each do |parent_name|
      parent_vertex = vertex_named!(parent_name)
      add_edge(parent_vertex, vertex, requirement)
    end
    vertex
  end

  # Adds a vertex with the given name, or updates the existing one.
  # @param [String] name
  # @param [Object] payload
  # @return [Vertex] the vertex that was added to `self`
  def add_vertex(name : String, payload : P, root : Bool = false)
    log.add_vertex(self, name, payload, root)
  end

  # Detaches the {#vertex_named} `name` {Vertex} from the graph, recursively
  # removing any non-root vertices that were orphaned in the process
  # @param [String] name
  # @return [Array<Vertex>] the vertices which have been detached
  def detach_vertex_named(name)
    log.detach_vertex_named(self, name)
  end

  # @param [String] name
  # @return [Vertex,nil] the vertex with the given name
  def vertex_named(name) : Vertex(P, R)?
    vertices[name]?
  end

  # @param [String] name
  # @return [Vertex,nil] the vertex with the given name
  def vertex_named!(name) : Vertex(P, R)
    vertices[name]
  end

  # @param [String] name
  # @return [Vertex,nil] the root vertex with the given name
  def root_vertex_named(name) : Vertex(P, R)?
    vertex = vertex_named(name)
    vertex if vertex && vertex.root
  end

  # Adds a new {Edge} to the dependency graph
  # @param [Vertex] origin
  # @param [Vertex] destination
  # @param [Object] requirement the requirement that this edge represents
  # @return [Edge] the added edge
  def add_edge(origin : Vertex(P, R), destination : Vertex(P, R), requirement : R)
    if destination.path_to?(origin)
      raise CircularDependencyError(P, R).new(path(destination, origin))
    end
    add_edge_no_circular(origin, destination, requirement)
  end

  # Sets the payload of the vertex with the given name
  # @param [String] name the name of the vertex
  # @param [Object] payload the payload
  # @return [Void]
  def set_payload(name, payload)
    log.set_payload(self, name, payload)
  end

  # Adds a new {Edge} to the dependency graph without checking for
  # circularity.
  # @param (see #add_edge)
  # @return (see #add_edge)
  private def add_edge_no_circular(origin, destination, requirement)
    log.add_edge_no_circular(self, origin.name, destination.name, requirement)
  end

  # Returns the path between two vertices
  # @raise [ArgumentError] if there is no path between the vertices
  # @param [Vertex] from
  # @param [Vertex] to
  # @return [Array<Vertex>] the shortest path from `from` to `to`
  def path(from, to)
    distances = Hash(String, Int32).new(vertices.size + 1)
    distances[from.name] = 0
    predecessors = {} of Vertex(P, R) => Vertex(P, R)
    each do |vertex|
      vertex.successors.each do |successor|
        if distances[successor.name] > distances[vertex.name] + 1
          distances[successor.name] = distances[vertex.name] + 1
          predecessors[successor] = vertex
        end
      end
    end

    path = [to]
    while before = predecessors[to]?
      path << before
      to = before
      break if to == from
    end

    unless path.last == from
      raise ArgumentError.new("There is no path from #{from.name} to #{to.name}")
    end

    path.reverse
  end
end
