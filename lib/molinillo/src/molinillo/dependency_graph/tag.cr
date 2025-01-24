require "./action"

class Molinillo::DependencyGraph
  class Tag(P, R) < Action(P, R)
    abstract struct Value
      def self.new(value : Reference)
        ReferenceValue.new(value)
      end

      def self.new(value : Symbol)
        OtherValue.new(value)
      end
    end

    struct ReferenceValue < Value
      @value : UInt64

      def initialize(value : Reference)
        @value = value.object_id
      end
    end

    struct OtherValue < Value
      @value : Symbol

      def initialize(@value)
      end
    end

    getter tag : Value

    def up(graph)
    end

    def down(graph)
    end

    def initialize(tag)
      @tag = Value.new(tag)
    end
  end
end
