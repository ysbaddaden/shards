require "./add_vertex"
require "./add_edge_no_circular"

class Molinillo::DependencyGraph::Log(P, R)
  @current_action : Action(P, R)?
  @first_action : Action(P, R)?

  def tag(graph, tag)
    push_action(graph, Tag(P, R).new(tag))
  end

  def add_vertex(graph, name : String, payload : P, root)
    push_action(graph, AddVertex(P, R).new(name, payload, root))
  end

  def detach_vertex_named(graph, name)
    push_action(graph, DetachVertexNamed(P, R).new(name))
  end

  def add_edge_no_circular(graph, origin, destination, requirement)
    push_action(graph, AddEdgeNoCircular(P, R).new(origin, destination, requirement))
  end

  # {include:DependencyGraph#delete_edge}
  # @param [Graph] graph the graph to perform the action on
  # @param [String] origin_name
  # @param [String] destination_name
  # @param [Object] requirement
  # @return (see DependencyGraph#delete_edge)
  def delete_edge(graph, origin_name, destination_name, requirement)
    push_action(graph, DeleteEdge.new(origin_name, destination_name, requirement))
  end

  # @macro action
  def set_payload(graph, name, payload)
    push_action(graph, SetPayload(P, R).new(name, payload))
  end

  # Pops the most recent action from the log and undoes the action
  # @param [DependencyGraph] graph
  # @return [Action] the action that was popped off the log
  def pop!(graph)
    return unless action = @current_action
    unless @current_action = action.previous
      @first_action = nil
    end
    action.down(graph)
    action
  end

  # Enumerates each action in the log
  # @yield [Action]
  def each
    action = @first_action
    loop do
      break unless action
      yield action
      action = action.next
    end
    self
  end

  def rewind_to(graph, tag)
    tag_value = Tag::Value.new(tag)
    loop do
      action = pop!(graph)
      raise "No tag #{tag.inspect} found" unless action
      break if action.is_a?(Tag(P, R)) && action.tag == tag_value
    end
  end

  # Adds the given action to the log, running the action
  # @param [DependencyGraph] graph
  # @param [Action] action
  # @return The value returned by `action.up`
  private def push_action(graph, action)
    action.previous = @current_action
    if current_action = @current_action
      current_action.next = action
    end
    @current_action = action
    @first_action ||= action
    action.up(graph)
  end
end
