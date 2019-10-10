require "../integration_helper"

class RunCommandTest < Minitest::Test
  def setup
    Dir.mkdir(File.join(application_path, "src"))
    File.write(File.join(application_path, "src", "cli.cr"), "puts __FILE__")
  end

  def teardown
    File.delete File.join(application_path, "shard.yml")
  end

  def bin_path(name)
    File.join(application_path, "bin", name)
  end

  def test_runs_specific_target
    File.write File.join(application_path, "shard.yml"), <<-YAML
      name: build
      version: 0.1.0
      targets:
        app:
          main: src/cli.cr
        alt:
          main: src/cli.cr
    YAML

    Dir.cd(application_path) do
      run "shards run app --no-color"
      assert File.exists?(bin_path("app"))

      assert_equal File.join(application_path, "src", "cli.cr"), `#{bin_path("app")}`.chomp
    end
  end

  def test_runs_when_only_one_target
    File.write File.join(application_path, "shard.yml"), <<-YAML
      name: build
      version: 0.1.0
      targets:
        app:
          main: src/cli.cr
    YAML

    Dir.cd(application_path) do
      run "shards run --no-color"
      assert File.exists?(bin_path("app"))

      assert_equal File.join(application_path, "src", "cli.cr"), `#{bin_path("app")}`.chomp
    end
  end

  def test_fails_when_multiple_targets_no_arg
    File.write File.join(application_path, "shard.yml"), <<-YAML
      name: build
      version: 0.1.0
      targets:
        app:
          main: src/cli.cr
        alt:
          main: src/cli.cr
    YAML

    ex = assert_raises(FailedCommand) do
      run "shards run --no-color"
    end
    assert_match /Error More than 1 target defined. Must pass target as parameter./, ex.stdout
  end

  def test_fails_when_no_targets_defined
    File.write File.join(application_path, "shard.yml"), <<-YAML
      name: build
      version: 0.1.0
    YAML

    ex = assert_raises(FailedCommand) do
      run "shards run --no-color"
    end
    assert_match /Error No targets defined./, ex.stdout
  end

  def test_fails_when_no_targets_defined_with_target
    File.write File.join(application_path, "shard.yml"), <<-YAML
      name: build
      version: 0.1.0
    YAML

    ex = assert_raises(FailedCommand) do
      run "shards run missing --no-color"
    end
    assert_match /Error Target missing not found./, ex.stdout
  end
end
