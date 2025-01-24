# frozen_string_literal: true

require "../spec_helper"

alias DG = Molinillo::DependencyGraph(Int32, Int32)

def shared_examples_for_replay(prepare)
  it "replays the log" do
    copy = DG.new
    graph = DG.new.tap { |g| prepare.call(g) }
    graph.log.each &.up(copy)
    copy.should eq(graph)
  end

  it "can undo to an empty graph" do
    graph = DG.new
    tag = Reference.new
    graph.tag(tag)
    prepare.call(graph)
    graph.rewind_to(tag)
    graph.should eq(DG.new)
  end
end

describe Molinillo::DependencyGraph::Log do
  describe "with empty log" do
    shared_examples_for_replay ->(g : DG) {}
  end

  describe "with some graph" do
    shared_examples_for_replay ->(g : DG) do
      g.add_child_vertex("Foo", 1, [nil] of String?, 4)
      g.add_child_vertex("Bar", 2, ["Foo", nil], 3)
      g.add_child_vertex("Baz", 3, %w(Foo Bar), 2)
      g.add_child_vertex("Foo", 4, [] of String?, 1)
    end
  end
end
