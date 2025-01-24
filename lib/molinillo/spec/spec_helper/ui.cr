module Molinillo
  class TestUI
    include UI

    @output : IO?

    def output
      @output ||= if debug?
                    STDERR
                  else
                    File.open("/dev/null", "w")
                  end
    end
  end
end
