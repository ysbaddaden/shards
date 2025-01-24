class Molinillo::DependencyGraph::Vertex(P, R)
  property root = false
  property name : String
  property payload : P
  getter explicit_requirements : Array(R)
  getter outgoing_edges : Array(Edge(P, R))
  getter incoming_edges : Array(Edge(P, R))

  def initialize(@name, @payload : P)
    @explicit_requirements = Array(R).new
    @outgoing_edges = Array(Edge(P, R)).new
    @incoming_edges = Array(Edge(P, R)).new
  end

  # @return [Array<Object>] all of the requirements that required
  #   this vertex
  def requirements
    (incoming_edges.map(&.requirement) + explicit_requirements).uniq
  end

  # @return [Array<Vertex>] the vertices of {#graph} that have an edge with
  #   `self` as their {Edge#destination}
  def predecessors
    incoming_edges.map &.origin
  end

  # @return [Array<Vertex>] the vertices of {#graph} that have an edge with
  #   `self` as their {Edge#origin}
  def successors
    outgoing_edges.map &.destination
  end

  def ==(other)
    super || (
      name == other.name &&
        payload == other.payload &&
        successors.to_set == other.successors.to_set
    )
  end

  def_hash @name

  # Is there a path from `self` to `other` following edges in the
  # dependency graph?
  # @return true iff there is a path following edges within this {#graph}
  def path_to?(other)
    _path_to?(other)
  end

  # @param [Vertex] other the vertex to check if there's a path to
  # @param [Set<Vertex>] visited the vertices of {#graph} that have been visited
  # @return [Boolean] whether there is a path to `other` from `self`
  protected def _path_to?(other, visited = Set(self).new)
    return false unless visited.add?(self)
    return true if self == other
    successors.any? { |v| v._path_to?(other, visited) }
  end
end
