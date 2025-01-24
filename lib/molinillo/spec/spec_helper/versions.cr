module Shards
  module Versions
    # :nodoc:
    struct Segment
      NON_ALPHANUMERIC                           = /[^a-zA-Z0-9]/
      NATURAL_SORT_EXTRACT_NEXT_CHARS_AND_DIGITS = /^(\D*)(\d*)(.*)$/

      protected getter! segment : String

      def initialize(@str : String)
        if index = @str.index('+')
          @str = @str[0...index]
        end
      end

      def next
        @segment, _, @str = @str.partition(NON_ALPHANUMERIC)
        segment
      end

      def empty?
        segment.empty?
      end

      def to_i?
        segment.to_i?(whitespace: false)
      end

      def <=>(b : self)
        natural_sort(segment, b.segment)
      end

      # Original natural sorting algorithm from:
      # https://github.com/sourcefrog/natsort/blob/master/natcmp.rb
      # Copyright (C) 2003 by Alan Davies <cs96and_AT_yahoo_DOT_co_DOT_uk>.
      private def natural_sort(a, b)
        if (a_num = a.to_i?(whitespace: false)) && (b_num = b.to_i?(whitespace: false))
          return a_num <=> b_num
        end

        loop do
          return 0 if a.empty? && b.empty?

          a =~ NATURAL_SORT_EXTRACT_NEXT_CHARS_AND_DIGITS
          a_chars, a_digits, a = $1, $2, $3

          b =~ NATURAL_SORT_EXTRACT_NEXT_CHARS_AND_DIGITS
          b_chars, b_digits, b = $1, $2, $3

          ret = a_chars <=> b_chars
          return ret unless ret == 0

          a_num = a_digits.to_i?(whitespace: false)
          b_num = b_digits.to_i?(whitespace: false)

          if a_num && b_num
            ret = a_num.to_i <=> b_num.to_i
            return ret unless ret == 0
          else
            ret = a_digits <=> b_digits
            return ret unless ret == 0
          end
        end
      end

      def only_zeroes?
        return if empty?
        yield unless to_i? == 0

        loop do
          self.next

          return if empty?
          yield unless to_i? == 0
        end
      end

      def prerelease?
        segment.each_char.any?(&.ascii_letter?)
      end

      def inspect(io)
        @segment.inspect(io)
      end
    end

    def self.sort(versions)
      versions.sort { |a, b| compare(a, b) }
    end

    def self.compare(a, b)
      if a == b
        return 0
      end

      a_segment = Segment.new(a)
      b_segment = Segment.new(b)

      loop do
        # extract next segment from version number ("1.0.2" => "1" then "0" then "2"):
        a_segment.next
        b_segment.next

        # accept unbalanced version numbers ("1.0" == "1.0.0.0", "1.0" < "1.0.1")
        if a_segment.empty?
          b_segment.only_zeroes? { return b_segment.prerelease? ? -1 : 1 }
          return 0
        end

        # accept unbalanced version numbers ("1.0.0.0" == "1.0", "1.0.1" > "1.0")
        if b_segment.empty?
          a_segment.only_zeroes? { return a_segment.prerelease? ? 1 : -1 }
          return 0
        end

        # try to convert segments to numbers:
        a_num = a_segment.to_i?
        b_num = b_segment.to_i?

        ret =
          if a_num && b_num
            # compare numbers (for natural 1, 2, ..., 10, 11 ordering):
            b_num <=> a_num
          elsif a_num
            # b is preliminary version:
            a_segment.only_zeroes? do
              return b_segment <=> a_segment if a_segment.prerelease?
              return -1
            end
            return -1
          elsif b_num
            # a is preliminary version:
            b_segment.only_zeroes? do
              return b_segment <=> a_segment if b_segment.prerelease?
              return 1
            end
            return 1
          else
            # compare strings:
            b_segment <=> a_segment
          end

        # if different return the result (older or newer), otherwise continue
        # to the next segment:
        return ret unless ret == 0
      end
    end

    def self.prerelease?(str)
      str.each_char do |char|
        return true if char.ascii_letter?
        break if char == '+'
      end
      false
    end

    protected def self.without_prereleases(versions)
      versions.reject { |v| prerelease?(v) }
    end

    def self.resolve(versions, requirements : Enumerable(String), prereleases = false)
      unless prereleases || requirements.any? { |r| prerelease?(r) }
        versions = without_prereleases(versions)
      end

      matching_versions = requirements
        .map { |requirement| resolve(versions, requirement) }
        .reduce(versions) { |a, e| a & e }

      sort(matching_versions)
    end

    def self.resolve(versions, requirement : String)
      case requirement
      when "*", ""
        versions
      when /~>\s*([^\s]+)/
        ver = if idx = $1.rindex('.')
                $1[0...idx]
              else
                $1
              end
        versions.select { |version| matches_approximate?(version, $1, ver) }
      when /\s*(~>|>=|<=|>|<|=)\s*([^~<>=\s]+)\s*/
        versions.select { |version| matches_operator?(version, $1, $2) }
      else
        versions.select { |version| matches_operator?(version, "=", requirement) }
      end
    end

    def self.matches?(version : String, requirement : String)
      case requirement
      when "*", ""
        true
      when /~>\s*([^\s]+)\d*/
        ver = if idx = $1.rindex('.')
                $1[0...idx]
              else
                $1
              end
        matches_approximate?(version, $1, ver)
      when /\s*(~>|>=|<=|>|<|!=|=)\s*([^~<>=\s]+)\s*/
        matches_operator?(version, $1, $2)
      else
        matches_operator?(version, "=", requirement)
      end
    end

    private def self.matches_approximate?(version, requirement, ver)
      version.starts_with?(ver) &&
        !version[ver.size]?.try(&.ascii_alphanumeric?) &&
        (compare(version, requirement) <= 0)
    end

    private def self.matches_operator?(version, operator, requirement)
      case operator
      when ">="
        compare(version, requirement) <= 0
      when "<="
        compare(version, requirement) >= 0
      when ">"
        compare(version, requirement) < 0
      when "<"
        compare(version, requirement) > 0
      when "!="
        compare(version, requirement) != 0
      else
        compare(version, requirement) == 0
      end
    end
  end
end
