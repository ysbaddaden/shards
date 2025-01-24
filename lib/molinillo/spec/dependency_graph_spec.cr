require "./spec_helper"

private def test_dependency_graph
  graph = Molinillo::DependencyGraph(String, String).new
  root = graph.add_vertex("Root", "Root", true)
  root2 = graph.add_vertex("Root2", "Root2", true)
  child = graph.add_child_vertex("Child", "Child", %w(Root), "Child")
  {graph: graph, root: root, root2: root2, child: child}
end

describe Molinillo::DependencyGraph do
  describe "in general" do
    it "returns root vertices by name" do
      data = test_dependency_graph
      data[:graph].root_vertex_named("Root").should eq(data[:root])
    end

    it "returns vertices by name" do
      data = test_dependency_graph
      data[:graph].vertex_named("Root").should eq(data[:root])
      data[:graph].vertex_named("Child").should eq(data[:child])
    end

    it "returns nil for non-existent root vertices" do
      data = test_dependency_graph
      data[:graph].root_vertex_named("missing").should be_nil
    end

    it "returns nil for non-existent vertices" do
      data = test_dependency_graph
      data[:graph].vertex_named("missing").should be_nil
    end
  end

  describe "detaching a vertex" do
    it "detaches a root vertex without successors" do
      graph = Molinillo::DependencyGraph(String, String).new
      root = graph.add_vertex("root", "root", true)
      graph.detach_vertex_named(root.name)
      graph.vertex_named(root.name).should be_nil
      graph.vertices.should be_empty
    end

    it "detaches a root vertex with successors" do
      graph = Molinillo::DependencyGraph(String, String).new
      root = graph.add_vertex("root", "root", true)
      child = graph.add_child_vertex("child", "child", %w(root), "child")
      graph.detach_vertex_named(root.name)
      graph.vertex_named(root.name).should be_nil
      graph.vertex_named(child.name).should be_nil
      graph.vertices.should be_empty
    end

    it "detaches a root vertex with successors with other parents" do
      graph = Molinillo::DependencyGraph(String, String).new
      root = graph.add_vertex("root", "root", true)
      root2 = graph.add_vertex("root2", "root2", true)
      child = graph.add_child_vertex("child", "child", %w(root root2), "child")
      graph.detach_vertex_named(root.name)
      graph.vertex_named(root.name).should be_nil
      graph.vertex_named(child.name).should eq(child)
      child.predecessors.should eq([root2])
      graph.vertices.size.should eq(2)
    end

    it "detaches a vertex with predecessors" do
      graph = Molinillo::DependencyGraph(String, String).new
      parent = graph.add_vertex("parent", "parent", true)
      child = graph.add_child_vertex("child", "child", %w(parent), "child")
      graph.detach_vertex_named(child.name)
      graph.vertex_named(child.name).should be_nil
      graph.vertices.should eq({parent.name => parent})
      parent.outgoing_edges.should be_empty
    end
  end
end
