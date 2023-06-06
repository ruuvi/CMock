require "#{ENV['CMOCK_DIR']}/lib/cmock"
require 'yaml'

raise 'Header file to mock must be specified!' unless ARGV.length >= 1

# Load the project configuration if provided, otherwise use default plugins
if ENV['CEEDLING_MAIN_PROJECT_FILE']
  project_config_file_name = ENV['CEEDLING_MAIN_PROJECT_FILE']
  project_config = YAML.load_file(project_config_file_name)
  if ENV['PROJECT_BUILD_ROOT']
    project_config[:project][:build_root] = ENV['PROJECT_BUILD_ROOT']
  end
  if ENV['MOCK_OUT']
    project_config[:cmock][:mock_path] = ENV['MOCK_OUT']
  end
  if ENV['MOCK_PREFIX']
    project_config[:cmock][:mock_prefix] = ENV['MOCK_PREFIX']
  end
  cmock = CMock.new(project_config[:cmock])
else
  plugins = %i[ignore return_thru_ptr]
  mock_out = ENV.fetch('MOCK_OUT', './build/test/mocks')
  mock_prefix = ENV.fetch('MOCK_PREFIX', 'mock_')
  cmock = CMock.new(:plugins => plugins, :mock_prefix => mock_prefix, :mock_path => mock_out)
end

cmock.setup_mocks(ARGV[0])
