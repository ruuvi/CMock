if $0 == __FILE__

  # make sure there is at least one parameter left (the input file)
  if ARGV.length < 2
    puts ["\nusage: ruby #{__FILE__} input_test_file (output)",
          '',
          '  input_test_file         - this is the C file you want to create a runner for',
          '  output                  - this is the name of the runner file to generate',
          '                            defaults to (input_test_file)_Runner'].join("\n")
    exit 1
  end

  require "#{ENV['UNITY_DIR']}/auto/generate_test_runner"
  require 'yaml'

  if ENV['CEEDLING_MAIN_PROJECT_FILE']
    project_config_file_name = ENV['CEEDLING_MAIN_PROJECT_FILE']
    project_config = YAML.load_file(project_config_file_name)
    if ENV['PROJECT_BUILD_ROOT']
      project_config[:project][:build_root] = ENV['PROJECT_BUILD_ROOT']
    end
    runner_generator = UnityTestRunnerGenerator.new(project_config[:cmock])
  else
    runner_generator = UnityTestRunnerGenerator.new()
  end

  test = ARGV[0]
  runner = ARGV[1]
  runner_generator.run(test, runner)
end
